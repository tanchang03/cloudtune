import 'package:drift/drift.dart';

/// 曲目索引表。
///
/// 主键用 `provider:remoteId` 复合语义（存成单列 `id`），而不是自增 ID ——
/// 这样重复扫描天然幂等，`upsert` 不会产生重复行。
@DataClassName('TrackRow')
class Tracks extends Table {
  /// 形如 `quark:8f3a...`
  TextColumn get id => text()();

  /// 网盘标识（`DriveProvider.id`）
  TextColumn get providerId => text()();

  /// 网盘侧文件 ID
  TextColumn get remoteId => text()();

  /// 原始文件名（含扩展名）
  TextColumn get name => text()();

  /// 父目录 ID
  TextColumn get parentId => text().nullable()();

  /// 所在目录展示路径，如 `/音乐/华语/`
  TextColumn get path => text().nullable()();

  IntColumn get sizeBytes => integer().nullable()();

  TextColumn get mimeType => text().nullable()();

  DateTimeColumn get modifiedAt => dateTime().nullable()();

  /// 元数据标题（扫描时由文件名解析，将来可由标签读取覆盖）
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().nullable()();

  /// CUE 里的音轨号（1 起）。非空表示这条曲目由 CUE 参与确定。
  ///
  /// 冗余存一份而不是从 `id` 的后缀解析：`id` 的后缀规则只对整轨分段生效，
  /// 分轨增强的曲目没有后缀却也需要轨号（界面要显示「第 3 轨」、
  /// 分组头要显示「CUE 分轨」）。解析字符串当数据用，迟早会踩到。
  IntColumn get cueTrackNo => integer().nullable()();

  /// 在整轨文件内的起点（毫秒）。只有整轨切出来的一段才有值。
  ///
  /// 播放引擎靠它 `seek` 到本轨起点、并在 `起点 + durationMs` 处切歌。
  /// 不单独存终点：终点恒等于「起点 + 时长」，多存一列只会多一个
  /// 可能自相矛盾的字段。
  IntColumn get cueStartMs => integer().nullable()();

  /// **冗余存储的可播性快照**。
  ///
  /// 本可由 `sizeBytes` 与网盘能力实时算出，但冗余一份能让
  /// 「只列可播曲目」这类查询走索引而不是全表扫描。
  /// 代价：网盘能力变化（例如 50MB 上限被取消）时必须**重新扫描**来刷新。
  BoolColumn get isPlayable => boolean().withDefault(const Constant(true))();

  /// `PlayabilityState.name`。
  ///
  /// 单独存一份是为了让统计能区分「明确超限」与「体积未知（乐观可播）」——
  /// 只靠 `isPlayable` 布尔会把两者混为一谈，而它们对用户的含义完全不同。
  TextColumn get playabilityState =>
      text().withDefault(const Constant('playable'))();

  /// 超出体积上限的具体原因（面向用户，可直接展示）
  TextColumn get playabilityNote => text().nullable()();

  /// 历史播放次数 —— 随机播放「少听优先」加权的依据
  IntColumn get playCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  /// 本条记录被索引的时间
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 专辑封面表。**每张专辑一行。**
///
/// 键是**目录**而不是专辑名：一个目录 = 一张专辑这件事永远成立，而专辑名
/// 是从目录名猜的（见 `LibraryGrouping`）。与 `Tracks.path` 的对应关系是
/// `rtrim(tracks.path, '/') = album_covers.dir_path`。
///
/// 只存**引用**（封面是哪张图），不存图片字节。字节在网盘上，按需取并缓存在
/// 应用支持目录（见 `AlbumCoverCache`）—— 扫描时把每张封面都下载下来会把
/// 一次扫描变成一次批量下载，而用户可能根本不打开专辑视图。
///
/// 和 `Tracks` 一样属于**可重建的索引数据**：整张表清掉只影响观感，
/// 重新扫一次就回来了。
@DataClassName('AlbumCoverRow')
class AlbumCovers extends Table {
  TextColumn get providerId => text()();

  /// 专辑目录（归一化，不带结尾斜杠），如 `/音乐/华语/周杰伦`
  TextColumn get dirPath => text()();

  /// 封面图片的网盘文件 ID（取字节用）
  TextColumn get fileId => text()();

  /// 封面图片的原始文件名（缓存按它取扩展名，日志里也要能读出是哪张图）
  TextColumn get fileName => text()();

  IntColumn get sizeBytes => integer().nullable()();

  /// 本条记录被索引的时间
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {providerId, dirPath};
}

/// 已授权账号表。
///
/// ⚠️ **不存任何凭证**。Cookie / token 只落在系统钥匙串（见 `CredentialStore`）。
/// 这张表只放展示与状态信息。
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get providerId => text()();

  /// `AuthMode.id`
  TextColumn get authModeId => text()();

  TextColumn get userId => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();

  DateTimeColumn get authorizedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  IntColumn get storageUsedBytes => integer().nullable()();
  IntColumn get storageTotalBytes => integer().nullable()();

  /// 会员标识，如 `SUPER_VIP`
  TextColumn get memberLabel => text().nullable()();

  /// 最近一次扫描完成时间
  DateTimeColumn get lastScannedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {providerId};
}

/// 收藏（「喜欢」）表。
@DataClassName('FavoriteRow')
class Favorites extends Table {
  TextColumn get trackId => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// 用户手动排序位（越小越前）
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// 断点续扫状态表。**每个网盘一行。**
///
/// 把 `ScanCursor` 整个序列化进来：BFS 队列、当前目录、分页游标、
/// 计数全部持久化，因此 App 被杀后能原地续扫。
@DataClassName('ScanStateRow')
class ScanStates extends Table {
  TextColumn get providerId => text()();

  TextColumn get rootId => text()();
  TextColumn get rootPath => text()();

  /// BFS 队列（JSON 数组，元素形如 `{"id":..,"path":..,"depth":..}`）
  TextColumn get pendingDirsJson => text()();

  /// 当前正在扫的目录（JSON 对象，可为空）
  TextColumn get currentDirJson => text().nullable()();

  /// 当前目录的下一页游标
  TextColumn get currentPageToken => text().nullable()();

  /// `ScanStage.name`
  TextColumn get stageId => text()();

  IntColumn get scannedDirs => integer().withDefault(const Constant(0))();
  IntColumn get scannedFiles => integer().withDefault(const Constant(0))();
  IntColumn get foundTracks => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  IntColumn get failedDirs => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {providerId};
}

/// 播放历史。用于「最近播放」，与 `Tracks.playCount` 互补：
/// 前者给时间线，后者给随机权重。
@DataClassName('PlayHistoryRow')
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get trackId => text()();

  DateTimeColumn get playedAt => dateTime()();

  /// 实际播放时长（秒）。用于将来做「跳过率」统计。
  IntColumn get playedSeconds => integer().withDefault(const Constant(0))();
}
