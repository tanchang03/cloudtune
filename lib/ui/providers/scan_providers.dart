import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/drive_error.dart';
import '../../domain/entities/drive_provider.dart';
import '../../domain/services/scan_service.dart';
import 'app_providers.dart';
import 'library_providers.dart';

/// 扫描页状态。
class ScanUiState {
  const ScanUiState({
    this.progress,
    this.running = false,
    this.outcome,
    this.error,
  });

  /// 实时进度。冷启动时由 [ScanService.lastProgress] 兜底。
  final ScanProgress? progress;

  final bool running;

  /// 最近一次完整结果（完成/取消/失败后才有）
  final ScanOutcome? outcome;

  /// 中断原因，面向用户
  final String? error;

  bool get hasProgress => progress != null;

  @override
  String toString() => 'ScanUiState(running=$running, ${progress ?? "无进度"})';
}

/// 扫描控制器。
///
/// 刻意**不用 autoDispose**：扫描是长流程，用户切到别的标签页时不能把它丢掉。
class ScanController extends Notifier<ScanUiState> {
  @override
  ScanUiState build() {
    final service = ref.watch(scanServiceProvider);
    return ScanUiState(progress: service.lastProgress, running: service.isRunning);
  }

  /// 开始（或继续）扫描。
  ///
  /// [resume] 为真时接着上次的游标扫；上次已扫完会自动从头开始。
  Future<void> start({bool resume = true}) async {
    if (state.running) return;
    final service = ref.read(scanServiceProvider);

    state = ScanUiState(progress: state.progress, running: true);

    try {
      final outcome = await service.scan(
        DriveProvider.quark,
        resume: resume,
        onProgress: (progress) => state = ScanUiState(
          progress: progress,
          running: progress.isRunning,
        ),
      );
      state = ScanUiState(
        progress: service.lastProgress,
        running: false,
        outcome: outcome,
      );
      _refreshDerived();
    } on DriveException catch (e) {
      state = ScanUiState(
        progress: service.lastProgress,
        running: false,
        error: e.message,
      );
    } catch (e) {
      state = ScanUiState(
        progress: service.lastProgress,
        running: false,
        error: '$e',
      );
    }
  }

  /// 请求停止（协作式，在当前页边界生效）。
  void cancel() => ref.read(scanServiceProvider).requestCancel();

  /// 扫描改了曲库，把派生数据全部作废重算。
  void _refreshDerived() {
    ref.invalidate(libraryTracksProvider);
    ref.invalidate(favoritesTracksProvider);
    ref.invalidate(libraryStatsProvider);
    ref.invalidate(playabilitySummaryProvider);
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(shuffleWeightsProvider);
  }
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanUiState>(ScanController.new);
