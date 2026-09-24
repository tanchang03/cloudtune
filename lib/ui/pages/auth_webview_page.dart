import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/drive_provider.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';
import '../widgets/page_back_button.dart';

/// 内置浏览器登录页。
///
/// 职责边界很清楚：**页面只负责渲染与交互**，至于「怎样才算登录成功」
/// 「从哪里取凭证」都在 [BrowserAuthorizer] 的实现里，页面不做判断。
class AuthWebViewPage extends ConsumerStatefulWidget {
  const AuthWebViewPage({super.key});

  @override
  ConsumerState<AuthWebViewPage> createState() => _AuthWebViewPageState();
}

class _AuthWebViewPageState extends ConsumerState<AuthWebViewPage> {
  String _currentUrl = '';
  String? _status;
  bool _capturing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authorizer = ref.watch(browserAuthorizerProvider);
    final loginUrl = authorizer.loginUrl(DriveProvider.quark);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 系统标题栏已经被抹掉（见 macos/Runner/MainFlutterWindow.swift），
          // AppBar 会变成「第二条标题栏」，所以换成一条不带底色的工具行。
          // 页面名「登录夸克网盘」由虚拟标题栏承担，这里只放返回和动作。
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
            child: Row(
              children: [
                const PageBackButton(),
                const Spacer(),
                if (_capturing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _tryCapture,
                    child: const Text('我已登录'),
                  ),
              ],
            ),
          ),
          if (_status != null)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _status!,
                style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(loginUrl.toString())),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onLoadStop: (controller, url) async {
                _currentUrl = url?.toString() ?? '';
                await _maybeAutoCapture();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 页面加载完成后自动判断一次。登录成功通常会发生跳转，
  /// 所以「加载停止」是最自然的检查时机，用户不必手动点按钮。
  Future<void> _maybeAutoCapture() async {
    if (_capturing) return;
    final authorizer = ref.read(browserAuthorizerProvider);
    final loggedIn = await authorizer.isLoggedIn(
      provider: DriveProvider.quark,
      currentUrl: _currentUrl,
    );
    if (!mounted || !loggedIn) return;
    // 自动触发时不弹提示：夸克首页本身匿名可访问，
    // 首次加载就会「看着像已登录」，此时报错纯属噪声。
    await _tryCapture(silent: true);
  }

  Future<void> _tryCapture({bool silent = false}) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _status = null;
    });

    try {
      final authorizer = ref.read(browserAuthorizerProvider);
      final credential = await authorizer.capture(DriveProvider.quark);
      if (!mounted) return;

      if (credential == null) {
        setState(() {
          _capturing = false;
          if (!silent) {
            _status = '还没读到登录凭证 —— 请先在页面里完成登录，再点右上角「我已登录」。';
          }
        });
        return;
      }

      final error =
          await ref.read(authControllerProvider.notifier).authorize(credential);
      if (!mounted) return;

      if (error == null) {
        // 授权状态变化会触发路由重定向；这里再兜一次，避免重定向未及时生效
        context.go('/library');
      } else {
        setState(() {
          _capturing = false;
          _status = error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _status = '读取凭证失败：$e';
      });
    }
  }
}
