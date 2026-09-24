import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/playback_queue.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';

/// 播放模式按钮：**单击在「顺序 / 随机」之间直接互切**，右键或长按弹出
/// 三种模式的菜单（当前模式带勾选）。
///
/// 为什么不做「点一下轮转三种」：用户最常做的一次切换是「随机听腻了换回
/// 顺序」，轮转会在中间插一次单曲循环 —— 等于要求用户背下按钮顺序，
/// 每按一次还得看一眼图标确认现在到哪一档。
/// 单曲循环并没有被砍掉，只是不再挡在两个高频模式中间。
///
/// 另一个副作用是它**不需要有歌在播才能点**：播放顺序是个偏好，
/// 用户完全可以先选好随机/顺序再去列表里点第一首。
class PlaybackModeButton extends ConsumerWidget {
  const PlaybackModeButton({
    super.key,
    this.size = 34,
    this.iconSize = 19,
  });

  /// 点击热区（正方形）边长
  final double size;

  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerProvider).mode;
    // 顺序播放是「没开任何额外开关」的默认态，不上色 ——
    // 上色的那一个才是用户主动打开的东西
    final highlighted = mode != PlaybackMode.sequential;

    return Tooltip(
      // 长按归菜单用，所以这里只保留鼠标悬停提示
      triggerMode: TooltipTriggerMode.manual,
      message: '${mode.label} · 点击切换顺序/随机，右键可选单曲循环',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => ref.read(playerProvider.notifier).toggleMode(),
          onLongPress: () => _pickMode(context, ref, mode),
          onSecondaryTap: () => _pickMode(context, ref, mode),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              mode.icon,
              size: iconSize,
              color: highlighted ? AppTheme.accent : AppTheme.text,
            ),
          ),
        ),
      ),
    );
  }

  /// 在按钮上弹出模式菜单。
  ///
  /// 用 [showMenu] 而不是自己搭浮层：位置计算、贴边翻转、点外部关闭
  /// 都由它负责，而且它认得 overlay 的边界 —— 播放条就在窗口最底部，
  /// 菜单必须能自动翻到按钮上方，否则会被窗口切掉。
  Future<void> _pickMode(
    BuildContext context,
    WidgetRef ref,
    PlaybackMode mode,
  ) async {
    // 先取好 notifier：await 之后这个 context 可能已经失效了
    final notifier = ref.read(playerProvider.notifier);

    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !overlay.hasSize) {
      return;
    }

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final chosen = await showMenu<PlaybackMode>(
      context: context,
      position: position,
      color: AppTheme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.line),
      ),
      items: [
        for (final m in PlaybackMode.values)
          PopupMenuItem<PlaybackMode>(
            value: m,
            height: 38,
            child: Row(
              children: [
                Icon(
                  m.icon,
                  size: 15,
                  color: m == mode ? AppTheme.accent : AppTheme.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    m.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          m == mode ? FontWeight.w600 : FontWeight.w400,
                      color: m == mode ? AppTheme.text : AppTheme.muted,
                    ),
                  ),
                ),
                if (m == mode)
                  const Icon(Icons.check, size: 14, color: AppTheme.accent),
              ],
            ),
          ),
      ],
    );

    if (chosen != null) notifier.setMode(chosen);
  }
}
