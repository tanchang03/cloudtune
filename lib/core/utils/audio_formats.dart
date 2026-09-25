/// 音频格式识别，以及从**文件名 + 目录名**推断展示元数据。
///
/// 网盘接口不返回任何 ID3 / Vorbis 标签（夸克实测：列表接口只有
/// 文件名、体积、修改时间），所以曲名、艺术家、专辑这三样只能从
/// 命名习惯里推。推断分两层：
///
///   1. **目录级**：一个目录里的全部文件名放在一起看，判断该目录用的是
///      `艺术家 - 曲名` 还是 `曲名 - 艺术家`（见 [detectNameStyle]），
///      并从目录名里取专辑名与艺术家提示（见 [folderAlbumName] /
///      [folderArtistHint]）。
///   2. **单文件级**：按上面定下的约定拆分单个文件名（见 [splitTrackName]）。
///
/// 为什么必须分两层：`群星 - 古惑仔最强精选集/爱情岁月 - 郑伊健.flac` 这种
/// 精选集里，连字符**左边是曲名、右边才是艺术家**，与常见的
/// `周杰伦 - 晴天` 正好相反。只看单个文件名无法区分这两种情况；
/// 但同一个目录里「重复出现的那一侧」几乎总是艺术家 —— 这个信号很稳。
library;

/// 有损 / 无损 / DSD / 环绕等常见音频扩展名
const Set<String> kAudioExtensions = {
  // 常见
  'mp3', 'flac', 'm4a', 'aac', 'wav', 'ape', 'ogg', 'wma', 'opus',
  // 高解析 / DSD
  'dsf', 'dff', 'aif', 'aiff', 'alac', 'tak', 'wv', 'tta',
  // 环绕 / 容器
  'dts', 'ac3', 'mp4a', 'mka',
};

/// 需要额外提示「体积偏大」的扩展名（实测这类文件普遍超过网盘体积上限）
const Set<String> kHighResExtensions = {
  'dsf', 'dff', 'wav', 'aiff', 'aif',
};

/// 取小写扩展名，无扩展名返回空串。
String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// 是否为音频文件。
bool isAudioFile(String fileName, {String? mimeType}) {
  if (kAudioExtensions.contains(extensionOf(fileName))) return true;
  final mime = (mimeType ?? '').toLowerCase();
  return mime.startsWith('audio/');
}

/// 是否为高解析格式。
bool isHighRes(String fileName) =>
    kHighResExtensions.contains(extensionOf(fileName));

/// CUE 分轨表扩展名。
const String kCueExtension = 'cue';

/// 是否为 CUE 分轨表。
///
/// CUE **刻意不进 [kAudioExtensions]**：它本身不是音频，混进去会让「曲目数」
/// 虚增、也会让可播性判定把它当成一首播不了的歌。扫描器需要单独认它 ——
/// 认出来是为了**读它的内容去描述别的音频文件**，不是为了把它当曲目。
bool isCueFile(String fileName) => extensionOf(fileName) == kCueExtension;

// ---------------------------------------------------------------------------
// 音质规格（格式家族 + 平均码率）
// ---------------------------------------------------------------------------

/// 音质家族：按**编码方式**给音频分档。
///
/// 为什么要有这个概念：网盘接口只给「文件名 / 体积 / 时长」，
/// 既没有码率也没有采样率 —— 夸克列目录实测 51 个字段，一个音质字段都没有。
/// 所以「这首是什么音质」只能推：**扩展名回答「无损还是有损」，
/// 体积÷时长回答「有损里是 320 还是 128」**，两者合起来才够用。
enum AudioQuality {
  /// DSD（`.dsf` / `.dff`）。1bit 超高采样，规格上高于 PCM 无损。
  dsd,

  /// 无损压缩（`.flac` / `.ape` / `.wv` / `.tak` / `.tta`，以及 ALAC）。
  lossless,

  /// 未压缩 PCM（`.wav` / `.aiff` / `.aif`）。体积大，但仍是普通 PCM 采样。
  uncompressed,

  /// 有损压缩（`.mp3` / `.aac` / `.m4a` / `.ogg` / `.opus` / `.wma`）。
  lossy,

  /// 多声道封装（`.dts` / `.ac3` / `.mka`），多半是影视伴音而非音乐。
  surround,

  /// 认不出来。
  unknown,
}

/// 扩展名 → 音质家族。**容器自证得清楚的那部分**都写在这里。
///
/// 故意不放进来的两类：
///   - `.m4a` / `.mp4a`：同一容器既可能装 AAC（有损）也可能装 ALAC（无损），
///     光看扩展名分不出来，交给 [audioQualityOf] 用码率补判；
///   - `.mp3` 之类「有损但档位差别巨大」的：家族只能说是「有损」，
///     具体 320 还是 128 靠码率，不在这里硬编。
const Map<String, AudioQuality> _qualityByExtension = {
  // DSD
  'dsf': AudioQuality.dsd,
  'dff': AudioQuality.dsd,
  // 无损压缩
  'flac': AudioQuality.lossless,
  'alac': AudioQuality.lossless,
  'ape': AudioQuality.lossless,
  'wv': AudioQuality.lossless,
  'tak': AudioQuality.lossless,
  'tta': AudioQuality.lossless,
  // 未压缩 PCM
  'wav': AudioQuality.uncompressed,
  'aiff': AudioQuality.uncompressed,
  'aif': AudioQuality.uncompressed,
  // 有损
  'mp3': AudioQuality.lossy,
  'aac': AudioQuality.lossy,
  'ogg': AudioQuality.lossy,
  'opus': AudioQuality.lossy,
  'wma': AudioQuality.lossy,
  // 多声道封装
  'dts': AudioQuality.surround,
  'ac3': AudioQuality.surround,
  'mka': AudioQuality.surround,
  // 注意：`mp4a` **不在这里**。它和 `m4a` 是同一个容器，
  // 要按码率分 AAC / ALAC，所以由 [audioQualityOf] 的分支处理。
  // 早先在这里写了 `'mp4a': surround`，但那行永远走不到 ——
  // 表里的项被前面的分支挡住，就是一段会误导后来人的死代码。
};

/// ALAC 的平均码率下限（kbps）。
///
/// 无损压缩再差也接近 CD 的 900kbps 量级（44.1kHz/16bit 立体声未压缩 = 1411，
/// 压完通常 700~1000）；AAC 极少超过 512。取 900 做分界，两边都不会误伤。
const int kAlacMinKbps = 900;

/// 判定音质家族。
///
/// [bitrateKbps] 只在**容器无法自证**时才起作用：`.m4a` 里装 AAC 还是有损的
/// ALAC 光看名字分不出，而这两种对用户的意义完全不同（一个能转存、一个值得留），
/// 所以用 [averageBitrateKbps] 算出的平均码率补一刀。
/// 传 `null`（拿不到时长）时按更常见的 AAC 算，即「有损」。
AudioQuality audioQualityOf(String fileName, {int? bitrateKbps}) {
  final ext = extensionOf(fileName);
  if (ext == 'm4a' || ext == 'mp4a') {
    final kbps = bitrateKbps;
    if (kbps != null && kbps >= kAlacMinKbps) return AudioQuality.lossless;
    return AudioQuality.lossy;
  }
  return _qualityByExtension[ext] ?? AudioQuality.unknown;
}

/// 展示用的格式标签：大写扩展名。
///
/// 认不出扩展名时返回 `音频` 而不是空串或 `未知` —— 能走到这一行的曲目
/// 一定是靠 MIME（`audio/*`）被判成音频的，说「音频」比说「未知」诚实。
String formatLabelOf(String fileName) {
  final ext = extensionOf(fileName);
  return ext.isEmpty ? '音频' : ext.toUpperCase();
}

/// 平均码率（kbps）= 体积 × 8 ÷ 时长。
///
/// 单位推演：`字节 × 8 = 比特`，`比特 ÷ 秒 = bps`，再 ÷1000 得 kbps；
/// 而 `毫秒 ÷ 1000 = 秒`，两个 1000 正好约掉，所以直接用
/// `字节 × 8 ÷ 毫秒` 就是 kbps，不需要中间换算。
///
/// 实测校验（2026-09-24）：夸克上 `李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav`
/// 体积 765145628 字节、时长 4338 秒 → 算出 **1411 kbps**，
/// 正是 CD 音质（44.1kHz / 16bit / 立体声）的标准码率，说明这个推法与真值吻合。
///
/// ⚠️ 它是**平均值**，不是文件头里写的规格：
///   - CBR 的 mp3 上它就等于标称码率；
///   - VBR 的 mp3 / 所有无损格式上，它是「这段时间里平均每秒塞了多少数据」，
///     只能用来判断量级（320 还是 128、是不是 24/96 的母带），不能当精确参数。
///
/// 体积或时长任一缺失/非正时返回 `null` —— 宁可什么都不显示，
/// 也不要拿一个用 0 除出来的假数字去误导用户。
int? averageBitrateKbps({int? sizeBytes, int? durationMs}) {
  if (sizeBytes == null || sizeBytes <= 0) return null;
  if (durationMs == null || durationMs <= 0) return null;
  final kbps = sizeBytes * 8 / durationMs;
  if (kbps <= 0 || !kbps.isFinite) return null;
  return kbps.round();
}

// ---------------------------------------------------------------------------
// 文件名解析
// ---------------------------------------------------------------------------

/// 开头的音轨号：`01. `、`01 - `、`01_`、`1. `
final RegExp _trackNoPrefix = RegExp(r'^\d{1,3}\s*[.\-_]\s*');

/// 两侧**带空格**的连字符（`艺术家 - 曲名`）。没空格时不拆，见 [splitTrackName]。
final RegExp _spacedSeparator = RegExp(r'\s+[-–—]\s+');

/// 裸连字符（`任素汐-别来无恙`）。只有在目录里多个文件都这么命名时才敢用。
final RegExp _bareSeparator = RegExp(r'[-–—]');

/// 左侧超过这个长度就不当人名 —— 否则整句文案会被误认成艺术家。
const int _maxArtistLength = 40;

/// 名字两侧可能残留的分隔符。
///
/// 真实库里就有 `刘德华.-.[你是我的骄傲演唱会 CD1](2002)[WAV].wav` ——
/// 在连字符上拆开后，艺术家是 `刘德华.`、曲名开头多一个 `.`，两边都得修。
final RegExp _edgeSeparators = RegExp(r'^[\s.\-–—_·]+|[\s.\-–—_·]+$');

String _trimSeparators(String s) => s.replaceAll(_edgeSeparators, '').trim();

/// 至少含一个中文 / 拉丁字母 / 数字，用来挡掉 `》` 这种纯标点。
bool _hasContent(String s) =>
    RegExp(r'[A-Za-z0-9\u4e00-\u9fff]').hasMatch(s);

/// 一段文本像不像「艺术家」。
///
/// **只在从目录名猜艺术家时使用**，不用在文件名解析上 ——
/// 文件名那一侧有整个目录的重复度做判据，比这个启发式可靠得多，
/// 而且这里「连续 4 个以上拉丁字母即否决」的规则会误伤
/// `The Beatles` 这类西文人名。
bool _looksLikeArtistName(String s) {
  final v = s.trim();
  if (v.isEmpty || v.length > 24) return false;
  // `张学友.2018《真情流露》HQ+S` —— 整张专辑被当成人名
  if (RegExp(r'[《》【】（）()\[\]]').hasMatch(v)) return false;
  if (RegExp(r'\d').hasMatch(v)) return false;
  if (RegExp(r'[A-Za-z]{4,}').hasMatch(v)) return false;
  return true;
}

/// 去掉扩展名与开头的音轨号，得到用于解析的主干。
String trackStem(String fileName) {
  var base = fileName;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  return base.replaceFirst(_trackNoPrefix, '').trim();
}

/// 文件名里 `-` 两侧的排列约定。
enum NameOrder {
  /// `艺术家 - 曲名`（最常见）
  artistFirst,

  /// `曲名 - 艺术家`（精选集、合辑里常见）
  titleFirst,
}

/// 一个目录内文件名的命名约定。
class NameStyle {
  const NameStyle({
    this.order = NameOrder.artistFirst,
    this.bareHyphen = false,
  });

  final NameOrder order;

  /// 是否允许在**不带空格**的连字符上拆分。
  ///
  /// 单文件无法判断 `Love-Me-Tender` 是曲名还是 `艺术家-曲名`，
  /// 所以默认不拆；只有同目录里多个文件都这么写时才打开。
  final bool bareHyphen;

  /// 没有目录上下文时的保守默认：按通用约定，且不拆裸连字符。
  static const NameStyle fallback = NameStyle();

  @override
  String toString() => 'NameStyle(${order.name}, bareHyphen: $bareHyphen)';
}

/// 从**一个目录内的全部文件名**推断命名约定。
///
/// 判据：连字符某一侧的取值种类更少，那一侧就是艺术家
/// （同一位歌手往往占满整张专辑，而曲名几乎不重复）。
/// 样本不足 2 条时不敢下结论，退回 [NameStyle.fallback]。
///
/// 先试带空格的分隔符；一个都没有时才退到裸连字符 ——
/// 否则 `Love-Me-Tender` 这类曲名会被误拆。
NameStyle detectNameStyle(Iterable<String> fileNames) {
  final names = fileNames.toList();

  for (final bare in const [false, true]) {
    final lefts = <String>{};
    final rights = <String>{};
    var pairs = 0;

    for (final name in names) {
      final base = trackStem(name);
      final match = _spacedSeparator.firstMatch(base) ??
          (bare ? _bareSeparator.firstMatch(base) : null);
      if (match == null) continue;

      final left = _trimSeparators(base.substring(0, match.start));
      final right = _trimSeparators(base.substring(match.end));
      if (left.isEmpty || right.isEmpty) continue;
      if (left.length > _maxArtistLength || right.length > _maxArtistLength) {
        continue;
      }
      pairs++;
      lefts.add(left);
      rights.add(right);
    }

    if (pairs < 2) continue; // 样本太少，不足以判断

    final order = rights.length < lefts.length
        ? NameOrder.titleFirst
        : NameOrder.artistFirst;
    return NameStyle(order: order, bareHyphen: bare);
  }

  return NameStyle.fallback;
}

/// 按已知约定拆分单个文件名。
///
/// 解析不出来时曲名退化为去掉扩展名（与音轨号）的文件名。
({String title, String? artist}) splitTrackName(
  String fileName, [
  NameStyle style = NameStyle.fallback,
]) {
  final base = trackStem(fileName);
  final match = _spacedSeparator.firstMatch(base) ??
      (style.bareHyphen ? _bareSeparator.firstMatch(base) : null);
  if (match == null) return (title: base, artist: null);

  final left = _trimSeparators(base.substring(0, match.start));
  final right = _trimSeparators(base.substring(match.end));
  if (left.isEmpty || right.isEmpty) return (title: base, artist: null);

  final titleFirst = style.order == NameOrder.titleFirst;
  final artist = titleFirst ? right : left;
  final title = titleFirst ? left : right;

  // 被当成艺术家的那一侧过长时，多半是整句文案，放弃拆分
  if (artist.length > _maxArtistLength) {
    return (title: base, artist: null);
  }
  return (title: title, artist: artist);
}

/// 从文件名猜测曲名与艺术家（**无目录上下文**的保守版本）。
///
/// 只在拿不到同目录其它文件名时使用，例如播放列表里临时构造的曲目。
/// 有目录信息时应该走 `LibraryGrouping.deriveMetadata`，
/// 它能识别 `曲名 - 艺术家` 这种反向命名。
({String title, String? artist}) guessTitleArtist(String fileName) =>
    splitTrackName(fileName);

// ---------------------------------------------------------------------------
// 目录名解析
// ---------------------------------------------------------------------------

/// 方括号片段：`[16B-44.1kHz]`、`【WAV+CUE】`
final RegExp _bracketGroup = RegExp(r'[\[【]([^\]】]*)[\]】]');

/// 圆括号片段：`(FLAC 24bit 48khz)`、`(2025 Remastered)`
final RegExp _parenGroup = RegExp(r'[（(]([^）)]*)[）)]');

/// 目录名里「艺术家 - 专辑」的分隔符。
///
/// 三种写法都要认：
///   - `周华健 - 小天堂`         一般的 ` - `
///   - `群星.2016 -《鉴听天碟》` 连字符直接贴着书名号
///   - `蔡琴《试音蔡琴》`         连「艺术家.年份」和书名号之间什么都没有
final RegExp _folderSeparator =
    RegExp(r'\s+[-–—]\s+|\s*[-–—]?\s*(?=[《【])');

/// 结尾的年份：`周华健 - 小天堂(...) - 1996`、`李克勤.2014-《...》`、
/// `香港群星 - 你不能没听过的粤语金曲 2026`
///
/// 连字符/点号是可选的 —— 年份和名字之间常常只有一个空格。
final RegExp _trailingYear = RegExp(r'\s*[-–—.]?\s*(?:19|20)\d{2}\s*$');

/// 明确的音质 / 格式词。**只用于判断括号片段是不是噪声**，
/// 所以刻意不含 `remaster`、`live`、`deluxe` 这类版本信息 ——
/// `(2025 Remastered)` 是专辑身份的一部分，不该被抹掉。
///
/// 也刻意不含 `cd`：`[你是我的骄傲演唱会 CD1]` 里的 `CD1` 是「第 1 张碟」，
/// 抹掉会把整段演唱会名一起删掉。单纯的 `[CD]` 由「短标记」规则兜住。
const List<String> _noiseWords = [
  // 拉丁
  'flac', 'wav', 'ape', 'dsf', 'dff', 'aif', 'aiff', 'alac', 'sacd', 'xrcd',
  'mp3', 'm4a', 'tak', 'wv', 'tta', 'cue', 'log', 'bit', 'khz', 'kbps', 'hz',
  'hires', 'hi-res', 'hq',
  // 中文
  '母带', '臻品', '无损', '原抓', '分轨', '整轨', '首版', '引进版', '银合金',
];

/// 结尾处可以整段丢掉的格式词（`... 1996   Flac` 里的 `Flac`）
///
/// 裸数字那一支刻意排除了 4 位年份：`... - 1996` 应该整段（含连字符）
/// 交给 [_trailingYear] 处理，否则会剩下一个孤零零的 ` -`。
///
/// 末尾允许带一个多余的右括号 —— 真实目录里就有
/// `... FLAC Hi-Res 24bit 48khz)+192khz` 这种括号没配平的写法。
final RegExp _formatTailToken = RegExp(
  r'^(?:(?!\d{4}$)\d+\s*(?:b|bit|khz|kbps|hz)?|\d+cd|'
  r'flac|wav|ape|dsf|dff|aiff?|alac|mp3|m4a|tak|wv|tta|sacd|xrcd|cue|log|'
  r'hi-?res|hq|母带|臻品|臻品母带|无损|原抓|分轨|整轨)[)\]]*$',
  caseSensitive: false,
);

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

/// 数字紧贴在右括号后面的尾巴：`Über den Wolken(qobuz)24 48` 里的 `24`。
///
/// 它和前面的括号粘成一个 token，按空格切不出来，得单独认一次。
final RegExp _trailingParenNumber = RegExp(r'\)\s*\d+\s*$');

bool _hasCjk(String s) => _cjk.hasMatch(s);

/// 括号里的内容是否只是音质 / 格式噪声。
bool _isNoise(String inner) {
  final low = inner.toLowerCase().trim();
  if (low.isEmpty) return true;
  if (RegExp(r'^\d{4}$').hasMatch(low)) return true; // 年份，如 [2023]
  if (low.length <= 2 && !_hasCjk(low)) return true; // 如 [Q]

  for (final word in _noiseWords) {
    if (_hasCjk(word)) {
      if (low.contains(word)) return true;
    } else {
      // 拉丁词要求词边界，否则 `cd` 会命中 `银合金CD` 之外的 `sacd` 之类
      final re = RegExp('(^|[^a-z])${RegExp.escape(word)}([^a-z]|\$)');
      if (re.hasMatch(low)) return true;
    }
  }
  return false;
}

/// 丢掉结尾处连续的格式词：`... - 1996   Flac` → `... - 1996`
String _stripFormatTail(String raw) {
  final parts = raw.split(' ').where((p) => p.isNotEmpty).toList();
  while (parts.length > 1) {
    final tail = parts.last;
    final chunks = tail.split(RegExp(r'[+&]')).where((c) => c.isNotEmpty);
    if (chunks.isEmpty || !chunks.every(_formatTailToken.hasMatch)) break;
    parts.removeLast();
  }
  return parts.join(' ');
}

/// 去掉命名里的音质 / 格式噪声，得到可直接展示的名称。
///
/// 目录名与解析出的曲名共用这一套清洗：两者都会被塞进
/// `[无损音质]`、`(FLAC 24bit 48khz)`、`臻品母带` 这类尾巴。
///
/// 例：`小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]`
///     → `小虎队 - 爱 (2025 Remastered)`
///     `周华健 - 小天堂(周华健&EASY BAND) - 1996   Flac`
///     → `周华健 - 小天堂(周华健&EASY BAND)`
///     `别来无恙[无损音质]` → `别来无恙`
String cleanDisplayName(String raw) {
  var s = raw.replaceAllMapped(
    _bracketGroup,
    (m) => _isNoise(m.group(1)!) ? ' ' : m.group(0)!,
  );
  s = s.replaceAllMapped(
    _parenGroup,
    (m) => _isNoise(m.group(1)!) ? ' ' : m.group(0)!,
  );

  // 格式尾巴与年份会交替出现（`... - 1996   Flac`、`...   Flac - 1996`），
  // 剥掉一层可能又露出下一层，所以剥到稳定为止，不能只走一遍。
  // 每轮都严格变短，因此一定会终止。
  var changed = true;
  while (changed) {
    changed = false;
    final collapsed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final cleaned = _stripFormatTail(collapsed)
        .replaceFirst(_trailingParenNumber, ')')
        .replaceFirst(_trailingYear, '')
        .trim();
    if (cleaned != s) {
      s = cleaned;
      changed = true;
    }
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 目录名 → `(艺术家, 专辑)`。推不出来返回 `null`。
///
/// 两种写法都认：
///   - `周华健 - 小天堂(周华健&EASY BAND)` → `('周华健', '小天堂(周华健&EASY BAND)')`
///   - `周传雄 烟雨平生`（空格分两段）      → `('周传雄', '烟雨平生')`
///
/// 两种都要求「左边真的像个人名」—— 目录名里塞整张专辑信息的写法太常见
/// （`张学友.2018《真情流露》HQ+S 纯银深度`），不设这道闸就会把专辑当歌手。
(String, String)? _splitFolderName(String folderName) {
  final cleaned = cleanDisplayName(folderName);
  if (cleaned.isEmpty) return null;

  final match = _folderSeparator.firstMatch(cleaned);
  if (match != null) {
    // 先把 `群星.2016` 这种尾巴上的年份去掉再判断像不像人名
    final left = _trimSeparators(
      cleaned.substring(0, match.start).replaceFirst(_trailingYear, ''),
    );
    final right = cleaned.substring(match.end).trim();
    if (_looksLikeArtistName(left) && _hasContent(right)) return (left, right);
  }

  // 没有连字符时，`艺术家 专辑` 这种两段式命名很常见；三段以上不敢猜
  final tokens = cleaned.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.length == 2 &&
      _looksLikeArtistName(tokens[0]) &&
      _hasContent(tokens[1])) {
    return (tokens[0], tokens[1]);
  }

  return null;
}

/// 目录名 → 艺术家提示；推断不出返回 `null`。
///
/// 只作为**兜底**：文件名里已经解析出艺术家时以文件名为准
/// （合辑目录叫 `群星`，不能拿它当每首歌的艺术家）。
String? folderArtistHint(String folderName) {
  final parts = _splitFolderName(folderName);
  if (parts == null) return null;
  final hint = _trimSeparators(parts.$1);
  return hint.isEmpty ? null : hint;
}

/// 目录名 → 专辑展示名；目录名为空时返回 `null`。
///
/// 推不出「艺术家 - 专辑」结构时，整段清洗后的目录名就是专辑名 ——
/// 对单曲合集（如 `凤凰传奇(FLAC 24bit 192khz)`）来说这是最好的答案。
String? folderAlbumName(String folderName) {
  final cleaned = cleanDisplayName(folderName);
  if (cleaned.isEmpty) return null;
  final parts = _splitFolderName(folderName);
  if (parts != null && parts.$2.trim().isNotEmpty) return parts.$2.trim();
  return cleaned;
}

/// 路径里最后一段目录名，`/a/b/` 与 `/a/b` 都返回 `b`；没有目录返回空串。
String lastPathSegment(String? path) {
  final p = (path ?? '').trim();
  if (p.isEmpty) return '';
  final segments = p.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.last;
}

/// 归一化目录路径：去掉结尾斜杠，便于当分组的稳定键。
String normalizeDirPath(String? path) {
  final p = (path ?? '').trim();
  if (p.isEmpty) return '';
  return p.endsWith('/') ? p.substring(0, p.length - 1) : p;
}
