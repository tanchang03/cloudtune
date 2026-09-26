import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'providers/new_songs_providers.dart';
import 'widgets/window_top_inset.dart';

/// 应用根组件。
class CloudTuneApp extends ConsumerWidget {
  const CloudTuneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 常驻启动自动扫描（授权后才真正开始，注销后停下）。一直 watch 保证它在
    // 应用生命周期内不被销毁。
    ref.watch(autoScanKickerProvider);
    return MaterialApp.router(
      title: '云韵 CloudTune',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // 设计原型（prototype/index.html）是深色主题，1:1 还原故锁定深色
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // 原型 body 上叠了两处径向光晕（左上蓝 / 右上紫），
      // 挂在 builder 上才能真正铺在所有路由（含启动页、授权页）之下。
      builder: (context, child) => DesignBackground(
        child: _WindowChrome(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// 窗口外壳：顶部留白 + 路由内容。
///
/// 挂在 `MaterialApp.builder` 上，也就是 **Navigator 之上** ——
/// 这样顶部留白不跟着路由转场一起滑动/缩放。
///
/// 这里只有一条 [WindowTopInset]，不再有标题栏：系统标题栏已抹掉，
/// 而自绘一条横条只会让人以为「标题栏没去掉」。当前页名字由各页面
/// 自己的标题承担，所以也不需要监听路由变化。
class _WindowChrome extends StatelessWidget {
  const _WindowChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const WindowTopInset(),
        Expanded(child: child),
      ],
    );
  }
}
