import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/data/registry/drive_adapter_registry.dart';
import 'package:cloudtune/domain/adapters/cloud_drive_adapter.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/scan_cursor.dart';
import 'package:cloudtune/domain/entities/scan_policy.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/scan_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

// =====================================================================
// 假网盘：用一棵内存目录树驱动扫描器，并记录调用轨迹
// =====================================================================

class _FakeDriveAdapter implements CloudDriveAdapter {
  _FakeDriveAdapter({
    required this.tree,
    this.forcedPageSize,
    this.failDirIds = const {},
    this.failNeedsReauth = false,
    this.canListDirectory = true,
  });

  /// `dirId → 该目录下的条目`。没有 key 视为空目录。
  final Map<String, List<DriveEntry>> tree;

  @override
  DriveProvider get provider => DriveProvider.quark;

  /// 强制每页条目数，用来验证分页循环（不管调用方传多少）
  final int? forcedPageSize;

  /// 这些目录列目录时抛错
  final Set<String> failDirIds;

  /// 抛出的错误是否属于「需要重新授权」
  final bool failNeedsReauth;

  final bool canListDirectory;

  /// 列目录的调用轨迹：`dirId` 或 `dirId#pageToken`
  final List<String> calls = [];

  @override
  Capabilities get capabilities => Capabilities(
        provider: DriveProvider.quark,
        maxSingleFileBytes: Capabilities.fiftyMiB,
        canListDirectory: canListDirectory,
      );

  @override
  String get rootId => 'root';

  @override
  Future<DrivePage> listDirectory({
    required String dirId,
    String? pageToken,
    int? pageSize,
  }) async {
    calls.add(pageToken == null ? dirId : '$dirId#$pageToken');

    if (failDirIds.contains(dirId)) {
      throw DriveException(
        type: failNeedsReauth
            ? DriveErrorType.unauthorized
            : DriveErrorType.permissionDenied,
        message: '列目录失败：$dirId',
      );
    }

    final all = tree[dirId] ?? const <DriveEntry>[];
    final size = forcedPageSize ?? pageSize ?? 50;
    final start = pageToken == null ? 0 : int.parse(pageToken);
    final end = (start + size).clamp(0, all.length);
    return DrivePage(
      entries: all.sublist(start, end),
      nextPageToken: end >= all.length ? null : '$end',
    );
  }

  @override
  Future<List<DriveEntry>> search({
    required String keyword,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<StreamTicket> resolveStream(String fileId) async =>
      throw UnimplementedError('扫描流程不应取直链');

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> ping() async => true;

  @override
  Future<void> dispose() async {}
}

// =====================================================================
// 造节点
// =====================================================================

DriveEntry _dir(String id, String name) =>
    DriveEntry(id: id, name: name, isDirectory: true);

DriveEntry _file(String id, String name, {int? size = 1024}) => DriveEntry(
      id: id,
      name: name,
      isDirectory: false,
      sizeBytes: size,
    );

/// 标准目录树：
///
/// ```
/// /（root）
/// ├── 华语/（d1）
/// │   ├── 周杰伦/（d2）    → 3 首 flac（30/20/10 MiB，都可播）
/// │   ├── 陈奕迅/（d3）    → 1 首 flac（25 MiB）+ 1 首 dsf（200 MiB，超限）
/// │   └── 说明.txt
/// ├── 欧美/（d4）          → 2 首 flac（15/18 MiB）
/// ├── .Trash/（d5）        → 应被策略跳过
/// └── 封面.jpg
/// ```
///
/// 合计：**7 个音频文件 / 318 MiB**、3 个非音频文件、5 个待扫目录。
Map<String, List<DriveEntry>> _standardTree() => {
      'root': [
        _dir('d1', '华语'),
        _dir('d4', '欧美'),
        _dir('d5', '.Trash'),
        _file('fcover', '封面.jpg', size: 200 * 1024),
      ],
      'd1': [
        _dir('d2', '周杰伦'),
        _dir('d3', '陈奕迅'),
        _file('freadme', '说明.txt', size: 10),
      ],
      'd2': [
        _file('f1', '周杰伦 - 晴天.flac', size: 30 * _mib),
        _file('f2', '周杰伦 - 七里香.flac', size: 20 * _mib),
        _file('f3', '周杰伦 - 夜曲.flac', size: 10 * _mib),
      ],
      'd3': [
        _file('f4', '陈奕迅 - 浮夸.flac', size: 25 * _mib),
        _file('f5', '陈奕迅 - 富士山下.dsf', size: 200 * _mib),
        _file('f6', 'cover.jpg', size: 100 * 1024),
      ],
      'd4': [
        _file('f7', 'Adele - Hello.flac', size: 15 * _mib),
        _file('f8', 'Adele - Easy On Me.flac', size: 18 * _mib),
      ],
      'd5': [
        _file('f9', '回收站里的歌.flac', size: 5 * _mib),
      ],
    };

/// `root` 下有 [n] 个子目录，每个子目录各一首 1MiB 的 flac。
Map<String, List<DriveEntry>> _wideTree(int n) => {
      'root': [for (var i = 0; i < n; i++) _dir('d$i', 'dir$i')],
      for (var i = 0; i < n; i++)
        'd$i': [_file('f$i', 'track$i.flac', size: _mib)],
    };

/// 一条「网盘侧已被删除」的曲目，用来验证陈旧清理。
Track _staleTrack() => Track(
      provider: DriveProvider.quark,
      remoteId: 'stale',
      name: '已经删掉的歌.flac',
      sizeBytes: 1024,
    );

void main() {
  late AppDatabase db;
  late DriftLibraryRepository repo;
  late _FakeDriveAdapter adapter;

  /// 造一个新的扫描服务（同时替换掉 [adapter]）。
  ScanService build({
    Map<String, List<DriveEntry>>? tree,
    int? forcedPageSize,
    Set<String> failDirIds = const {},
    bool failNeedsReauth = false,
    bool canListDirectory = true,
    ScanPolicy policy = const ScanPolicy(),
  }) {
    adapter = _FakeDriveAdapter(
      tree: tree ?? _standardTree(),
      forcedPageSize: forcedPageSize,
      failDirIds: failDirIds,
      failNeedsReauth: failNeedsReauth,
      canListDirectory: canListDirectory,
    );
    return ScanService(
      registry: DefaultDriveAdapterRegistry([adapter]),
      library: repo,
      policy: policy,
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() => db.close());

  // ===================================================================
  // 全盘遍历
  // ===================================================================

  group('全盘遍历', () {
    test('BFS 遍历所有目录，只把音频文件入库', () async {
      final service = build();

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.tracksIndexed, 7);
      expect(await repo.countTracks(), 7);

      final names = (await repo.queryTracks()).map((t) => t.name).toSet();
      expect(names, contains('周杰伦 - 晴天.flac'));
      expect(names, contains('陈奕迅 - 富士山下.dsf'),
          reason: '超限曲目仍要入库，只是打上不可播标记');
      expect(names, isNot(contains('封面.jpg')));
      expect(names, isNot(contains('说明.txt')));
    });

    test('按 BFS 层序访问目录：先根、再第一层、最后第二层', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      expect(adapter.calls, ['root', 'd1', 'd4', 'd2', 'd3'],
          reason: 'BFS 而非 DFS：同层目录连续访问');
    });

    test('跳过隐藏目录（不浪费接口配额）', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      expect(adapter.calls, isNot(contains('d5')),
          reason: '.Trash 应被 ScanPolicy 跳过');
      final names = (await repo.queryTracks()).map((t) => t.name).toList();
      expect(names, isNot(contains('回收站里的歌.flac')));
    });

    test('记录所在目录路径，便于 UI 按目录浏览', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      final track = await repo.trackById('quark:f1');
      expect(track!.path, '/华语/周杰伦/');
    });

    test('计数与体积统计正确（非音频只计数不入库）', () async {
      final service = build();

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.cursor.scannedDirs, 5, reason: 'root + d1 + d4 + d2 + d3');
      expect(outcome.cursor.scannedFiles, 10, reason: '7 音频 + 3 非音频');
      expect(outcome.cursor.foundTracks, 7);
      expect(outcome.cursor.totalBytes, 318 * _mib);
      expect(outcome.wasCancelled, isFalse);
      expect(outcome.error, isNull);
      expect(outcome.isComplete, isTrue);
    });

    test('扫描完成后阶段为 completed，游标已落库且队列清空', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      final persisted = await repo.loadScanCursor(DriveProvider.quark);
      expect(persisted!.stage, ScanStage.completed);
      expect(persisted.isComplete, isTrue);
      expect(persisted.pendingDirs, isEmpty);
      expect(persisted.currentDir, isNull);
      expect(persisted.hasPendingWork, isFalse);
    });

    test('返回可播性体检报告，超限与可播分开计数', () async {
      final service = build();

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.playability.playable, 6);
      expect(outcome.playability.overLimit, 1, reason: '200 MiB 的 dsf');
      expect(outcome.playability.notAudio, 0, reason: '非音频压根不入库');
      expect(outcome.playability.playableBytes, 118 * _mib);
      expect(outcome.playability.totalBytes, 318 * _mib);
    });

    test('空目录树不会卡住，直接完成', () async {
      final service = build(tree: {'root': []});

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.isComplete, isTrue);
      expect(outcome.cursor.scannedDirs, 1);
      expect(await repo.countTracks(), 0);
    });
  });

  // ===================================================================
  // 分页
  // ===================================================================

  group('分页', () {
    test('一个目录跨多页时全部取回（不因只取一页而漏曲）', () async {
      final service = build(
        tree: {
          'root': [
            for (var i = 0; i < 7; i++) _file('p$i', 'track$i.flac', size: _mib),
          ],
        },
        forcedPageSize: 2,
      );

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.tracksIndexed, 7);
      expect(adapter.calls, ['root', 'root#2', 'root#4', 'root#6'],
          reason: '每页 2 条，取到不满页为止');
    });

    test('恰好整页时也能正确终止（靠「不满页」判断，不靠 total）', () async {
      final service = build(
        tree: {
          'root': [
            for (var i = 0; i < 4; i++) _file('e$i', 'track$i.flac', size: _mib),
          ],
        },
        forcedPageSize: 2,
      );

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.tracksIndexed, 4);
      expect(adapter.calls, ['root', 'root#2'],
          reason: '第二页取满后不会再发第三页请求');
    });

    test('每页都会落库续扫游标（中途被杀能原地续上）', () async {
      final service = build(
        tree: {
          'root': [
            for (var i = 0; i < 6; i++) _file('p$i', 'track$i.flac', size: _mib),
          ],
        },
        forcedPageSize: 2,
      );

      final seenTokens = <String?>[];
      await service.scan(
        DriveProvider.quark,
        onProgress: (p) => seenTokens.add(p.cursor.currentPageToken),
      );

      // 进度回调里能看到中间态 pageToken，说明是「逐页落库」而不是最后一次性写
      expect(seenTokens, contains('2'));
      expect(seenTokens, contains('4'));
      expect(seenTokens.length, greaterThan(3));
    });
  });

  // ===================================================================
  // 断点续扫
  // ===================================================================

  group('断点续扫', () {
    test('从未扫过时从根目录开始', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      expect(adapter.calls.first, 'root');
    });

    test('已有未完成游标时接着扫，不重扫已完成的目录', () async {
      // 模拟「上次扫完 root 与 d1 就被杀了」
      await repo.saveScanCursor(
        ScanCursor.fresh(
          provider: DriveProvider.quark,
          rootId: 'root',
          now: DateTime(2026, 9, 23, 10),
        )
            .dequeue(DateTime(2026, 9, 23, 10)) // 取出 root
            .copyWith(
              clearCurrentDir: true,
              scannedDirs: 1,
              stage: ScanStage.paused,
            )
            .enqueueIfAbsent(
              const PendingDir(id: 'd2', path: '/华语/周杰伦/', depth: 2),
              DateTime(2026, 9, 23, 10),
            )
            .enqueueIfAbsent(
              const PendingDir(id: 'd4', path: '/欧美/', depth: 1),
              DateTime(2026, 9, 23, 10),
            ),
      );

      final service = build();
      await service.scan(DriveProvider.quark);

      expect(adapter.calls, isNot(contains('root')),
          reason: 'root 已扫过，不该重扫');
      expect(adapter.calls, isNot(contains('d1')));
      expect(adapter.calls, containsAll(['d2', 'd4']));
    });

    test('resume: false 时无视旧游标，从头重扫', () async {
      await repo.saveScanCursor(ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: 'root',
        now: DateTime(2026, 9, 23, 10),
      ).pause(DateTime(2026, 9, 23, 10)));

      final service = build();
      await service.scan(DriveProvider.quark, resume: false);

      expect(adapter.calls.first, 'root');
      expect(adapter.calls, containsAll(['d1', 'd4']));
    });

    test('上次已扫完时自动重新开始，不会拿着 completed 游标空转', () async {
      await repo.saveScanCursor(ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: 'root',
        now: DateTime(2026, 9, 23, 10),
      ).markCompleted(DateTime(2026, 9, 23, 10)));

      final service = build();
      final outcome = await service.scan(DriveProvider.quark);

      expect(adapter.calls.first, 'root');
      expect(outcome.tracksIndexed, 7);
    });
  });

  // ===================================================================
  // 取消
  // ===================================================================

  group('取消', () {
    test('取消后阶段为 paused 且队列保留，可续扫', () async {
      final service = build(tree: _wideTree(10), forcedPageSize: 1);
      final cancel = ScanCancellation();

      final outcome = await service.scan(
        DriveProvider.quark,
        cancel: cancel,
        onProgress: (p) {
          if (p.cursor.scannedDirs >= 3) cancel.cancel();
        },
      );

      expect(outcome.wasCancelled, isTrue);
      expect(outcome.isComplete, isFalse);
      expect(outcome.cursor.stage, ScanStage.paused);
      expect(outcome.cursor.hasPendingWork, isTrue,
          reason: '队列必须保留，否则续扫会漏目录');

      final persisted = await repo.loadScanCursor(DriveProvider.quark);
      expect(persisted!.stage, ScanStage.paused);
      expect(persisted.pendingDirs, isNotEmpty);
    });

    test('取消后再扫能接着扫完，两次合起来不重不漏', () async {
      final service = build(tree: _wideTree(10), forcedPageSize: 1);
      final cancel = ScanCancellation();

      await service.scan(
        DriveProvider.quark,
        cancel: cancel,
        onProgress: (p) {
          if (p.cursor.scannedDirs >= 3) cancel.cancel();
        },
      );
      final afterFirst = await repo.countTracks();
      expect(afterFirst, lessThan(10));

      final second = await service.scan(DriveProvider.quark);

      expect(second.isComplete, isTrue);
      expect(await repo.countTracks(), 10);
    });

    test('requestCancel 通过服务实例也能停', () async {
      final service = build(tree: _wideTree(8), forcedPageSize: 1);

      final outcome = await service.scan(
        DriveProvider.quark,
        onProgress: (p) {
          if (p.cursor.scannedDirs >= 2) service.requestCancel();
        },
      );

      expect(outcome.wasCancelled, isTrue);
    });

    test('取消时不做陈旧清理（否则会误删还没扫到的曲目）', () async {
      await repo.upsertTracks(
        [_staleTrack()],
        capabilities: const Capabilities(provider: DriveProvider.quark),
      );

      final service = build(tree: _wideTree(8), forcedPageSize: 1);
      final cancel = ScanCancellation();

      await service.scan(
        DriveProvider.quark,
        cancel: cancel,
        onProgress: (p) {
          if (p.cursor.scannedDirs >= 2) cancel.cancel();
        },
      );

      expect(await repo.trackById('quark:stale'), isNotNull,
          reason: '中途取消时索引不完整，清理会误删');
    });

    test('续扫完成时也不清理：本次只看到部分目录，白名单不完整', () async {
      await repo.upsertTracks(
        [_staleTrack()],
        capabilities: const Capabilities(provider: DriveProvider.quark),
      );

      final service = build(tree: _wideTree(8), forcedPageSize: 1);
      final cancel = ScanCancellation();

      await service.scan(
        DriveProvider.quark,
        cancel: cancel,
        onProgress: (p) {
          if (p.cursor.scannedDirs >= 2) cancel.cancel();
        },
      );
      await service.scan(DriveProvider.quark); // 续扫到完成

      expect(await repo.trackById('quark:stale'), isNotNull,
          reason: '续扫只扫了后半段，拿本次 id 当白名单会误删前半段');

      // 下一次从零扫描会补上这次清理
      final full = build(tree: _wideTree(8), forcedPageSize: 1);
      final outcome = await full.scan(DriveProvider.quark);
      expect(outcome.removedTracks, 1);
      expect(await repo.trackById('quark:stale'), isNull);
    });

    test('pruneStale: false 时保留陈旧曲目', () async {
      await repo.upsertTracks(
        [_staleTrack()],
        capabilities: const Capabilities(provider: DriveProvider.quark),
      );

      final service = build();
      await service.scan(DriveProvider.quark, pruneStale: false);

      expect(await repo.trackById('quark:stale'), isNotNull);
    });
  });

  // ===================================================================
  // 陈旧清理
  // ===================================================================

  group('陈旧清理', () {
    test('完整扫完后删掉网盘侧已删除的曲目', () async {
      await repo.upsertTracks(
        [_staleTrack()],
        capabilities: const Capabilities(provider: DriveProvider.quark),
      );

      final service = build();
      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.removedTracks, 1);
      expect(await repo.trackById('quark:stale'), isNull);
      expect(await repo.countTracks(), 7, reason: '只有陈旧那条被清掉');
    });

    test('白名单来自「本次扫到的 id」而不是「库里现有的曲目」', () async {
      // 先完整扫一遍
      await build().scan(DriveProvider.quark);
      expect(await repo.countTracks(), 7);

      // 网盘侧删掉 f3 后再扫：必须真的删掉，不能变成空操作
      final tree = _standardTree();
      tree['d2']!.removeWhere((e) => e.id == 'f3');

      final outcome = await build(tree: tree).scan(DriveProvider.quark);

      expect(outcome.removedTracks, 1);
      expect(await repo.countTracks(), 6);
      expect(await repo.trackById('quark:f3'), isNull);
    });

    test('不清理其他网盘的曲目', () async {
      await repo.upsertTracks(
        [
          Track(
            provider: DriveProvider.aliyun,
            remoteId: 'ali1',
            name: '别的盘上的歌.flac',
            sizeBytes: 1024,
          ),
        ],
        capabilities: const Capabilities(provider: DriveProvider.aliyun),
      );

      final service = build();
      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.removedTracks, 0);
      expect(await repo.trackById('aliyun:ali1'), isNotNull);
    });

    test('扫描结果为空时不清理（适配器异常不该清空整个曲库）', () async {
      await build().scan(DriveProvider.quark);
      expect(await repo.countTracks(), 7);

      // 网盘返回空目录（异常情况）
      final outcome = await build(tree: {'root': []}).scan(DriveProvider.quark);

      expect(outcome.removedTracks, 0);
      expect(await repo.countTracks(), 7, reason: '宁可留着陈旧行，也不能清空曲库');
    });
  });

  // ===================================================================
  // 失败处理
  // ===================================================================

  group('失败处理', () {
    test('单个目录失败不中断整次扫描，只计入 failedDirs', () async {
      final service = build(failDirIds: {'d3'});

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.error, isNull, reason: '单目录失败不该让整次扫描失败');
      expect(outcome.isComplete, isTrue);
      expect(outcome.cursor.failedDirs, 1);
      expect(outcome.cursor.lastError, isNotNull);
      expect(adapter.calls, containsAll(['d2', 'd4']),
          reason: '其余目录必须继续扫');
      expect(await repo.countTracks(), 5, reason: 'd3 下的 2 首拿不到');
    });

    test('失败目录不计入 scannedDirs（避免虚报进度）', () async {
      final service = build(failDirIds: {'d3'});

      final outcome = await service.scan(DriveProvider.quark);

      expect(outcome.cursor.scannedDirs, 4, reason: '5 个目录里 1 个失败');
    });

    test('授权失效立刻上抛，继续扫只会拿到一堆 31001', () async {
      final service = build(failDirIds: {'d3'}, failNeedsReauth: true);

      await expectLater(
        service.scan(DriveProvider.quark),
        throwsA(isA<DriveException>()
            .having((e) => e.needsReauth, 'needsReauth', isTrue)),
      );
    });

    test('授权失效时把 failed 阶段落库，便于 UI 引导重新登录后续扫', () async {
      final service = build(failDirIds: {'d3'}, failNeedsReauth: true);

      try {
        await service.scan(DriveProvider.quark);
        fail('应当抛出 DriveException');
      } on DriveException {
        // 期望路径
      }

      final persisted = await repo.loadScanCursor(DriveProvider.quark);
      expect(persisted!.stage, ScanStage.failed);
      expect(persisted.lastError, isNotNull);
      expect(persisted.hasPendingWork, isTrue);
    });

    test('网盘不支持列目录时直接抛 unsupported，不发任何请求', () async {
      final service = build(canListDirectory: false);

      await expectLater(
        service.scan(DriveProvider.quark),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.unsupported)),
      );
      expect(adapter.calls, isEmpty);
    });

    test('未注册的网盘抛 StateError', () async {
      final service = ScanService(
        registry: DefaultDriveAdapterRegistry([]),
        library: repo,
      );

      await expectLater(
        service.scan(DriveProvider.quark),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ===================================================================
  // 并发保护与进度
  // ===================================================================

  group('并发与进度', () {
    test('已有扫描进行中时再次调用抛 StateError', () async {
      final service = build();
      final first = service.scan(DriveProvider.quark);

      await expectLater(
        service.scan(DriveProvider.quark),
        throwsA(isA<StateError>()),
      );

      await first;
    });

    test('扫描结束后 isRunning 复位', () async {
      final service = build();
      expect(service.isRunning, isFalse);

      final future = service.scan(DriveProvider.quark);
      expect(service.isRunning, isTrue);

      await future;
      expect(service.isRunning, isFalse);
    });

    test('lastProgress 记录最近进度，UI 冷启动可直接展示', () async {
      final service = build();

      await service.scan(DriveProvider.quark);

      final p = service.lastProgress;
      expect(p, isNotNull);
      expect(p!.isRunning, isFalse);
      expect(p.cursor.isComplete, isTrue);
      expect(p.scannedDirs, 5);
      expect(p.foundTracks, 7);
      expect(p.pendingDirs, 0);
      expect(p.message, '已完成');
    });

    test('首次进度回调发生在请求网盘之前（UI 能立刻显示「扫描中」）', () async {
      final service = build();
      final events = <int>[];

      await service.scan(
        DriveProvider.quark,
        onProgress: (p) => events.add(p.cursor.scannedDirs),
      );

      expect(events.first, 0);
      expect(adapter.calls, isNotEmpty);
    });
  });

  // ===================================================================
  // 策略限制
  // ===================================================================

  group('扫描策略', () {
    test('目录数上限把队列中的待扫目录也算进去', () async {
      final service = build(
        tree: _wideTree(20),
        policy: const ScanPolicy(maxDirectories: 3),
      );

      await service.scan(DriveProvider.quark);

      // root 处理时 scannedDirs 还是 0，若只看已完成数就会把 20 个目录
      // 全部入队，上限形同虚设。计入队列后只入队 d0/d1/d2。
      expect(adapter.calls, ['root', 'd0', 'd1', 'd2']);
    });

    test('深度超限的子目录不入队', () async {
      final service = build(
        tree: {
          'root': [_dir('l1', 'l1')],
          'l1': [_dir('l2', 'l2')],
          'l2': [_dir('l3', 'l3')],
          'l3': [_file('deep', 'deep.flac', size: _mib)],
        },
        policy: const ScanPolicy(maxDepth: 2),
      );

      await service.scan(DriveProvider.quark);

      expect(adapter.calls, ['root', 'l1', 'l2']);
      expect(await repo.countTracks(), 0);
    });

    test('自定义分页大小会传给适配器', () async {
      final service = build(
        tree: {
          'root': [
            for (var i = 0; i < 5; i++) _file('p$i', 'track$i.flac', size: _mib),
          ],
        },
        policy: const ScanPolicy(pageSize: 100),
      );

      await service.scan(DriveProvider.quark);

      expect(adapter.calls, ['root'], reason: '5 条一次取完');
    });
  });

  // ===================================================================
  // 幂等
  // ===================================================================

  group('重复扫描', () {
    test('扫两遍不产生重复行，且不丢失收藏与播放统计', () async {
      await build().scan(DriveProvider.quark);
      await repo.recordPlay('quark:f1', played: const Duration(seconds: 60));
      await repo.setFavorite('quark:f1', value: true);

      await build().scan(DriveProvider.quark);

      expect(await repo.countTracks(), 7);
      expect(await repo.isFavorite('quark:f1'), isTrue);
      expect((await repo.recentlyPlayed()).map((t) => t.id), contains('quark:f1'));
    });
  });
}
