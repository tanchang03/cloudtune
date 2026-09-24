import 'dart:convert';

import '../../domain/entities/drive_provider.dart';
import '../../domain/entities/scan_cursor.dart';
import 'app_database.dart';

/// [ScanCursor] ↔ 数据库行的编解码。
///
/// 单独抽出来是为了**可测**：续扫的正确性完全取决于「序列化后能否原样还原」，
/// 而这条路径一旦出错的表现是「续扫时漏目录 / 重复扫」，很难在现场定位。
class ScanStateCodec {
  const ScanStateCodec._();

  // ------------------------------------------------------------------
  // BFS 队列
  // ------------------------------------------------------------------

  static String encodePendingDirs(List<PendingDir> dirs) =>
      jsonEncode(dirs.map((d) => d.toJson()).toList());

  /// 解码队列。损坏的条目被跳过而不是整体失败 ——
  /// 宁可少扫一个目录，也不要因为一条脏数据丢掉整个续扫进度。
  static List<PendingDir> decodePendingDirs(String? json) {
    if (json == null || json.isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final out = <PendingDir>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final dir = PendingDir.fromJson(item.cast<String, Object?>());
      if (dir.id.isEmpty) continue;
      out.add(dir);
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 当前目录
  // ------------------------------------------------------------------

  static String? encodeCurrentDir(PendingDir? dir) =>
      dir == null ? null : jsonEncode(dir.toJson());

  static PendingDir? decodeCurrentDir(String? json) {
    if (json == null || json.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final dir = PendingDir.fromJson(decoded.cast<String, Object?>());
    return dir.id.isEmpty ? null : dir;
  }

  // ------------------------------------------------------------------
  // 行 → 领域对象
  // ------------------------------------------------------------------

  /// 从数据库行还原 [ScanCursor]。
  ///
  /// 未知的 `stageId` 回落到 `paused`（可续扫）而不是 `completed`——
  /// 前者最坏是多扫一次，后者会让用户以为扫完了、实际漏了目录。
  static ScanCursor toCursor(ScanStateRow row) {
    final provider = DriveProvider.fromId(row.providerId);

    return ScanCursor(
      provider: provider ?? DriveProvider.quark,
      rootId: row.rootId,
      rootPath: row.rootPath,
      updatedAt: row.updatedAt,
      pendingDirs: decodePendingDirs(row.pendingDirsJson),
      currentDir: decodeCurrentDir(row.currentDirJson),
      currentPageToken: row.currentPageToken,
      stage: _parseStage(row.stageId),
      scannedDirs: row.scannedDirs,
      scannedFiles: row.scannedFiles,
      foundTracks: row.foundTracks,
      totalBytes: row.totalBytes,
      failedDirs: row.failedDirs,
      lastError: row.lastError,
    );
  }

  static ScanStage _parseStage(String id) {
    for (final s in ScanStage.values) {
      if (s.name == id) return s;
    }
    return ScanStage.paused;
  }
}
