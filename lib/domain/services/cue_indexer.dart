import 'dart:typed_data';

import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../../core/utils/cue_sheet.dart';
import '../entities/drive_entry.dart';
import '../entities/track.dart';

/// 「读一个小文件的原始字节」—— [CueIndexer] 唯一需要的网盘能力。
///
/// 刻意**不依赖整个 `CloudDriveAdapter`**：分轨只用到「读 CUE」这一个动作，
/// 依赖收窄到这一步，测试就不必为了跑通而实现 9 个用不到的方法。
/// 适配器的方法可以直接当它用（多出来的可选参数不影响赋值）。
typedef CueFileReader = Future<Uint8List> Function(String fileId);
/// 一个目录的 CUE 处理结果。
///
/// 三份输出对应三种动作，由调用方（扫描器）分别落到库里：
///   - [extraTracks]：**新增**（整轨切出的虚拟曲目）
///   - [patchedTracks]：**覆盖**（既有曲目换了更可信的元数据，id 不变）
///   - [replacedImageIds]：**删除**（整轨文件本身已被切出的段取代）
class CueIndexResult {
  const CueIndexResult({
    this.extraTracks = const [],
    this.patchedTracks = const [],
    this.replacedImageIds = const {},
  });

  final List<Track> extraTracks;
  final List<Track> patchedTracks;

  /// 已被虚拟曲目取代的整轨文件 id。
  ///
  /// 为什么要删掉整轨本身：一张 72 分钟的 WAV 展开成 15 首之后，再留着
  /// 「1 首 72 分钟」那一行，用户看到的是 16 行、其中一行点下去还是整张专辑 ——
  /// 那正是 CUE 支持要消灭的体验。整轨的入口改为分组头的「整轨连播」。
  final Set<String> replacedImageIds;

  bool get isEmpty =>
      extraTracks.isEmpty && patchedTracks.isEmpty && replacedImageIds.isEmpty;

  @override
  String toString() => 'CueIndexResult(新增 ${extraTracks.length}, '
      '覆盖 ${patchedTracks.length}, 取代 ${replacedImageIds.length})';
}

/// 把目录里的 `.cue` 分轨表变成曲库里的曲目。
///
/// **为什么放在扫描流程里而不是读的时候现算**：分轨信息必须落进 `Tracks` 表，
/// 收藏、播放次数、随机权重、搜索才都能照旧工作。如果做成「查询时展开」，
/// 那 15 首虚拟曲目就没有行、收藏不了也随机不到 —— CUE 支持也就没了意义。
///
/// 两条完全不同的处理路径（见 [indexDirectory]）：
///   - **整轨**（1 个 FILE + N 轨）：切出 N 条虚拟曲目，隐藏整轨文件；
///   - **分轨**（N 个 FILE）：不动曲目结构，只把 CUE 里的曲名/艺术家/专辑
///     覆盖到对应文件上 —— 这种目录里文件本来就是分开的，
///     CUE 唯一的价值是元数据比文件名猜的准。
class CueIndexer {
  const CueIndexer();

  /// 处理一个目录。
  ///
  /// [readFile] 是读 CUE 内容的能力（通常是 `adapter.readFileBytes`）。
  /// 刻意做成**参数**而不是构造参数：适配器是扫描时才按网盘解析出来的，
  /// 放进构造函数就得再套一层工厂；放这里则让本类保持无状态、可 `const`，
  /// 测试也只要传个闭包。
  ///
  /// [tracks] 是该目录下已识别出的音频曲目，[cueFiles] 是该目录下的 `.cue`
  /// 条目。两者都只属于**同一个目录** —— CUE 里的 `FILE` 是相对同目录的
  /// 文件名，跨目录匹配只会误伤。
  ///
  /// 整个过程**永不抛异常**：CUE 是锦上添花，读不到、解析失败、网盘不支持
  /// 都只该让这个目录退回「没有 CUE」的样子，绝不能让整次扫描失败。
  Future<CueIndexResult> indexDirectory({
    required CueFileReader readFile,
    required List<Track> tracks,
    required List<DriveEntry> cueFiles,
  }) async {
    if (tracks.isEmpty || cueFiles.isEmpty) return const CueIndexResult();

    final extra = <Track>[];
    final patched = <String, Track>{};
    final replaced = <String>{};

    for (final cue in cueFiles) {
      final sheet = await _loadSheet(readFile, cue);
      if (sheet == null) continue;

      if (sheet.isSingleImage) {
        _expandImage(sheet, cue, tracks, extra, replaced);
      } else {
        _patchMetadata(sheet, cue, tracks, patched);
      }
    }

    if (extra.isEmpty && patched.isEmpty && replaced.isEmpty) {
      return const CueIndexResult();
    }
    return CueIndexResult(
      extraTracks: extra,
      patchedTracks: patched.values.toList(),
      replacedImageIds: replaced,
    );
  }

  // -------------------------------------------------------------------
  // 整轨：切段
  // -------------------------------------------------------------------

  /// 整轨展开。
  ///
  /// 注意这里**先补齐末轨终点再切**：CUE 里同一个 `FILE` 的最后一轨没有终点
  /// （终点要靠下一轨的起点推），而整轨的最后一轨后面没有下一轨了。
  /// 不补的话最后一首永远是 `--:--`、也永远不会自动切歌。
  /// 整轨文件的真实时长正好是它的终点 —— 网盘列目录就带 `duration`。
  void _expandImage(
    CueSheet sheet,
    DriveEntry cue,
    List<Track> tracks,
    List<Track> extra,
    Set<String> replaced,
  ) {
    final fileRef = sheet.files.single;
    final image = _matchFile(fileRef.name, tracks);
    if (image == null) {
      diag.warn('CUE', '${cue.name}：整轨文件 "${fileRef.name}" 在本目录没找到，跳过');
      return;
    }

    final filled = sheet.withFileEnd(
      (_) => image.durationMs,
    );

    final segments = <Track>[];
    for (final t in filled.tracks) {
      // 单轨时长 = 终点 - 起点；终点未知（整轨本身没给出时长）时留 null，
      // 界面上显示 `--:--` 比显示一个编造的时长诚实。
      final duration = t.duration;
      segments.add(Track.cueSegment(
        source: image,
        trackNo: t.number,
        startMs: t.startMs,
        durationMs: duration?.inMilliseconds,
        title: t.title,
        artist: t.performer ?? filled.performer,
        album: filled.title ?? image.album,
      ));
    }
    if (segments.isEmpty) return;

    extra.addAll(segments);
    // 整轨本身让位给切出的段
    replaced.add(image.id);
    diag.info(
      'CUE',
      '${cue.name}：整轨 "${fileRef.name}" 展开为 ${segments.length} 首'
      '（整轨 ${image.durationMs ?? "未知"}ms）',
    );
  }

  // -------------------------------------------------------------------
  // 分轨：只覆盖元数据
  // -------------------------------------------------------------------

  /// 分轨元数据增强。
  ///
  /// 只覆盖 `title` / `artist` / `album`，**绝不碰 `id`**：这些曲目是货真价实的
  /// 独立文件，主键一旦因为 CUE 而变，用户之前收藏的那条就成了孤儿。
  void _patchMetadata(
    CueSheet sheet,
    DriveEntry cue,
    List<Track> tracks,
    Map<String, Track> patched,
  ) {
    var hits = 0;
    for (final fileRef in sheet.files) {
      final target = _matchFile(fileRef.name, tracks);
      if (target == null) continue;

      // 这个 FILE 块里的轨（通常是 1 轨，也可能多轨共享一个文件）
      final own = sheet.tracks.where((t) => t.fileName == fileRef.name).toList();
      final first = own.isEmpty ? null : own.first;

      final updated = target.copyWith(
        cueTrackNo: first?.number ?? target.cueTrackNo,
        title: first?.title ?? target.title,
        artist: first?.performer ?? sheet.performer ?? target.artist,
        album: sheet.title ?? target.album,
      );
      patched[target.id] = updated;
      hits++;
    }

    if (hits == 0) {
      diag.warn('CUE', '${cue.name}：CUE 引用的文件在本目录一个都没找到，跳过');
      return;
    }
    diag.info('CUE', '${cue.name}：为 $hits 首曲目补上 CUE 元数据');
  }

  // -------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------

  /// 读 + 解码 + 解析一份 CUE。任何一步失败都返回 `null`（并留日志）。
  Future<CueSheet?> _loadSheet(CueFileReader readFile, DriveEntry cue) async {
    Uint8List bytes;
    try {
      bytes = await readFile(cue.id);
    } on DriveException catch (e) {
      // `unsupported` 是预期内的（不是每家网盘都给读文件的能力），
      // 其余才是真的异常，日志级别区分开。
      if (e.type == DriveErrorType.unsupported) {
        diag.info('CUE', '${cue.name}：该网盘不支持读取文件内容，跳过');
      } else {
        diag.warn('CUE', '${cue.name}：读取失败（${e.type.name}）${e.message}');
      }
      return null;
    } catch (e) {
      diag.warn('CUE', '${cue.name}：读取抛出非预期异常', error: e);
      return null;
    }

    final sheet = parseCue(decodeCueBytes(bytes));
    if (sheet == null) {
      diag.warn('CUE', '${cue.name}：解析不出任何音轨（${bytes.length}B），跳过');
      return null;
    }
    return sheet;
  }

  /// 把 CUE 里的文件名对上目录里的曲目。
  ///
  /// 三级匹配，从严到宽 —— 真实抓轨的 CUE 与文件常有细微出入：
  ///   1. 完全一致；
  ///   2. 忽略大小写（`CDImage.WAV` vs `cdimage.wav`，Windows 抓轨很常见）；
  ///   3. 忽略扩展名（CUE 写 `.wav` 而实际是 `.flac`，或扩展名拼错）。
  ///
  /// 只按**文件名**比较：CUE 的 `FILE` 是相对同目录的，带路径前缀时取最后一段。
  static Track? _matchFile(String cueName, List<Track> tracks) {
    final wanted = _baseName(cueName);
    if (wanted.isEmpty) return null;

    for (final t in tracks) {
      if (t.name == wanted) return t;
    }
    final lower = wanted.toLowerCase();
    for (final t in tracks) {
      if (t.name.toLowerCase() == lower) return t;
    }
    final wantedStem = _stem(lower);
    for (final t in tracks) {
      if (_stem(t.name.toLowerCase()) == wantedStem) return t;
    }
    return null;
  }

  /// 取路径最后一段（CUE 里偶尔写成 `FILE "sub\a.wav"`）。
  static String _baseName(String p) {
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    return (i < 0 ? p : p.substring(i + 1)).trim();
  }

  static String _stem(String name) {
    final i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }
}
