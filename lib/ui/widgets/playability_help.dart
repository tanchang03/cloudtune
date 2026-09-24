import 'package:flutter/material.dart';

import '../../domain/entities/playability.dart';
import '../../domain/entities/track.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard.dart';

/// 打开「这首能不能播」的说明。
///
/// 列表行里的徽标只有四个字，说不清事情。用户真正需要的是三个问题的答案：
///   ① 哪些文件会这样？ ② 什么原因？ ③ 什么条件下才能播？
/// 这里按设计原型的信息层级把三者摊开讲清楚，并附上可复制的完整路径，
/// 方便用户直接去网盘里找到这个文件。
Future<void> showPlayabilityHelp(
  BuildContext context, {
  required Track track,
  required Playability playability,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _PlayabilityDialog(track: track, playability: playability),
  );
}

class _PlayabilityDialog extends StatelessWidget {
  const _PlayabilityDialog({required this.track, required this.playability});

  final Track track;
  final Playability playability;

  @override
  Widget build(BuildContext context) {
    final state = playability.state;
    final color = state.color(Theme.of(context).colorScheme);

    return Dialog(
      backgroundColor: AppTheme.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      state.badgeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      state.helpTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.dim),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 三段说明 + 文件事实可能很长（中文段落 + 系统字号放大），
              // 窗口一矮就会顶破弹窗高度、画出黄黑条纹 —— 而条纹底下的内容
              // 用户永远看不到。所以这一段必须是**可滚动**的，
              // 而不是硬塞进 Column 里按自然高度排。
              //
              // 标题与底部按钮刻意留在滚动区之外：无论内容多长，
              // 「这是什么状态」和「关闭 / 复制路径」都必须在视野里。
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Section(label: '哪些文件会这样', text: state.explainWhat),
                      _Section(label: '什么原因', text: state.explainWhy),
                      _Section(
                        label: '怎样才能播',
                        text: state.explainHow,
                        highlight: true,
                      ),
                      const Divider(height: 22, color: AppTheme.line),
                      _Section(
                        label: '这个文件',
                        text: _fileFacts(),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          copyText(context, track.fullPath, label: '已复制路径'),
                      icon: const Icon(Icons.copy_all, size: 16),
                      label: const Text('复制完整路径'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('知道了'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 把这个文件的客观事实列出来 —— 用户要判断「是不是同名文件搞错了」时有用
  String _fileFacts() {
    final facts = <String>[
      '文件名：${track.name}',
      '位置：${track.fullPath}',
      '网盘：${track.provider.displayName}',
      '体积：${formatBytes(track.sizeBytes)}',
      if (playability.limitBytes != null)
        '取链接口的单文件上限：${formatBytes(playability.limitBytes)}',
    ];
    return facts.join('\n');
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.text,
    this.highlight = false,
    this.dense = false,
  });

  final String label;
  final String text;

  /// 高亮段（「怎样才能播」）：这是用户唯一能采取行动的一条
  final bool highlight;

  /// 紧凑段（文件事实）：等宽小字，方便扫读
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: highlight ? AppTheme.accent : AppTheme.dim,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: dense ? 11 : 12.5,
              height: dense ? 1.75 : 1.7,
              color: dense ? AppTheme.muted : const Color(0xFFC3CDE3),
              fontFamily: dense ? 'Menlo' : null,
            ),
          ),
        ],
      ),
    );
  }
}
