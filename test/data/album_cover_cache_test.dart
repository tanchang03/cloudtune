import 'dart:io';
import 'dart:typed_data';

import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/covers/album_cover_cache.dart';
import 'package:cloudtune/data/registry/drive_adapter_registry.dart';
import 'package:cloudtune/domain/adapters/cloud_drive_adapter.dart';
import 'package:cloudtune/domain/entities/album_cover.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只实现「读一个小文件」的假网盘 —— 封面缓存只需要这一个能力。
class _FakeImageAdapter extends CloudDriveAdapter {
  _FakeImageAdapter({this.bytes = const {}, this.failure});

  /// `fileId → 字节`
  final Map<String, List<int>> bytes;

  /// 非空则每次读取都抛这个错误
  final DriveException? failure;

  /// 读取调用轨迹
  final List<String> calls = [];

  @override
  DriveProvider get provider => DriveProvider.quark;

  @override
  Capabilities get capabilities =>
      Capabilities(provider: DriveProvider.quark);

  @override
  String get rootId => '0';

  @override
  Future<Uint8List> readFileBytes(
    String fileId, {
    int maxBytes = 512 * 1024,
  }) async {
    calls.add(fileId);
    final f = failure;
    if (f != null) throw f;
    final data = bytes[fileId];
    if (data == null) {
      throw DriveException(
        type: DriveErrorType.notFound,
        message: '无此文件：$fileId',
      );
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<DrivePage> listDirectory({
    required String dirId,
    String? pageToken,
    int? pageSize,
  }) async =>
      const DrivePage.empty();

  @override
  Future<List<DriveEntry>> search({
    required String keyword,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<StreamTicket> resolveStream(String fileId) async =>
      throw UnimplementedError();

  @override
  Future<bool> ping() async => true;

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  late _FakeImageAdapter adapter;

  /// 可控时钟，用来验证失败冷却期
  late DateTime now;

  AlbumCover cover(String fileId, {String dir = '/音乐/专辑'}) => AlbumCover(
        provider: DriveProvider.quark,
        dirPath: dir,
        fileId: fileId,
        fileName: 'cover.jpg',
        sizeBytes: 1024,
      );

  AlbumCoverCache build({
    Map<String, List<int>> bytes = const {},
    DriveException? failure,
    List<CloudDriveAdapter>? adapters,
    int memoryEntries = 24,
    int maxCacheFiles = 600,
    int maxCacheBytes = 256 * 1024 * 1024,
    int trimEveryWrites = 200,
    String? dirPath,
  }) {
    adapter = _FakeImageAdapter(bytes: bytes, failure: failure);
    return AlbumCoverCache(
      registry: DefaultDriveAdapterRegistry(adapters ?? [adapter]),
      cacheDirPath: dirPath ?? tmp.path,
      memoryEntries: memoryEntries,
      maxCacheFiles: maxCacheFiles,
      maxCacheBytes: maxCacheBytes,
      trimEveryWrites: trimEveryWrites,
      clock: () => now,
    );
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cloudtune_cover_cache_');
    now = DateTime(2026, 9, 25, 12);
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('取到字节并落内存：第二次不再打接口', () async {
    final cache = build(bytes: {
      'img1': [1, 2, 3],
    });

    expect(await cache.load(cover('img1')), Uint8List.fromList([1, 2, 3]));
    expect(await cache.load(cover('img1')), Uint8List.fromList([1, 2, 3]));
    expect(adapter.calls, ['img1'], reason: '第二次必须命中内存缓存');
  });

  test('落盘：换一个实例（等于重启应用）不再打接口', () async {
    final first = build(bytes: {
      'img1': [9, 8, 7],
    });
    await first.load(cover('img1'));

    // 新实例、新注册表 —— 只有磁盘上那份字节能救它
    final second = build(adapters: const []);
    expect(await second.load(cover('img1')), Uint8List.fromList([9, 8, 7]));
    expect(adapter.calls, isEmpty, reason: '第二次不该再打网盘');
  });

  test('取不到返回 null，不抛异常', () async {
    final cache = build();

    expect(await cache.load(cover('missing')), isNull);
    expect(await cache.load(cover('missing')), isNull);
  });

  test('失败后有冷却期：同一张图不会被反复重试', () async {
    final cache = build();

    await cache.load(cover('img1'));
    now = now.add(const Duration(seconds: 30));
    await cache.load(cover('img1'));

    expect(adapter.calls, ['img1'], reason: '冷却期内不该再请求');
  });

  test('冷却期过去后会重试（网络抖动不该永久放弃）', () async {
    final cache = build();

    await cache.load(cover('img1'));
    now = now.add(const Duration(minutes: 3));
    await cache.load(cover('img1'));

    expect(adapter.calls, ['img1', 'img1']);
  });

  test('0 字节当作失败，不写盘也不进内存', () async {
    final cache = build(bytes: {'img1': const []});

    expect(await cache.load(cover('img1')), isNull);
    expect(cache.cachedInMemory, 0);
    expect(
      tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')),
      isEmpty,
    );
  });

  test('网盘不支持读文件时只记日志，返回 null', () async {
    final cache = build(
      failure: const DriveException(
        type: DriveErrorType.unsupported,
        message: '该网盘不支持读取文件内容',
      ),
    );

    expect(await cache.load(cover('img1')), isNull);
  });

  test('未注册的网盘不会崩，只是没有封面', () async {
    final cache = build(adapters: const []);

    expect(await cache.load(cover('img1')), isNull);
  });

  test('内存缓存按 LRU 淘汰', () async {
    final cache = build(
      bytes: {
        'a': [1],
        'b': [2],
        'c': [3],
      },
      memoryEntries: 2,
    );

    await cache.load(cover('a'));
    await cache.load(cover('b'));
    await cache.load(cover('c'));

    expect(cache.cachedInMemory, 2);
    // a 已被挤出内存，但磁盘上有，所以不会再打接口
    expect(await cache.load(cover('a')), Uint8List.fromList([1]));
    expect(adapter.calls, ['a', 'b', 'c'], reason: 'a 应从磁盘读回');
  });

  test('磁盘上残留的空文件会被删掉并重新取', () async {
    final first = build();
    // 模拟「上次写到一半被杀」：留下一个 0 字节的目标文件
    final path = '${tmp.path}${Platform.pathSeparator}quark_img1.jpg';
    File(path).writeAsBytesSync(const []);

    final second = build(bytes: {
      'img1': [4, 5, 6],
    });
    expect(await second.load(cover('img1')), Uint8List.fromList([4, 5, 6]));
    expect(adapter.calls, ['img1'], reason: '空文件不能当成缓存命中');
    expect(File(path).lengthSync(), 3);
    expect(first.cachedInMemory, 0);
  });

  test('文件名对人类可读；ID 含特殊字符时补哈希避免撞名', () async {
    final cache = build(bytes: {
      'abc123': [1],
      'a/b': [2],
    });

    await cache.load(cover('abc123'));
    await cache.load(cover('a/b'));

    final names = tmp
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(names, contains('quark_abc123.jpg'));
    expect(
      names.where((n) => n.startsWith('quark_a_b_')).length,
      1,
      reason: '转义过的 ID 要带哈希后缀，否则 a/b 与 a_b 会压成同一个文件名',
    );
  });

  test('缓存超量时按最久未修改淘汰', () async {
    final cache = build(
      bytes: {
        'a': [1],
        'b': [2],
        'c': [3],
      },
      maxCacheFiles: 2,
      // 每写一张就检查一次，测试里不必真写 200 张
      trimEveryWrites: 1,
    );

    await cache.load(cover('a'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await cache.load(cover('b'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await cache.load(cover('c'));

    final names = tmp
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(names, hasLength(2));
    expect(names, isNot(contains('quark_a.jpg')), reason: '最旧的先走');
    expect(names, containsAll(<String>['quark_b.jpg', 'quark_c.jpg']));
  });

  test('同一个 ID 被两张专辑引用时只取一次', () async {
    final cache = build(bytes: {
      'shared': [7],
    });

    final a = await cache.load(cover('shared', dir: '/音乐/专辑A'));
    final b = await cache.load(cover('shared', dir: '/音乐/专辑B'));

    expect(a, b);
    expect(adapter.calls, ['shared'], reason: 'AlbumCover 的相等性基于 provider:fileId');
  });
}
