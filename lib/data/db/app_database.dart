import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 本地索引数据库。
///
/// 只放**可重建**的索引数据：曲目、专辑封面、歌词、账号展示信息、收藏、
/// 续扫游标、播放历史。凭证不进这里（走系统钥匙串）；任何一张索引表被清掉
/// 都只影响体验，不影响授权。
///
/// 唯一的例外是 `settings`：它是**用户偏好**，清空曲库不该顺手把它清掉，
/// 所以 `clearProvider` 刻意不动它。
///
/// 用 `NativeDatabase.memory()` 可以在纯 Dart 单元测试里跑完整的 SQL 行为，
/// 不需要平台通道 —— 这是把仓储层做薄、把 SQL 逻辑集中在这里的原因。
@DriftDatabase(
  tables: [
    Tracks,
    AlbumCovers,
    Lyrics,
    Settings,
    Accounts,
    Favorites,
    ScanStates,
    PlayHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2：CUE 分轨。两条 nullable 列，老数据自动是 NULL
          // （等价于「不是 CUE 曲目」），不需要任何回填。
          if (from < 2) {
            await m.addColumn(tracks, tracks.cueTrackNo);
            await m.addColumn(tracks, tracks.cueStartMs);
          }
          // v2 → v3：专辑封面。整张新表，老库扫一次就有封面了，
          // 不需要回填 —— 也没法回填，封面路径是扫描时才发现的。
          if (from < 3) {
            await m.createTable(albumCovers);
          }
          // v3 → v4：歌词与设置。两张新表，同样不需要回填：
          // 歌词引用是扫描时才发现 `.lrc` 得来的，设置则本来就该用默认值
          // 起步（联网歌词默认关闭）。
          if (from < 4) {
            await m.createTable(lyrics);
            await m.createTable(settings);
          }
          // v4 → v5：新歌功能。给曲目加 `first_seen_at` 列。
          // 老库没有这一列，需要回填：把已存在的行补成 `indexed_at` ——
          // 这样升级前就躺在曲库里的歌不会被错误地标成「新」。
          // 「新」的判定是 `first_seen_at > 用户上次看了新歌的时间`，
          // 而那个水位由扫描服务在第一次成功扫描后设为「现在」，
          // 于是升级后的第一次扫描只是建立基线，不会把整库都刷成新歌。
          if (from < 5) {
            await m.addColumn(tracks, tracks.firstSeenAt);
            await customStatement(
              'UPDATE tracks SET first_seen_at = indexed_at '
              'WHERE first_seen_at IS NULL',
            );
          }
          // 升级后补建索引：onCreate 里建过的不重复建（都是 IF NOT EXISTS）
          await _createIndexes();
        },
        beforeOpen: (details) async {
          // 外键约束：收藏、播放历史与歌词在曲目被删除后应级联清理。
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
          // 歌词跟着曲目走：曲目被清掉之后，那一行歌词再也指不到任何东西，
          // 留着只会让「歌词覆盖数」永远偏高。
          await customStatement(
            'CREATE TRIGGER IF NOT EXISTS trg_tracks_delete_lyrics '
            'AFTER DELETE ON tracks BEGIN '
            'DELETE FROM lyrics WHERE track_id = OLD.id; '
            'END',
          );
        },
      );

  /// 常用查询路径建索引：按网盘过滤、按可播性过滤、按艺术家/专辑分组、
  /// 以及「列某个目录下的曲目」。
  ///
  /// 抽成方法是因为 `onCreate` 与 `onUpgrade` 都要用 —— 升级上来的库
  /// 同样需要这些索引，漏掉会让老用户的新库少了索引却毫无提示。
  Future<void> _createIndexes() async {
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
    // 新歌查询：`first_seen_at > 水位` 走索引，避免全表扫。
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_first_seen '
      'ON tracks (provider_id, first_seen_at)',
    );
    // 专辑详情页按目录取曲目，条件是 `rtrim(path, '/') = ?`。
    // 表达式索引让这个查询也走上索引（SQLite 3.9+ 支持）。
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_dir '
      "ON tracks (provider_id, rtrim(path, '/'))",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_album_covers_provider '
      'ON album_covers (provider_id)',
    );
    // 歌词按网盘清理（`deleteLyricsNotIn` / `lyricsCount`）与按曲目取
    // （`lyricsFor`，主键已覆盖）这两条路径。
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lyrics_provider '
      'ON lyrics (provider_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_play_history_at '
      'ON play_history (played_at DESC)',
    );
  }
}
