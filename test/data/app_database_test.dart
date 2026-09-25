import 'package:cloudtune/data/db/app_database.dart';
// drift 也导出一个 `isNull`（SQL 的 IS NULL），与 matcher 的同名断言冲突
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Drift 能在**纯 Dart 环境**下用内存库跑起来。
///
/// 这是整个索引层可测试性的前提：如果这里不通，仓储层就只能靠平台通道，
/// 单元测试覆盖不到 SQL 行为。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('内存库可建表并写入 / 读取曲目', () async {
    await db.into(db.tracks).insert(TracksCompanion.insert(
          id: 'quark:f1',
          providerId: 'quark',
          remoteId: 'f1',
          name: '晴天.flac',
          sizeBytes: const Value(31457280),
          title: const Value('晴天'),
          artist: const Value('周杰伦'),
          indexedAt: DateTime(2026, 9, 23),
        ));

    final rows = await db.select(db.tracks).get();
    expect(rows.length, 1);
    expect(rows.single.name, '晴天.flac');
    expect(rows.single.sizeBytes, 31457280);
    expect(rows.single.isPlayable, isTrue, reason: '默认应为可播');
    expect(rows.single.playCount, 0);
  });

  test('索引已建立（常用查询路径）', () async {
    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final names = indexes.map((r) => r.read<String>('name')).toSet();

    expect(names, contains('idx_tracks_provider'));
    expect(names, contains('idx_tracks_playable'));
    expect(names, contains('idx_tracks_artist'));
    expect(names, contains('idx_tracks_parent'));
    expect(names, contains('idx_play_history_at'));
  });

  test('触发器已建立（级联清理收藏、播放历史与歌词）', () async {
    final triggers = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    final names = triggers.map((r) => r.read<String>('name')).toSet();

    expect(names, contains('trg_tracks_delete_favorites'));
    expect(names, contains('trg_tracks_delete_history'));
    expect(names, contains('trg_tracks_delete_lyrics'));
  });

  test('删除曲目时级联清掉收藏与播放历史', () async {
    await db.into(db.tracks).insert(TracksCompanion.insert(
          id: 'quark:f1',
          providerId: 'quark',
          remoteId: 'f1',
          name: 'a.flac',
          indexedAt: DateTime(2026, 9, 23),
        ));
    await db.into(db.favorites).insert(FavoritesCompanion.insert(
          trackId: 'quark:f1',
          createdAt: DateTime(2026, 9, 23),
        ));
    await db.into(db.playHistory).insert(PlayHistoryCompanion.insert(
          trackId: 'quark:f1',
          playedAt: DateTime(2026, 9, 23),
        ));

    await (db.delete(db.tracks)..where((t) => t.id.equals('quark:f1'))).go();

    expect(await db.select(db.favorites).get(), isEmpty);
    expect(await db.select(db.playHistory).get(), isEmpty);
  });

  test('主键冲突时 upsert 不产生重复行（重复扫描幂等）', () async {
    for (var i = 0; i < 2; i++) {
      await db.into(db.tracks).insert(
            TracksCompanion.insert(
              id: 'quark:f1',
              providerId: 'quark',
              remoteId: 'f1',
              name: 'a.flac',
              sizeBytes: const Value(100),
              indexedAt: DateTime(2026, 9, 23),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
    expect((await db.select(db.tracks).get()).length, 1);
  });

  test('每个网盘一行续扫状态', () async {
    await db.into(db.scanStates).insert(ScanStatesCompanion.insert(
          providerId: 'quark',
          rootId: '0',
          rootPath: '/',
          pendingDirsJson: '[]',
          stageId: 'idle',
          updatedAt: DateTime(2026, 9, 23),
        ));
    final row = await (db.select(db.scanStates)
          ..where((s) => s.providerId.equals('quark')))
        .getSingle();
    expect(row.rootId, '0');
    expect(row.scannedDirs, 0);
  });

  group('CUE 分轨列（v1 → v2）', () {
    test('tracks 表带 cue_track_no / cue_start_ms', () async {
      final cols = await db.customSelect('PRAGMA table_info(tracks)').get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('cue_track_no'));
      expect(names, contains('cue_start_ms'));
    });

    test('v1 库升级到 v2：补上两列，且老曲目与播放统计原样保留', () async {
      // 手工造一个 **v1 结构** 的库：没有 CUE 两列、user_version = 1。
      // 这正是已有用户升级时真实面对的状态。onUpgrade 写错的后果是
      // 一启动就崩（列不存在）或静默丢数据，值得按真实结构测一次。
      final upgraded = AppDatabase(NativeDatabase.memory(setup: (raw) {
        // `sqlite3` 的 execute 是同步的（返回 void），不要 await
        raw.execute('''
          CREATE TABLE tracks (
            id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            remote_id TEXT NOT NULL,
            name TEXT NOT NULL,
            parent_id TEXT,
            path TEXT,
            size_bytes INTEGER,
            mime_type TEXT,
            modified_at INTEGER,
            title TEXT,
            artist TEXT,
            album TEXT,
            duration_ms INTEGER,
            is_playable INTEGER NOT NULL DEFAULT 1,
            playability_state TEXT NOT NULL DEFAULT 'playable',
            playability_note TEXT,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at INTEGER,
            indexed_at INTEGER NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
        // 触发器要引用这两张表，缺了 beforeOpen 会直接报错
        raw.execute('CREATE TABLE favorites ('
            'track_id TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (track_id))');
        raw.execute('CREATE TABLE play_history ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL, '
            'played_at INTEGER NOT NULL, '
            'played_seconds INTEGER NOT NULL DEFAULT 0)');
        raw.execute(
            "INSERT INTO tracks (id, provider_id, remote_id, name, title, "
            "artist, play_count, indexed_at) "
            "VALUES ('quark:old', 'quark', 'old', '老歌.flac', '老歌', "
            "'周杰伦', 7, 0)",
        );
        raw.execute('PRAGMA user_version = 1');
      }));
      addTearDown(upgraded.close);

      // 第一次使用才真正打开并跑迁移
      final rows = await upgraded.select(upgraded.tracks).get();

      expect(rows, hasLength(1));
      expect(rows.single.title, '老歌');
      expect(rows.single.artist, '周杰伦');
      expect(rows.single.playCount, 7, reason: '迁移绝不能清掉播放统计');
      expect(rows.single.cueTrackNo, isNull, reason: '老数据自动等价于「非 CUE 曲目」');
      expect(rows.single.cueStartMs, isNull);

      // 升级上来的库同样要拿到索引（onUpgrade 里也调了建索引）
      final indexes = await upgraded
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('idx_tracks_provider'));
      expect(names, contains('idx_tracks_parent'));
    });
  });

  group('专辑封面表（v2 → v3）', () {
    test('album_covers 表与索引都在', () async {
      final cols = await db.customSelect('PRAGMA table_info(album_covers)').get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll(<String>[
          'provider_id', 'dir_path', 'file_id', 'file_name', 'size_bytes',
          'indexed_at',
        ]),
      );

      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
      expect(indexNames, contains('idx_album_covers_provider'));
      // 专辑详情页按目录取曲目，靠这个**表达式索引**（rtrim(path,'/')）
      expect(indexNames, contains('idx_tracks_dir'));
    });

    test('v2 库升级到 v3：补出 album_covers，老曲目与播放统计原样保留', () async {
      // v2 结构 = 当前 tracks 的列 + CUE 两列，但没有 album_covers 表。
      final upgraded = AppDatabase(NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE tracks (
            id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            remote_id TEXT NOT NULL,
            name TEXT NOT NULL,
            parent_id TEXT,
            path TEXT,
            size_bytes INTEGER,
            mime_type TEXT,
            modified_at INTEGER,
            title TEXT,
            artist TEXT,
            album TEXT,
            duration_ms INTEGER,
            cue_track_no INTEGER,
            cue_start_ms INTEGER,
            is_playable INTEGER NOT NULL DEFAULT 1,
            playability_state TEXT NOT NULL DEFAULT 'playable',
            playability_note TEXT,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at INTEGER,
            indexed_at INTEGER NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
        raw.execute('CREATE TABLE favorites ('
            'track_id TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (track_id))');
        raw.execute('CREATE TABLE play_history ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL, '
            'played_at INTEGER NOT NULL, '
            'played_seconds INTEGER NOT NULL DEFAULT 0)');
        raw.execute(
            "INSERT INTO tracks (id, provider_id, remote_id, name, title, "
            "artist, cue_track_no, cue_start_ms, play_count, indexed_at) "
            "VALUES ('quark:seg#c3', 'quark', 'seg', '整轨.wav', '第三轨', "
            "'李克勤', 3, 420000, 5, 0)",
        );
        raw.execute('PRAGMA user_version = 2');
      }));
      addTearDown(upgraded.close);

      final rows = await upgraded.select(upgraded.tracks).get();

      expect(rows, hasLength(1));
      expect(rows.single.cueTrackNo, 3, reason: 'v2 已有的 CUE 列不能被迁移弄丢');
      expect(rows.single.cueStartMs, 420000);
      expect(rows.single.playCount, 5);

      // 新表可写可读
      await upgraded.into(upgraded.albumCovers).insert(
            AlbumCoversCompanion.insert(
              providerId: 'quark',
              dirPath: '/音乐/华语/李克勤',
              fileId: 'img1',
              fileName: 'cover.jpg',
              indexedAt: DateTime(2026, 9, 25),
            ),
          );
      final covers = await upgraded.select(upgraded.albumCovers).get();
      expect(covers.single.fileName, 'cover.jpg');
    });
  });

  group('歌词表与设置表（v3 → v4）', () {
    test('schemaVersion 为 4，两张表与歌词索引都在', () async {
      expect(db.schemaVersion, 4);

      final lyricCols =
          await db.customSelect('PRAGMA table_info(lyrics)').get();
      expect(
        lyricCols.map((r) => r.read<String>('name')).toSet(),
        containsAll(<String>[
          'track_id', 'provider_id', 'source_id', 'instrumental', 'content',
          'file_id', 'file_name', 'size_bytes', 'indexed_at',
        ]),
      );

      final settingCols =
          await db.customSelect('PRAGMA table_info(settings)').get();
      expect(
        settingCols.map((r) => r.read<String>('name')).toSet(),
        containsAll(<String>['setting_key', 'setting_value']),
      );

      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')).toSet(),
        contains('idx_lyrics_provider'),
      );
    });

    test('歌词 content 可以为空（「已定位、尚未读取」是一个合法状态）', () async {
      await db.into(db.lyrics).insert(LyricsCompanion.insert(
            trackId: 'quark:f1',
            providerId: 'quark',
            sourceId: 'local',
            fileId: const Value('lrc1'),
            fileName: const Value('晴天.lrc'),
            indexedAt: DateTime(2026, 9, 25),
          ));

      final row = await db.select(db.lyrics).getSingle();
      expect(row.content, isNull);
      expect(row.fileId, 'lrc1');
      expect(row.instrumental, isFalse, reason: '默认不是纯音乐');
    });

    test('v3 库升级到 v4：补出两张新表，老曲目与播放统计原样保留', () async {
      final upgraded = AppDatabase(NativeDatabase.memory(setup: (raw) {
        // v3 结构 = 当前 tracks 的列 + album_covers 表
        raw.execute('''
          CREATE TABLE tracks (
            id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            remote_id TEXT NOT NULL,
            name TEXT NOT NULL,
            parent_id TEXT,
            path TEXT,
            size_bytes INTEGER,
            mime_type TEXT,
            modified_at INTEGER,
            title TEXT,
            artist TEXT,
            album TEXT,
            duration_ms INTEGER,
            cue_track_no INTEGER,
            cue_start_ms INTEGER,
            is_playable INTEGER NOT NULL DEFAULT 1,
            playability_state TEXT NOT NULL DEFAULT 'playable',
            playability_note TEXT,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played_at INTEGER,
            indexed_at INTEGER NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
        raw.execute('CREATE TABLE favorites ('
            'track_id TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (track_id))');
        raw.execute('CREATE TABLE play_history ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL, '
            'played_at INTEGER NOT NULL, '
            'played_seconds INTEGER NOT NULL DEFAULT 0)');
        raw.execute('CREATE TABLE album_covers ('
            'provider_id TEXT NOT NULL, dir_path TEXT NOT NULL, '
            'file_id TEXT NOT NULL, file_name TEXT NOT NULL, size_bytes INTEGER, '
            'indexed_at INTEGER NOT NULL, PRIMARY KEY (provider_id, dir_path))');
        raw.execute(
            "INSERT INTO tracks (id, provider_id, remote_id, name, title, "
            "play_count, indexed_at) "
            "VALUES ('quark:old', 'quark', 'old', '老歌.flac', '老歌', 9, 0)",
        );
        raw.execute(
            "INSERT INTO album_covers VALUES "
            "('quark', '/音乐/老专辑', 'img9', 'cover.jpg', 100, 0)",
        );
        raw.execute('PRAGMA user_version = 3');
      }));
      addTearDown(upgraded.close);

      final rows = await upgraded.select(upgraded.tracks).get();
      expect(rows, hasLength(1));
      expect(rows.single.playCount, 9, reason: '迁移绝不能清掉播放统计');
      expect((await upgraded.select(upgraded.albumCovers).get()).single.fileName,
          'cover.jpg');

      // 新表可写可读
      await upgraded.into(upgraded.lyrics).insert(LyricsCompanion.insert(
            trackId: 'quark:old',
            providerId: 'quark',
            sourceId: 'lrclib',
            content: const Value('[00:01.00]A'),
            indexedAt: DateTime(2026, 9, 25),
          ));
      await upgraded.into(upgraded.settings).insert(
            SettingsCompanion.insert(
              settingKey: 'lyrics.network_enabled',
              settingValue: 'true',
            ),
          );
      expect((await upgraded.select(upgraded.lyrics).get()).single.content,
          '[00:01.00]A');
      expect((await upgraded.select(upgraded.settings).get()).single.settingValue,
          'true');
    });

    test('删曲目时级联清掉歌词（不留指向不存在曲目的孤儿行）', () async {
      await db.into(db.tracks).insert(TracksCompanion.insert(
            id: 'quark:f1',
            providerId: 'quark',
            remoteId: 'f1',
            name: 'a.flac',
            indexedAt: DateTime(2026, 9, 25),
          ));
      await db.into(db.lyrics).insert(LyricsCompanion.insert(
            trackId: 'quark:f1',
            providerId: 'quark',
            sourceId: 'local',
            indexedAt: DateTime(2026, 9, 25),
          ));

      await (db.delete(db.tracks)..where((t) => t.id.equals('quark:f1'))).go();

      expect(await db.select(db.lyrics).get(), isEmpty);
    });

    test('设置表在清空曲库后依然保留（用户偏好不是索引数据）', () async {
      await db.into(db.settings).insert(SettingsCompanion.insert(
            settingKey: 'lyrics.network_enabled',
            settingValue: 'true',
          ));
      // clearProvider 由仓储层实现，这里只断言表本身与 tracks 无关联
      await db.into(db.tracks).insert(TracksCompanion.insert(
            id: 'quark:f1',
            providerId: 'quark',
            remoteId: 'f1',
            name: 'a.flac',
            indexedAt: DateTime(2026, 9, 25),
          ));
      await (db.delete(db.tracks)).go();

      expect(await db.select(db.settings).get(), hasLength(1));
    });
  });
}
