import 'dart:math';

import '../entities/track.dart';
import 'shuffle_engine.dart';

/// 播放模式。
enum PlaybackMode {
  /// 顺序播放：按曲池（= 用户看到的那份列表）的次序走，播到末尾回到第一首
  sequential,

  /// 随机播放：一轮之内不重复，抽空后重洗且首曲不与刚播完的重复
  shuffle,

  /// 单曲循环
  repeatOne;

  bool get isShuffle => this == PlaybackMode.shuffle;

  /// 「顺序 / 随机」互切。
  ///
  /// 这是用户做得最多的一次切换 —— 随机听腻了想按列表顺序听，反之亦然。
  /// 所以它必须是**一次点击**：三态轮转（顺序 → 随机 → 单曲循环 → 顺序）
  /// 会让「随机换回顺序」多按一次，中间还闪一下用户并不想要的单曲循环。
  ///
  /// 单曲循环不是「播放顺序」的一种，从它切出去落在顺序播放上：
  /// 用户按这个按钮时想表达的是「换个播放顺序」，不是「继续单曲循环」。
  PlaybackMode get toggled => switch (this) {
        PlaybackMode.sequential => PlaybackMode.shuffle,
        PlaybackMode.shuffle => PlaybackMode.sequential,
        PlaybackMode.repeatOne => PlaybackMode.sequential,
      };
}

/// 播放队列。
///
/// **纯 Dart，无 IO、无 Flutter 依赖**，因此「随机播放」这套最容易出错的
/// 规则可以在单元测试里用固定随机种子穷举。
///
/// 三类状态分得很清楚：
///   - [_tracks]：曲池（顺序即「顺序播放」的次序）；
///   - [_history]：已播过的顺序，支撑「上一首」；
///   - [_playedInRound]：随机模式本轮已抽到的，保证一轮不重复。
///
/// 「上一首」用历史栈而不是「下标 -1」，因为随机模式下根本没有可回退的
/// 线性次序 —— 必须记住实际播过什么。
class PlaybackQueue {
  PlaybackQueue({
    List<Track> tracks = const [],
    Map<String, ShuffleCandidate> weights = const {},
    this.mode = PlaybackMode.sequential,
    ShuffleEngine? shuffle,
    DateTime Function()? clock,
  })  : _tracks = List<Track>.from(tracks),
        _weights = Map<String, ShuffleCandidate>.from(weights),
        _shuffle = shuffle ?? ShuffleEngine(),
        _clock = clock ?? DateTime.now {
    _reindex();
  }

  final ShuffleEngine _shuffle;
  final DateTime Function() _clock;

  List<Track> _tracks;
  Map<String, ShuffleCandidate> _weights;
  final List<String> _history = [];
  Set<String> _playedInRound = <String>{};
  Map<String, Track> _byId = {};

  PlaybackMode mode;

  String? _currentId;

  /// 曲池（顺序播放的次序）
  List<Track> get tracks => List.unmodifiable(_tracks);

  int get length => _tracks.length;

  bool get isEmpty => _tracks.isEmpty;

  bool get isNotEmpty => _tracks.isNotEmpty;

  /// 当前曲目
  Track? get current => _currentId == null ? null : _byId[_currentId!];

  String? get currentId => _currentId;

  /// 本轮随机已抽到的 id（顺序模式恒为空）
  Set<String> get playedInRound =>
      mode.isShuffle ? Set.unmodifiable(_playedInRound) : const {};

  /// 是否还能「上一首」
  bool get canGoPrevious => _history.isNotEmpty;

  /// 队列里是否有这一首
  bool contains(String trackId) => _byId.containsKey(trackId);

  Track? trackById(String trackId) => _byId[trackId];

  void _reindex() {
    _byId = {for (final t in _tracks) t.id: t};
    // 曲池变了以后，当前曲目可能已经不在了
    if (_currentId != null && !_byId.containsKey(_currentId)) {
      _currentId = null;
    }
    _history.removeWhere((id) => !_byId.containsKey(id));
    _playedInRound = _playedInRound.intersection(_byId.keys.toSet());
  }

  /// 直接定位到某一首（不经过 next/previous 的挑选逻辑）。
  ///
  /// 用户点列表里的某一首时用这个。返回 `null` 表示队列里没有这一首。
  Track? jumpTo(String trackId) => _moveTo(trackId, recordHistory: true);

  /// 移动当前曲。
  ///
  /// [recordHistory] 为真时把「离开的那一首」压入历史。两个细节：
  ///   - **目标与当前相同时不记历史**，否则连点同一首歌会把当前曲推进
  ///     历史，之后「上一首」就变成原地踏步；
  ///   - `previous()` 里的顺序回退不记历史，否则「上一首」按两次会又
  ///     回到原来的位置，行为很怪。
  Track? _moveTo(String trackId, {required bool recordHistory}) {
    final t = _byId[trackId];
    if (t == null) return null;
    if (recordHistory && _currentId != null && _currentId != trackId) {
      _pushHistory(_currentId!);
    }
    _currentId = trackId;
    _playedInRound.add(trackId);
    return t;
  }

  /// 抽下一首。队列为空返回 `null`。
  Track? next() {
    if (_tracks.isEmpty) return null;

    switch (mode) {
      case PlaybackMode.repeatOne:
        // 单曲循环：直接返回当前曲；没有当前曲时退化为顺序取第一首
        final cur = current;
        if (cur != null) return cur;
        return jumpTo(_tracks.first.id);

      case PlaybackMode.shuffle:
        final r = _shuffle.nextInRound(
          _candidates(),
          played: _playedInRound,
          currentId: _currentId,
          now: _clock(),
        );
        if (r.nextId == null) return null;
        _playedInRound = r.played;
        return jumpTo(r.nextId!);

      case PlaybackMode.sequential:
        if (_currentId == null) return jumpTo(_tracks.first.id);
        final idx = _indexOf(_currentId!);
        if (idx < 0) return jumpTo(_tracks.first.id);
        // 播到末尾回到第一首（列表循环）
        return jumpTo(_tracks[(idx + 1) % _tracks.length].id);
    }
  }

  /// 回上一首。没有历史时：顺序模式退回列表上一首，随机模式返回 `null`。
  Track? previous() {
    if (_tracks.isEmpty) return null;

    if (_history.isNotEmpty) {
      final prevId = _history.removeLast();
      final t = _byId[prevId];
      if (t != null) {
        _currentId = prevId;
        return t;
      }
      // 历史里的曲目已被移除，继续往前找
      return previous();
    }

    if (mode == PlaybackMode.shuffle) return null;
    if (_currentId == null) return jumpTo(_tracks.first.id);

    final idx = _indexOf(_currentId!);
    if (idx < 0) return jumpTo(_tracks.first.id);
    // 顺序回退不记历史，否则连按「上一首」会来回打转
    return _moveTo(
      _tracks[(idx - 1 + _tracks.length) % _tracks.length].id,
      recordHistory: false,
    );
  }

  /// 切换播放模式。
  ///
  /// 进入随机模式时**清空本轮记录**：否则切模式前的播放历史会与新的一轮
  /// 混在一起，导致「刚播过的又立刻被抽到」。
  void setMode(PlaybackMode next) {
    if (next == mode) return;
    mode = next;
    _playedInRound = <String>{};
  }

  /// 替换曲池（重新扫描、筛选、搜索后调用）。
  ///
  /// [keepCurrent] 为真且当前曲目仍在新池子里时，保留当前曲目继续播。
  ///
  /// ⚠️ **不要在这里「顺手选中第一首」**。`current` 的语义是「已经装载、
  /// 正在播的那一首」，而不是「列表里高亮的那一行」。如果这里抢先把它设成
  /// 第一首，紧接着的 `next()` 就会跳过第一首 —— 用户按「播放」直接从第二首
  /// 开始，而且更糟的是当前曲目其实没在播，UI 显示与实际出声不一致。
  void replaceTracks(List<Track> tracks, {bool keepCurrent = true}) {
    _tracks = List<Track>.from(tracks);
    if (!keepCurrent) {
      _currentId = null;
      _history.clear();
    }
    _reindex();
  }

  /// 从队列里移除一首（例如网盘侧已删除、或运行时发现不可播）。
  ///
  /// 如果移除的正是当前曲目，[current] 会变为 `null`，由调用方决定接哪一首。
  void removeTrack(String trackId) {
    _tracks.removeWhere((t) => t.id == trackId);
    _weights.remove(trackId);
    _history.removeWhere((id) => id == trackId);
    if (_currentId == trackId) _currentId = null;
    _reindex();
  }

  /// 更新随机权重（播放统计变化后调用，让「少听优先」立刻生效）。
  void updateWeights(Map<String, ShuffleCandidate> weights) {
    _weights = Map<String, ShuffleCandidate>.from(weights);
  }

  /// 重置到「一首都没播过」的状态。
  void reset() {
    _currentId = null;
    _history.clear();
    _playedInRound = <String>{};
  }

  void _pushHistory(String? id) {
    if (id == null) return;
    // 连续两次跳到同一首时不记历史，否则「上一首」会原地踏步
    if (_history.isNotEmpty && _history.last == id) return;
    _history.add(id);
  }

  int _indexOf(String id) => _tracks.indexWhere((t) => t.id == id);

  /// 构造随机候选集：播放次数与最近播放时间来自仓储，权重缺失时按 0 处理。
  List<ShuffleCandidate> _candidates() => [
        for (final t in _tracks)
          _weights[t.id] ?? ShuffleCandidate(id: t.id),
      ];

  @override
  String toString() => 'PlaybackQueue(${_tracks.length} 首, ${mode.name}, '
      '当前=${_currentId ?? "-"}, 历史=${_history.length})';
}

/// 便捷构造：用一个固定种子的随机源，便于测试与「可复现的随机」。
ShuffleEngine seededShuffleEngine(int seed) =>
    ShuffleEngine(random: Random(seed));
