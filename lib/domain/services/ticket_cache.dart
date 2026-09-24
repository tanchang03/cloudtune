import '../entities/stream_ticket.dart';

/// 播放直链缓存。
///
/// 网盘直链是带签名的临时 URL，取链本身有配额成本（夸克实测约 1 QPS 安全线），
/// 所以「同一首反复播」不该反复取链。但缓存又不能一直用 —— 直链过期后
/// 播放器会拿到 `403` / `412`，用户看到的是「播到一半断了」。
///
/// 因此这里做两件事：
///   1. 命中未过期的票据直接复用，省配额；
///   2. 对**没有 `expiresAt` 的票据**套一个保守的默认 TTL ——
///      否则会被永久缓存，等到播放器报错才发现，那时体验已经很差了。
///
/// 时钟可注入，因此过期行为在单元测试里完全确定，不需要 `sleep`。
class TicketCache {
  TicketCache({
    this.defaultTtl = const Duration(minutes: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 网盘没给出过期时间时使用的保守 TTL。
  ///
  /// 取 20 分钟：夸克实测 `auth_key` 的 TTL 是 6 小时，20 分钟远小于它，
  /// 足够安全；又远大于一首歌的时长，不会导致频繁重取。
  final Duration defaultTtl;

  final DateTime Function() _clock;

  /// trackId → 缓存条目
  final Map<String, _Entry> _entries = {};

  int get length => _entries.length;

  /// 取一条**仍然新鲜**的票据。过期或不存在返回 `null`。
  ///
  /// 过期条目会被顺手清掉，避免缓存里堆积死数据。
  StreamTicket? get(String trackId) {
    final e = _entries[trackId];
    if (e == null) return null;
    if (_isStale(e, _clock())) {
      _entries.remove(trackId);
      return null;
    }
    return e.ticket;
  }

  /// 条目是否已不可用。
  ///
  /// 网盘给了 `expiresAt` 时交给 [StreamTicket.isExpiredAt] 判定 ——
  /// 它带 30 秒安全余量，避免把「还剩几秒」的票据当成可用、结果刚起播就断流。
  /// 没给过期时间时用「写入时刻 + [defaultTtl]」兜底，否则会被永久缓存。
  static bool _isStale(_Entry e, DateTime now) {
    final expiry = e.ticket.expiresAt;
    if (expiry != null) return e.ticket.isExpiredAt(now);
    return !now.isBefore(e.fallbackExpiry!);
  }

  /// 写入票据。`trackId` 为空或 URL 为空时忽略（防御脏数据）。
  void put(String trackId, StreamTicket ticket) {
    if (trackId.isEmpty || ticket.url.toString().isEmpty) return;
    _entries[trackId] = _Entry(
      ticket: ticket,
      // 只在网盘没给过期时间时才需要兜底时刻
      fallbackExpiry:
          ticket.expiresAt == null ? _clock().add(defaultTtl) : null,
    );
  }

  /// 主动作废一条票据。播放中出现 `403` 时调用，逼下一次取链走网络。
  void invalidate(String trackId) => _entries.remove(trackId);

  void clear() => _entries.clear();

  /// 剔除全部已过期条目，返回剔除数量。
  int evictExpired() {
    final now = _clock();
    final dead = _entries.entries
        .where((e) => _isStale(e.value, now))
        .map((e) => e.key)
        .toList();
    for (final k in dead) {
      _entries.remove(k);
    }
    return dead.length;
  }

  /// 缓存里是否有仍可用的票据。
  bool containsFresh(String trackId) => get(trackId) != null;

  @override
  String toString() => 'TicketCache(${_entries.length} 条, ttl=$defaultTtl)';
}

class _Entry {
  const _Entry({required this.ticket, this.fallbackExpiry});

  final StreamTicket ticket;

  /// 仅在网盘未给出 `expiresAt` 时有值：写入时刻 + [TicketCache.defaultTtl]
  final DateTime? fallbackExpiry;
}
