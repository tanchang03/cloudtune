import '../../core/utils/audio_formats.dart';
import '../entities/drive_entry.dart';
import '../entities/drive_provider.dart';
import '../entities/lyrics.dart';
import '../entities/track.dart';

/// 一个目录的本地歌词索引结果。
class LyricsIndexResult {
  const LyricsIndexResult({this.matches = const []});

  /// 每个元素都是一条**只有引用、没有正文**的歌词（`content == null`），
  /// 由扫描器落库；正文等这首歌被播放时再去读。
  final List<Lyrics> matches;

  bool get isEmpty => matches.isEmpty;

  @override
  String toString() => 'LyricsIndexResult(${matches.length} 首)';
}

/// 把一个目录里的 `.lrc` 文件对上这个目录里的曲目。
///
/// **为什么不能简单地「同名即匹配」**：网盘里的歌词文件名和音频文件名
/// 对不上的情况太常见了 ——
///   - 一边带音轨号一边不带（`01. 晴天.lrc` vs `晴天.flac`）；
///   - 一边带 `[无损]` / `(Live)` 之类的尾巴；
///   - 整轨 CUE 专辑里音频只有一个 `专辑.wav`，歌词却是一首一个文件。
/// 只认完全相等会让一大批本来能用的歌词白白浪费，而**猜错比猜不到更糟** ——
/// 显示别人的歌词看起来像应用坏了。所以这里按「从严到宽」分档打分，
/// 只在有把握的档位上认领。
///
/// 纯函数、不碰 IO，可以拿真实文件名直接跑单测
/// （见 `test/domain/lyrics_indexer_test.dart`）。
class LyricsIndexer {
  const LyricsIndexer();

  /// 打分档位。**数字越小越可信。**
  static const int scoreExact = 0;
  static const int scoreTitle = 1;
  static const int scoreTrackNo = 2;
  static const int scoreContains = 3;

  /// 兜底：整个目录只有一个 `.lrc`、只有一首曲目。
  static const int scoreSolePair = 9;

  static const int noMatch = 1 << 30;

  /// 匹配一个目录。
  ///
  /// [tracks] 必须是这个目录**最终的**曲目列表 —— 也就是 CUE 展开**之后**的
  /// 结果。整轨被切成 N 段之后，歌词是按段落的，拿展开前的「一首 72 分钟」
  /// 去匹配等于把整张专辑的歌词塞给一个不存在的曲目。
  ///
  /// [lrcFiles] 是这个目录下的 `.lrc` 条目（非 `.lrc` 会被忽略）。
  ///
  /// 一个曲目最多认领一份歌词，一份歌词最多给一个曲目：多个 `.lrc` 抢同一首
  /// 时留下得分更高的那个（同分则按文件名序，保证结果确定）。
  LyricsIndexResult indexDirectory({
    required DriveProvider provider,
    required List<Track> tracks,
    required List<DriveEntry> lrcFiles,
  }) {
    if (tracks.isEmpty) return const LyricsIndexResult();

    final files = lrcFiles
        .where((e) => !e.isDirectory && isLrcFile(e.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (files.isEmpty) return const LyricsIndexResult();

    final claims = <String, ({Lyrics lyrics, int score})>{};

    for (final file in files) {
      final stem = _stemOf(file.name);
      if (stem.isEmpty) continue;
      final no = leadingTrackNo(file.name);

      Track? best;
      var bestScore = noMatch;
      for (final t in tracks) {
        final score = _score(stem: stem, trackNo: no, track: t);
        if (score < bestScore) {
          best = t;
          bestScore = score;
        }
      }
      if (best == null) continue;

      final existing = claims[best.id];
      // 同分时保留先来的（files 已按文件名排序，所以是确定的）
      if (existing != null && existing.score <= bestScore) continue;

      claims[best.id] = (
        lyrics: Lyrics(
          trackId: best.id,
          provider: provider,
          source: LyricsSource.local,
          fileId: file.id,
          fileName: file.name,
          sizeBytes: file.sizeBytes,
        ),
        score: bestScore,
      );
    }

    // 兜底：目录里只有一个 `.lrc`、只有一首歌，那就别管名字了。
    // 这是 `lyrics.lrc` / `歌词.lrc` 这类通用名的唯一出路 ——
    // 没有歧义可言（只有一首歌），认下来只会更准。
    if (claims.isEmpty && tracks.length == 1 && files.length == 1) {
      final file = files.single;
      final track = tracks.single;
      claims[track.id] = (
        lyrics: Lyrics(
          trackId: track.id,
          provider: provider,
          source: LyricsSource.local,
          fileId: file.id,
          fileName: file.name,
          sizeBytes: file.sizeBytes,
        ),
        score: scoreSolePair,
      );
    }

    if (claims.isEmpty) return const LyricsIndexResult();
    return LyricsIndexResult(matches: [for (final c in claims.values) c.lyrics]);
  }

  /// 一个 `.lrc` 对一首曲目的匹配分。认不出返回 [noMatch]。
  static int _score({
    required String stem,
    required int? trackNo,
    required Track track,
  }) {
    // 整轨分段**不参与按文件名匹配**：同一张整轨切出的 N 段共用同一个
    // `name`（就是那个 `专辑.wav`），拿它做任何比较都会同时命中 N 段。
    // 而「整张专辑的歌词文件」被认领到第 1 段之后，用户切到第 5 段时
    // 会看到第 1 段的歌词 —— 那比没有歌词更像故障。
    //
    // 分段的身份只在 `displayTitle`（CUE 里的 TITLE）与轨号上。
    if (!track.isCueSegment) {
      final name = _stemOf(track.name);
      if (name.isNotEmpty && name == stem) return scoreExact;
    }

    final title = _norm(track.displayTitle);
    if (title.isNotEmpty && title == stem) return scoreTitle;

    // CUE 分段按轨号认领：`05 - 歌名.lrc` 里的 5 对得上第 5 轨。
    // 非 CUE 曲目没有轨号，这一档对它们永远不成立。
    final no = track.cueTrackNo;
    if (no != null && trackNo != null && no == trackNo) return scoreTrackNo;

    if (!track.isCueSegment) {
      if (_eitherContains(stem, _stemOf(track.name))) return scoreContains;
    }
    if (_eitherContains(stem, title)) return scoreContains;

    return noMatch;
  }

  /// 一方包含另一方（且短的那一方够「有信息量」）。
  ///
  /// 「够长」这条闸不能只数字符个数：**两个汉字就是一个完整的曲名**
  /// （`晴天`、`红豆`、`后来`、`浮夸` —— 华语歌里绝大多数就是两三个字），
  /// 而两个拉丁字母什么都不是（`A.lrc` 会命中 `Adele - Hello`）。
  /// 所以按「汉字按字算、拉丁按字母算」分别设下限。
  static bool _eitherContains(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final short = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;

    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(short);
    if (hasCjk) {
      if (short.length < 2) return false; // 单个汉字太容易巧合
    } else if (short.length < 4) {
      return false; // 拉丁文至少要 4 个字母
    }
    return long.contains(short);
  }

  /// 归一化：小写、去掉空白与各种括号，用于**比较**。
  ///
  /// 去括号是因为真实文件名里的 `[无损]` / `(Live)` / `【HQ】` 在音频和歌词
  /// 两边常常不一致 —— 一边有一边没有。它们对「这是不是同一首歌」没有信息量。
  static final RegExp _noise = RegExp(r'[\s\[\]【】（）()·・]+');

  static String _norm(String s) => s.toLowerCase().replaceAll(_noise, '');

  /// 归一化后的文件名主干（已去掉扩展名与开头的音轨号）
  static String _stemOf(String fileName) => _norm(trackStem(fileName));

  /// 文件名开头的音轨号，如 `05 - 歌名.lrc` → `5`。没有返回 `null`。
  ///
  /// 刻意**只认一到三位数字 + 分隔符**：
  ///   - `1 歌.lrc` 没有分隔符，不算（分不清是轨号还是曲名的一部分）；
  ///   - `2024.lrc` 是四位，也不算 —— 那是个年份（`2024 年度精选`），
  ///     把它当成「第 2024 轨」不会匹配到任何曲目，但会白白抬高日志里的
  ///     噪音；真正要防的是它跟某个轨号撞上。
  static final RegExp _leadingNo = RegExp(r'^(\d{1,3})\s*[.\-_]\s*');

  static int? leadingTrackNo(String fileName) {
    var base = fileName;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final m = _leadingNo.firstMatch(base.trim());
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n <= 0) return null;
    return n;
  }
}
