import '../../domain/adapters/credential_store.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/drive_provider.dart';

/// 内存凭证库。
///
/// 三个用途：
///   1. **单元测试** —— 不触碰平台通道；
///   2. **Web 端与「不记住登录」模式** —— 会话只活在当前进程内；
///   3. **纯 Dart 环境**（CLI 诊断脚本）—— 不能依赖 `flutter_secure_storage`。
///
/// 刻意放在独立文件里、**不 import 任何 Flutter 包**，
/// 这样 `dart run` 的诊断脚本也能复用适配器。
class InMemoryCredentialStore implements CredentialStore {
  InMemoryCredentialStore([Map<DriveProvider, AuthCredential>? initial])
      : _store = {...?initial};

  final Map<DriveProvider, AuthCredential> _store;

  @override
  bool get supportsPersistence => false;

  @override
  Future<void> save(AuthCredential credential) async {
    _store[credential.provider] = credential;
  }

  @override
  Future<AuthCredential?> load(DriveProvider provider) async => _store[provider];

  @override
  Future<void> clear(DriveProvider provider) async {
    _store.remove(provider);
  }

  @override
  Future<List<DriveProvider>> authorizedProviders() async => _store.keys.toList();
}
