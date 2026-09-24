import '../../core/utils/audio_formats.dart';
import '../services/playability_resolver.dart';
import 'capabilities.dart';
import 'drive_entry.dart';
import 'drive_provider.dart';
import 'playability.dart';

/// 统一曲目模型。
///
/// 三家网盘的文件都归一到这一个结构。播放引擎、索引库、UI 只认 [Track]，
/// 不认任何网盘的私有字段。
///
/// **等价性约定**：`==` / `hashCode` 只基于 `(provider, remoteId)`，
/// 也就是「同一个网盘上的同一个文件」。这样曲目可以安全地放进 `Set`
/// 做去重、放进 `Map` 做收藏索引。要判断元数据是否变化，用
/// [hasSameMetadataAs]。
class Track {
  Track({
    required this.provider,
    required this.remoteId,
    required this.name,
    this.parentId,
    this.path,
    this.sizeBytes,
    this.mimeType,
    this.modifiedAt,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  /// 从网盘原始节点构造。
  ///
  /// [path] 由扫描器在遍历时按栈拼出（网盘接口通常不返回完整路径）。
  ///
  /// ⚠️ [entry] **必须是文件**。搜索接口会返回目录（夸克实测），
  /// 调用方必须先过滤 `entry.isFile`。
  factory Track.fromEntry({
    required DriveEntry entry,
    required DriveProvider provider,
    String? path,
  }) {
    assert(!entry.isDirectory, '不能把目录转成曲目：${entry.name}');
    final guessed = guessTitleArtist(entry.name);
    return Track(
      provider: provider,
      remoteId: entry.id,
      name: entry.name,
      parentId: entry.parentId,
      path: path ?? entry.path,
      sizeBytes: entry.sizeBytes,
      mimeType: entry.mimeType,
      modifiedAt: entry.modifiedAt,
      // 文件名解析出的结果先落库，后续接入标签读取时可覆盖
      title: guessed.title,
      artist: guessed.artist,
      // 时长直接来自网盘元数据（夸克列目录就带 `duration`），
      // 不必为了显示一个 mm:ss 去把每个文件都下载/试播一遍
      durationMs: entry.durationMs,
    );
  }

  final DriveProvider provider;

  /// 网盘侧文件 ID
  final String remoteId;

  /// 原始文件名（含扩展名）
  final String name;

  final String? parentId;

  /// 所在目录的展示路径，如 `/音乐/华语/`
  final String? path;

  final int? sizeBytes;
  final String? mimeType;
  final DateTime? modifiedAt;

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// 全局唯一主键，同时作为本地索引库主键。
  ///
  /// 形如 `quark:8f3a...`。用「网盘 + 远端 ID」而非自增 ID，
  /// 这样重新扫描时天然幂等，不会产生重复行。
  String get id => '${provider.id}:$remoteId';

  /// 小写扩展名（不含点），无扩展名返回空串
  String get extension => extensionOf(name);

  /// 是否为高解析格式（DSD / WAV / AIFF 等）
  bool get isHighResFormat => isHighRes(name);

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// 展示用标题：优先元数据，退化到文件名解析结果
  late final ({String title, String? artist}) _guessed = guessTitleArtist(name);

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return _guessed.title;
  }

  String? get displayArtist {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return _guessed.artist;
  }

  /// 完整网盘路径：`所在目录 + 文件名`。
  ///
  /// 用户要拿着它去网盘里定位文件（或在网盘客户端里搜索），
  /// 所以这里给的是**可直接复制使用的完整位置**，而不是只有目录。
  String get fullPath {
    final dir = path?.trim() ?? '';
    if (dir.isEmpty) return name;
    return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
  }

  /// 展示用副标题：`艺术家 · 专辑`，都没有则退回所在目录名
  String get displaySubtitle {
    final parts = <String>[];
    final a = displayArtist;
    if (a != null && a.isNotEmpty) parts.add(a);
    final al = album?.trim();
    if (al != null && al.isNotEmpty) parts.add(al);
    if (parts.isEmpty) {
      final p = path?.trim() ?? '';
      if (p.isNotEmpty) {
        final segs = p.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) parts.add(segs.last);
      }
    }
    return parts.join(' · ');
  }

  /// 判定可播性。业务规则见 [resolvePlayability]。
  Playability playability(Capabilities capabilities) => resolvePlayability(
        fileName: name,
        capabilities: capabilities,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
      );

  /// 元数据是否与另一条相同（不比较身份）。
  ///
  /// 用于扫描时判断「这条曲目是否需要写库」，避免无谓的 UPDATE。
  bool hasSameMetadataAs(Track other) =>
      name == other.name &&
      sizeBytes == other.sizeBytes &&
      parentId == other.parentId &&
      path == other.path &&
      modifiedAt == other.modifiedAt &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      durationMs == other.durationMs;

  Track copyWith({
    String? name,
    String? parentId,
    String? path,
    int? sizeBytes,
    String? mimeType,
    DateTime? modifiedAt,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    return Track(
      provider: provider,
      remoteId: remoteId,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track && other.provider == provider && other.remoteId == remoteId;

  @override
  int get hashCode => Object.hash(provider, remoteId);

  @override
  String toString() => 'Track($id, "$name", ${sizeBytes ?? "-"}B)';
}
