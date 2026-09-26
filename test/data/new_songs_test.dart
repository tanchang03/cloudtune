import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/data/db/settings_store.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id, String name) {
  // 注意：upsert 时 first_seen_at 由「扫描时刻 now」落库，Track 上的
  // firstSeenAt 字段会被忽略（它是只读的查询输出）。所以这里不传 firstSeenAt。
  return Track.fromEntry(
    entry: DriveEntry(id: id, name: name, isDirectory: false),
    provider: DriveProvider.quark,
  );
}

void main() {
  group('新歌：first_seen_at 与查询', () {
    late AppDatabase db;
    late DriftLibraryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLibraryRepository(db);
    });
    tearDown(() => db.close());

    test('首次 upsert 写入 first_seen_at = now，重扫不覆盖', () async {
      final early = DateTime(2026, 1, 1);
      final later = DateTime(2026, 6, 1);
      await repo.upsertTracks([_track('a1', 'a.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: early);
      await repo.upsertTracks([_track('a1', 'a.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: later); // 重扫

      final rows = await repo.queryTracks();
      expect(rows, hasLength(1));
      expect(rows.first.firstSeenAt, early,
          reason: '重扫只刷新 indexed_at，first_seen_at 必须保留首次入库时间，'
              '否则每次重扫都会把所有歌刷成「新」');
    });

    test('newTracksCount：晚于水位的才算新', () async {
      final base = DateTime(2026, 5, 1);
      final old1 = DateTime(2026, 4, 1); // 早于水位
      final new1 = DateTime(2026, 6, 1); // 晚于水位
      final new2 = DateTime(2026, 7, 1);
      await repo.upsertTracks([_track('o1', 'old.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: old1);
      await repo.upsertTracks([_track('n1', 'new1.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: new1);
      await repo.upsertTracks([_track('n2', 'new2.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: new2);

      expect(await repo.newTracksCount(seenAt: base), 2,
          reason: 'base 之前入库的不算新');

      final list = await repo.newTracks(seenAt: base);
      expect(list.map((t) => t.id), ['quark:n2', 'quark:n1'],
          reason: '按 first_seen_at 倒序，最新的在最前');
    });

    test('newTracksCount：水位为 null 时只按 first_seen_at 非空计', () async {
      // 这条测的是「仓储方法本身」的语义：seenAt 为 null 时不过滤时间。
      // 真正的「全库不算新」保护在 newSongsCountProvider 里（见 provider 测试）。
      final t = DateTime(2026, 1, 1);
      await repo.upsertTracks([_track('x1', 'x.mp3')], capabilities: const Capabilities(provider: DriveProvider.quark), now: t);
      expect(await repo.newTracksCount(seenAt: null), 1);
    });

    test('SettingsStore：newSongsSeenAt 用 ISO8601 往返', () async {
      final store = SettingsStore(db);
      expect(await store.readDateTime(SettingKeys.newSongsSeenAt), isNull);
      final ts = DateTime(2026, 8, 8, 12, 30);
      await store.writeDateTime(SettingKeys.newSongsSeenAt, ts);
      expect(await store.readDateTime(SettingKeys.newSongsSeenAt), ts);
      await store.remove(SettingKeys.newSongsSeenAt);
      expect(await store.readDateTime(SettingKeys.newSongsSeenAt), isNull);
    });
  });
}
