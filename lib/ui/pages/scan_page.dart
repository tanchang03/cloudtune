import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/adapters/library_repository.dart';
import '../../domain/entities/playability.dart';
import '../../domain/services/playability_resolver.dart';
import '../../domain/services/scan_service.dart';
import '../providers/library_providers.dart';
import '../providers/scan_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';

/// 扫描页：发起遍历，并实时看进度与可播性体检结果。
class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final stats = ref.watch(libraryStatsProvider).valueOrNull;
    final summary = ref.watch(playabilitySummaryProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const PageHeader(
              title: '扫描',
              hint: '按目录逐层遍历并识别音频文件，每页都会落库 —— 中途退出也不会丢进度',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                children: [
                  _ScanControl(scan: scan),
                  const SizedBox(height: 16),
                  _StatsCard(stats: stats),
                  const SizedBox(height: 16),
                  _PlayabilityCard(summary: summary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanControl extends ConsumerWidget {
  const _ScanControl({required this.scan});

  final ScanUiState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final progress = scan.progress;
    final controller = ref.read(scanControllerProvider.notifier);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '遍历网盘音乐库',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '按目录逐层遍历并识别音频文件，每页都会落库 —— '
              '中途退出也不会丢进度，下次可以接着扫。',
              style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            if (scan.running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                progress?.currentDirPath ?? '正在准备…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
            ],
            if (progress != null) _ProgressGrid(progress: progress),
            if (scan.error != null) ...[
              const SizedBox(height: 14),
              _Notice(
                icon: Icons.error_outline,
                color: scheme.error,
                text: scan.error!,
              ),
            ],
            if (!scan.running && scan.outcome != null) ...[
              const SizedBox(height: 14),
              _Notice(
                icon: scan.outcome!.isComplete
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                color: scan.outcome!.isComplete ? scheme.primary : scheme.tertiary,
                text: _describeOutcome(scan.outcome!),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: scan.running ? null : () => controller.start(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(progress == null ? '开始扫描' : '继续扫描'),
                  ),
                ),
                if (scan.running) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('停止'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _describeOutcome(ScanOutcome outcome) {
    final parts = <String>[
      '入库 ${outcome.tracksIndexed} 首',
      if (outcome.removedTracks > 0) '清理 ${outcome.removedTracks} 首',
      outcome.wasCancelled
          ? '已停止（可续扫）'
          : (outcome.error != null ? '中断：${outcome.error}' : '已完成'),
    ];
    return parts.join(' · ');
  }
}

class _ProgressGrid extends StatelessWidget {
  const _ProgressGrid({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Stat(label: '已扫目录', value: '${progress.scannedDirs}'),
        _Stat(label: '已扫文件', value: '${progress.scannedFiles}'),
        _Stat(label: '识别曲目', value: '${progress.foundTracks}'),
        _Stat(label: '待扫目录', value: '${progress.pendingDirs}'),
        if (progress.failedDirs > 0)
          _Stat(label: '失败目录', value: '${progress.failedDirs}', danger: true),
        _Stat(label: '累计体积', value: formatBytes(progress.totalBytes)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: danger ? scheme.error : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final LibraryStats? stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = stats;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '曲库概览',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            if (s == null || s.isEmpty)
              Text(
                '还没有扫描过。点上面的「开始扫描」把网盘里的音乐建成本地索引。',
                style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Stat(label: '曲目总数', value: '${s.trackCount}'),
                  _Stat(label: '确认可播', value: '${s.playableCount}'),
                  _Stat(label: '可尝试', value: '${s.attemptableCount}'),
                  _Stat(label: '收藏', value: '${s.favoriteCount}'),
                  _Stat(label: '艺术家', value: '${s.artistCount}'),
                  _Stat(label: '专辑', value: '${s.albumCount}'),
                  _Stat(label: '总体积', value: formatBytes(s.totalBytes)),
                  _Stat(label: '可播体积', value: formatBytes(s.playableBytes)),
                ],
              ),
              const SizedBox(height: 16),
              _Meter(
                label: '值得尝试播放的比例',
                ratio: s.attemptableRatio,
                detail: '${s.attemptableCount} / ${s.trackCount} 首',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayabilityCard extends StatelessWidget {
  const _PlayabilityCard({required this.summary});

  final PlayabilitySummary? summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = summary;

    if (s == null || s.total == 0) {
      return const SizedBox.shrink();
    }

    final entries = <(PlayabilityState, int)>[
      (PlayabilityState.playable, s.playable),
      (PlayabilityState.unknownSize, s.unknownSize),
      (PlayabilityState.overLimit, s.overLimit),
      (PlayabilityState.unsupportedByProvider, s.unsupported),
      (PlayabilityState.notAudio, s.notAudio),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '可播性体检',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '网盘允许「列出」的文件未必允许「取链」。这里统计扫描时的判定结果；'
              '扫描时判不准的，会在真正播放失败时补记，不会白跑一趟。',
              style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (final (state, count) in entries)
                      if (count > 0)
                        Expanded(
                          flex: count,
                          child: ColoredBox(color: state.color(scheme)),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final (state, count) in entries)
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: state.color(scheme),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 72,
                        child: Text(
                          state.badgeLabel,
                          style: TextStyle(fontSize: 12, color: scheme.onSurface),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          state.badgeHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.ratio, required this.detail});

  final String label;
  final double ratio;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              '${(ratio * 100).toStringAsFixed(1)}%  ·  $detail',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: ratio, minHeight: 6),
        ),
      ],
    );
  }
}
