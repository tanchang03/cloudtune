/// LRC 歌词解析。
///
/// **为什么值得单独写一个解析器**：网盘里的歌词文件是用户自己丢进去的，
/// 来源五花八门（千千静听、foobar2000、各种「歌词下载器」），写法比 CUE 还杂。
/// 但它同时也是**唯一一种能跟着播放位置走**的歌词格式 —— 没有时间轴就只能在
/// 旁边摆一坨文本。所以这里的目标是：能解析出时间轴的一律解析出来，
/// 实在没有时间轴的才退化成纯文本。
///
/// 纯函数、不依赖 Flutter 与网络，可以拿真实歌词文本直接跑单测
/// （见 `test/core/lrc_test.dart`）。
library;

/// 一行带时间轴的歌词。
class LrcLine {
  const LrcLine({required this.at, required this.text});

  /// 这一行该在什么时候被点亮。已包含 `[offset:]` 的修正。
  final Duration at;

  /// 歌词正文。**允许为空串** —— `[00:12.34]` 单独一行是「间奏」的常见写法，
  /// 抹掉它会让后面所有行提前，还不如照实保留一个空行。
  final String text;

  @override
  String toString() => 'LrcLine(${at.inMilliseconds}ms, "$text")';
}

/// 一份解析后的歌词。
class LrcDocument {
  const LrcDocument({
    this.lines = const [],
    this.plainText,
    this.title,
    this.artist,
    this.album,
    this.offsetMs = 0,
  });

  /// 按时间升序排列的歌词行。没有时间轴时为空。
  final List<LrcLine> lines;

  /// **没有任何时间轴**时的兜底：整份文本按原样保留（已去掉标签行）。
  ///
  /// 与 [lines] 互斥地表达「这份歌词能不能跟着播放走」：有 [lines] 就能，
  /// 只有 [plainText] 就只能在界面上静态展示。
  final String? plainText;

  /// `[ti:]`
  final String? title;

  /// `[ar:]`
  final String? artist;

  /// `[al:]`
  final String? album;

  /// `[offset:]` 标签的原始值（毫秒）。
  ///
  /// **它已经应用在 [lines] 的时间上了**，这里再留一份只是为了让诊断日志与
  /// 测试能断言「这个偏移确实被读到了」。不要拿它再算一次。
  final int offsetMs;

  /// 有没有时间轴（即能不能跟着播放位置高亮）。
  bool get isSynced => lines.isNotEmpty;

  bool get isEmpty =>
      lines.isEmpty && (plainText == null || plainText!.trim().isEmpty);

  bool get isNotEmpty => !isEmpty;

  static const LrcDocument empty = LrcDocument();

  /// 在 [position] 这一刻应当高亮的行下标；还没到第一行时返回 `-1`。
  ///
  /// 用二分而不是线性扫描：播放位置每帧都在变，而歌词可能有几百行。
  ///
  /// 返回「最后一个 `at <= position` 的行」而不是「最接近的一行」：
  /// 歌词是**从某时刻起一直有效**的，不是只在那一刻闪一下。
  int lineIndexAt(Duration position) {
    final ms = position.inMilliseconds;
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].at.inMilliseconds <= ms) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  @override
  String toString() => 'LrcDocument(${lines.length} 行'
      '${plainText == null ? "" : "，纯文本 ${plainText!.length} 字"}'
      '${offsetMs == 0 ? "" : "，offset ${offsetMs}ms"})';
}

/// 行首连续的 `[xxx]` 标签。
final RegExp _tagRe = RegExp(r'\[([^\]]*)\]');

/// 时间戳标签的内容：`mm:ss`、`mm:ss.xx`、`mm:ss.xxx`。
///
/// 分钟允许 1~3 位（演唱会歌词能超过 100 分钟），秒必须 1~2 位，
/// 小数部分 1~3 位（1 位 = 100ms，2 位 = 10ms，3 位 = 1ms）。
/// 分隔符 `.` 与 `:` 都认 —— 两种写法在真实文件里都常见。
final RegExp _timestampRe = RegExp(r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$');

/// 元数据标签：`[ti:晴天]`、`[offset:+500]`。
///
/// 键必须以字母开头，这条限制正是它和时间戳的分界线：`[00:12.34]`
/// 的键是 `00`，永远落不进这个正则。
final RegExp _metaRe = RegExp(r'^([A-Za-z][A-Za-z0-9_#-]*)\s*:\s*(.*)$');

/// 增强型 LRC 的词级时间标签：`<00:12.34>`。
///
/// 解析器只做**行级**高亮，所以这些标签要抹掉，否则会原样显示成
/// `<00:12.34>故<00:12.90>事`。
final RegExp _wordTimingRe = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

/// 解析一份 LRC 文本。
///
/// 容错优先，永不抛异常：认不出时间轴就退化成 [LrcDocument.plainText]，
/// 连正文都没有才返回 [LrcDocument.empty]。
///
/// 认下来的写法：
///   - 行首**多个**时间戳共用一个正文（`[00:12.34][01:20.00]副歌`）——
///     会展开成多行，这是副歌歌词的标准写法，不展开就会只显示一遍；
///   - 元数据 `[ti:]` / `[ar:]` / `[al:]` / `[offset:]`；
///   - 增强型 LRC 的词级标签（抹掉）；
///   - CRLF / CR / LF 混用、UTF-8 BOM。
///
/// 刻意的取舍：
///   - **`[offset:]` 会真的应用到时间上**（`at = 标签时间 - offset`，即正值让
///     歌词**提前**出现）。这是 foobar2000 / QQ音乐 / 网易云一致的读法。
///     这个标签很少见，但一旦出现，不应用就会整首歌词系统性偏移，
///     比读错方向还难发现。
///   - **带时间轴的行与不带时间轴的行混排时，后者被丢掉**。真实文件里
///     那些「不带时间戳的行」几乎都是文件头的说明文字（`[ti:]` 之外的
///     歌名重复、下载来源），把它们塞进时间轴只会污染显示。
LrcDocument parseLrc(String raw) {
  if (raw.trim().isEmpty) return LrcDocument.empty;

  // 行下标参与排序的并列裁决：Dart 的 `sort` 对大列表**不稳定**，
  // 同一时刻的多行（`[00:12.34][00:12.34]A` / `B`）会被打乱次序。
  final dated = <({Duration at, int order, String text})>[];
  final plain = <String>[];
  var order = 0;

  String? title;
  String? artist;
  String? album;
  var offsetMs = 0;

  for (final rawLine in raw.split(RegExp(r'\r\n|\r|\n'))) {
    var rest = rawLine.trim();
    if (rest.isEmpty) continue;

    final stamps = <Duration>[];
    var sawTag = false;

    while (true) {
      final m = _tagRe.matchAsPrefix(rest);
      if (m == null) break;
      sawTag = true;
      final inner = m.group(1)!.trim();
      final stamp = _parseTimestamp(inner);
      if (stamp != null) {
        stamps.add(stamp);
      } else {
        final meta = _metaRe.firstMatch(inner);
        if (meta != null) {
          final key = meta.group(1)!.toLowerCase();
          final value = meta.group(2)!.trim();
          switch (key) {
            case 'ti':
              title ??= value.isEmpty ? null : value;
            case 'ar':
              artist ??= value.isEmpty ? null : value;
            case 'al':
              album ??= value.isEmpty ? null : value;
            case 'offset':
              offsetMs = _parseOffset(value) ?? offsetMs;
          }
        }
      }
      rest = rest.substring(m.end).trimLeft();
    }

    // 词级标签要在取正文之前抹掉
    final text = rest.replaceAll(_wordTimingRe, '').trim();

    if (stamps.isNotEmpty) {
      for (final at in stamps) {
        dated.add((at: at, order: order++, text: text));
      }
    } else if (!sawTag && text.isNotEmpty) {
      plain.add(text);
    }
  }

  if (dated.isEmpty) {
    if (plain.isEmpty) {
      // 只有元数据、没有正文。**不能直接返回 [LrcDocument.empty]** ——
      // 那样会把刚读到的 `[ti:]` / `[ar:]` 一起丢掉，而「这首歌叫什么」
      // 恰恰是界面在「暂无歌词」时唯一还能显示的东西。
      return LrcDocument(
        title: title,
        artist: artist,
        album: album,
        offsetMs: offsetMs,
      );
    }
    return LrcDocument(
      plainText: plain.join('\n'),
      title: title,
      artist: artist,
      album: album,
      offsetMs: offsetMs,
    );
  }

  // 应用 offset：正值让歌词提前出现（见函数头注释）
  final shift = Duration(milliseconds: offsetMs);
  final lines = dated
      .map((e) {
        final at = e.at - shift;
        return (
          at: at.isNegative ? Duration.zero : at,
          order: e.order,
          text: e.text,
        );
      })
      .toList()
    ..sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });

  return LrcDocument(
    lines: [for (final l in lines) LrcLine(at: l.at, text: l.text)],
    title: title,
    artist: artist,
    album: album,
    offsetMs: offsetMs,
  );
}

/// `mm:ss(.ff)` → `Duration`。认不出返回 `null`。
Duration? _parseTimestamp(String inner) {
  final m = _timestampRe.firstMatch(inner);
  if (m == null) return null;
  final minutes = int.parse(m.group(1)!);
  final seconds = int.parse(m.group(2)!);
  final frac = m.group(3);
  var ms = 0;
  if (frac != null && frac.isNotEmpty) {
    final value = int.parse(frac);
    // 位数决定单位：`12` 是 12 厘秒（=120ms），`123` 是 123 毫秒
    ms = switch (frac.length) {
      1 => value * 100,
      2 => value * 10,
      _ => value,
    };
  }
  return Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
}

/// `[offset:]` 的值，允许带正负号。认不出返回 `null`。
int? _parseOffset(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  // 真实文件里有写 `+500ms`、`- 200` 的，宽松一点
  final m = RegExp(r'^([+-]?)\s*(\d+)').firstMatch(v);
  if (m == null) return null;
  final n = int.tryParse(m.group(2)!);
  if (n == null) return null;
  return m.group(1) == '-' ? -n : n;
}
