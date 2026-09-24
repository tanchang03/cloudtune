import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/auth_page.dart';
import '../pages/auth_qr_login_page.dart';
import '../pages/auth_webview_page.dart';
import '../pages/diagnostics_page.dart';
import '../pages/favorites_page.dart';
import '../pages/library_page.dart';
import '../pages/player_page.dart';
import '../pages/scan_page.dart';
import '../pages/settings_page.dart';
import '../pages/splash_page.dart';
import '../providers/auth_providers.dart';
import '../shell/app_shell.dart';

/// 把 Riverpod 的状态变化桥接给 go_router 的 `refreshListenable`。
///
/// go_router 的 `redirect` 只在「路由变化」或「refreshListenable 触发」时求值。
/// 授权状态是异步解析出来的，不主动通知它重算的话，登录成功后页面不会跳走。
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authControllerProvider, (_, __) => refresh.ping());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // 授权状态还没解析出来时停在启动页，
      // 否则会「先闪一下授权页、再跳回曲库」。
      if (auth.isLoading) return location == '/splash' ? null : '/splash';

      final authorized = auth.valueOrNull?.isAuthorized ?? false;
      if (location == '/splash') return authorized ? '/library' : '/auth';

      final atAuth = location.startsWith('/auth');
      if (!authorized && !atAuth) return '/auth';
      if (authorized && atAuth) return '/library';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthPage(),
        routes: [
          GoRoute(
            path: 'browser',
            builder: (_, __) => const AuthWebViewPage(),
          ),
          GoRoute(
            path: 'qr',
            builder: (_, __) => const AuthQrLoginPage(),
          ),
        ],
      ),
      GoRoute(path: '/player', builder: (_, __) => const PlayerPage()),
      // 诊断日志是**全屏页**（`push` 进入，`pop` 返回），不进侧栏分支：
      // 它是排查工具，不是产品功能的一级入口。
      GoRoute(path: '/diagnostics', builder: (_, __) => const DiagnosticsPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(shell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/library', builder: (_, __) => const LibraryPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, __) => const FavoritesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/scan', builder: (_, __) => const ScanPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
            ],
          ),
        ],
      ),
    ],
  );
});
