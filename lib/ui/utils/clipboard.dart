import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 复制文本并给一条可确认的提示。
///
/// 路径这种东西复制完没有任何视觉变化，不给反馈的话用户会怀疑到底复制了没有。
/// 顺带把提示内容一起显示出来，复制错了能立刻发现。
Future<void> copyText(
  BuildContext context,
  String text, {
  String? label,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 460,
        content: Row(
          children: [
            const Icon(Icons.check, size: 16, color: AppTheme.ok),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${label ?? '已复制'}：$text',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
}
