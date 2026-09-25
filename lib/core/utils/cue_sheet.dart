/// CUE 分轨表解析，以及 CUE 文本的编码判定。
///
/// **为什么需要它**：网盘上的无损专辑大量是「整轨 + CUE」—— 一个 72 分钟的
/// WAV 装着整张 CD，配一个 `.cue` 描述每首歌从第几分几秒开始。
/// 没有 CUE，这张专辑在曲库里就是「1 首 72 分钟的歌」，用户选不了单曲、
/// 也没法随机到其中某一首。CUE 的真正价值不是「多认一个文件类型」，
/// 而是**把一个不可导航的整轨变成 N 首能点、能收藏、能随机的歌**。
///
/// 解析器刻意做成纯函数、不依赖 Flutter 与网络，因此可以拿真实 CUE 文本
/// 直接跑单元测试（见 `test/core/cue_sheet_test.dart`）。
library;

import 'text_encoding.dart';

/// CUE 里一个 `FILE` 块。
///
/// 一个 CUE 可能引用多个音频文件：**整轨**是「1 个 FILE + N 个 TRACK」，
/// **分轨**是「N 个 FILE，每个 1 个 TRACK」。两者的处理方式完全不同，
/// 所以要把这个结构如实解析出来，不能只看 TRACK 总数。
class CueFileRef {
  const CueFileRef({
    required this.name,
    required this.type,
    required this.trackNumbers,
  });

  /// `FILE` 指令里的文件名（相对同目录，不含路径）
  final String name;

  /// `WAVE` / `MP3` / `AIFF` …；没写时是空串
  final String type;

  /// 这个 FILE 覆盖的音轨号（1 起）
  final List<int> trackNumbers;

  int get trackCount => trackNumbers.length;

  @override
  String toString() => 'CueFileRef("$name", $type, ${trackNumbers.length} 轨)';
}

/// CUE 里的一轨（`TRACK nn AUDIO`）。
class CueTrack {
  const CueTrack({
    required this.number,
    required this.fileName,
    required this.startMs,
    this.endMs,
    this.title,
    this.performer,
    this.songwriter,
    this.isrc,
  });

  /// 音轨号（1 起）。**保留 CUE 里的原始编号**，即使中间有轨被跳过 ——
  /// 编号是用户对着 CD 封面对号入座的依据，不能重新编号。
  final int number;

  /// 所属 `FILE` 的名字
  final String fileName;

  /// 在整轨文件内的起点（毫秒），来自 `INDEX 01`
  final int startMs;

  /// 在整轨文件内的终点（毫秒）。
  ///
  /// 由**下一轨的 `INDEX 01`** 推出；同一个 FILE 的最后一轨为 `null`，
  /// 需要调用方用音频文件的真实时长补齐（见 [CueSheet.withFileEnd]）。
  final int? endMs;

  final String? title;
  final String? performer;
  final String? songwriter;
  final String? isrc;

  /// 轨长。终点未知或数据错乱（终点 ≤ 起点）时为 `null` ——
  /// 宁可显示 `--:--`，也不要拿负数当时长。
  Duration? get duration {
    final end = endMs;
    if (end == null || end <= startMs) return null;
    return Duration(milliseconds: end - startMs);
  }

  CueTrack copyWith({int? endMs}) => CueTrack(
        number: number,
        fileName: fileName,
        startMs: startMs,
        endMs: endMs ?? this.endMs,
        title: title,
        performer: performer,
        songwriter: songwriter,
        isrc: isrc,
      );

  @override
  String toString() =>
      'CueTrack($number, "$title", ${startMs}ms${endMs == null ? "" : "→${endMs}ms"})';
}

/// 一张 CUE 分轨表。
class CueSheet {
  const CueSheet({
    required this.tracks,
    required this.files,
    this.title,
    this.performer,
    this.genre,
    this.date,
    this.catalog,
    this.comment,
  });

  /// 全部音轨，跨 FILE 按出现顺序排列
  final List<CueTrack> tracks;

  final List<CueFileRef> files;

  /// 专辑名（TRACK 之外的 `TITLE`）
  final String? title;

  /// 专辑艺术家（TRACK 之外的 `PERFORMER`）
  final String? performer;

  final String? genre;
  final String? date;
  final String? catalog;
  final String? comment;

  int get trackCount => tracks.length;

  /// 是否是「整轨 + CUE」：只引用一个音频文件，且切出不止一轨。
  ///
  /// 只有一轨时不该走整轨物化 —— 那和原来的单行曲目没有区别，
  /// 白白多出一层间接。
  bool get isSingleImage => files.length == 1 && tracks.length > 1;

  /// 是否是「分轨 + CUE」：CUE 引用了多个音频文件。
  ///
  /// 这种目录里音频文件本身就是分开的，CUE 的价值只剩**更可信的元数据**
  /// （曲名、艺术家、专辑名），不该再切出虚拟曲目。
  bool get isMultiFile => files.length > 1;

  CueTrack? trackByNumber(int number) {
    for (final t in tracks) {
      if (t.number == number) return t;
    }
    return null;
  }

  /// 用某个音频文件的真实时长补上「该 FILE 最后一轨」的终点。
  ///
  /// [endMsOf] 收到 `FILE` 里的文件名，返回该文件的时长（毫秒）；
  /// 返回 `null` 表示拿不到，该轨的终点就保持未知。
  CueSheet withFileEnd(int? Function(String fileName) endMsOf) {
    final out = <CueTrack>[];
    var changed = false;
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final isLastOfFile =
          i == tracks.length - 1 || tracks[i + 1].fileName != track.fileName;
      if (!isLastOfFile || track.endMs != null) {
        out.add(track);
        continue;
      }
      final end = endMsOf(track.fileName);
      if (end == null || end <= track.startMs) {
        out.add(track);
        continue;
      }
      out.add(track.copyWith(endMs: end));
      changed = true;
    }
    if (!changed) return this;
    return CueSheet(
      tracks: out,
      files: files,
      title: title,
      performer: performer,
      genre: genre,
      date: date,
      catalog: catalog,
      comment: comment,
    );
  }

  @override
  String toString() => 'CueSheet("${title ?? "-"}", '
      '${files.length} 个文件 / ${tracks.length} 轨)';
}

/// 按 CUE 的**实际编码**解出文本。
///
/// 判定规则已经抽到 [decodeTextBytes]（歌词要用的同一套），这里只是保留
/// 原来的名字 —— 调用点与测试都在用 `decodeCueBytes`，改名的收益抵不上
/// 一次全仓库替换的风险。
///
/// 中文抓轨的 CUE 大量是 GBK：EAC / foobar2000 在中文 Windows 上默认写本地
/// 代码页。判定顺序、BOM 处理、兜底策略的完整理由见 [decodeTextBytes]。
String decodeCueBytes(List<int> bytes) => decodeTextBytes(bytes);

/// 解析 CUE 文本。认不出任何音轨时返回 `null`。
///
/// 解析是**容错**的，真实 CUE 的写法很杂：
///   - 关键字大小写不一（`track 01 audio`）；
///   - 值可能带引号也可能不带（`TITLE 红日`）；
///   - `INDEX` 可能是 `0:00:00`（分钟不补零）；
///   - 行尾 CRLF / LF 混用；
///   - 夹着 `REM` / `FLAGS` / `ISRC` / `PREGAP` 等大量无关指令。
///
/// 两条刻意的取舍：
///   - **`INDEX 00` 一律忽略**。它是 pregap（轨前静音），真正的声音从
///     `INDEX 01` 开始；按 `INDEX 00` 切会让每首歌都拖一段上一首的尾巴。
///   - **没有 `INDEX 01` 的轨直接跳过**。定位不了起点就没法播，
///     留着只会生成一条点不动的假曲目。
CueSheet? parseCue(String text) {
  if (text.trim().isEmpty) return null;

  String? albumTitle;
  String? albumPerformer;
  String? genre;
  String? date;
  String? catalog;
  String? comment;

  final files = <_MutableFile>[];
  final tracks = <_MutableTrack>[];
  _MutableFile? currentFile;
  _MutableTrack? currentTrack;

  for (final rawLine in text.split(RegExp(r'\r\n|\r|\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final sp = line.indexOf(RegExp(r'\s'));
    final keyword = (sp < 0 ? line : line.substring(0, sp)).toUpperCase();
    final rest = sp < 0 ? '' : line.substring(sp + 1);

    switch (keyword) {
      case 'REM':
        // 只认 `REM GENRE x` / `REM DATE x` / `REM COMMENT x` 这三种有结构的
        // 注释，其余 `REM` 是自由文本，没有解析价值
        final rsp = rest.indexOf(RegExp(r'\s'));
        final key = (rsp < 0 ? rest : rest.substring(0, rsp)).toUpperCase();
        final value = _unquote(rsp < 0 ? '' : rest.substring(rsp + 1));
        if (value == null) break;
        switch (key) {
          case 'GENRE':
            genre ??= value;
          case 'DATE':
            date ??= value;
          case 'COMMENT':
            comment ??= value;
        }

      case 'CATALOG':
        catalog ??= _unquote(rest);

      case 'FILE':
        final parsed = _parseFileDirective(rest);
        if (parsed == null) break;
        currentFile = _MutableFile(name: parsed.name, type: parsed.type);
        files.add(currentFile);
        // FILE 之后必须先出现 TRACK；这里清掉上一轨，避免跨 FILE 的
        // TITLE / PERFORMER 被错误地挂到上一个 FILE 的最后一轨上
        currentTrack = null;

      case 'TRACK':
        final number = int.tryParse(rest.trim().split(RegExp(r'\s')).first);
        if (number == null) break;
        currentTrack = _MutableTrack(
          number: number,
          fileName: currentFile?.name ?? '',
        );
        tracks.add(currentTrack);
        currentFile?.trackNumbers.add(number);

      case 'TITLE':
        final value = _unquote(rest);
        if (value == null) break;
        if (currentTrack != null) {
          currentTrack.title ??= value;
        } else {
          albumTitle ??= value;
        }

      case 'PERFORMER':
        final value = _unquote(rest);
        if (value == null) break;
        if (currentTrack != null) {
          currentTrack.performer ??= value;
        } else {
          albumPerformer ??= value;
        }

      case 'SONGWRITER':
        currentTrack?.songwriter ??= _unquote(rest);

      case 'ISRC':
        currentTrack?.isrc ??= _unquote(rest);

      case 'INDEX':
        final parts = rest.trim().split(RegExp(r'\s+'));
        final track = currentTrack;
        if (track == null || parts.length < 2) break;
        // 只要 INDEX 01（声音起点）；INDEX 00 是 pregap，见函数注释
        if (int.tryParse(parts[0]) != 1) break;
        final ms = _msfToMs(parts[1]);
        if (ms != null) track.startMs ??= ms;

      default:
        // FLAGS / PREGAP / POSTGAP / CDTEXTFILE / ARRANGER … 与分轨无关
        break;
    }
  }

  final parsedTracks = <CueTrack>[];
  final placed = tracks.where((t) => t.startMs != null).toList();
  for (var i = 0; i < placed.length; i++) {
    final t = placed[i];
    final next = i + 1 < placed.length ? placed[i + 1] : null;
    // 只有同一 FILE 内的下一轨才能当终点：跨 FILE 时下一轨是另一个文件的
    // 第 0 毫秒，拿它当终点会算出一个巨大的负数轨长
    final endMs = (next != null && next.fileName == t.fileName) ? next.startMs : null;
    parsedTracks.add(CueTrack(
      number: t.number,
      fileName: t.fileName,
      startMs: t.startMs!,
      endMs: endMs,
      title: t.title,
      performer: t.performer,
      songwriter: t.songwriter,
      isrc: t.isrc,
    ));
  }
  if (parsedTracks.isEmpty) return null;

  return CueSheet(
    tracks: parsedTracks,
    files: [
      for (final f in files)
        CueFileRef(name: f.name, type: f.type, trackNumbers: List.of(f.trackNumbers)),
    ],
    title: albumTitle,
    performer: albumPerformer,
    genre: genre,
    date: date,
    catalog: catalog,
    comment: comment,
  );
}

// ---------------------------------------------------------------------------
// 内部
// ---------------------------------------------------------------------------

class _MutableFile {
  _MutableFile({required this.name, required this.type});

  final String name;
  final String type;
  final List<int> trackNumbers = [];
}

class _MutableTrack {
  _MutableTrack({required this.number, required this.fileName});

  final int number;
  final String fileName;
  int? startMs;
  String? title;
  String? performer;
  String? songwriter;
  String? isrc;
}

/// `mm:ss:ff` → 毫秒。
///
/// CUE 的时间码来自 CD 的物理寻址：**1 秒 = 75 帧**，所以最后一段是
/// 75 进制而不是十进制 —— 把 `ff` 当百分秒会让每一轨都偏几十毫秒。
int? _msfToMs(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final m = int.tryParse(parts[0].trim());
  final s = int.tryParse(parts[1].trim());
  if (m == null || s == null || m < 0 || s < 0) return null;
  final f = parts.length == 3 ? (int.tryParse(parts[2].trim()) ?? 0) : 0;
  if (f < 0) return null;
  return m * 60000 + s * 1000 + (f * 1000 / 75).round();
}

/// 去掉两侧引号；空值返回 `null`。
///
/// 不带引号时**整段都当值**（`TITLE 我 爱 你` 不该被截成 `我`）。
String? _unquote(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('"')) {
    final end = v.indexOf('"', 1);
    v = end > 0 ? v.substring(1, end) : v.substring(1);
  }
  v = v.trim();
  return v.isEmpty ? null : v;
}

/// `FILE "x.wav" WAVE` / `FILE x.wav WAVE` / `FILE "x.wav"` 三种写法都认。
({String name, String type})? _parseFileDirective(String rest) {
  var v = rest.trim();
  if (v.isEmpty) return null;

  if (v.startsWith('"')) {
    final end = v.indexOf('"', 1);
    if (end < 0) return (name: v.substring(1).trim(), type: '');
    final name = v.substring(1, end).trim();
    if (name.isEmpty) return null;
    return (name: name, type: v.substring(end + 1).trim());
  }

  // 不带引号时，最后一个「不含点、不像文件名」的 token 才是类型
  final lastSp = v.lastIndexOf(RegExp(r'\s'));
  if (lastSp > 0) {
    final last = v.substring(lastSp + 1).trim();
    if (_looksLikeFileType(last)) {
      return (name: v.substring(0, lastSp).trim(), type: last);
    }
  }
  return (name: v, type: '');
}

bool _looksLikeFileType(String token) {
  if (token.isEmpty || token.contains('.')) return false;
  return RegExp(r'^[A-Za-z][A-Za-z0-9/]{1,9}$').hasMatch(token);
}
