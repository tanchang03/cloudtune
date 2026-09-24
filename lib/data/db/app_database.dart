import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 本地索引数据库。
///
/// 只放**可重建**的索引数据：曲目、账号展示信息、收藏、续扫游标、播放历史。
/// 凭证不进这里（走系统钥匙串）；任何一张表被清掉都只影响体验，不影响授权。
///
/// 用 `NativeDatabase.memory()` 可以在纯 Dart 单元测试里跑完整的 SQL 行为，
/// 不需要平台通道 —— 这是把仓储层做薄、把 SQL 逻辑集中在这里的原因。
@DriftDatabase(tables: [Tracks, Accounts, Favorites, ScanStates, PlayHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 常用查询路径建索引：按网盘过滤、按可播性过滤、按艺术家/专辑分组、
          // 以及「列某个目录下的曲目」
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tracks_provider '
            'ON tracks (provider_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tracks_playable '
            'ON tracks (provider_id, is_playable)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tracks_artist '
            'ON tracks (artist)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tracks_album '
            'ON tracks (album)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tracks_parent '
            'ON tracks (provider_id, parent_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_play_history_at '
            'ON play_history (played_at DESC)',
          );
        },
        beforeOpen: (details) async {
          // 外键约束：收藏与播放历史在曲目被删除后应级联清理。
          // 用触发器实现，避免依赖 Drift 的表级 references 配置。
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement(
            'CREATE TRIGGER IF NOT EXISTS trg_tracks_delete_favorites '
            'AFTER DELETE ON tracks BEGIN '
            'DELETE FROM favorites WHERE track_id = OLD.id; '
            'END',
          );
          await customStatement(
            'CREATE TRIGGER IF NOT EXISTS trg_tracks_delete_history '
            'AFTER DELETE ON tracks BEGIN '
            'DELETE FROM play_history WHERE track_id = OLD.id; '
            'END',
          );
        },
      );
}
