import 'dart:math';

/// 随机播放候选。
///
/// 只带随机策略需要的最小信息，不依赖 [Track]，
/// 这样随机引擎可以被独立穷举测试。
class ShuffleCandidate {
  const ShuffleCandidate({
    required this.id,
    this.playCount = 0,
    this.lastPlayedAt,
  });

  final String id;

  /// 历史播放次数。次数越少，被抽中的权重越高（「少听优先」）。
  final int playCount;

  /// 最近一次播放时间。越近，权重越低。
  final DateTime? lastPlayedAt;

  @override
  String toString() => 'ShuffleCandidate($id, plays=$playCount)';
}

/// 随机播放引擎。
///
/// 解决「随机播放」的三个真实痛点：
///   1. **不重复**：一轮之内同一首歌不出现两次（池子抽空才重洗）；
///   2. **不立即重复**：重洗后首曲不与刚播完的那首相撞，避免「怎么又是这首」；
///   3. **少听优先**：按播放次数反比加权，让冷门曲目有机会被听到，
///      而不是纯均匀随机导致的「热门永远被听到、冷门永远沉底」。
///
/// 全程使用注入的 [Random]，因此测试可用固定种子做到完全确定。
class ShuffleEngine {
  ShuffleEngine({Random? random, this.avoidImmediateRepeat = true})
      : _random = random ?? Random();

  final Random _random;

  /// 是否避免首曲与上一首重复
  final bool avoidImmediateRepeat;

  /// 均匀随机重排（Fisher-Yates）。
  ///
  /// 返回**新列表**，不修改入参。
  ///
  /// [avoidFirst] 指定时，若重排后首元素恰好等于它，则与随机位置交换。
  /// 注意：元素数 ≤ 1 时无法规避，直接返回。
  List<String> shuffleIds(
    List<String> ids, {
    String? avoidFirst,
  }) {
    final pool = List<String>.from(ids);
    if (pool.length <= 1) return pool;

    for (var i = pool.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }

    if (avoidImmediateRepeat && avoidFirst != null && pool.first == avoidFirst) {
      // 与 [1, length) 中的随机位置交换，保证首位不再是 avoidFirst
      final swapWith = 1 + _random.nextInt(pool.length - 1);
      final tmp = pool[0];
      pool[0] = pool[swapWith];
      pool[swapWith] = tmp;
    }
    return pool;
  }

  /// 计算单条候选的抽取权重。
  ///
  /// ```
  /// weight = 1 / (1 + playCount)          // 次数反比
  ///        × 最近播放惩罚                  // 24h 内 ×0.2，7d 内 ×0.6
  /// ```
  ///
  /// 永不返回 0，保证任何曲目都有被抽中的可能（避免「冷门永久沉底」）。
  double weightOf(ShuffleCandidate c, {DateTime? now}) {
    var weight = 1.0 / (1.0 + (c.playCount < 0 ? 0 : c.playCount));
    final lp = c.lastPlayedAt;
    if (lp != null) {
      final ref = now ?? DateTime.now();
      final hours = ref.difference(lp).inHours;
      if (hours >= 0) {
        if (hours < 24) {
          weight *= 0.2;
        } else if (hours < 24 * 7) {
          weight *= 0.6;
        }
      }
    }
    return weight;
  }

  /// 加权随机重排（不放回轮盘赌）。
  ///
  /// 逐位抽取：每轮按当前权重做一次轮盘赌，抽中即移出池子。
  /// 复杂度 O(n²)，对「曲目数」这个量级（实测单账号 444 首，上限几千）
  /// 完全够用，且比 alias method 更易读、更易测。
  List<String> weightedShuffle(
    List<ShuffleCandidate> candidates, {
    String? avoidFirst,
    DateTime? now,
  }) {
    final pool = List<ShuffleCandidate>.from(candidates);
    if (pool.isEmpty) return const [];
    if (pool.length == 1) return [pool.first.id];

    final result = <String>[];
    // 只有存在多个候选时才需要规避首曲重复
    String? pendingAvoid = avoidImmediateRepeat ? avoidFirst : null;

    while (pool.isNotEmpty) {
      var total = 0.0;
      for (final c in pool) {
        total += weightOf(c, now: now);
      }

      var chosenIndex = pool.length - 1; // 兜底：全零权重时取末位
      if (total > 0) {
        var target = _random.nextDouble() * total;
        for (var i = 0; i < pool.length; i++) {
          target -= weightOf(pool[i], now: now);
          if (target <= 0) {
            chosenIndex = i;
            break;
          }
        }
      } else {
        chosenIndex = _random.nextInt(pool.length);
      }

      // 若首位恰好是要规避的曲目，且池中还有别的选择，则换一个
      if (pendingAvoid != null &&
          pool.length > 1 &&
          pool[chosenIndex].id == pendingAvoid) {
        final alt = (chosenIndex + 1 + _random.nextInt(pool.length - 1)) %
            pool.length;
        chosenIndex = alt == chosenIndex ? (chosenIndex + 1) % pool.length : alt;
      }

      result.add(pool.removeAt(chosenIndex).id);
      pendingAvoid = null; // 只需规避第一首
    }

    return result;
  }

  /// 从候选集中抽下一首（用于「下一首」按钮）。
  ///
  /// [exclude] 中的 id 不会被选中（通常是刚播过的）。
  /// 候选被排除空时退化为「允许重复」，保证永远能返回一首而不是 `null`。
  String? pickNext(
    List<ShuffleCandidate> candidates, {
    Set<String> exclude = const {},
    DateTime? now,
  }) {
    if (candidates.isEmpty) return null;

    var pool = candidates.where((c) => !exclude.contains(c.id)).toList();
    if (pool.isEmpty) {
      pool = List<ShuffleCandidate>.from(candidates);
      // 池子被排除空：先把最久没听的放回来，保证「总有下一首」
    }
    if (pool.length == 1) return pool.first.id;

    var total = 0.0;
    for (final c in pool) {
      total += weightOf(c, now: now);
    }
    if (total <= 0) return pool[_random.nextInt(pool.length)].id;

    var target = _random.nextDouble() * total;
    for (final c in pool) {
      target -= weightOf(c, now: now);
      if (target <= 0) return c.id;
    }
    return pool.last.id;
  }

  /// 从候选集中抽下一首，并跳过本轮已播过的（一轮抽空后自动重置）。
  ///
  /// 这是播放队列真正使用的入口：[played] 是当前这一轮已经播过的 id 集合。
  /// 当候选里除 [played] 外还有别的曲目时，只在「未播过」的里抽；
  /// 若已抽空（一轮结束），则**清空本轮记录**重新开始。
  ({String? nextId, Set<String> played}) nextInRound(
    List<ShuffleCandidate> candidates, {
    required Set<String> played,
    String? currentId,
    DateTime? now,
  }) {
    if (candidates.isEmpty) {
      return (nextId: null, played: played);
    }

    final allIds = candidates.map((c) => c.id).toSet();
    // 清理已不在候选集中的陈旧记录，避免 played 无限膨胀
    var effectivePlayed = played.intersection(allIds);

    var unplayed = candidates.where((c) => !effectivePlayed.contains(c.id)).toList();

    if (unplayed.isEmpty) {
      // 一轮结束：重置本轮记录
      effectivePlayed = <String>{};
      unplayed = List<ShuffleCandidate>.from(candidates);
      // 重置后若只剩「刚播完的那首」，仍要能返回它
    }

    final exclude = <String>{
      if (currentId != null && unplayed.length > 1) currentId,
    };

    final next = pickNext(unplayed, exclude: exclude, now: now);
    if (next == null) {
      return (nextId: null, played: effectivePlayed);
    }
    return (nextId: next, played: {...effectivePlayed, next});
  }
}
