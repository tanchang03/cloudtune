import '../../../domain/adapters/cloud_drive_adapter.dart';
import '../../../domain/entities/drive_provider.dart';

/// 默认适配器注册表。
///
/// 组合根（`main.dart`）在这里把「已支持的网盘」注册一次，
/// 之后 UI、扫描器、播放引擎都通过它按 provider 取适配器。
/// **新增网盘只需在组合根多传一个适配器实例。**
class DefaultDriveAdapterRegistry implements DriveAdapterRegistry {
  DefaultDriveAdapterRegistry(Iterable<CloudDriveAdapter> adapters)
      : _byProvider = {for (final a in adapters) a.provider: a};

  final Map<DriveProvider, CloudDriveAdapter> _byProvider;

  @override
  CloudDriveAdapter? adapterFor(DriveProvider provider) => _byProvider[provider];

  @override
  CloudDriveAdapter requireAdapter(DriveProvider provider) {
    final a = _byProvider[provider];
    if (a == null) {
      throw StateError('未注册 ${provider.displayName} 的适配器');
    }
    return a;
  }

  @override
  List<CloudDriveAdapter> get all => _byProvider.values.toList();

  @override
  List<DriveProvider> get providers => _byProvider.keys.toList();

  /// 是否已注册某网盘
  bool contains(DriveProvider provider) => _byProvider.containsKey(provider);

  /// 释放所有适配器
  Future<void> disposeAll() async {
    for (final a in _byProvider.values) {
      await a.dispose();
    }
  }
}
