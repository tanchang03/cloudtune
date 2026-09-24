import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/track.dart';
import '../../domain/services/playback_controller.dart';
import '../../domain/services/playback_queue.dart';
import 'app_providers.dart';

/// 播放器 UI 状态。
class PlayerState {
  const PlayerState({
    this.current,
    this.mode = PlaybackMode.sequential,
    this.busy = false,
    this.notice,
    this.noticeIsProblem = false,
  });

  /// 当前已装载的曲目。`null` 表示还没开始播。
  final Track? current;

  final PlaybackMode mode;

  /// 正在取链/装载
  final bool busy;

  /// 最近一条提示（跳过、续链、失败…）
  final String? notice;

  final bool noticeIsProblem;

  bool get hasTrack => current != null;

  @override
  String toString() => 'PlayerState(${current?.name ?? "无"}, ${mode.name})';
}

/// 播放器控制器。
///
/// 只做两件事：把领域层的事件流翻译成 UI 状态、把 UI 动作转成引擎调用。
/// 真正的编排（取链、缓存、续链、跳过、统计）全在 `PlaybackController` 里，
/// 这里刻意不重复实现任何一条规则。
class PlayerNotifier extends Notifier<PlayerState> {
  Timer? _noticeTimer;
  bool _busy = false;
  String? _notice;
  bool _noticeProblem = false;

  @override
  PlayerState build() {
    final controller = ref.watch(playbackControllerProvider);
    final subscription = controller.events.listen(_onEvent);
    ref.onDispose(() {
      subscription.cancel();
      _noticeTimer?.cancel();
    });
    return _snapshot(controller);
  }

  PlayerState _snapshot(PlaybackController controller) => PlayerState(
        current: controller.current,
        mode: controller.queue.mode,
        busy: _busy,
        notice: _notice,
        noticeIsProblem: _noticeProblem,
      );

  void _onEvent(PlaybackEvent event) {
    if (event.message != null) {
      _notice = event.message;
      _noticeProblem = event.isProblem;
      _noticeTimer?.cancel();
      // 提示是瞬时的：不自动清掉的话，用户会一直以为当前还在出错
      _noticeTimer = Timer(const Duration(seconds: 4), () {
        _notice = null;
        _noticeProblem = false;
        state = _snapshot(ref.read(playbackControllerProvider));
      });
    }
    state = _snapshot(ref.read(playbackControllerProvider));
  }

  void dismissNotice() {
    _noticeTimer?.cancel();
    _notice = null;
    _noticeProblem = false;
    state = _snapshot(ref.read(playbackControllerProvider));
  }

  /// 从某个列表开始播放。会**重设播放队列**为这个列表。
  Future<void> playFrom(List<Track> tracks, Track selected) async {
    final controller = ref.read(playbackControllerProvider);
    _busy = true;
    state = _snapshot(controller);
    try {
      final weights = await ref.read(libraryProvider).shuffleCandidates();
      controller.setQueue(tracks, weights: weights);
      await controller.playTrack(selected);
    } catch (e) {
      _notice = '播放失败：$e';
      _noticeProblem = true;
    } finally {
      _busy = false;
      state = _snapshot(controller);
    }
  }

  /// 播放 / 暂停切换。
  Future<void> togglePlay() async {
    final controller = ref.read(playbackControllerProvider);
    try {
      if (controller.isPlaying) {
        await controller.pause();
      } else {
        await controller.resume();
      }
    } finally {
      state = _snapshot(controller);
    }
  }

  Future<void> next() async {
    final controller = ref.read(playbackControllerProvider);
    try {
      await controller.next();
    } finally {
      state = _snapshot(controller);
    }
  }

  Future<void> previous() async {
    final controller = ref.read(playbackControllerProvider);
    try {
      await controller.previous();
    } finally {
      state = _snapshot(controller);
    }
  }

  Future<void> seek(Duration position) =>
      ref.read(playbackControllerProvider).seek(position);

  /// 顺序 / 随机 互切。播放条上那个按钮单击就是这一下。
  ///
  /// 切到随机时 `PlaybackQueue.setMode` 会清空本轮记录；切回顺序时曲池
  /// 本身没被动过，所以「下一首」立刻恢复成用户看到的那份列表的次序。
  void toggleMode() =>
      setMode(ref.read(playbackControllerProvider).queue.mode.toggled);

  /// 直接指定模式（菜单里选中哪一项就是哪一项，不再轮转）。
  void setMode(PlaybackMode mode) {
    final controller = ref.read(playbackControllerProvider);
    controller.setMode(mode);
    state = _snapshot(controller);
  }
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);

/// 播放位置。直接透传 `AudioOutput` 的流 —— 进度条需要高频刷新，
/// 不适合走状态对象。
final playbackPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioOutputProvider).positionStream,
);

final playbackDurationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(audioOutputProvider).durationStream,
);

/// 播放器真实播放状态（以平台播放器为准，而不是我们自己的标志位）。
final playbackPlayingProvider = StreamProvider<bool>(
  (ref) => ref.watch(audioOutputProvider).playingStream,
);

/// 播放模式的展示文案与图标。
///
/// 文案与用户的口径保持一致：他关心的是「随机还是顺序」，而不是
/// 「列表到底会不会循环」。顺序模式播到末尾确实会回到第一首，
/// 但把它叫「列表循环」会让用户以为这是第三种模式。
extension PlaybackModeVisuals on PlaybackMode {
  String get label => switch (this) {
        PlaybackMode.sequential => '顺序播放',
        PlaybackMode.shuffle => '随机播放',
        PlaybackMode.repeatOne => '单曲循环',
      };

  IconData get icon => switch (this) {
        PlaybackMode.sequential => Icons.repeat,
        PlaybackMode.shuffle => Icons.shuffle,
        PlaybackMode.repeatOne => Icons.repeat_one,
      };
}
