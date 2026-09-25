import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../domain/adapters/credential_store.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/drive_provider.dart';
import 'credential_codec.dart';

/// 基于系统安全存储的凭证库。
///
/// 落盘位置：
///   - iOS / macOS：Keychain（macOS 走**传统钥匙串**，理由见 [macOsOptions]）
///   - Android：EncryptedSharedPreferences（Keystore 保护）
///   - Windows：DPAPI
///   - Linux：libsecret
///   - **Web：不是真安全存储**（只有 localStorage + 弱混淆）。
///     因此 Web 端 [supportsPersistence] 返回 `false`，只做内存会话，
///     与「Web 定位为浏览管理端、不用于播放」的决策一致。
class SecureCredentialStore implements CredentialStore {
  /// macOS 侧的安全存储选项。
  ///
  /// ⚠️ `useDataProtectionKeyChain: false` 是**必需**的，不是随手写的。
  ///
  /// 这个开关默认为 `true`，会把读写打到「data protection keychain」上。
  /// 那条路径要求进程持有 `application-identifier` 或
  /// `keychain-access-groups` entitlement —— 两者都只能由**描述文件**下发。
  /// 而本仓库刻意不落库任何签名身份（`CODE_SIGN_IDENTITY = "-"`、
  /// `DEVELOPMENT_TEAM` 为空，保证谁 clone 下来都能直接构建），拿不到描述文件。
  /// 结果就是每一次写入都抛：
  ///
  /// ```
  /// PlatformException(Code: -34018,
  ///   Message: A required entitlement isn't present.)
  /// ```
  ///
  /// 然后 [ResilientCredentialStore] 静默降级到内存 —— 表现就是
  /// 「每次打开都要重新登录」。2026-09-24 的日志里，从 14:14 到 21:01
  /// 的**每一次启动**都是这个错，即使产物已经是 Developer ID 正式签名。
  ///
  /// 关掉它走**传统钥匙串**：那条路径只依赖代码签名，不需要任何 entitlement，
  /// 手动 / ad-hoc / Developer ID 签名都能用。
  ///
  /// ⛔ 另一条路是「加 `keychain-access-groups` entitlement」——**那是错的**：
  /// 它同样要求描述文件，加上之后构建直接失败
  /// （`"Runner" requires a provisioning profile.`）。
  static const MacOsOptions macOsOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    useDataProtectionKeyChain: false,
  );

  SecureCredentialStore({FlutterSecureStorage? storage, this.prefix = 'cloudtune.cred'})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: macOsOptions,
            );

  final FlutterSecureStorage _storage;

  /// Key 前缀，避免与宿主应用的其他 Key 冲突
  final String prefix;

  @override
  bool get supportsPersistence => !kIsWeb;

  String _keyFor(DriveProvider provider) => '$prefix.${provider.id}';

  @override
  Future<void> save(AuthCredential credential) async {
    if (!supportsPersistence) return;
    final key = _keyFor(credential.provider);
    try {
      await _storage.write(
        key: key,
        value: CredentialCodec.encode(credential),
      );
      diag.info('钥匙串', '写入 $key：成功');
    } catch (e, st) {
      // 写失败必须把**原始错误**记下来。macOS 上最典型的失败是
      // errSecMissingEntitlement(-34018)：说明有人把 [macOsOptions] 的
      // `useDataProtectionKeyChain` 又打开了（或加了需要描述文件的
      // entitlement）。这一行是唯一能直接指认它的证据。
      diag.error('钥匙串', '写入 $key 失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<AuthCredential?> load(DriveProvider provider) async {
    if (!supportsPersistence) return null;
    final key = _keyFor(provider);
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) {
        diag.info('钥匙串', '读取 $key：没有条目（需要重新登录）');
        return null;
      }
      diag.info('钥匙串', '读取 $key：命中，${raw.length} 字符');
      return CredentialCodec.decode(raw);
    } catch (e, st) {
      diag.error('钥匙串', '读取 $key 失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<void> clear(DriveProvider provider) async {
    if (!supportsPersistence) return;
    final key = _keyFor(provider);
    try {
      await _storage.delete(key: key);
      diag.info('钥匙串', '删除 $key：成功');
    } catch (e, st) {
      diag.error('钥匙串', '删除 $key 失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<List<DriveProvider>> authorizedProviders() async {
    if (!supportsPersistence) return const [];
    final out = <DriveProvider>[];
    for (final p in DriveProvider.values) {
      final raw = await _storage.read(key: _keyFor(p));
      if (raw != null && raw.isNotEmpty) out.add(p);
    }
    return out;
  }
}

/// 内存凭证库见 `memory_credential_store.dart` ——
/// 它刻意独立成文件且不 import 任何 Flutter 包，
/// 以便纯 Dart 诊断脚本（`dart run`）也能复用适配器。
