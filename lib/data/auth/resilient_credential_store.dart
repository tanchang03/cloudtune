import 'dart:developer' as developer;

import '../../core/diagnostics/diag_log.dart';
import '../../domain/adapters/credential_store.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/drive_provider.dart';
import 'memory_credential_store.dart';

/// 带降级的凭证存储。
///
/// 为什么需要它：系统安全存储并非永远可用 ——
///   - macOS 沙箱应用未正确签名时，钥匙串读写会抛 `errSecMissingEntitlement`；
///   - Linux 桌面缺 `libsecret`；
///   - Web 端的 `flutter_secure_storage` 只有 localStorage，不是真安全存储。
///
/// 主存储一旦不可用就**整体退化到内存**，而不是让授权流程直接失败。
/// 用户体验变成「本次会话有效、重启后需重新登录」，远好于「点了登录没反应」。
/// 降级状态通过 [isDegraded] 暴露给 UI，由设置页明确告知用户。
///
/// ⚠️ 降级是**静默**的，这很危险：界面看起来一切正常（账号信息还在数据库里），
/// 但凭证其实没落盘，重启就没了。所以降级时必须往诊断日志里写一条 ERROR ——
/// 否则「为什么每次打开都要重新登录 / 为什么取不到直链」会永远查不出来。
class ResilientCredentialStore implements CredentialStore {
  ResilientCredentialStore(this._primary);

  final CredentialStore _primary;
  final InMemoryCredentialStore _fallback = InMemoryCredentialStore();

  bool _degraded = false;
  String? _degradedReason;

  /// 是否已降级到内存存储（凭证不会跨重启保留）
  bool get isDegraded => _degraded;

  /// 降级原因，供设置页展示排查
  String? get degradedReason => _degradedReason;

  void _degrade(Object error) {
    if (_degraded) return;
    _degraded = true;
    _degradedReason = error.toString();
    developer.log('凭证存储降级到内存：$error', name: 'cloudtune.credential');
    diag.error(
      '凭证',
      '安全存储不可用，已降级到内存：本次会话内可用，'
      '**重启后凭证会丢失、需要重新登录**',
      error: error,
    );
  }

  @override
  bool get supportsPersistence => !_degraded && _primary.supportsPersistence;

  @override
  Future<void> save(AuthCredential credential) async {
    if (!_degraded) {
      try {
        await _primary.save(credential);
        return;
      } catch (e) {
        _degrade(e);
      }
    }
    await _fallback.save(credential);
  }

  @override
  Future<AuthCredential?> load(DriveProvider provider) async {
    if (!_degraded) {
      try {
        final loaded = await _primary.load(provider);
        if (loaded == null) {
          diag.info('凭证', '${provider.displayName}：安全存储里没有凭证');
        } else {
          diag.info('凭证', '${provider.displayName}：已从安全存储恢复会话');
        }
        return loaded;
      } catch (e) {
        _degrade(e);
      }
    }
    final fallback = await _fallback.load(provider);
    diag.warn(
      '凭证',
      '${provider.displayName}：走内存存储，'
      '${fallback == null ? "没有凭证" : "有本次会话的凭证"}',
    );
    return fallback;
  }

  @override
  Future<void> clear(DriveProvider provider) async {
    if (!_degraded) {
      try {
        await _primary.clear(provider);
      } catch (e) {
        _degrade(e);
      }
    }
    await _fallback.clear(provider);
  }

  @override
  Future<List<DriveProvider>> authorizedProviders() async {
    if (!_degraded) {
      try {
        return await _primary.authorizedProviders();
      } catch (e) {
        _degrade(e);
      }
    }
    return _fallback.authorizedProviders();
  }
}
