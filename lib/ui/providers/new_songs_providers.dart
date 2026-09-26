import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../data/db/settings_store.dart';
import '../../domain/services/auto_scan_service.dart';
import '../../domain/services/scan_service.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';

/// 用户上次「看完新歌」的时间（水位）。
///
/// 一首歌「新不新」= 它第一次进库的时间（[Track.firstSeenAt]）是否晚于这个值。
/// 这个值是 [AsyncNotifier] 而不是裸的 [FutureProvider]，因为「标记已看」
/// 需要改它再让依赖者（徽标、计数、曲目标签）立刻重算 —— 用一个可变状态
/// 比「写设置 + 手动 invalidate 一圈」干净得多。
final newSongsSeenAtProvider =
    AsyncNotifierProvider<_NewSongsSeenAt, DateTime?>(_NewSongsSeenAt.new);

class _NewSongsSeenAt extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    final store = ref.watch(settingsStoreProvider);
    return store.readDateTime(SettingKeys.newSongsSeenAt);
  }

  /// 标记「已看完新歌」：把水位设为现在，并让计数/标签立刻重算。
  ///
  /// 写进设置（重启后依然有效，这不是「这次会话没新歌」），再更新内存状态。
  Future<void> markSeen() async {
    final store = ref.read(settingsStoreProvider);
    final now = DateTime.now();
    await store.writeDateTime(SettingKeys.newSongsSeenAt, now);
    state = AsyncData(now);
    ref.invalidate(newSongsCountProvider);
  }
}

/// 新歌数量：第一次进库时间晚于水位的曲目数。
///
/// ⚠️ 水位为 `null`（基线还没建立，或老用户还没扫过第一次）时返回 **0**，
/// 而不是「全库都算新」—— 否则升级后第一次打开会把整库刷成红点，毫无意义。
/// 基线由 [ScanService] 在**第一次成功扫描后**写入，详见 `scan_service.dart`。
final newSongsCountProvider = FutureProvider<int>((ref) async {
  final seenAt = await ref.watch(newSongsSeenAtProvider.future);
  if (seenAt == null) return 0;
  final library = ref.watch(libraryProvider);
  return library.newTracksCount(seenAt: seenAt);
});

/// 后台自动扫描服务（不定期发现新歌）。
///
/// 只在桌面端常驻的前提下有意义：它是一个 `Timer`，应用退出即终止。
/// 授权后才启动，注销后停下 —— 见 [_AutoScanKicker]。
final autoScanServiceProvider = Provider<AutoScanService>((ref) {
  final scan = ref.watch(scanServiceProvider);
  return AutoScanService(
    runner: ScanServiceRunner(scan),
    // 每次排程都重新求值：授权状态会变
    getProviders: () {
      final account = ref.read(authControllerProvider).valueOrNull?.account;
      return account == null ? const [] : [account.provider];
    },
    // 默认每 2 小时扫一遍，±30 分钟抖动，避免所有客户端在同一秒打接口
    interval: const Duration(hours: 2),
    jitter: const Duration(minutes: 30),
    // 每轮扫完（无论成败）让徽标/计数重算；基线也是扫完后才落库的
    onCycleDone: () => ref.invalidate(newSongsSeenAtProvider),
    onError: (e, provider) =>
        diag.warn('自动扫描', '$provider 自动扫描失败：$e'),
  );
});

/// 自动扫描的「启动开关」。
///
/// 它本身不持有计时器（那在 [autoScanServiceProvider] 里），只负责：
///   - 授权已就绪 → 启动；
///   - 未授权 / 登出 → 停下。
/// 由 [CloudTuneApp] 一直 watch，保证它在应用生命周期内常驻。
final autoScanKickerProvider =
    AsyncNotifierProvider<_AutoScanKicker, void>(_AutoScanKicker.new);

class _AutoScanKicker extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    final auth = await ref.watch(authControllerProvider.future);
    final service = ref.watch(autoScanServiceProvider);
    if (auth.isAuthorized) {
      service.start();
    } else {
      service.stop();
    }
  }
}
