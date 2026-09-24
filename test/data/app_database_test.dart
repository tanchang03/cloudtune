import 'package:cloudtune/data/db/app_database.dart';
import 'package:drift/drift.dart';
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

  test('触发器已建立（级联清理收藏与播放历史）', () async {
    final triggers = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    final names = triggers.map((r) => r.read<String>('name')).toSet();

    expect(names, contains('trg_tracks_delete_favorites'));
    expect(names, contains('trg_tracks_delete_history'));
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
}
