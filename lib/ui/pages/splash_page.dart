import 'package:flutter/material.dart';

/// 启动页。
///
/// 授权状态是异步解析的（要读钥匙串 + 打一次 `/member` 校验），
/// 这段时间需要一个稳定的页面兜住，否则会「先闪授权页、再跳曲库」。
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.graphic_eq, size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              '云韵 CloudTune',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '正在恢复会话…',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
