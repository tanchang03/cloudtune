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

  /// **首次被发现的时间**。与 `indexedAt` 不同：后者每次重扫都会刷新，
  /// 前者只在**第一次入库**时写，之后永不更新。
  ///
  /// 它的唯一用途是支撑「新歌」功能：一首歌「新不新」取决于它第一次进库
  /// 的时间，而不是最近一次被扫到的时间 —— 否则每次重扫都会把所有歌
  /// 重新标成「新」，这个功能就毫无意义了。
  ///
  /// 写入规则在 `_upsertTrackSql`：INSERT 时写 `excluded.indexed_at`，
  /// ON CONFLICT DO UPDATE 时**不**更新这一列。
  /// 老库升级时回填为 `indexed_at`（见 `app_database.dart` 的 v4→v5）。
  DateTimeColumn get firstSeenAt => dateTime().nullable()();

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

/// 歌词表。**每首曲目一行。**
///
/// 键是**曲目**而不是目录：歌词天然属于某一首歌，而 CUE 分段的存在让
/// 「一个目录」和「一首歌」之间不再是多对一 —— 一张整轨切出的 N 段各自
/// 需要自己的歌词行（它们的 `Track.id` 带 `#cN` 后缀，互不相同）。
///
/// 和 `AlbumCovers` 一样，**大部分行一开始只有引用、没有正文**：
/// 扫描时只在网盘上发现 `.lrc` 并把它对上曲目（`file_id` / `file_name`），
/// 正文（`content`）等这首歌第一次被播放时再读。这样扫描不会为了歌词
/// 多发请求 —— 夸克的接口有 QPS 限制，而歌词可能永远没人看。
///
/// 于是 `content IS NULL` 有一个明确含义：**已定位，尚未读取**。
/// 界面上它是「正在获取歌词」，不是「没有歌词」。
///
/// ⚠️ 与 `AlbumCovers` 的一处关键差别：联网歌词（`source_id = 'lrclib'`）
/// **没有可回读的源**（文件不在用户网盘上，重取要打第三方接口且有速率限制），
/// 所以那种行的正文必须存下来。这也是本项目唯一一处会把第三方文本写进
/// 本地库的地方，默认关闭、需要用户明确开启 —— 见 README 的合规说明。
@DataClassName('LyricsRow')
class Lyrics extends Table {
  /// 曲目主键（`Track.id`），形如 `quark:8f3a...` 或 `quark:8f3a...#c3`
  TextColumn get trackId => text()();

  /// 网盘标识（`DriveProvider.id`）。用于 `clearProvider` 与全量清理。
  TextColumn get providerId => text()();

  /// `LyricsSource.id`：`local` / `lrclib`
  ///
  /// 存 `id` 而不是枚举名：枚举常量改名会静默把老数据变成认不出的值。
  TextColumn get sourceId => text()();

  /// 第三方明确告知「这是纯音乐」。是**确定的答案**而不是「查不到」，
  /// 所以必须落库 —— 否则每次播放都要再去问一遍。
  BoolColumn get instrumental => boolean().withDefault(const Constant(false))();

  /// 歌词正文。`null` = 已定位但还没读（见类注释）。
  TextColumn get content => text().nullable()();

  /// 本地 `.lrc` 在网盘上的文件 ID（取正文用）。联网来源恒为 `null`。
  TextColumn get fileId => text().nullable()();

  /// 本地 `.lrc` 的原始文件名。展示「来自 xxx.lrc」与排查用。
  TextColumn get fileName => text().nullable()();

  IntColumn get sizeBytes => integer().nullable()();

  /// 本条记录被索引的时间
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// 应用设置表（键值对）。**每个键一行。**
///
/// 为什么用库表而不是内存态或配置文件：
///   - 内存态活不过重启，而「联网歌词」这类开关一旦被用户打开，
///     期望是**一直有效**的，不该每次启动都回到默认值；
///   - 单独开一个配置文件就得再引入一个目录注入点（见 `main()` 里
///     数据库与封面缓存目录的注入），为了一个布尔值不值当。
///
/// ⚠️ 它**不属于可重建的索引数据**，所以 `clearProvider` 刻意不动它 ——
/// 清空曲库不该顺手把用户的偏好也清掉。
///
/// 列名刻意用 `setting_key` / `setting_value` 而不是 `key` / `value`：
/// 后者在生成的 Drift 代码里会和 `Table` / `Column` 上的同名成员撞车，
/// 报错信息很难指向真正的原因。
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {settingKey};
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
