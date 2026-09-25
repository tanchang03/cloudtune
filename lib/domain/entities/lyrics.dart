import '../../core/utils/lrc.dart';
import 'drive_provider.dart';

/// 歌词是从哪来的。
///
/// 两档的差别不只是「谁提供的」，还决定了**要不要把正文存下来**：
/// 本地歌词的源文件在用户自己的网盘上，随时能重读；联网歌词的源在第三方
/// 接口上（有速率限制、也会挂），重取一次成本高得多。
enum LyricsSource {
  /// 与音频同目录的 `.lrc` 文件 —— 用户自己放进网盘的
  local('local', '本地歌词'),

  /// [LRCLIB](https://lrclib.net) 联网获取
  lrclib('lrclib', 'LRCLIB');

  const LyricsSource(this.id, this.label);

  /// 落库用的稳定标识。**不要用 `name`**：枚举常量改名会静默把老数据
  /// 变成认不出的值（与 `AuthMode.id` 同一个理由）。
  final String id;

  /// 界面上显示给用户的来源说明
  final String label;

  static LyricsSource? fromId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// 一首歌的歌词。
///
/// **`content` 可以为 `null`** —— 这是本类最重要的一个状态，不是遗漏：
/// 扫描时只在网盘上**发现**了 `.lrc` 并把它对上曲目（只记引用，不读内容），
/// 真正把正文读下来发生在**这首歌第一次被播放**的时候。理由：
///   - 读歌词要发请求，而夸克的列目录/读文件接口有 QPS 限制。为了一个
///     可能永远不播的曲目在扫描阶段多发一次请求，等于把扫描时间拉长；
///   - 一首 3 分钟的歌配一个 4KB 的 `.lrc`，按需读的代价可以忽略。
///
/// 所以 `content == null` 的语义是「**已经知道有，但还没读**」，界面上应当
/// 显示成「正在获取歌词」而不是「没有歌词」。
class Lyrics {
  Lyrics({
    required this.trackId,
    required this.provider,
    required this.source,
    this.content,
    this.fileId,
    this.fileName,
    this.sizeBytes,
    this.instrumental = false,
  });

  /// 曲目主键（`Track.id`）。CUE 分段带 `#cN` 后缀，所以同一张整轨的
  /// 每一段各自一行 —— 它们本来就可能各有各的歌词。
  final String trackId;

  final DriveProvider provider;
  final LyricsSource source;

  /// 歌词正文（LRC 原文）。`null` 表示「已定位，尚未读取」。
  final String? content;

  /// 本地歌词在网盘上的文件 ID（取正文用）。联网来源恒为 `null`。
  final String? fileId;

  /// 本地歌词的原始文件名（含扩展名）。展示「来自 xxx.lrc」与排查用。
  final String? fileName;

  final int? sizeBytes;

  /// LRCLIB 明确告知「这是纯音乐，没有歌词」。
  ///
  /// 与「查不到」是两回事：纯音乐是一个**确定的答案**，界面该显示
  /// 「纯音乐，无歌词」而不是「没找到歌词，试试联网」。所以这个标志
  /// 必须落库 —— 否则每次播放都要去问一遍第三方接口。
  final bool instrumental;

  /// 解析后的文档。惰性算一次 —— 播放时每帧都要问「现在该高亮哪一行」，
  /// 不能每次都重新解析。
  LrcDocument get document => _doc ??= parseLrc(content ?? '');

  LrcDocument? _doc;

  /// 已定位但正文还没读（本地来源才有这个状态）
  bool get isPending => content == null;

  /// 正文非空
  bool get hasContent => content != null && content!.trim().isNotEmpty;

  /// 有时间轴，能跟着播放位置走
  bool get isSynced => document.isSynced;

  /// 值不值得在界面上占一块地方。
  ///
  /// 纯音乐也算 —— 它要显示的是「纯音乐，无歌词」这句话本身。
  bool get isDisplayable => hasContent || instrumental;

  Lyrics copyWith({
    LyricsSource? source,
    String? content,
    bool clearContent = false,
    String? fileId,
    String? fileName,
    int? sizeBytes,
    bool? instrumental,
  }) {
    return Lyrics(
      trackId: trackId,
      provider: provider,
      source: source ?? this.source,
      content: clearContent ? null : (content ?? this.content),
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      instrumental: instrumental ?? this.instrumental,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Lyrics &&
          other.trackId == trackId &&
          other.source == source &&
          other.content == content &&
          other.instrumental == instrumental;

  @override
  int get hashCode => Object.hash(trackId, source, content, instrumental);

  @override
  String toString() => 'Lyrics($trackId, ${source.id}, '
      '${isPending ? "未读取" : "${content!.length} 字"}'
      '${instrumental ? ", 纯音乐" : ""})';
}
