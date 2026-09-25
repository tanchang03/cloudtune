import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/domain/entities/album_cover.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/scan_cursor.dart';
import 'package:cloudtune/domain/entities/track.dart';
// drift 与 matcher 都导出 isNull / isNotNull，这里以 matcher 为准
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假想的能力声明（含 50MiB 播放取链上限）——可播性判定的基准。
/// 注意夸克的真实声明**没有**体积上限，见 QuarkAdapter.quarkCapabilities。
const _quarkCap = Capabilities(
  provider: DriveProvider.quark,
  maxSingleFileBytes: Capabilities.fiftyMiB,
);

const _mib = 1024 * 1024;

/// 造一条曲目。默认 1KiB / flac → 判定为可播。
Track _track({
  String remoteId = 'f1',
  String name = 'a.flac',
  int? size = 1024,
  String? artist,
  String? album,
  String? title,
  String? path,
  DriveProvider provider = DriveProvider.quark,
  DateTime? modifiedAt,
}) =>
    Track(
      provider: provider,
      remoteId: remoteId,
      name: name,
      sizeBytes: size,
      artist: artist,
      album: album,
      title: title,
      path: path,
      modifiedAt: modifiedAt,
    );

void main() {
  late AppDatabase db;
  late DriftLibraryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() => db.close());

  // ===================================================================
  // upsert
  // ===================================================================

  group('upsertTracks', () {
    test('重复 upsert 同一曲目不产生重复行（重复扫描幂等）', () async {
      final t = _track(remoteId: 'f1');
      await repo.upsertTracks([t], capabilities: _quarkCap);
      await repo.upsertTracks([t], capabilities: _quarkCap);

      expect(await repo.countTracks(), 1);
    });

    test('upsert 不覆盖 playCount / lastPlayedAt（重复扫描不能清零播放统计）', () async {
      final t = _track(remoteId: 'f1', name: '晴天.flac', size: 1024);
      await repo.upsertTracks([t], capabilities: _quarkCap);

      final playedAt = DateTime(2026, 9, 20, 10, 30);
      await repo.recordPlay(t.id, played: const Duration(seconds: 120), now: playedAt);
      await repo.recordPlay(t.id, now: playedAt);

      // 模拟第二次全盘扫描：网盘侧文件改名且体积变了
      await repo.upsertTracks(
        [t.copyWith(name: '晴天 (Remaster).flac', sizeBytes: 2048)],
        capabilities: _quarkCap,
      );

      final row = (await db.select(db.tracks).get()).single;
      expect(row.playCount, 2, reason: '播放次数必须保留');
      expect(row.lastPlayedAt, playedAt, reason: '最近播放时间必须保留');
      expect(row.name, '晴天 (Remaster).flac', reason: '元数据必须被刷新');
      expect(row.sizeBytes, 2048);
    });

    test('落库可播性快照，四种状态各自可查', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok', name: 'a.flac', size: 1024),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
        _track(remoteId: 'unknown', name: 'c.flac', size: null),
        _track(remoteId: 'txt', name: 'cover.txt', size: 10),
      ], capabilities: _quarkCap);

      final byId = {
        for (final r in await db.select(db.tracks).get()) r.remoteId: r,
      };

      expect(byId['ok']!.isPlayable, isTrue);
      expect(byId['ok']!.playabilityState, 'playable');
      expect(byId['ok']!.playabilityNote, isNull);

      expect(byId['big']!.isPlayable, isFalse);
      expect(byId['big']!.playabilityState, 'overLimit');
      expect(byId['big']!.playabilityNote, isNotNull,
          reason: '超限要给出可直接展示的中文原因');

      expect(byId['unknown']!.isPlayable, isTrue,
          reason: '体积未知应当乐观可播，不该判死');
      expect(byId['unknown']!.playabilityState, 'unknownSize');

      expect(byId['txt']!.isPlayable, isFalse);
      expect(byId['txt']!.playabilityState, 'notAudio');
    });

    test('空列表是安全的空操作', () async {
      await repo.upsertTracks([], capabilities: _quarkCap);
      expect(await repo.countTracks(), 0);
    });

    test('网盘能力变化后重新 upsert 会刷新可播性快照', () async {
      await repo.upsertTracks(
        [_track(remoteId: 'big', name: 'a.flac', size: 60 * _mib)],
        capabilities: _quarkCap,
      );
      expect((await repo.trackById('quark:big'))!.playability(_quarkCap).state.name,
          'overLimit');

      // 假设将来夸克取消 50MB 上限
      await repo.upsertTracks(
        [_track(remoteId: 'big', name: 'a.flac', size: 60 * _mib)],
        capabilities: const Capabilities(provider: DriveProvider.quark),
      );

      final row = (await db.select(db.tracks).get()).single;
      expect(row.playabilityState, 'playable');
      expect(row.isPlayable, isTrue);
    });
  });

  // ===================================================================
  // 查询
  // ===================================================================

  group('queryTracks', () {
    test('按网盘过滤', () async {
      await repo.upsertTracks([
        _track(remoteId: 'q1'),
        _track(remoteId: 'a1', provider: DriveProvider.aliyun),
      ], capabilities: _quarkCap);

      final quark = await repo.queryTracks(
        const TrackQuery(provider: DriveProvider.quark),
      );
      expect(quark.map((t) => t.remoteId).toList(), ['q1']);
    });

    test('playableOnly 走快照列过滤', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok', name: 'a.flac'),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
      ], capabilities: _quarkCap);

      final playable =
          await repo.queryTracks(const TrackQuery(playableOnly: true));
      expect(playable.map((t) => t.remoteId).toList(), ['ok']);

      final blocked =
          await repo.queryTracks(const TrackQuery(playableOnly: false));
      expect(blocked.map((t) => t.remoteId).toList(), ['big']);
    });

    test('关键字里的 % 与 _ 按字面匹配，不当通配符', () async {
      await repo.upsertTracks([
        _track(remoteId: 'pct', name: '100%.flac'),
        _track(remoteId: 'plain', name: '100x.flac'),
        _track(remoteId: 'und', name: 'a_b.flac'),
        _track(remoteId: 'und2', name: 'axb.flac'),
      ], capabilities: _quarkCap);

      final pct = await repo.queryTracks(const TrackQuery(keyword: '%'));
      expect(pct.map((t) => t.remoteId).toList(), ['pct'],
          reason: '搜索 % 不能匹配到所有曲目');

      final und = await repo.queryTracks(const TrackQuery(keyword: '_'));
      expect(und.map((t) => t.remoteId).toList(), ['und'],
          reason: '搜索 _ 不能匹配任意单字符');
    });

    test('关键字可命中艺术家与专辑', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a', name: 'a.flac', artist: '周杰伦', album: '叶惠美'),
        _track(remoteId: 'b', name: 'b.flac', artist: '陈奕迅', album: 'U87'),
      ], capabilities: _quarkCap);

      final byArtist = await repo.queryTracks(const TrackQuery(keyword: '周杰伦'));
      expect(byArtist.map((t) => t.remoteId).toList(), ['a']);

      final byAlbum = await repo.queryTracks(const TrackQuery(keyword: 'U87'));
      expect(byAlbum.map((t) => t.remoteId).toList(), ['b']);
    });

    test('排序带 id 兜底，同键记录次序稳定（分页不会重复/遗漏）', () async {
      await repo.upsertTracks([
        _track(remoteId: 'z', name: 'same.flac'),
        _track(remoteId: 'a', name: 'same.flac'),
        _track(remoteId: 'm', name: 'same.flac'),
      ], capabilities: _quarkCap);

      final list = await repo.queryTracks();
      expect(list.map((t) => t.remoteId).toList(), ['a', 'm', 'z']);
    });

    test('按体积倒序可快速定位「不可播的大文件」', () async {
      await repo.upsertTracks([
        _track(remoteId: 'small', name: 's.flac', size: 1024),
        _track(remoteId: 'huge', name: 'h.flac', size: 600 * _mib),
        _track(remoteId: 'mid', name: 'm.flac', size: 10 * _mib),
      ], capabilities: _quarkCap);

      final list = await repo.queryTracks(const TrackQuery(sort: TrackSort.sizeDesc));
      expect(list.map((t) => t.remoteId).toList(), ['huge', 'mid', 'small']);
    });

    test('按艺术家 → 专辑 → 文件名排序', () async {
      await repo.upsertTracks([
        _track(remoteId: '1', name: 'b.flac', artist: 'B', album: 'X'),
        _track(remoteId: '2', name: 'a.flac', artist: 'A', album: 'Z'),
        _track(remoteId: '3', name: 'a.flac', artist: 'A', album: 'A'),
      ], capabilities: _quarkCap);

      final list =
          await repo.queryTracks(const TrackQuery(sort: TrackSort.artistAsc));
      expect(list.map((t) => t.remoteId).toList(), ['3', '2', '1']);
    });

    test('limit / offset 分页', () async {
      await repo.upsertTracks(
        List.generate(5, (i) => _track(remoteId: 'f$i', name: 't$i.flac')),
        capabilities: _quarkCap,
      );

      final page1 = await repo.queryTracks(const TrackQuery(limit: 2));
      expect(page1.map((t) => t.remoteId).toList(), ['f0', 'f1']);

      final page2 = await repo.queryTracks(const TrackQuery(limit: 2, offset: 2));
      expect(page2.map((t) => t.remoteId).toList(), ['f2', 'f3']);

      final page3 = await repo.queryTracks(const TrackQuery(offset: 4));
      expect(page3.map((t) => t.remoteId).toList(), ['f4']);
    });

    test('favoritesOnly 只返回已收藏', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);
      await repo.setFavorite('quark:a', value: true);

      final favs = await repo.queryTracks(const TrackQuery(favoritesOnly: true));
      expect(favs.map((t) => t.remoteId).toList(), ['a']);
    });

    test('trackById 命中与未命中', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);

      final hit = await repo.trackById('quark:a');
      expect(hit, isNotNull);
      expect(hit!.remoteId, 'a');
      expect(hit.path, isNull);

      expect(await repo.trackById('quark:nope'), isNull);
    });

    test('countTracks 支持按网盘与可播性组合计数', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok'),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
        _track(remoteId: 'ali', provider: DriveProvider.aliyun),
      ], capabilities: _quarkCap);

      expect(await repo.countTracks(), 3);
      expect(await repo.countTracks(provider: DriveProvider.quark), 2);
      expect(
        await repo.countTracks(provider: DriveProvider.quark, playableOnly: true),
        1,
      );
      expect(
        await repo.countTracks(provider: DriveProvider.quark, playableOnly: false),
        1,
      );
    });
  });

  // ===================================================================
  // 清理
  // ===================================================================

  group('删除', () {
    test('deleteTracksNotIn 只删该网盘下的陈旧曲目', () async {
      await repo.upsertTracks([
        _track(remoteId: 'keep'),
        _track(remoteId: 'stale'),
        _track(remoteId: 'other', provider: DriveProvider.aliyun),
      ], capabilities: _quarkCap);

      final removed =
          await repo.deleteTracksNotIn(DriveProvider.quark, {'quark:keep'});

      expect(removed, 1);
      final ids = (await repo.queryTracks()).map((t) => t.id).toSet();
      expect(ids, {'quark:keep', 'aliyun:other'},
          reason: '其他网盘的曲目不能被误删');
    });

    test('deleteTracksNotIn 用临时表，数千 ID 不撞 SQLite 绑定变量上限', () async {
      // 直插 2500 行（绕过 upsert 以提速），保留前 2000
      await db.batch((b) {
        b.insertAll(db.tracks, [
          for (var i = 0; i < 2500; i++)
            TracksCompanion.insert(
              id: 'quark:f$i',
              providerId: 'quark',
              remoteId: 'f$i',
              name: 't$i.flac',
              indexedAt: DateTime(2026, 9, 23),
            ),
        ]);
      });

      final keep = {for (var i = 0; i < 2000; i++) 'quark:f$i'};
      final removed = await repo.deleteTracksNotIn(DriveProvider.quark, keep);

      expect(removed, 500);
      expect(await repo.countTracks(), 2000);
    });

    test('deleteTracksNotIn 传入空集合会清空该网盘（调用方需自行守卫）', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);

      final removed = await repo.deleteTracksNotIn(DriveProvider.quark, {});

      expect(removed, 2);
      expect(await repo.countTracks(), 0);
    });

    test('deleteTracks 按 ID 批量删除，分片不出错', () async {
      await repo.upsertTracks(
        List.generate(900, (i) => _track(remoteId: 'f$i', name: 't$i.flac')),
        capabilities: _quarkCap,
      );

      await repo.deleteTracks({for (var i = 0; i < 900; i += 2) 'quark:f$i'});

      expect(await repo.countTracks(), 450);
    });

    test('clearProvider 清空该网盘的曲目、收藏、历史与续扫状态', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'ali', provider: DriveProvider.aliyun),
      ], capabilities: _quarkCap);
      await repo.setFavorite('quark:a', value: true);
      await repo.recordPlay('quark:a');
      await repo.saveScanCursor(ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: '0',
      ));

      await repo.clearProvider(DriveProvider.quark);

      expect(await repo.countTracks(provider: DriveProvider.quark), 0);
      expect(await repo.countTracks(provider: DriveProvider.aliyun), 1,
          reason: '不能波及其他网盘');
      expect(await repo.favoriteCount(), 0);
      expect(await repo.recentlyPlayed(), isEmpty);
      expect(await repo.loadScanCursor(DriveProvider.quark), isNull);
    });
  });

  // ===================================================================
  // 收藏
  // ===================================================================

  group('收藏', () {
    test('收藏可增删且幂等', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);

      expect(await repo.isFavorite('quark:a'), isFalse);

      await repo.setFavorite('quark:a', value: true);
      await repo.setFavorite('quark:a', value: true);
      expect(await repo.isFavorite('quark:a'), isTrue);
      expect(await repo.favoriteCount(), 1, reason: '重复收藏不能产生两行');

      await repo.setFavorite('quark:a', value: false);
      await repo.setFavorite('quark:a', value: false);
      expect(await repo.isFavorite('quark:a'), isFalse);
      expect(await repo.favoriteIds(), isEmpty);
    });

    test('删除曲目时级联清掉收藏与播放历史', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);
      await repo.setFavorite('quark:a', value: true);
      await repo.recordPlay('quark:a');

      await repo.deleteTracks({'quark:a'});

      expect(await repo.favoriteCount(), 0);
      expect(await repo.recentlyPlayed(), isEmpty);
    });
  });

  // ===================================================================
  // 运行时不可播标记
  // ===================================================================

  group('markUnplayable', () {
    test('标为超限后 is_playable 置 0 并写入原因', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);
      expect((await db.select(db.tracks).get()).single.isPlayable, isTrue);

      await repo.markUnplayable(
        'quark:a',
        state: PlayabilityState.overLimit,
        reason: '文件超出网盘允许的下载体积',
      );

      final row = (await db.select(db.tracks).get()).single;
      expect(row.isPlayable, isFalse);
      expect(row.playabilityState, 'overLimit');
      expect(row.playabilityNote, '文件超出网盘允许的下载体积');
    });

    test('标为「网盘不支持直链」同样置为不可播', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);

      await repo.markUnplayable(
        'quark:a',
        state: PlayabilityState.unsupportedByProvider,
        reason: '未开放直链',
      );

      final row = (await db.select(db.tracks).get()).single;
      expect(row.isPlayable, isFalse);
      expect(row.playabilityState, 'unsupportedByProvider');
    });

    test('标为体积未知时仍保持乐观可播（不该被误杀）', () async {
      await repo.upsertTracks(
        [_track(remoteId: 'a', name: 'a.flac', size: 1024)],
        capabilities: _quarkCap,
      );

      await repo.markUnplayable(
        'quark:a',
        state: PlayabilityState.unknownSize,
        reason: '体积待确认',
      );

      final row = (await db.select(db.tracks).get()).single;
      expect(row.isPlayable, isTrue, reason: 'unknownSize 属于乐观可播口径');
      expect(row.playabilityState, 'unknownSize');
    });

    test('reason 为 null 时保留原有的说明文案', () async {
      await repo.upsertTracks([_track(remoteId: 'a')], capabilities: _quarkCap);
      await repo.markUnplayable('quark:a',
          state: PlayabilityState.overLimit, reason: '第一次的原因');

      await repo.markUnplayable('quark:a', state: PlayabilityState.overLimit);

      final row = (await db.select(db.tracks).get()).single;
      expect(row.playabilityNote, '第一次的原因',
          reason: 'COALESCE 保留旧值，不该被 null 抹掉');
    });

    test('标记后立刻反映到统计里', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a', name: 'a.flac', size: 1024),
        _track(remoteId: 'b', name: 'b.flac', size: 2048),
      ], capabilities: _quarkCap);

      await repo.markUnplayable('quark:a',
          state: PlayabilityState.overLimit, reason: '运行时发现超限');

      final s = await repo.stats();
      expect(s.trackCount, 2);
      expect(s.playableCount, 1);
      expect(s.overLimitCount, 1);
      expect(s.playableBytes, 2048);
    });

    test('标记后该曲目退出随机候选集', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);

      await repo.markUnplayable('quark:a',
          state: PlayabilityState.overLimit, reason: '运行时发现超限');

      final cands = await repo.shuffleCandidates();
      expect(cands.keys.toSet(), {'quark:b'});
    });

    test('对不存在的 id 是安全空操作', () async {
      await expectLater(
        repo.markUnplayable('quark:nope',
            state: PlayabilityState.overLimit, reason: 'x'),
        completes,
      );
    });

    test('不影响其他曲目的可播状态', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);

      await repo.markUnplayable('quark:a',
          state: PlayabilityState.overLimit, reason: 'x');

      final rows = {
        for (final r in await db.select(db.tracks).get()) r.remoteId: r,
      };
      expect(rows['b']!.isPlayable, isTrue);
      expect(rows['b']!.playabilityState, 'playable');
    });
  });

  // ===================================================================
  // 播放统计
  // ===================================================================

  group('播放统计', () {
    test('recordPlay 累加次数并写历史；recentlyPlayed 按时间倒序', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a', name: 'a.flac'),
        _track(remoteId: 'b', name: 'b.flac'),
      ], capabilities: _quarkCap);

      await repo.recordPlay('quark:a', now: DateTime(2026, 9, 20));
      await repo.recordPlay('quark:b', now: DateTime(2026, 9, 22));
      await repo.recordPlay('quark:a',
          played: const Duration(seconds: 30), now: DateTime(2026, 9, 21));

      final recent = await repo.recentlyPlayed();
      expect(recent.map((t) => t.remoteId).toList(), ['b', 'a'],
          reason: '按最近一次播放时间倒序');

      final rows = {for (final r in await db.select(db.tracks).get()) r.remoteId: r};
      expect(rows['a']!.playCount, 2);
      expect(rows['a']!.lastPlayedAt, DateTime(2026, 9, 21));
      expect(rows['b']!.playCount, 1);

      final history = await db.select(db.playHistory).get();
      expect(history.length, 3);
      expect(history.map((h) => h.playedSeconds), contains(30));
    });

    test('recentlyPlayed 的 limit 生效且同一首只出现一次', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);

      await repo.recordPlay('quark:a', now: DateTime(2026, 9, 20));
      await repo.recordPlay('quark:a', now: DateTime(2026, 9, 21));
      await repo.recordPlay('quark:b', now: DateTime(2026, 9, 19));

      final recent = await repo.recentlyPlayed(limit: 1);
      expect(recent.map((t) => t.remoteId).toList(), ['a']);
    });

    test('shuffleCandidates 只含可尝试曲目并带出播放次数', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok', name: 'a.flac'),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
        _track(remoteId: 'unk', name: 'c.flac', size: null),
      ], capabilities: _quarkCap);
      await repo.recordPlay('quark:ok', now: DateTime(2026, 9, 22));

      final cands = await repo.shuffleCandidates(provider: DriveProvider.quark);

      expect(cands.keys.toSet(), {'quark:ok', 'quark:unk'},
          reason: '超限曲目不该进入随机池');
      expect(cands['quark:ok']!.playCount, 1);
      expect(cands['quark:ok']!.lastPlayedAt, DateTime(2026, 9, 22));
      expect(cands['quark:unk']!.playCount, 0);
      expect(cands['quark:unk']!.lastPlayedAt, isNull);
    });

    test('shuffleCandidates 关掉 playableOnly 时包含全部曲目', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok', name: 'a.flac'),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
      ], capabilities: _quarkCap);

      final cands = await repo.shuffleCandidates(
        provider: DriveProvider.quark,
        playableOnly: false,
      );
      expect(cands.length, 2);
    });

    test('未播放过的曲目也在候选集里（否则冷门永远沉底）', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a'),
        _track(remoteId: 'b'),
      ], capabilities: _quarkCap);

      final cands = await repo.shuffleCandidates();
      expect(cands.length, 2);
      expect(cands.values.every((c) => c.playCount == 0), isTrue);
    });
  });

  // ===================================================================
  // 统计口径
  // ===================================================================

  group('stats / playabilitySummary', () {
    test('stats 区分「严格可播」与「可尝试」，比例不重复计数', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok1', name: 'a.flac', size: 1024),
        _track(remoteId: 'ok2', name: 'b.flac', size: 2048),
        _track(remoteId: 'big', name: 'c.flac', size: 60 * _mib),
        _track(remoteId: 'unk', name: 'd.flac', size: null),
      ], capabilities: _quarkCap);

      final s = await repo.stats(provider: DriveProvider.quark);

      expect(s.trackCount, 4);
      expect(s.playableCount, 2, reason: '严格口径：只有 2 首确认可播');
      expect(s.unknownSizeCount, 1);
      expect(s.attemptableCount, 3, reason: '乐观口径：2 可播 + 1 体积未知');
      expect(s.overLimitCount, 1);
      expect(s.playableRatio, closeTo(0.75, 1e-9),
          reason: '未知体积只能算一次，否则比例虚高');
      expect(s.attemptableRatio, closeTo(0.75, 1e-9));
      expect(s.totalBytes, 1024 + 2048 + 60 * _mib);
      expect(s.playableBytes, 1024 + 2048);
      expect(s.playableBytesRatio, lessThan(0.01));
    });

    test('stats 统计艺术家与专辑去重数，空值不计入', () async {
      await repo.upsertTracks([
        _track(remoteId: '1', artist: '周杰伦', album: '叶惠美'),
        _track(remoteId: '2', artist: '周杰伦', album: '七里香'),
        _track(remoteId: '3', artist: '陈奕迅', album: 'U87'),
        _track(remoteId: '4', artist: '', album: null),
      ], capabilities: _quarkCap);

      final s = await repo.stats();
      expect(s.artistCount, 2);
      expect(s.albumCount, 3);
    });

    test('stats 可按网盘分别统计', () async {
      await repo.upsertTracks([
        _track(remoteId: 'q1'),
        _track(remoteId: 'a1', provider: DriveProvider.aliyun),
        _track(remoteId: 'a2', provider: DriveProvider.aliyun),
      ], capabilities: _quarkCap);

      expect((await repo.stats(provider: DriveProvider.quark)).trackCount, 1);
      expect((await repo.stats(provider: DriveProvider.aliyun)).trackCount, 2);
      expect((await repo.stats()).trackCount, 3);
    });

    test('空库的 stats 是零值且比例不炸', () async {
      final s = await repo.stats();
      expect(s.isEmpty, isTrue);
      expect(s.playableRatio, 0);
      expect(s.playableBytesRatio, 0);
      expect(s.attemptableRatio, 0);
    });

    test('playabilitySummary 与扫描阶段同口径', () async {
      await repo.upsertTracks([
        _track(remoteId: 'ok', name: 'a.flac', size: 1024),
        _track(remoteId: 'big', name: 'b.flac', size: 60 * _mib),
        _track(remoteId: 'unk', name: 'c.flac', size: null),
        _track(remoteId: 'txt', name: 'cover.txt', size: 10),
      ], capabilities: _quarkCap);

      final s = await repo.playabilitySummary(provider: DriveProvider.quark);

      expect(s.playable, 1);
      expect(s.overLimit, 1);
      expect(s.unknownSize, 1);
      expect(s.notAudio, 1);
      expect(s.unsupported, 0);
      expect(s.total, 4);
      expect(s.playableBytes, 1024, reason: '体积未知按 0 计入可播体积');
      expect(s.playableRatio, closeTo(2 / 3, 1e-9),
          reason: '分母刻意排除 notAudio（非音频文件不该算进「想听的曲目」），'
              '即 (可播 1 + 未知 1) / (可播 1 + 超限 1 + 未知 1)');
    });

    test('能力不支持直链时整体判为 unsupportedByProvider', () async {
      await repo.upsertTracks(
        [_track(remoteId: 'a', name: 'a.flac')],
        capabilities: const Capabilities(
          provider: DriveProvider.quark,
          canResolveDirectLink: false,
        ),
      );

      final s = await repo.playabilitySummary();
      expect(s.unsupported, 1);
      expect(s.playable, 0);
    });
  });

  // ===================================================================
  // 续扫游标
  // ===================================================================

  group('续扫游标', () {
    test('完整往返：队列 / 当前目录 / 分页游标 / 计数 / 阶段', () async {
      final base = ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: '0',
        now: DateTime(2026, 9, 23, 10),
      )
          .enqueueIfAbsent(
            const PendingDir(id: 'd1', path: '/音乐/', depth: 1),
            DateTime(2026, 9, 23, 10),
          )
          .addCounts(
            dirs: 3,
            files: 40,
            tracks: 12,
            bytes: 999,
            failures: 1,
            now: DateTime(2026, 9, 23, 10),
          );

      await repo.saveScanCursor(base.copyWith(
        currentDir: const PendingDir(id: 'd9', path: '/音乐/华语/', depth: 2),
        currentPageToken: 'tok-2',
        stage: ScanStage.running,
      ));

      final back = await repo.loadScanCursor(DriveProvider.quark);

      expect(back, isNotNull);
      expect(back!.provider, DriveProvider.quark);
      expect(back.rootId, '0');
      expect(back.pendingDirs.map((d) => d.id).toList(), ['0', 'd1'],
          reason: 'BFS 队列顺序必须原样保留');
      expect(back.pendingDirs.last.path, '/音乐/');
      expect(back.pendingDirs.last.depth, 1);
      expect(back.currentDir?.id, 'd9');
      expect(back.currentDir?.path, '/音乐/华语/');
      expect(back.currentPageToken, 'tok-2');
      expect(back.stage, ScanStage.running);
      expect(back.scannedDirs, 3);
      expect(back.scannedFiles, 40);
      expect(back.foundTracks, 12);
      expect(back.totalBytes, 999);
      expect(back.failedDirs, 1);
    });

    test('同一网盘只保留一行（重复保存是覆盖不是追加）', () async {
      for (var i = 0; i < 3; i++) {
        await repo.saveScanCursor(ScanCursor.fresh(
          provider: DriveProvider.quark,
          rootId: '0',
          now: DateTime(2026, 9, 23, 10 + i),
        ));
      }

      final rows = await db.select(db.scanStates).get();
      expect(rows.length, 1);
      expect(rows.single.updatedAt, DateTime(2026, 9, 23, 12));
    });

    test('每个网盘的续扫状态互不干扰', () async {
      await repo.saveScanCursor(ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: '0',
      ));
      await repo.saveScanCursor(ScanCursor.fresh(
        provider: DriveProvider.aliyun,
        rootId: 'root',
      ));

      expect((await repo.loadScanCursor(DriveProvider.quark))!.rootId, '0');
      expect((await repo.loadScanCursor(DriveProvider.aliyun))!.rootId, 'root');
      expect(await repo.loadScanCursor(DriveProvider.baidu), isNull);
    });

    test('未知 stageId 回落到 paused（可续扫），不会假装已扫完', () async {
      await db.into(db.scanStates).insert(ScanStatesCompanion.insert(
            providerId: 'quark',
            rootId: '0',
            rootPath: '/',
            pendingDirsJson: '[]',
            stageId: 'stage-from-a-newer-version',
            updatedAt: DateTime(2026, 9, 23),
          ));

      final c = await repo.loadScanCursor(DriveProvider.quark);

      expect(c!.stage, ScanStage.paused);
      expect(c.isComplete, isFalse,
          reason: '最坏是多扫一次，不能骗用户说扫完了');
    });

    test('损坏的队列 JSON 被跳过而不是整体失败', () async {
      await db.into(db.scanStates).insert(ScanStatesCompanion.insert(
            providerId: 'quark',
            rootId: '0',
            rootPath: '/',
            pendingDirsJson: 'this is not json',
            currentDirJson: const Value('{"id":"d1","path":"/音乐/","depth":1}'),
            stageId: 'paused',
            updatedAt: DateTime(2026, 9, 23),
          ));

      final c = await repo.loadScanCursor(DriveProvider.quark);

      expect(c!.pendingDirs, isEmpty);
      expect(c.currentDir?.id, 'd1');
    });

    test('队列里 id 为空的脏条目被丢弃', () async {
      await db.into(db.scanStates).insert(ScanStatesCompanion.insert(
            providerId: 'quark',
            rootId: '0',
            rootPath: '/',
            pendingDirsJson:
                '[{"id":"good","path":"/a/","depth":1},{"path":"/b/","depth":1}]',
            stageId: 'paused',
            updatedAt: DateTime(2026, 9, 23),
          ));

      final c = await repo.loadScanCursor(DriveProvider.quark);
      expect(c!.pendingDirs.map((d) => d.id).toList(), ['good']);
    });

    test('clearScanCursor 只清指定网盘', () async {
      await repo.saveScanCursor(
          ScanCursor.fresh(provider: DriveProvider.quark, rootId: '0'));
      await repo.saveScanCursor(
          ScanCursor.fresh(provider: DriveProvider.aliyun, rootId: 'root'));

      await repo.clearScanCursor(DriveProvider.quark);

      expect(await repo.loadScanCursor(DriveProvider.quark), isNull);
      expect(await repo.loadScanCursor(DriveProvider.aliyun), isNotNull);
    });
  });

  // ===================================================================
  // 账号
  // ===================================================================

  group('账号', () {
    test('账号展示信息往返，且表里不含任何凭证字段', () async {
      await repo.saveAccount(
        CloudAccount(
          provider: DriveProvider.quark,
          authMode: AuthMode.browserCookie,
          authorizedAt: DateTime(2026, 9, 23),
          userId: 'u1',
          displayName: '听歌的人',
          storageUsedBytes: 100,
          storageTotalBytes: 1000,
          memberLabel: 'SUPER_VIP',
        ),
        scannedAt: DateTime(2026, 9, 23, 12),
      );

      final list = await repo.accounts();
      expect(list.length, 1);
      expect(list.single.displayName, '听歌的人');
      expect(list.single.authMode, AuthMode.browserCookie);
      expect(list.single.memberLabel, 'SUPER_VIP');
      expect(list.single.storageRatio, closeTo(0.1, 1e-9));

      final s = await repo.stats(provider: DriveProvider.quark);
      expect(s.lastScannedAt, DateTime(2026, 9, 23, 12));

      // 凭证只进钥匙串，账号表里绝不能有相关列
      final cols = await db.customSelect('PRAGMA table_info(accounts)').get();
      final names = cols.map((r) => r.read<String>('name')).toList();
      for (final forbidden in ['cookie', 'token', 'credential', 'secret', 'password']) {
        expect(names.any((n) => n.contains(forbidden)), isFalse,
            reason: 'accounts 表不该出现 $forbidden 字段');
      }
    });

    test('重复保存同一账号是覆盖，不产生第二行', () async {
      for (var i = 0; i < 3; i++) {
        await repo.saveAccount(CloudAccount(
          provider: DriveProvider.quark,
          authMode: AuthMode.browserCookie,
          authorizedAt: DateTime(2026, 9, 23),
          displayName: '第 $i 次',
        ));
      }

      final list = await repo.accounts();
      expect(list.length, 1);
      expect(list.single.displayName, '第 2 次');
    });

    test('removeAccount 只移除指定网盘', () async {
      await repo.saveAccount(CloudAccount(
        provider: DriveProvider.quark,
        authMode: AuthMode.browserCookie,
        authorizedAt: DateTime(2026, 9, 23),
      ));
      await repo.saveAccount(CloudAccount(
        provider: DriveProvider.aliyun,
        authMode: AuthMode.oauth,
        authorizedAt: DateTime(2026, 9, 23),
      ));

      await repo.removeAccount(DriveProvider.quark);

      final list = await repo.accounts();
      expect(list.map((a) => a.provider).toList(), [DriveProvider.aliyun]);
    });

    test('未知 providerId / authModeId 的行被安全跳过或回落', () async {
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            providerId: 'unknown-drive',
            authModeId: 'browser_cookie',
            authorizedAt: DateTime(2026, 9, 23),
          ));

      expect(await repo.accounts(), isEmpty,
          reason: '认不出的网盘不能崩，直接跳过');
    });
  });

  // ===================================================================
  // CUE 分轨字段
  // ===================================================================

  group('CUE 分轨字段落库与回读', () {
    /// 一张整轨 WAV（72:18 / 765MB），用来切段。
    Track image() => Track(
          provider: DriveProvider.quark,
          remoteId: 'wav765',
          name: 'CD1.wav',
          path: '/音乐/精选/',
          sizeBytes: 765145628,
          durationMs: 4338000,
          title: '精选到无朋友',
        );

    test('整轨切出的 N 段都能入库，且是 N 行而不是 1 行', () async {
      final src = image();
      await repo.upsertTracks([
        src,
        Track.cueSegment(
            source: src, trackNo: 1, startMs: 0, durationMs: 200493, title: '红日'),
        Track.cueSegment(
            source: src,
            trackNo: 2,
            startMs: 200493,
            durationMs: 219507,
            title: '月半小夜曲'),
        Track.cueSegment(
            source: src,
            trackNo: 3,
            startMs: 420000,
            durationMs: 300000,
            title: '护花使者'),
      ], capabilities: _quarkCap);

      // 4 行：整轨本身 + 3 段。主键是 id（带 #cN 后缀），所以不会互相覆盖。
      expect(await repo.countTracks(), 4);

      final tracks = await repo.queryTracks();
      final segments = tracks.where((t) => t.isCueSegment).toList();
      expect(segments, hasLength(3));
      expect(segments.map((t) => t.id).toSet(), hasLength(3));
    });

    test('轨号 / 起点 / 本轨时长能原样回读', () async {
      final src = image();
      final seg = Track.cueSegment(
        source: src,
        trackNo: 2,
        startMs: 200493,
        durationMs: 219507,
        title: '月半小夜曲',
        artist: '李克勤',
        album: '精选到无朋友',
      );
      await repo.upsertTracks([src, seg], capabilities: _quarkCap);

      final back = await repo.trackById(seg.id);
      expect(back, isNotNull);
      expect(back!.cueTrackNo, 2);
      expect(back.cueStartMs, 200493);
      expect(back.durationMs, 219507);
      // 起点 + 本轨时长 = 终点，播放引擎靠它切歌
      expect(back.cueEndMs, 420000);
      expect(back.title, '月半小夜曲');
      expect(back.artist, '李克勤');
      expect(back.album, '精选到无朋友');
      // 取流要用整轨文件的 id，不能是带后缀的曲目 id
      expect(back.remoteId, 'wav765');
      expect(back.id, 'quark:wav765#c2');
    });

    test('普通曲目回读时 CUE 两列为 null（不是 0）', () async {
      await repo.upsertTracks([_track(remoteId: 'plain')],
          capabilities: _quarkCap);

      final back = await repo.trackById('quark:plain');
      expect(back!.cueTrackNo, isNull);
      expect(back.cueStartMs, isNull);
      expect(back.isCueSegment, isFalse);
      expect(back.isFromCue, isFalse);
    });

    test('换了一份 CUE（分轨点变了）→ 重复 upsert 会覆盖，不产生新行', () async {
      final src = image();
      await repo.upsertTracks(
        [Track.cueSegment(source: src, trackNo: 1, startMs: 0, durationMs: 1000)],
        capabilities: _quarkCap,
      );
      // 同一轨号 → 同一 id → 覆盖
      await repo.upsertTracks(
        [Track.cueSegment(source: src, trackNo: 1, startMs: 32, durationMs: 968)],
        capabilities: _quarkCap,
      );

      expect(await repo.countTracks(), 1);
      final back = await repo.trackById('quark:wav765#c1');
      expect(back!.cueStartMs, 32, reason: '分轨点必须是新的那份 CUE 的值');
    });

    test('收藏按曲目 id 记，同整轨的不同段互不影响', () async {
      final src = image();
      final seg1 =
          Track.cueSegment(source: src, trackNo: 1, startMs: 0, durationMs: 1000);
      final seg2 = Track.cueSegment(
          source: src, trackNo: 2, startMs: 1000, durationMs: 1000);
      await repo.upsertTracks([seg1, seg2], capabilities: _quarkCap);

      await repo.setFavorite(seg1.id, value: true);

      expect(await repo.isFavorite(seg1.id), isTrue);
      expect(await repo.isFavorite(seg2.id), isFalse);
      expect(await repo.favoriteIds(), {seg1.id});
    });

    test('分轨元数据增强：只覆盖 title/artist/album，id 不变', () async {
      // 分轨场景下每首歌本来就是独立文件，CUE 只提供更可信的元数据
      final own = _track(
        remoteId: 'flac1',
        name: '01 - unknown.flac',
        title: '未知',
      ).copyWith(cueTrackNo: 1, title: '红日', artist: '李克勤');

      await repo.upsertTracks([own], capabilities: _quarkCap);

      final back = await repo.trackById('quark:flac1');
      expect(back!.id, 'quark:flac1', reason: '独立文件的主键不该被 CUE 改掉');
      expect(back.cueTrackNo, 1);
      expect(back.cueStartMs, isNull, reason: '独立文件没有「整轨内起点」');
      expect(back.isCueSegment, isFalse);
      expect(back.title, '红日');
      expect(back.artist, '李克勤');
    });
  });

  // ===================================================================
  // 专辑封面
  // ===================================================================

  AlbumCover coverRow({
    String dirPath = '/音乐/叶惠美',
    String fileId = 'img1',
    String fileName = 'cover.jpg',
    int? size = 200 * 1024,
    DriveProvider provider = DriveProvider.quark,
  }) =>
      AlbumCover(
        provider: provider,
        dirPath: dirPath,
        fileId: fileId,
        fileName: fileName,
        sizeBytes: size,
      );

  group('专辑封面', () {
    test('写入后可查询，按目录索引', () async {
      await repo.upsertAlbumCovers([
        coverRow(),
        coverRow(dirPath: '/音乐/七里香', fileId: 'img2', fileName: 'folder.png'),
      ]);

      final covers = await repo.albumCovers(DriveProvider.quark);

      expect(covers.keys, containsAll(['/音乐/叶惠美', '/音乐/七里香']));
      expect(covers['/音乐/叶惠美']!.fileName, 'cover.jpg');
      expect(covers['/音乐/七里香']!.fileName, 'folder.png');
      expect(covers['/音乐/七里香']!.provider, DriveProvider.quark);
    });

    test('同一目录重复写入是覆盖，不是新增', () async {
      await repo.upsertAlbumCovers([coverRow(fileId: 'old', fileName: 'old.jpg')]);
      await repo.upsertAlbumCovers([coverRow(fileId: 'new', fileName: 'new.jpg')]);

      final covers = await repo.albumCovers(DriveProvider.quark);
      expect(covers, hasLength(1));
      expect(covers['/音乐/叶惠美']!.fileId, 'new');
    });

    test('空列表是空操作', () async {
      await repo.upsertAlbumCovers(const []);
      expect(await repo.albumCovers(DriveProvider.quark), isEmpty);
    });

    test('按网盘隔离 —— 两个网盘的同名目录互不覆盖', () async {
      await repo.upsertAlbumCovers([
        coverRow(provider: DriveProvider.quark, fileId: 'q'),
        coverRow(provider: DriveProvider.aliyun, fileId: 'a'),
      ]);

      expect(
        (await repo.albumCovers(DriveProvider.quark))['/音乐/叶惠美']!.fileId,
        'q',
      );
      expect(
        (await repo.albumCovers(DriveProvider.aliyun))['/音乐/叶惠美']!.fileId,
        'a',
      );
    });

    test('清理陈旧封面：只留白名单里的目录', () async {
      await repo.upsertAlbumCovers([
        coverRow(dirPath: '/a', fileId: '1'),
        coverRow(dirPath: '/b', fileId: '2'),
        coverRow(dirPath: '/c', fileId: '3'),
      ]);

      final removed = await repo.deleteAlbumCoversNotIn(
        DriveProvider.quark,
        {'/a', '/c'},
      );

      expect(removed, 1);
      final covers = await repo.albumCovers(DriveProvider.quark);
      expect(covers.keys, containsAll(['/a', '/c']));
      expect(covers.keys, isNot(contains('/b')));
    });

    test('清理陈旧封面时不影响别的网盘', () async {
      await repo.upsertAlbumCovers([
        coverRow(provider: DriveProvider.quark, dirPath: '/a', fileId: '1'),
        coverRow(provider: DriveProvider.aliyun, dirPath: '/a', fileId: '2'),
      ]);

      await repo.deleteAlbumCoversNotIn(DriveProvider.quark, const {});

      expect(await repo.albumCovers(DriveProvider.quark), isEmpty);
      expect(await repo.albumCovers(DriveProvider.aliyun), hasLength(1));
    });

    test('清空网盘时封面一起清掉', () async {
      await repo.upsertAlbumCovers([coverRow()]);

      await repo.clearProvider(DriveProvider.quark);

      expect(await repo.albumCovers(DriveProvider.quark), isEmpty);
    });
  });

  // ===================================================================
  // 按目录查曲目 / 排序
  // ===================================================================

  group('TrackQuery.dirPath（专辑详情页）', () {
    test('带不带结尾斜杠都能查到 —— path 是展示路径，目录键是归一化的', () async {
      await repo.upsertTracks([
        _track(remoteId: 'f1', name: 'a.flac', path: '/音乐/叶惠美/'),
        _track(remoteId: 'f2', name: 'b.flac', path: '/音乐/七里香/'),
      ], capabilities: _quarkCap);

      for (final dir in const [
        '/音乐/叶惠美',
        '/音乐/叶惠美/',
      ]) {
        final hits = await repo.queryTracks(TrackQuery(dirPath: dir));
        expect(hits, hasLength(1), reason: dir);
        expect(hits.single.remoteId, 'f1', reason: dir);
      }
    });

    test('同名专辑（不同目录）不会互相混入', () async {
      await repo.upsertTracks([
        _track(remoteId: 'a', name: 'x.flac', album: '叶惠美',
            path: '/音乐/叶惠美 [16B-44.1kHz]/'),
        _track(remoteId: 'b', name: 'x.flac', album: '叶惠美',
            path: '/音乐/叶惠美 [24B-48kHz]/'),
      ], capabilities: _quarkCap);

      final hits = await repo
          .queryTracks(const TrackQuery(dirPath: '/音乐/叶惠美 [24B-48kHz]'));
      expect(hits.map((t) => t.remoteId), ['b']);
    });

    test('path 为 null 的曲目不会命中任何目录', () async {
      await repo.upsertTracks([
        _track(remoteId: 'f1', name: 'a.flac'),
      ], capabilities: _quarkCap);

      expect(await repo.queryTracks(const TrackQuery(dirPath: '/')), isEmpty);
    });
  });

  group('整轨分段的排序', () {
    /// 一张整轨切出的 12 段，全部同名（都叫整轨文件名）
    Future<void> seedSegments() async {
      final image = Track(
        provider: DriveProvider.quark,
        remoteId: 'wav',
        name: 'CD1.wav',
        sizeBytes: 700 * _mib,
        path: '/音乐/精选/',
      );
      final segments = [
        for (var i = 1; i <= 12; i++)
          Track.cueSegment(
            source: image,
            trackNo: i,
            startMs: (i - 1) * 200000,
            durationMs: 200000,
          ),
      ];
      await repo.upsertTracks(segments, capabilities: _quarkCap);
    }

    test('按轨号而不是 id 字典序 —— 第 10 首不该排到第 2 首前面', () async {
      await seedSegments();

      final tracks = await repo.queryTracks();

      expect(tracks, hasLength(12));
      expect(
        tracks.map((t) => t.cueTrackNo).toList(),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        reason: 'id 是 quark:wav#c1 / #c10 / #c2…，只按 id 排会把第 10 首排到前面',
      );
    });

    test('专辑页用的排序同样按轨号', () async {
      await seedSegments();

      final tracks = await repo.queryTracks(
        const TrackQuery(dirPath: '/音乐/精选', sort: TrackSort.albumAsc),
      );

      expect(tracks.map((t) => t.cueTrackNo).toList(), List.generate(12, (i) => i + 1));
    });
  });
}
