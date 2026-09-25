import 'drive_provider.dart';

/// 一张专辑的封面引用。
///
/// **只记录「封面是哪张图」，不记录图片本身。** 图片字节在网盘上，按需取
/// （见 `AlbumCoverCache`）—— 扫描时把每个封面都下载下来会把一次扫描变成
/// 一次批量下载，而且用户可能永远不打开专辑视图。
///
/// 键是**目录**而不是专辑名：一个目录 = 一张专辑这件事永远成立，而专辑名
/// 是从目录名猜的（见 `LibraryGrouping`）。这与 `TrackGroup.key` 同一口径，
/// 所以「曲目分组」与「封面」能按同一个键对上。
class AlbumCover {
  const AlbumCover({
    required this.provider,
    required this.dirPath,
    required this.fileId,
    required this.fileName,
    this.sizeBytes,
  });

  final DriveProvider provider;

  /// 专辑目录（归一化，不带结尾斜杠），如 `/音乐/华语/周杰伦`
  final String dirPath;

  /// 图片在网盘上的文件 ID（取字节用）
  final String fileId;

  /// 原始文件名（含扩展名）—— 缓存要按它取扩展名，日志里也要能读出是哪张图
  final String fileName;

  /// 图片体积。用于展示与「同档取大图」的挑选，拿不到时为 `null`。
  final int? sizeBytes;

  /// 图片自身的身份键：`provider:fileId`。
  ///
  /// 与 [dirPath] 是两个维度：前者回答「这是哪张图」（取字节、做缓存用），
  /// 后者回答「它属于哪张专辑」（按专辑查封面用）。
  String get key => '${provider.id}:$fileId';

  /// 小写扩展名（不含点）
  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AlbumCover && other.key == key;

  /// 基于 [key]：同一张图被两张专辑引用时，取字节的 provider family
  /// 会把它当成同一个参数、只取一次 —— 这正是想要的。
  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'AlbumCover($dirPath ← "$fileName", ${sizeBytes ?? "-"}B)';
}
