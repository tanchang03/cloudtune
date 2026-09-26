import 'dart:async';
import 'dart:math';

import '../entities/drive_provider.dart';
import 'scan_service.dart';

/// 单次增量扫描的抽象。把 [ScanService] 包一层，便于测试用假实现替换。
///
/// 自动扫描服务只关心「给一个网盘、扫一次」，不关心扫描内部怎么走；
/// 把这一段抽成接口，测试就能用零依赖的假实现覆盖调度逻辑。
abstract class ScanRunner {
  /// 是否已有扫描在进行中（自动扫描要避开，否则会和手动/续扫互相打架）。
  bool get isRunning;

  /// 对一个网盘做一次增量扫描（续扫 + 陈旧清理）。
  Future<ScanOutcome> scan(DriveProvider provider);
}

/// [ScanService] 的 [ScanRunner] 适配。
class ScanServiceRunner implements ScanRunner {
  ScanServiceRunner(this.service, {this.pruneStale = true});

  final ScanService service;
  final bool pruneStale;

  @override
  bool get isRunning => service.isRunning;

  @override
  Future<ScanOutcome> scan(DriveProvider provider) =>
      service.scan(provider, resume: true, pruneStale: pruneStale);
}

/// 自动发现新歌的后台扫描服务。
///
/// 思路：**不定期**地把所有已授权网盘增量扫一遍，让新加进网盘的文件被
/// 索引进来（[ScanService] 会写 `first_seen_at`，UI 据此显示「新」标签）。
///
/// 「不定期」不是噱头：固定间隔会让所有客户端在同一秒同时打接口，给网盘
/// 服务端造成可预测的流量尖峰。这里在 `interval` 基础上叠加 ±`jitter` 的
/// 随机抖动，使各客户端的触发时刻错开。
///
/// 设计取舍：
///   - 只在**桌面端常驻**的前提下有意义 —— 它是一个 `Timer`，应用退出即终止。
///     不做 OS 级后台调度（那是另一回事，超出本功能范围）。
///   - 一个周期正在进行（手动扫描或上一次自动周期尚未结束）时，跳过本次，
///     绝不并发两路扫描（[ScanService.scan] 会对并发直接抛 `StateError`）。
///   - 单个网盘扫描失败**不**中断整轮：其余网盘照常扫，失败信息由回调上报。
class AutoScanService {
  AutoScanService({
    required this.runner,
    required this.getProviders,
    required this.interval,
    this.jitter = Duration.zero,
    Random? random,
    this.onError,
    this.onCycleDone,
    this.timerFactory = Timer.new,
  })  : _random = random ?? Random();

  /// 计时器工厂，默认 [Timer.new]。测试可注入一个不真正触发（或可控触发）
  /// 的实现，避免真实 `Timer` 让调度逻辑变得不可控。
  final Timer Function(Duration, void Function()) timerFactory;

  /// 执行单次扫描的入口（被测抽象）。
  final ScanRunner runner;

  /// 取当前已授权的网盘列表。每次排程都重新求值：授权状态会变。
  final List<DriveProvider> Function() getProviders;

  /// 基础扫描间隔。
  final Duration interval;

  /// 抖动幅度：实际间隔在 `[interval - jitter, interval + jitter]` 之间。
  final Duration jitter;

  /// 单个网盘扫描失败时上报（不中断整轮）。可用于写诊断日志。
  final void Function(Object error, DriveProvider provider)? onError;

  /// 每一轮（无论成败）结束后回调。用于让依赖新歌数据的 UI 重算 ——
  /// 基线水位正是某一轮成功扫描后才落库的，不刷新就看不到新歌。
  final void Function()? onCycleDone;

  final Random _random;

  Timer? _timer;
  bool _active = false;

  /// 是否已启动（用于避免重复 `start`）。
  bool get isActive => _active;

  /// 下一次触发还要多久（测试可断言）。
  Duration? get nextDelay => _nextDelay;
  Duration? _nextDelay;

  /// 启动后台扫描。已启动则幂等返回。
  void start() {
    if (_active) return;
    _active = true;
    _scheduleNext();
  }

  /// 停止并取消计时器。
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _nextDelay = null;
  }

  /// 立即跑一轮（不依赖计时器）。测试与「手动触发一次」都用它。
  ///
  /// 返回本轮实际扫过的网盘数（跳过正在进行的、未授权的都不算）。
  Future<int> runOnce() async {
    if (!_active) return 0;
    if (runner.isRunning) return 0;

    final providers = getProviders();
    var scanned = 0;
    for (final provider in providers) {
      try {
        await runner.scan(provider);
        scanned++;
      } catch (e) {
        onError?.call(e, provider);
      }
    }
    return scanned;
  }

  void _scheduleNext() {
    if (!_active) return;
    final base = interval.inMilliseconds;
    final j = jitter.inMilliseconds;
    final offset = j == 0 ? 0 : (_random.nextDouble() * 2 - 1) * j;
    final nextMs = max(0, (base + offset).round());
    _nextDelay = Duration(milliseconds: nextMs);
    _timer = timerFactory(_nextDelay!, () => _onTick());
  }

  void _onTick() {
    if (!_active) return;
    // 直接在 tick 里跑，跑完再排下一轮 —— 这样「一轮耗时」不会叠加进间隔，
    // 间隔始终是两轮**开始**之间的间隔，不会因为一轮扫得久就把下一轮往后挤。
    _timer = null;
    _nextDelay = null;
    runOnce().whenComplete(() {
      onCycleDone?.call();
      _scheduleNext();
    });
  }
}
