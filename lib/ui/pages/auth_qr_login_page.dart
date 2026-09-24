import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/redact.dart';
import '../../data/auth/quark_qr_login.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/drive_provider.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/page_back_button.dart';

/// 扫码登录页。
///
/// ⚠️ **这是实验性入口**（2026-09-24 新增，用于验证 CAS 扫码流程）。
///
/// 整条链路都已实现并单测覆盖：
/// 取 token → 生成二维码 → 轮询（`uop.quark.cn`，无鉴权无签名）
/// → 用 `service_ticket` 兑换 `pan.quark.cn` 的 `__pus`/`__puus` Cookie
/// → 组装 `AuthCredential(AuthMode.qrCode)` 调 `authController.authorize` 完成真实登录。
///
/// 仍标「实验性」的原因：整条链路只在我本机静态分析 + 一次接口探测下验证过，
/// 还没用真机扫码实测过（要验证手机确认后回执里 `service_ticket` 的真实形态、
/// 以及兑换出的 Cookie 能否通过网盘校验）。扫码全程不接触用户密码，不越 DISCLAIMER 红线。
///
/// 页面把每个阶段的服务端回执/ Cookie 键原样展示出来，方便排查。

class AuthQrLoginPage extends ConsumerStatefulWidget {
  const AuthQrLoginPage({super.key});

  @override
  ConsumerState<AuthQrLoginPage> createState() => _AuthQrLoginPageState();
}

/// 页面阶段。
enum _QrPhase {
  /// 正在取 token
  loading,

  /// 二维码已就绪，等待扫码
  waiting,

  /// 服务端给了确认回执
  confirmed,

  /// 正在用票据兑换账号 Cookie
  exchanging,

  /// 兑换成功并已触发登录
  loggedIn,

  /// token 失效 / 超时
  expired,

  /// 出错
  error,
}

class _AuthQrLoginPageState extends ConsumerState<AuthQrLoginPage> {
  _QrPhase _phase = _QrPhase.loading;
  QrLoginSession? _session;
  QrPollConfirmed? _confirmed;
  String? _detail;
  bool _revealToken = false;

  /// 兑换成功后拿到的账号 Cookie 键（只存键名，不存值）。
  List<String> _cookieKeys = const [];

  /// 兑换/登录阶段的错误文案。
  String? _loginError;

  Timer? _timer;
  DateTime? _startedAt;
  int _pollFailures = 0;

  /// 轮询间隔。太快会被风控，太慢用户会觉得卡 —— 2s 是折中。
  static const Duration _pollInterval = Duration(seconds: 2);

  /// 二维码有效期兜底。服务端没告诉我们 TTL，超时就提示刷新。
  static const Duration _sessionTtl = Duration(minutes: 5);

  /// 连续轮询失败上限。单次失败**不该**终止流程 —— 网络抖一下很常见。
  static const int _maxPollFailures = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _phase = _QrPhase.loading;
      _session = null;
      _confirmed = null;
      _detail = null;
      _pollFailures = 0;
    });

    try {
      final session = await ref.read(qrLoginClientProvider).start();
      if (!mounted) return;
      setState(() {
        _session = session;
        _phase = _QrPhase.waiting;
        _startedAt = DateTime.now();
      });
      _beginPolling();
    } on QrLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _QrPhase.error;
        _detail = e.message;
      });
    }
  }

  void _beginPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final session = _session;
    if (session == null) return;

    final started = _startedAt;
    if (started != null && DateTime.now().difference(started) > _sessionTtl) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _phase = _QrPhase.expired;
        _detail = '二维码已超时，请刷新后重试';
      });
      return;
    }

    final outcome = await ref.read(qrLoginClientProvider).poll(session);
    if (!mounted) return;

    switch (outcome) {
      case QrPollWaiting():
        _pollFailures = 0;
        // 正常态，什么都不改 —— 每 2 秒 setState 会让二维码无谓重建
        break;

      case QrPollConfirmed():
        _timer?.cancel();
        setState(() {
          _phase = _QrPhase.confirmed;
          _confirmed = outcome;
          _detail = null;
        });
        _finishLogin(outcome);

      case QrPollExpired(: final message):
        _timer?.cancel();
        setState(() {
          _phase = _QrPhase.expired;
          _detail = message.isEmpty ? '二维码已失效' : message;
        });

      case QrPollError(: final message):
        _pollFailures++;
        if (_pollFailures >= _maxPollFailures) {
          _timer?.cancel();
          setState(() {
            _phase = _QrPhase.error;
            _detail = message;
          });
        } else if (mounted) {
          setState(() => _detail = '$message（第 $_pollFailures 次，继续重试）');
        }
    }
  }

  /// 扫码确认后：取 `service_ticket` → 兑换账号 Cookie → 触发真实登录。
  ///
  /// 这一步**可能真正登录成功**（若服务端回了 `__pus`/`__puus`）。
  /// 仍保留「实验性」标签，因为整条链路只在我本机静态分析 + 一次探测下验证过，
  /// 还没用真机扫码实测过；且 `authorize` 会真实打网盘接口校验 Cookie 有效性。
  Future<void> _finishLogin(QrPollConfirmed outcome) async {
    // 1. 从回执里取 service_ticket。
    final members = outcome.payload['members'];
    final ticket = members is Map ? members['service_ticket'] : null;
    if (ticket is! String || ticket.isEmpty) {
      if (!mounted) return;
      setState(() {
        _detail = '服务端回执里没有 service_ticket，无法继续兑换';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _QrPhase.exchanging);

    // 2. 兑换票据 → 账号 Cookie。
    final cookies = await _exchange(ticket);
    if (cookies == null) return; // 已 setState 报错

    // 3. 组装凭证并触发登录。
    final credential = AuthCredential(
      provider: DriveProvider.quark,
      mode: AuthMode.qrCode,
      capturedAt: DateTime.now(),
      cookies: filterQrCookiesForCredential(cookies.cookies),
    );
    final error = await ref
        .read(authControllerProvider.notifier)
        .authorize(credential);
    if (!mounted) return;
    if (error == null) {
      setState(() {
        _phase = _QrPhase.loggedIn;
        _cookieKeys = cookies.keys;
        _loginError = null;
      });
    } else {
      setState(() {
        _phase = _QrPhase.error;
        _cookieKeys = cookies.keys;
        _loginError = error;
      });
    }
  }

  /// 兑换票据；失败时在页面上给出错误并返回 `null`。
  Future<QrLoginCookies?> _exchange(String ticket) async {
    try {
      final result = await ref.read(qrLoginClientProvider).exchangeServiceTicket(ticket);
      if (!mounted) return null;
      setState(() => _cookieKeys = result.keys);
      return result;
    } on QrLoginException catch (e) {
      if (!mounted) return null;
      setState(() {
        _phase = _QrPhase.error;
        _loginError = e.message;
      });
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
              child: Row(
                children: [
                  const PageBackButton(),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _phase == _QrPhase.loading ? null : _start,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),
                        const Chip(
                          label: Text('实验性功能', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(height: 18),
                        _buildQrArea(),
                        const SizedBox(height: 18),
                        _buildStatus(),
                        const SizedBox(height: 20),
                        _buildDiagnostics(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrArea() {
    const size = 208.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line, width: 0.5),
      ),
      alignment: Alignment.center,
      child: switch (_phase) {
        _QrPhase.waiting || _QrPhase.confirmed || _QrPhase.expired =>
          _session == null
              ? const Icon(Icons.hourglass_empty, color: AppTheme.dim)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: QrImageView(
                    // 二维码必须深色模块 + 浅色底才扫得出来，别跟主题走。
                    data: _session!.qrUrl.toString(),
                    version: QrVersions.auto,
                    size: size - 24,
                    backgroundColor: Colors.white,
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
        _QrPhase.loading || _QrPhase.exchanging => const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _QrPhase.loggedIn => const Icon(
            Icons.check_circle_outline,
            size: 34,
            color: AppTheme.ok,
          ),
        _QrPhase.error => const Icon(Icons.wifi_off, size: 34, color: AppTheme.danger),
      },
    );
  }

  Widget _buildStatus() {
    final (text, color) = switch (_phase) {
      _QrPhase.loading => ('正在获取二维码…', AppTheme.muted),
      _QrPhase.waiting => ('用夸克 App 扫码确认', AppTheme.text),
      _QrPhase.confirmed => ('已拿到服务端回执', AppTheme.ok),
      _QrPhase.exchanging => ('正在兑换登录凭证…', AppTheme.text),
      _QrPhase.loggedIn => ('登录成功', AppTheme.ok),
      _QrPhase.expired => ('二维码已失效', AppTheme.warn),
      _QrPhase.error => ('出错了', AppTheme.danger),
    };

    return Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color),
        ),
        if (_detail != null) ...[
          const SizedBox(height: 8),
          Text(
            _detail!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.6, color: AppTheme.muted),
          ),
        ],
        if (_loginError != null && _phase == _QrPhase.error) ...[
          const SizedBox(height: 8),
          Text(
            _loginError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.6, color: AppTheme.danger),
          ),
        ],
        if (_phase == _QrPhase.loggedIn) ...[
          const SizedBox(height: 10),
          Text(
            '已用扫码拿到的凭证完成登录。这条链路仍是实验性的，'
            '若发现播放异常请在「设置 → 诊断日志」里排查。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, height: 1.7, color: AppTheme.ok),
          ),
        ],
        if (_phase == _QrPhase.confirmed) ...[
          const SizedBox(height: 10),
          Text(
            '回执不含 service_ticket，无法继续兑换（通常是扫码端未真正确认）。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, height: 1.7, color: AppTheme.warn),
          ),
        ],
      ],
    );
  }

  Widget _buildDiagnostics() {
    final session = _session;
    final confirmed = _confirmed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '调试信息',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.muted),
          ),
          const SizedBox(height: 10),
          if (session != null) ...[
            _kv('token', _revealToken ? session.token : maskSecret(session.token)),
            _kv('client_id', session.qrUrl.queryParameters['client_id'] ?? '-'),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _revealToken = !_revealToken),
                icon: Icon(
                  _revealToken ? Icons.visibility_off : Icons.visibility,
                  size: 14,
                ),
                label: Text(_revealToken ? '隐藏' : '显示原始值'),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copy(session.qrUrl.toString()),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('复制二维码内容'),
              ),
            ),
          ],
          if (confirmed != null) ...[
            const Divider(height: 20, color: AppTheme.line),
            const Text(
              '服务端回执',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            _kv('status', '${confirmed.status}'),
            _kv('payload 键', confirmed.payloadKeys.join(', ')),
            const SizedBox(height: 8),
            _MonoBlock(text: _safeEncode(confirmed.payload)),
          ],
          if (_cookieKeys.isNotEmpty) ...[
            const Divider(height: 20, color: AppTheme.line),
            const Text(
              '兑换到的账号 Cookie 键',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            _kv('cookie 键', _cookieKeys.join(', ')),
          ],
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: Text(
                key,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.dim),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.text),
              ),
            ),
          ],
        ),
      );

  /// 把 payload 编成 JSON 展示。
  ///
  /// 编码失败时给占位而不是抛异常 —— 服务端可能返回 Dart 侧无法序列化的结构。
  static String _safeEncode(Map<String, Object?> payload) {
    try {
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
      return '<无法序列化：${payload.keys.toList()}>';
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制二维码内容')),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.panel2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          fontFamily: 'Menlo',
          color: AppTheme.muted,
        ),
      ),
    );
  }
}
