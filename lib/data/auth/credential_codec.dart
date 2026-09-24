import 'dart:convert';

import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/drive_provider.dart';

/// 凭证的序列化编解码。
///
/// 单独抽出来是为了**可测试**：真正的钥匙串读写要走平台通道，
/// 单元测试跑不了；但「序列化后能否原样还原」是纯逻辑，必须覆盖到 ——
/// 因为凭证一旦在编解码环节丢字段，表现就是「授权成功但一重启就掉线」。
class CredentialCodec {
  const CredentialCodec._();

  /// 编码版本号。将来字段变化时用于兼容旧数据。
  static const int version = 1;

  static String encode(AuthCredential credential) {
    return jsonEncode({
      'v': version,
      'provider': credential.provider.id,
      'mode': credential.mode.id,
      'capturedAt': credential.capturedAt.toIso8601String(),
      'cookies': credential.cookies,
      'tokens': credential.tokens,
      'extra': credential.extra,
    });
  }

  /// 解码。数据损坏、版本不认识、网盘标识非法时返回 `null`
  /// （视为「没有凭证」，让用户重新授权，而不是崩在启动路径上）。
  static AuthCredential? decode(String raw) {
    if (raw.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final map = decoded.cast<Object?, Object?>();
    final v = map['v'];
    if (v is! int || v > version) return null;

    final providerId = map['provider'];
    if (providerId is! String) return null;
    final provider = DriveProvider.fromId(providerId);
    if (provider == null) return null;

    final modeId = map['mode'];
    final mode = (modeId is String ? AuthMode.fromId(modeId) : null) ??
        AuthMode.manualCookie;

    final capturedRaw = map['capturedAt'];
    final capturedAt = (capturedRaw is String ? DateTime.tryParse(capturedRaw) : null) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return AuthCredential(
      provider: provider,
      mode: mode,
      capturedAt: capturedAt,
      cookies: _stringMap(map['cookies']),
      tokens: _stringMap(map['tokens']),
      extra: _stringMap(map['extra']),
    );
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    final out = <String, String>{};
    value.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }
}
