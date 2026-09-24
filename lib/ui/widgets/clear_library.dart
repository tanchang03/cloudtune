import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/drive_provider.dart';
import '../providers/app_providers.dart';
import '../providers/library_providers.dart';

/// 清空本地曲库索引（含收藏与播放历史），**不动网盘上的文件**。
///
/// 抽成公共函数是因为曲库页和设置页都要用。两处各写一遍的话，
/// 「清完要刷新哪些 provider」这件事迟早会在其中一处漏掉，
/// 表现就是清空后列表还在、统计还是旧数字。
///
/// 返回 `true` 表示确实清空了（用户确认过）。
Future<bool> confirmAndClearLibrary(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('清空音乐库？'),
      content: const Text(
        '这会删除本地索引里的全部曲目、收藏与播放历史，'
        '「音乐库」会变回空列表。\n\n'
        '网盘上的文件不受影响，重新扫描就能恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('清空'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  await ref.read(libraryProvider).clearProvider(DriveProvider.quark);

  // 与曲库相关的 provider 全部失效，少一个就会出现「清了但界面没变」
  ref.invalidate(libraryStatsProvider);
  ref.invalidate(libraryTracksProvider);
  ref.invalidate(favoritesTracksProvider);
  ref.invalidate(playabilitySummaryProvider);
  ref.invalidate(favoriteIdsProvider);
  ref.invalidate(shuffleWeightsProvider);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空音乐库')),
    );
  }
  return true;
}
