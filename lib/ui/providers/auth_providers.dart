import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/drive_error.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/cloud_account.dart';
import '../../domain/entities/drive_provider.dart';
import 'app_providers.dart';

/// 授权状态快照。
class AuthState {
  const AuthState({
    this.account,
    this.error,
    this.busy = false,
    this.storageDegraded = false,
  });

  /// 已授权的账号，`null` 表示尚未授权
  final CloudAccount? account;

  /// 最近一次失败原因，面向用户
  final String? error;

  /// 是否正在执行授权/登出
  final bool busy;

  /// 凭证存储是否已降级到内存（重启后需重新登录）
  final bool storageDegraded;

  bool get isAuthorized => account != null;

  AuthState copyWith({
    CloudAccount? account,
    String? error,
    bool clearAccount = false,
    bool clearError = false,
    bool? busy,
    bool? storageDegraded,
  }) {
    return AuthState(
      account: clearAccount ? null : (account ?? this.account),
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
      storageDegraded: storageDegraded ?? this.storageDegraded,
    );
  }
}

/// 授权控制器。
///
/// 启动时用钥匙串里的凭证恢复会话；恢复失败（凭证已失效）会**清掉本地凭证**
/// 并回到未授权状态，而不是每次启动都弹一次同样的错误。
class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final store = ref.watch(credentialStoreProvider);
    final adapter = ref.watch(adapterRegistryProvider).adapterFor(DriveProvider.quark);
    if (adapter == null) {
      return const AuthState(error: '夸克网盘适配器未注册');
    }

    try {
      final account = await adapter.restoreSession();
      if (account != null) {
        await ref.read(libraryProvider).saveAccount(account);
      }
      return AuthState(account: account, storageDegraded: store.isDegraded);
    } on DriveException catch (e) {
      // 凭证存在但服务端不认了：清掉，让用户重新登录一次即可
      await adapter.signOut();
      return AuthState(error: e.message, storageDegraded: store.isDegraded);
    } catch (e) {
      return AuthState(error: '恢复会话失败：$e', storageDegraded: store.isDegraded);
    }
  }

  void _emit(AuthState next) => state = AsyncData(next);

  AuthState get _current => state.valueOrNull ?? const AuthState();

  /// 用一份凭证完成授权。成功返回 `null`，失败返回错误文案。
  Future<String?> authorize(AuthCredential credential) async {
    _emit(_current.copyWith(busy: true, clearError: true));

    try {
      final adapter = ref
          .read(adapterRegistryProvider)
          .requireAdapter(credential.provider);
      final account = await adapter.authorize(credential);
      await ref.read(libraryProvider).saveAccount(account);

      _emit(AuthState(
        account: account,
        storageDegraded: ref.read(credentialStoreProvider).isDegraded,
      ));
      return null;
    } on DriveException catch (e) {
      _emit(_current.copyWith(busy: false, error: e.message));
      return e.message;
    } catch (e) {
      final message = '授权失败：$e';
      _emit(_current.copyWith(busy: false, error: message));
      return message;
    }
  }

  /// 登出并清除本地凭证与账号展示信息。
  Future<void> signOut() async {
    _emit(_current.copyWith(busy: true, clearError: true));
    try {
      await ref
          .read(adapterRegistryProvider)
          .adapterFor(DriveProvider.quark)
          ?.signOut();
      await ref.read(libraryProvider).removeAccount(DriveProvider.quark);
    } finally {
      _emit(const AuthState());
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
