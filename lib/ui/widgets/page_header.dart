import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 页面标题区，对齐设计原型 `.desk-head`。
///
/// **高度由内容决定，不写死。** 原型里 `.desk-head` 是 `flex: 0 0 auto`，
/// 高度随内容长；只有下面的列表是 `flex: 1` 的滚动区。
///
/// 曾经这里实现成 `PreferredSizeWidget` 直接塞进 `Scaffold.appBar`，
/// 于是必须给一个固定的 `preferredSize`（58 / 76）。固定高度只要和真实
/// 行高对不上就会溢出 —— 本工程字体 PingFang SC 的行高系数是 **1.4**，
/// 19px 标题 ≈ 26.6px，比按 1.2 估的 22.8px 高出近 4px；带 hint 时
/// 26.6 + 5 + 16.1 + 上下内边距 30 = 77.7，正好顶破 76，
/// 画面上就是那条「BOTTOM OVERFLOWED BY 2.0 PIXELS」的黄黑条纹。
///
/// 现在它是个普通 widget，放在页面内容列的**第一个位置**，
/// 无论标题多长、hint 折几行、用户把系统字号调多大，都不会溢出。
/// 回归测试见 `test/ui/layout_overflow_test.dart`。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.hint,
    this.actions,
  });

  final String title;

  /// 标题下的一行说明（设计稿 `.hint`，11.5px muted）
  final String? hint;

  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 与原型 `.desk-head{padding:18px 22px 12px}` 一致
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppTheme.text,
                  ),
                ),
                if (hint case final hint?) ...[
                  const SizedBox(height: 5),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                  ),
                ],
              ],
            ),
          ),
          if (actions case final actions?)
            Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );
  }
}
