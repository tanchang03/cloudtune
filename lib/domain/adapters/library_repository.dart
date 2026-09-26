import '../entities/album_cover.dart';
import '../entities/capabilities.dart';
import '../entities/cloud_account.dart';
import '../entities/drive_provider.dart';
import '../entities/lyrics.dart';
import '../entities/playability.dart';
import '../entities/scan_cursor.dart';
import '../entities/track.dart';
import '../services/playability_resolver.dart';
import '../services/shuffle_engine.dart';

/// 曲目列表排序方式。
enum TrackSort {
  /// 文件名升序（默认）
  nameAsc,

  /// 艺术家 → 专辑 → 文件名
  artistAsc,

  /// 专辑 → 艺术家
  albumAsc,

  /// 体积从大到小（用来快速找出「哪些是不可播的大文件」）
  sizeDesc,

  /// 体积从小到大
  sizeAsc,

  /// 最近入库
  recentlyIndexed,

  /// 网盘侧最近修改
  recentlyModified,

  /// 播放次数最多
  mostPlayed,
}

/// 曲目查询条件。
class TrackQuery {
  const TrackQuery({
    this.provider,
    this.keyword,
    this.playableOnly,
    this.favoritesOnly = false,
    this.artist,
    this.album,
    this.dirPath,
    this.sort = TrackSort.nameAsc,
    this.limit,
    this.offset = 0,
  });

  final DriveProvider? provider;

  /// 模糊匹配 文件名 / 标题 / 艺术家 / 专辑 / 路径
  final String? keyword;

  /// `true` 只要可播；`false` 只要不可播；`null` 不限
  ///
  /// `false` 这一档**界面已经不提供了**（见 `LibraryScope` 的说明），
  /// 但仓储层保留它：诊断「哪些文件取不到地址」时还要按它筛选，
  /// 而且 `countTracks(playableOnly: false)` 是体检口径的一部分。
  final bool? playableOnly;

  final bool favoritesOnly;

  final String? artist;
  final String? album;

  /// 只要某个**目录**下的曲目，即「这张专辑」。传归一化后的目录路径
  /// （不带结尾斜杠，见 `normalizeDirPath`）。
  ///
  /// 与 [album] 的区别：专辑名是从目录名猜出来的，同名的两张专辑
  /// （`... [16B-44.1kHz]` 与 `... [24B-48kHz]`）会被合并；目录路径不会。
  /// 专辑详情页用它，这样「点开的到底是哪一张」不依赖命名推断。
  final String? dirPath;

  final TrackSort sort;

  final int? limit;
  final int offset;

  TrackQuery copyWith({
    DriveProvider? provider,
    String? keyword,
    bool? playableOnly,
    bool? favoritesOnly,
    String? artist,
    String? album,
    String? dirPath,
    TrackSort? sort,
    int? limit,
    int? offset,
  }) {
    return TrackQuery(
      provider: provider ?? this.provider,
      keyword: keyword ?? this.keyword,
      playableOnly: playableOnly ?? this.playableOnly,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      dirPath: dirPath ?? this.dirPath,
      sort: sort ?? this.sort,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  @override
  String toString() {
    // 注意：Dart 的词法器无法在同一引号类型的字符串插值里嵌套同类型字符串
    // （`'...${a ? '' : ''}...'` 会被提前截断），所以这里用 List.join 拼装。
    final parts = <String>[
      provider?.id ?? '全部',
      if (keyword != null) 'kw="$keyword"',
      if (playableOnly != null) 'playable=$playableOnly',
      if (favoritesOnly) '仅收藏',
      if (dirPath != null) 'dir=$dirPath',
      sort.name,
    ];
    return 'TrackQuery(${parts.join(', ')})';
  }
}

/// 曲库统计概览。用于首页与「可播体检」展示。
///
/// 口径说明（两个数容易混淆，必须分清）：
///   - [playableCount] 是**严格口径**：只有 `PlayabilityState.playable`，
///     也就是体积与格式都确认在网盘能力范围内；
///   - [attemptableCount] 是**乐观口径**：额外包含体积未知（`unknownSize`）
///     的曲目 —— 网盘没返回体积时宁可试一次，也不该直接判死。
///
/// 之所以要分开：如果 `playableCount` 用乐观口径、而 [playableRatio]
/// 又加一遍 `unknownSizeCount`，就会把同一批曲目算两次，比例虚高。
class LibraryStats {
  const LibraryStats({
    required this.trackCount,
    required this.playableCount,
    required this.attemptableCount,
    required this.overLimitCount,
    required this.unknownSizeCount,
    required this.favoriteCount,
    required this.totalBytes,
    required this.playableBytes,
    required this.artistCount,
    required this.albumCount,
    this.lastScannedAt,
  });

  final int trackCount;

  /// 确认可播的曲目数（严格口径）
  final int playableCount;

  /// 值得尝试播放的曲目数 = [playableCount] + [unknownSizeCount]
  final int attemptableCount;

  /// 因**取不到播放地址**而确定不可播的曲目数
  final int overLimitCount;

  /// 体积未知、需要运行时验证的曲目数
  final int unknownSizeCount;

  final int favoriteCount;

  final int totalBytes;

  /// 可尝试播放的曲目总体积（与 [attemptableCount] 同口径）
  final int playableBytes;

  final int artistCount;
  final int albumCount;
  final DateTime? lastScannedAt;

  bool get isEmpty => trackCount == 0;

  /// 可播比例（含体积未知的乐观估计）。
  ///
  /// 分子只加一次 [unknownSizeCount]：[playableCount] 是严格口径、不含
  /// 未知体积的曲目，因此这里不会重复计数。
  double get playableRatio {
    if (trackCount <= 0) return 0;
    return (playableCount + unknownSizeCount) / trackCount;
  }

  /// 值得尝试播放的比例
  double get attemptableRatio {
    if (trackCount <= 0) return 0;
    return attemptableCount / trackCount;
  }

  double get playableBytesRatio {
    if (totalBytes <= 0) return 0;
    return playableBytes / totalBytes;
  }

  static const LibraryStats empty = LibraryStats(
    trackCount: 0,
    playableCount: 0,
    attemptableCount: 0,
    overLimitCount: 0,
    unknownSizeCount: 0,
    favoriteCount: 0,
    totalBytes: 0,
    playableBytes: 0,
    artistCount: 0,
    albumCount: 0,
  );

  @override
  String toString() => 'LibraryStats($trackCount 首, 可播 $playableCount, '
      '可尝试 $attemptableCount, 收藏 $favoriteCount, '
      '$artistCount 位艺术家)';
}

/// 本地曲库仓储契约。
///
/// 上层（扫描服务、播放引擎、UI）只依赖这个接口，
/// 具体是 Drift / SQLite / 内存实现都无所谓 —— 测试可以注入内存假实现。
abstract class LibraryRepository {
  // -------------------------------------------------------------------
  // 曲目
  // -------------------------------------------------------------------

  /// 批量写入（upsert）曲目。
  ///
  /// **必须保留 `playCount` 与 `lastPlayedAt`**：重复扫描不能把用户的
  /// 播放统计清零。这是最容易写错的一点。
  ///
  /// [capabilities] 用于计算并落库可播性快照。
  Future<void> upsertTracks(
    Iterable<Track> tracks, {
    required Capabilities capabilities,
    DateTime? now,
  });

  Future<List<Track>> queryTracks([TrackQuery query = const TrackQuery()]);

  Future<Track?> trackById(String id);

  Future<int> countTracks({DriveProvider? provider, bool? playableOnly});

  /// 新歌数量：第一次入库时间晚于 [seenAt]（用户上次「看完新歌」）的曲目数。
  ///
  /// [seenAt] 为 `null` 时只数「有 first_seen_at」的曲 —— 但调用方（provider）
  /// 负责在水位数还没设过时不去用它，避免把整库刷成新歌。
  /// [provider] 为 `null` 表示跨网盘统计。
  Future<int> newTracksCount({DriveProvider? provider, DateTime? seenAt});

  /// 新歌列表，按 first_seen_at 倒序（最新进库的最靠前）。
  ///
  /// 与 `newTracksCount` 用同一套判定条件。详情见 `newTracksCount`。
  Future<List<Track>> newTracks({
    DriveProvider? provider,
    DateTime? seenAt,
    int? limit,
  });

  Future<void> deleteTracks(Set<String> ids);

  /// 删除某网盘下**不在 [keepIds] 中**的曲目。
  ///
  /// 全量扫描后调用，用来清理网盘侧已删除的文件。
  Future<int> deleteTracksNotIn(DriveProvider provider, Set<String> keepIds);

  /// 清空某网盘的全部曲目（连同收藏、播放历史与专辑封面）
  Future<void> clearProvider(DriveProvider provider);

  // -------------------------------------------------------------------
  // 专辑封面
  // -------------------------------------------------------------------

  /// 批量写入（upsert）专辑封面。
  ///
  /// 主键是 `(providerId, dirPath)`，所以重复扫描天然幂等：同一个目录换了
  /// 一张封面图时，旧的那行会被新的覆盖，不会两张图并存。
  ///
  /// ⚠️ 一个目录**只能有一张封面**。调用方（扫描器）负责先用
  /// `AlbumCoverIndexer` 挑出一张 —— 这里不做「挑」这件事，
  /// 仓储层不该知道 `back.jpg` 比 `cover.jpg` 差。
  Future<void> upsertAlbumCovers(
    Iterable<AlbumCover> covers, {
    DateTime? now,
  });

  /// 某网盘下全部专辑封面，按**目录路径**索引。
  ///
  /// [provider] 必传：`dirPath` 只在同一个网盘内唯一，不限定网盘时
  /// 两家网盘的 `/音乐/华语` 会互相覆盖。
  Future<Map<String, AlbumCover>> albumCovers(DriveProvider provider);

  /// 删除某网盘下**不在 [keepDirPaths] 中**的封面。
  ///
  /// 与 [deleteTracksNotIn] 同一个用途：全量扫描后清掉网盘侧已经删掉的
  /// 封面图（否则封面行会一直指向一个取不到字节的 ID）。
  Future<int> deleteAlbumCoversNotIn(
    DriveProvider provider,
    Set<String> keepDirPaths,
  );

  /// 运行时发现某首曲目不可播时落库，避免下次又白试一遍。
  ///
  /// 典型场景：网盘返回 `23018`（超出单文件下载上限）。这说明要么索引里的
  /// `sizeBytes` 不准，要么网盘侧的限制变了 —— 不管哪种，都该把它标成
  /// 不可播，而不是每次随机播放到它都去取一次链、失败、再跳过。
  ///
  /// [state] 为 `unknownSize` 时 `isPlayable` 仍置 1（乐观口径），
  /// 其余状态一律置 0。
  Future<void> markUnplayable(
    String trackId, {
    required PlayabilityState state,
    String? reason,
    DateTime? now,
  });

  // -------------------------------------------------------------------
  // 歌词
  // -------------------------------------------------------------------

  /// 批量写入（upsert）歌词。主键是 `trackId`。
  ///
  /// 写入分两种时机，**都走这一个方法**：
  ///   - 扫描时写「引用」（`content` 为 `null`，只有 `fileId` / `fileName`）；
  ///   - 播放时读到正文后回写（`content` 非空）。
  ///
  /// ⚠️ 因此 upsert 有一条**不能省的规则**：当新行的 `content` 为 `null`、
  /// 且 `fileId` 与库里那行一致时，必须**保留库里已有的 `content`**。
  /// 否则用户每重扫一次盘，之前读下来的歌词就全没了 —— 而重扫恰恰是
  /// 最常见的事。反过来，`fileId` 变了（网盘上换了歌词文件）就该丢掉旧的
  /// 正文，因为那份正文对应的已经不是一个文件了。
  Future<void> upsertLyrics(Iterable<Lyrics> lyrics, {DateTime? now});

  /// 取某首曲目的歌词。没有返回 `null`。
  ///
  /// 返回的 `content` 可能是 `null`（已定位、尚未读取），调用方需要区分
  /// 「没有歌词」和「有但还没读」两种情形。
  Future<Lyrics?> lyricsFor(String trackId);

  /// 按曲目删除歌词行。
  ///
  /// 用于「索引里记着某首歌有 `.lrc`，但真去读的时候发现文件已经没了」——
  /// 那时该把这一行清掉，否则每次播放都会白试一次。
  ///
  /// ⚠️ 与 [deleteLyricsNotIn] 是**两个不同的动作**，别混用：后者的语义是
  /// 「清理所有不在白名单里的」，拿它来删一行等于把整个曲库的歌词清空。
  Future<void> deleteLyrics(Set<String> trackIds);

  /// 统计歌词行数。[loadedOnly] 为 `true` 时只数**正文已经读下来**的那些。
  ///
  /// 两个口径的差别正是「已发现多少」与「已拿到多少」，设置页要分开显示。
  Future<int> lyricsCount({DriveProvider? provider, bool loadedOnly = false});

  /// 删除某网盘下**不在 [keepTrackIds] 中**的歌词。
  ///
  /// 与 [deleteAlbumCoversNotIn] 同一个用途：全量扫描后清掉网盘侧已经删掉的
  /// `.lrc`（否则那一行会一直指向一个读不到的文件 ID，界面上就是「永远在
  /// 获取歌词」）。
  ///
  /// ⚠️ 注意它和「曲目被删」不是一回事：后者由 `tracks` 上的删除触发器
  /// 自动级联，这里管的是**曲目还在、歌词文件没了**。
  Future<int> deleteLyricsNotIn(DriveProvider provider, Set<String> keepTrackIds);

  // -------------------------------------------------------------------
  // 收藏
  // -------------------------------------------------------------------

  Future<bool> isFavorite(String trackId);

  Future<void> setFavorite(String trackId, {required bool value, DateTime? now});

  Future<Set<String>> favoriteIds();

  Future<int> favoriteCount();

  // -------------------------------------------------------------------
  // 续扫状态
  // -------------------------------------------------------------------

  Future<ScanCursor?> loadScanCursor(DriveProvider provider);

  Future<void> saveScanCursor(ScanCursor cursor);

  Future<void> clearScanCursor(DriveProvider provider);

  // -------------------------------------------------------------------
  // 账号（只存展示信息，凭证在钥匙串）
  // -------------------------------------------------------------------

  Future<void> saveAccount(CloudAccount account, {DateTime? scannedAt});

  Future<List<CloudAccount>> accounts();

  Future<void> removeAccount(DriveProvider provider);

  // -------------------------------------------------------------------
  // 播放统计
  // -------------------------------------------------------------------

  /// 记录一次播放：`playCount +1`、更新 `lastPlayedAt`、追加历史。
  Future<void> recordPlay(
    String trackId, {
    Duration played = Duration.zero,
    DateTime? now,
  });

  Future<List<Track>> recentlyPlayed({int limit = 50});

  /// 供随机播放引擎使用的候选集（含播放次数与最近播放时间）。
  Future<Map<String, ShuffleCandidate>> shuffleCandidates({
    DriveProvider? provider,
    bool playableOnly = true,
  });

  // -------------------------------------------------------------------
  // 统计
  // -------------------------------------------------------------------

  Future<LibraryStats> stats({DriveProvider? provider});

  /// 与扫描阶段同口径的可播性汇总。
  Future<PlayabilitySummary> playabilitySummary({DriveProvider? provider});
}
