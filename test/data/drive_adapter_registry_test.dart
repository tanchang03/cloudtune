import 'package:cloudtune/data/registry/drive_adapter_registry.dart';
import 'package:cloudtune/domain/adapters/cloud_drive_adapter.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小可用假适配器：只验证注册表的路由与生命周期。
class _FakeAdapter implements CloudDriveAdapter {
  _FakeAdapter(this.provider);

  @override
  final DriveProvider provider;

  bool disposed = false;

  @override
  Capabilities get capabilities => Capabilities(provider: provider);

  @override
  String get rootId => '0';

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async => CloudAccount(
        provider: provider,
        authMode: credential.mode,
        authorizedAt: DateTime(2026, 9, 23),
      );

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
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('DefaultDriveAdapterRegistry', () {
    test('按 provider 路由到对应适配器', () {
      final quark = _FakeAdapter(DriveProvider.quark);
      final aliyun = _FakeAdapter(DriveProvider.aliyun);
      final registry = DefaultDriveAdapterRegistry([quark, aliyun]);

      expect(registry.adapterFor(DriveProvider.quark), same(quark));
      expect(registry.adapterFor(DriveProvider.aliyun), same(aliyun));
    });

    test('未注册的网盘返回 null（不抛异常，便于 UI 展示「暂不支持」）', () {
      final registry = DefaultDriveAdapterRegistry([_FakeAdapter(DriveProvider.quark)]);
      expect(registry.adapterFor(DriveProvider.baidu), isNull);
      expect(registry.contains(DriveProvider.baidu), isFalse);
    });

    test('requireAdapter 未注册时抛 StateError', () {
      final registry = DefaultDriveAdapterRegistry([]);
      expect(
        () => registry.requireAdapter(DriveProvider.quark),
        throwsA(isA<StateError>()),
      );
    });

    test('all / providers 反映已注册集合', () {
      final registry = DefaultDriveAdapterRegistry([
        _FakeAdapter(DriveProvider.quark),
        _FakeAdapter(DriveProvider.aliyun),
        _FakeAdapter(DriveProvider.baidu),
      ]);

      expect(registry.all.length, 3);
      expect(
        registry.providers,
        containsAll([DriveProvider.quark, DriveProvider.aliyun, DriveProvider.baidu]),
      );
    });

    test('空注册表可用', () {
      final registry = DefaultDriveAdapterRegistry([]);
      expect(registry.all, isEmpty);
      expect(registry.providers, isEmpty);
    });

    test('disposeAll 释放所有适配器', () async {
      final a = _FakeAdapter(DriveProvider.quark);
      final b = _FakeAdapter(DriveProvider.aliyun);
      await DefaultDriveAdapterRegistry([a, b]).disposeAll();

      expect(a.disposed, isTrue);
      expect(b.disposed, isTrue);
    });

    test('重复注册同一网盘时以后者为准（便于测试替换）', () {
      final first = _FakeAdapter(DriveProvider.quark);
      final second = _FakeAdapter(DriveProvider.quark);
      final registry = DefaultDriveAdapterRegistry([first, second]);

      expect(registry.adapterFor(DriveProvider.quark), same(second));
      expect(registry.all.length, 1);
    });
  });
}
