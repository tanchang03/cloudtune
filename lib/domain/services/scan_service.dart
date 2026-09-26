import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../../core/utils/audio_formats.dart';
import '../../core/utils/image_formats.dart';
import '../adapters/cloud_drive_adapter.dart';
import '../adapters/library_repository.dart';
import '../../data/db/settings_store.dart';
import '../entities/album_cover.dart';
import '../entities/drive_entry.dart';
import '../entities/drive_provider.dart';
import '../entities/scan_cursor.dart';
import '../entities/scan_policy.dart';
import '../entities/track.dart';
import '../services/album_cover_indexer.dart';
import '../services/cue_indexer.dart';
import '../services/lyrics_indexer.dart';
import '../services/playability_resolver.dart';

/// 扫描取消信号。
///
/// 不用 `Future.cancel`：扫描是「多页循环 + 每页落库」的长流程，
/// 需要一个能在页边界被检查的协作式开关。
class ScanCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 扫描进度快照（推给 UI）。
class ScanProgress {
  const ScanProgress({
    required this.cursor,
    required this.isRunning,
    this.currentDirPath,
    this.message,
  });

  final ScanCursor cursor;
  final bool isRunning;

  /// 正在扫的目录路径
  final String? currentDirPath;

  /// 状态文案，如「已完成」「已暂停」
  final String? message;

  int get scannedDirs => cursor.scannedDirs;
  int get scannedFiles => cursor.scannedFiles;
  int get foundTracks => cursor.foundTracks;
  int get totalBytes => cursor.totalBytes;
  int get pendingDirs => cursor.pendingDirs.length;
  int get failedDirs => cursor.failedDirs;

  @override
  String toString() => 'ScanProgress(目录 ${cursor.scannedDirs}, '
      '文件 ${cursor.scannedFiles}, 曲目 ${cursor.foundTracks}, '
      '待扫 ${cursor.pendingDirs.length})';
}

/// 一次扫描的结果。
class ScanOutcome {
  const ScanOutcome({
    required this.cursor,
    required this.tracksIndexed,
    required this.removedTracks,
    required this.playability,
    required this.wasCancelled,
    this.error,
  });

  final ScanCursor cursor;

  /// 本次扫描写入索引的曲目数（upsert 口径，含已存在的）
  final int tracksIndexed;

  /// 清理掉的陈旧曲目数（网盘侧已删除）
  final int removedTracks;

  final PlayabilitySummary playability;

  final bool wasCancelled;

  /// 非空表示扫描因错误中断（可能是部分失败）
  final String? error;

  bool get isComplete => cursor.isComplete && !wasCancelled && error == null;

  @override
  String toString() => 'ScanOutcome(入库 $tracksIndexed, 清理 $removedTracks, '
      '${wasCancelled ? "已取消" : (error == null ? "完成" : "出错：$error")})';
}

/// 扫描调度服务。
///
/// 负责「遍历搜索所有网盘音乐文件」这件事的全部编排：
///   - BFS 逐目录、逐页拉取（分页信号见 `QuarkAdapter.listDirectory` 的注释）
///   - 音频识别与可播性预判
///   - **每页落库**，任何时刻被杀都能原地续扫
///   - 单目录失败不终止整次扫描（记录并继续）
///   - 授权失效必须立刻上抛（继续扫只会拿到一堆 31001）
///   - 全量扫完后清理网盘侧已删除的陈旧曲目
///
/// 只依赖 [CloudDriveAdapter] 与 [LibraryRepository] 两个抽象，
/// 因此可以在单元测试里用假适配器 + 内存库完整覆盖。
class ScanService {
  ScanService({
    required DriveAdapterRegistry registry,
    required LibraryRepository library,
    required SettingsStore settings,
    this.policy = const ScanPolicy(),
    this.cueIndexer = const CueIndexer(),
    this.coverIndexer = const AlbumCoverIndexer(),
    this.lyricsIndexer = const LyricsIndexer(),
    DateTime Function()? clock,
  })  : _registry = registry,
        _library = library,
        _settings = settings,
        _clock = clock ?? DateTime.now;

  final DriveAdapterRegistry _registry;
  final LibraryRepository _library;
  final SettingsStore _settings;
  final ScanPolicy policy;

  /// CUE 分轨处理器。默认实例无状态，测试可换成假实现。
  final CueIndexer cueIndexer;

  /// 专辑封面挑选器。同上：无状态，只做「这几张图里挑一张」。
  final AlbumCoverIndexer coverIndexer;

  /// 本地歌词匹配器。同上：无状态，只做「这些 .lrc 对上哪些曲目」。
  final LyricsIndexer lyricsIndexer;

  final DateTime Function() _clock;

  ScanCancellation? _active;
  ScanProgress? _lastProgress;

  /// 最近一次进度（UI 冷启动时可直接展示）
  ScanProgress? get lastProgress => _lastProgress;

  bool get isRunning => _active != null;

  /// 请求停止当前扫描（协作式，在页边界生效）
  void requestCancel() => _active?.cancel();

  /// 执行一次扫描。
  ///
  /// [resume] 为真时从上次的续扫游标继续；上次已扫完则自动重新开始。
  /// [pruneStale] 为真时在**完整扫完**后清理网盘侧已删除的曲目
  /// （中途取消/失败不清理，否则会误删还没扫到的部分）。
  Future<ScanOutcome> scan(
    DriveProvider provider, {
    bool resume = true,
    bool pruneStale = true,
    ScanCancellation? cancel,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    if (_active != null) {
      throw StateError('已有扫描在进行中');
    }
    final token = cancel ?? ScanCancellation();
    _active = token;

    try {
      return await _run(provider,
          resume: resume, pruneStale: pruneStale, cancel: token, onProgress: onProgress);
    } finally {
      _active = null;
    }
  }

  Future<ScanOutcome> _run(
    DriveProvider provider, {
    required bool resume,
    required bool pruneStale,
    required ScanCancellation cancel,
    void Function(ScanProgress)? onProgress,
  }) async {
    final adapter = _registry.requireAdapter(provider);
    final capabilities = adapter.capabilities;

    // 扫描在日志里长期「隐身」：ScanService 以前完全不写 diag，
    // 排障时只能在日志里看到成片的裸 HTTP 行。这里补上起点与终点，
    // 让「一次扫描从哪开始、扫到哪了、结果如何」变成事后能翻查的事实。
    if (!capabilities.canListDirectory) {
      throw DriveException(
        type: DriveErrorType.unsupported,
        message: '${provider.displayName} 不支持列目录，无法遍历音乐库',
      );
    }

    // 只有在「有游标 且 尚未扫完」时才续扫；其余情况（从未扫过、上次已扫完）
    // 一律从头开始，避免拿着 completed 的游标空转一轮。
    final restored = resume ? await _library.loadScanCursor(provider) : null;
    final resumable =
        (restored != null && !restored.isComplete) ? restored : null;
    diag.section('扫描 ${resumable == null ? "开始" : "续扫"}（${provider.displayName}）');
    diag.info(
      '扫描',
      '根目录=${adapter.rootId} 续扫=${resumable != null} 策略: ${policy.toString()}',
    );
    var cursor = resumable ??
        ScanCursor.fresh(
          provider: provider,
          rootId: adapter.rootId,
          now: _clock(),
        );

    /// 本次是否从零开始。
    ///
    /// **陈旧清理只在「从零扫完」时才做**：续扫时本次运行只看到了部分目录，
    /// 拿本次看到的 id 当白名单会把上次扫到、这次还没扫到的曲目误删。
    final startedFresh = resumable == null;

    final buffer = <Track>[];

    /// 本次运行**实际扫到**的曲目 id —— 陈旧清理的白名单来源。
    final seenIds = <String>{};

    /// 本次运行**真正写出封面**的专辑目录 —— 封面陈旧清理的白名单来源。
    ///
    /// 注意它只收「找到了封面」的目录，而不是「扫过的」目录：曲库里有封面的
    /// 专辑往往只是一部分，拿「扫过的目录」当白名单会让清理失去意义。
    final seenCoverDirs = <String>{};

    /// 本次运行**真正写出歌词引用**的曲目 id —— 歌词陈旧清理的白名单来源。
    ///
    /// 与 [seenCoverDirs] 同一个口径：只收「这次确实给这首曲目记下了歌词」
    /// 的，而不是「扫过的曲目」。网盘上大部分曲目没有 `.lrc`，拿后者当白名单
    /// 等于永远不清理。
    final seenLyrics = <String>{};

    var indexed = 0;
    var removed = 0;
    var cancelled = false;
    String? error;

    /// 被 CUE 切出的虚拟曲目数 / 因 CUE 让位的整轨数（只用于日志）。
    var cueSegments = 0;
    var cueImagesHidden = 0;

    /// 落库的专辑封面数（只用于日志）
    var coversIndexed = 0;

    /// 落库的本地歌词引用数（只用于日志）。注意它数的是**引用**，
    /// 不是「读到了多少份歌词」—— 正文要等播放时才读。
    var lyricsIndexed = 0;

    // 节流计数：游标批量落盘 / 进度批量推送，避免 700+ 次 SQLite 写与 UI 重建。
    var pagesSinceCursorFlush = 0;
    var pagesSinceEmit = 0;

    /// 上一次列目录请求的**发起时刻**，供 [throttleList] 计算剩余等待。
    DateTime? lastListAt;

    /// 节流：保证相邻两次列目录请求之间至少间隔 [ScanPolicy.minRequestInterval]。
    ///
    /// ⚠️ 必须在**每次请求之前**调用，并按「上次发起时刻」算剩余等待时间。
    /// 早先的实现是在页尾固定 sleep 一次，但内层循环在 `pageToken == null`
    /// 时先 `break` 了 —— 于是「换目录」的那一次请求完全没被节流。对
    /// 「每个目录都只有一页」的曲库（很常见）等于**全程不节流**：
    /// 5000 个目录会以网络往返速度一路打过去，3 QPS 安全线形同虚设。
    ///
    /// 按请求**起点**而不是终点计时，才是「最小间隔」的正确语义 ——
    /// 请求本身就耗时 400ms 时不该再额外等 350ms，否则实际速率会被压到
    /// 远低于配置值（旧的页尾 sleep 就有这个毛病）。
    Future<void> throttleList() async {
      final interval = policy.minRequestInterval;
      if (interval <= Duration.zero) return;
      final last = lastListAt;
      if (last != null) {
        final wait = interval - _clock().difference(last);
        if (wait > Duration.zero) await Future.delayed(wait);
      }
      lastListAt = _clock();
    }

    void emit({bool running = true, String? message}) {
      final progress = ScanProgress(
        cursor: cursor,
        isRunning: running,
        currentDirPath: cursor.currentDir?.path,
        message: message,
      );
      _lastProgress = progress;
      onProgress?.call(progress);
    }

    emit();

    try {
      while (cursor.hasPendingWork) {
        if (cancel.isCancelled) {
          cancelled = true;
          break;
        }

        // 需要新目录时从队首取；续扫时 currentDir 已存在，直接接着扫
        if (cursor.currentDir == null) {
          cursor = cursor.dequeue(_clock());
          if (cursor.currentDir == null) break; // 队列空，收尾
        }
        final dir = cursor.currentDir!;

        /// 本目录扫到的音频曲目 —— 供 CUE 按 `FILE` 名字匹配。
        ///
        /// 只在目录内有效，且必须**收齐整个目录**才能交给 CUE 处理：
        /// 翻页顺序不保证 CUE 引用的音频先出现。
        final dirTracks = <Track>[];

        /// 本目录的 `.cue` 条目。**不是曲目**，单独收着。
        final dirCues = <DriveEntry>[];

        /// 本目录的图片条目 —— 专辑封面的第一候选来源。
        ///
        /// 和 CUE 一样：**不是曲目**，不能入库成曲目（否则封面图会变成
        /// 一首「非音频」的歌），但也不能直接丢掉。
        final dirImages = <DriveEntry>[];

        /// 本目录下**看起来是封面/图片目录**的子目录，封面认不出来时再去翻。
        ///
        /// 只收「策略允许进入」的目录：`.Trash` 这类被跳过的目录连列都不列。
        final artworkDirs = <DriveEntry>[];

        /// 本目录的 `.lrc` 歌词条目 —— 同样**不是曲目**。
        ///
        /// 和 CUE / 图片一样单独收着：它的价值是对上同目录的曲目，
        /// 直接丢掉就等于没有歌词功能。
        final dirLrc = <DriveEntry>[];

        /// 本目录需要从库里删掉的整轨 id（已被切出的段取代）。
        final replacedIds = <String>{};

        /// CUE 处理结果（本目录）。歌词匹配要用**展开后**的曲目列表，
        /// 所以它必须留到这里之后（见 dirFinalTracks）。
        CueIndexResult? cueResult;

        /// 本目录**最终**的曲目列表：原始曲目 − 让位的整轨 + CUE 切出的段
        /// + 被 CUE 补过元数据的版本。
        ///
        /// 歌词匹配必须用这个列表而不是 `dirTracks`：一张整轨切成 15 段之后，
        /// 歌词文件往往是**按段落**命名的（`05 - 歌名.lrc`），拿展开前的
        /// 「一首 72 分钟」去匹配，那 15 个歌词文件一个都对不上。
        final dirFinalTracks = <Track>[];

        var pageToken = cursor.currentPageToken;
        var dirFailed = false;

        while (true) {
          // 节流放在请求**之前**：这样同目录翻页、换目录、续扫首请求
          // 走的都是同一条限速逻辑，不会再有漏网的请求。
          await throttleList();

          DrivePage page;
          try {
            page = await adapter.listDirectory(
              dirId: dir.id,
              pageToken: pageToken,
              pageSize: policy.pageSize,
            );
          } on DriveException catch (e) {
            if (e.needsReauth) rethrow; // 授权问题必须让用户处理
            // 单个目录失败（无权限/超时）不该毁掉整次扫描
            cursor = cursor.addCounts(failures: 1, now: _clock());
            cursor = cursor.copyWith(lastError: e.message, updatedAt: _clock());
            dirFailed = true;
            break;
          }

          var newFiles = 0;
          var newTracks = 0;
          var newBytes = 0;

          for (final entry in page.entries) {
            if (entry.isDirectory) {
              final childDepth = dir.depth + 1;
              if (!policy.shouldEnterDir(entry.name, childDepth)) continue;
              if (isArtworkDirName(entry.name)) artworkDirs.add(entry);
              if (policy.reachedDirLimit(
                cursor.scannedDirs,
                queuedDirs: cursor.pendingDirs.length,
              )) {
                continue;
              }
              cursor = cursor.enqueueIfAbsent(
                PendingDir(
                  id: entry.id,
                  path: _joinPath(dir.path, entry.name),
                  depth: childDepth,
                ),
                _clock(),
              );
            } else {
              newFiles++;
              // CUE 分轨表不是音频，但要**单独收着**：它的价值是描述同目录的
              // 音频怎么切，所以既不能当曲目（曲目数会虚增），
              // 也不能像其它非音频那样直接丢掉。
              if (isCueFile(entry.name)) {
                dirCues.add(entry);
                continue;
              }
              // 图片同理：它是这张专辑的封面候选，不是曲目。
              if (isImageFile(entry.name, mimeType: entry.mimeType)) {
                dirImages.add(entry);
                continue;
              }
              // 歌词同理：`.lrc` 是几 KB 的文本，既不是音频、也不该当曲目，
              // 但它要跟同目录的曲目对上（见下方歌词匹配）。
              if (isLrcFile(entry.name)) {
                dirLrc.add(entry);
                continue;
              }
              if (!isAudioFile(entry.name, mimeType: entry.mimeType)) continue;
              final track = Track.fromEntry(
                entry: entry,
                provider: provider,
                path: dir.path,
              );
              buffer.add(track);
              dirTracks.add(track);
              seenIds.add(track.id);
              newTracks++;
              newBytes += entry.sizeBytes ?? 0;
            }
          }

          cursor = cursor.addCounts(
            files: newFiles,
            tracks: newTracks,
            bytes: newBytes,
            now: _clock(),
          );

          pageToken = page.nextPageToken;
          cursor = cursor.copyWith(
            currentPageToken: pageToken,
            clearPageToken: pageToken == null,
            updatedAt: _clock(),
          );

          pagesSinceCursorFlush++;
          pagesSinceEmit++;

          // 批量落库续扫游标：目录边界 / 取消 / 每 N 页 都落一次，
          // 避免 700+ 次 SQLite 写（每次都要把 pendingDirs 全量序列化进 JSON）。
          if (pageToken == null ||
              cancel.isCancelled ||
              pagesSinceCursorFlush >= policy.cursorFlushEveryPages) {
            await _library.saveScanCursor(cursor);
            pagesSinceCursorFlush = 0;
          }

          // 进度按页批量推送，避免扫描页每一页都重建一次。
          if (pageToken == null ||
              cancel.isCancelled ||
              pagesSinceEmit >= policy.progressEmitEveryPages) {
            emit();
            pagesSinceEmit = 0;
          }

          // 本目录已收集的曲目及时入库，避免长时间占用内存
          if (buffer.length >= 200) {
            await _library.upsertTracks(buffer,
                capabilities: capabilities, now: _clock());
            indexed += buffer.length;
            buffer.clear();
          }

          if (pageToken == null) break;
          if (cancel.isCancelled) {
            cancelled = true;
            break;
          }
          // 节流已移到内层循环开头（见 throttleList）—— 放这里会漏掉
          // 「本目录最后一页 → 下一个目录第一页」这次请求。
        }

        // 当前目录处理完毕
        cursor = cursor.copyWith(
          clearCurrentDir: true,
          clearPageToken: true,
          scannedDirs: dirFailed ? cursor.scannedDirs : cursor.scannedDirs + 1,
          updatedAt: _clock(),
        );

        // CUE 分轨：把一个不可导航的 72 分钟整轨变成 N 首能点、能收藏、
        // 能随机的歌。必须放在**本目录音频收齐之后**，理由见 dirTracks 注释。
        //
        // 已知边界：若上次扫描是在**本目录中途**被杀的，续扫进来时前几页的
        // 音频不在 dirTracks 里，CUE 可能匹配不上（结果是「这个目录这次没
        // 应用 CUE」）。不会产生错误结果，下一次完整扫描会补上。
        if (dirCues.isNotEmpty) {
          final result = await cueIndexer.indexDirectory(
            readFile: adapter.readFileBytes,
            tracks: dirTracks,
            cueFiles: dirCues,
          );
          cueResult = result;
          if (!result.isEmpty) {
            // 整轨让位给切出的段：先从待写缓冲里摘掉，否则紧接着的 flush
            // 会把它又插回去；库里可能残留的旧行随后单独删。
            if (result.replacedImageIds.isNotEmpty) {
              buffer.removeWhere(
                (t) => result.replacedImageIds.contains(t.id),
              );
              seenIds.removeAll(result.replacedImageIds);
              replacedIds.addAll(result.replacedImageIds);
            }
            for (final t in result.extraTracks) {
              buffer.add(t);
              seenIds.add(t.id);
            }
            for (final t in result.patchedTracks) {
              // 本目录扫出来的那条要被带 CUE 元数据的版本取代
              buffer.removeWhere((x) => x.id == t.id);
              buffer.add(t);
              seenIds.add(t.id);
            }
            cueSegments += result.extraTracks.length;
            cueImagesHidden += result.replacedImageIds.length;
          }
        }

        if (buffer.isNotEmpty) {
          await _library.upsertTracks(buffer,
              capabilities: capabilities, now: _clock());
          indexed += buffer.length;
          buffer.clear();
        }

        // 本目录最终的曲目列表（见 dirFinalTracks 的注释）。
        // 必须在 CUE 处理**之后**才算得出来。
        dirFinalTracks.addAll(dirTracks);
        final cue = cueResult;
        if (cue != null && !cue.isEmpty) {
          if (cue.replacedImageIds.isNotEmpty) {
            dirFinalTracks.removeWhere(
              (t) => cue.replacedImageIds.contains(t.id),
            );
          }
          for (final p in cue.patchedTracks) {
            final i = dirFinalTracks.indexWhere((t) => t.id == p.id);
            if (i >= 0) {
              dirFinalTracks[i] = p;
            } else {
              dirFinalTracks.add(p);
            }
          }
          dirFinalTracks.addAll(cue.extraTracks);
        }

        // 本地歌词：和封面一样放在**本目录收齐之后**。
        //
        // 只写**引用**（哪个 `.lrc` 对应哪首曲目），不读正文：扫描阶段每读
        // 一个 `.lrc` 都要发一次请求，而夸克接口有 QPS 限制 —— 一个几千张
        // 专辑的曲库会因此多出几千次请求，而其中大部分歌词可能永远没人看。
        // 正文等这首歌第一次被播放时再读（见 `LyricsResolver`）。
        //
        // 已知边界与 CUE 相同：若上次扫描是在本目录**中途**被杀的，续扫进来
        // 时前几页的曲目不在 dirFinalTracks 里，歌词可能对不上（结果是
        // 「这个目录这次没有歌词」）。不会产生错误结果，下次完整扫描会补上。
        if (dirLrc.isNotEmpty && dirFinalTracks.isNotEmpty) {
          final lyricsResult = lyricsIndexer.indexDirectory(
            provider: provider,
            tracks: dirFinalTracks,
            lrcFiles: dirLrc,
          );
          if (lyricsResult.matches.isNotEmpty) {
            await _library.upsertLyrics(lyricsResult.matches, now: _clock());
            for (final l in lyricsResult.matches) {
              seenLyrics.add(l.trackId);
            }
            lyricsIndexed += lyricsResult.matches.length;
            diag.info(
              '歌词',
              '${dir.path}：${dirLrc.length} 个 .lrc 对上 '
              '${lyricsResult.matches.length} 首曲目',
            );
          }
        }

        // 专辑封面：和 CUE 一样放在**本目录收齐之后**，理由也一样 ——
        // 得先知道这个目录到底有没有曲目（只有专辑才配一张封面），
        // 而「有没有曲目」要翻完整个目录才知道。
        //
        // 只写**引用**（哪张图），不下载图片字节：扫描时把每张封面都拉下来
        // 会把一次扫描变成一次批量下载，而用户可能根本不打开专辑视图。
        if (dirTracks.isNotEmpty) {
          final cover = await _resolveCover(
            adapter: adapter,
            provider: provider,
            dir: dir,
            sameDir: dirImages,
            artworkDirs: artworkDirs,
            throttle: throttleList,
          );
          if (cover != null) {
            await _library.upsertAlbumCovers([cover], now: _clock());
            seenCoverDirs.add(cover.dirPath);
            coversIndexed++;
          }
        }

        // 删在 flush **之后**：整轨文件可能早已作为普通曲目写进库里
        // （上一次扫描写的，或本次翻页时已 flush 出去）。
        // 不能只依赖最后的陈旧清理 —— 那只在「完整从头扫完」时才跑，
        // 续扫场景下这些行会一直留着，用户看到整轨与它的分轨同时存在。
        if (replacedIds.isNotEmpty) {
          await _library.deleteTracks(replacedIds);
          replacedIds.clear();
        }

        // 目录边界强制落盘 + 推进度，并归零节流计数
        await _library.saveScanCursor(cursor);
        emit();
        pagesSinceCursorFlush = 0;
        pagesSinceEmit = 0;

        // 周期性的进度日志（每 50 个目录一条），避免扫描全程在日志里「隐身」
        if (cursor.scannedDirs % 50 == 0) {
          diag.info(
            '扫描',
            '已扫 ${cursor.scannedDirs} 目录 / '
            '${cursor.scannedFiles} 文件 / ${cursor.foundTracks} 曲目…',
          );
        }

        if (cancelled) break;
      }

      if (buffer.isNotEmpty) {
        await _library.upsertTracks(buffer,
            capabilities: capabilities, now: _clock());
        indexed += buffer.length;
        buffer.clear();
      }

      if (cancelled) {
        cursor = cursor.pause(_clock());
      } else if (cursor.hasPendingWork) {
        // 队列还有活却退出了（正常不该发生），保守标记为暂停以便续扫
        cursor = cursor.pause(_clock());
      } else {
        cursor = cursor.markCompleted(_clock());
      }
    } on DriveException catch (e) {
      error = e.message;
      cursor = cursor.fail(e.message, _clock());
      await _library.saveScanCursor(cursor);
      emit(running: false, message: e.message);
      diag.error('扫描', '中断（需授权 ${e.needsReauth}）：${e.message}');
      rethrow;
    } catch (e) {
      error = e.toString();
      cursor = cursor.fail(error, _clock());
      await _library.saveScanCursor(cursor);
      emit(running: false, message: error);
      diag.error('扫描', '意外中断：$error');
    }

    // 陈旧清理：删掉该网盘下**本次没扫到**的曲目，即网盘侧已被删除的文件。
    //
    // 白名单必须是「本次运行实际扫到的 id」。早先这里用的是「库里现有的全部
    // 曲目」，那等于永远删不掉任何东西 —— 陈旧曲目会一直留在索引里。
    //
    // 三个前置条件缺一不可：
    //   - startedFresh：续扫时本次只看到部分目录，白名单不完整；
    //   - isComplete：中途取消 / 失败时索引不完整；
    //   - seenIds 非空：适配器异常返回空页时，不至于把整个曲库清空。
    if (pruneStale && startedFresh && cursor.isComplete && error == null) {
      // 新歌基线：第一次成功扫完时，把「用户看完新歌」的水位设为「现在」，
      // 让当时已有的曲库变成基线，之后进库的新歌才被算作「新」。
      // 只在水位还没建立时设（已经是 now 或某个时间点就不改），
      // 否则每次扫描都会把水位往前推、把整库变成「已看」，新歌永不可见。
      // 水位为 null 即「从未建立」—— 老库升级、全新安装都走这条。
      final previousSeen = await _settings.read(SettingKeys.newSongsSeenAt);
      if (previousSeen == null) {
        await _settings.writeDateTime(
          SettingKeys.newSongsSeenAt,
          _clock(),
        );
        diag.info('扫描', '已建立「新歌」基线（本次曲库视为已看）');
      }

      if (seenIds.isNotEmpty) {
        removed = await _library.deleteTracksNotIn(provider, seenIds);
        // 封面与曲目同一个白名单前提：只有「这次确实扫到了东西」才敢清理。
        // 曲库里有封面的专辑往往只是一部分，所以白名单用的是「写出封面的
        // 目录」而不是「扫过的目录」—— 前者才是本次运行的真实产出。
        await _library.deleteAlbumCoversNotIn(provider, seenCoverDirs);

        // 歌词多一道闸：**有目录列失败时不清理**。
        //
        // 失败目录里的曲目这次没被扫到，它们的歌词引用自然也不在
        // [seenLyrics] 里 —— 按白名单删会把那些**明明还在**的歌词全删掉，
        // 而失败往往只是超时（见 dirFailed 的处理），下一次扫描可能就好了。
        // 白名单式的清理在「白名单本身不完整」时是有害的，宁可这次不清理。
        //
        // ⚠️ 封面那条路径有同样的隐患，但它的影响面更大、改动也更大，
        // 不在这里一并改。
        if (cursor.failedDirs == 0) {
          await _library.deleteLyricsNotIn(provider, seenLyrics);
        }
      }
    }

    await _library.saveScanCursor(cursor);
    emit(running: false, message: cursor.isComplete ? '已完成' : null);

    if (cancelled) {
      diag.warn('扫描', '已取消：游标阶段=paused，可续扫'
          '（目录 ${cursor.scannedDirs} / 曲目 ${cursor.foundTracks}）');
    } else if (error != null) {
      diag.error('扫描', '结束但有问题：$error');
    } else {
      diag.info(
        '扫描',
        '完成：目录 ${cursor.scannedDirs} / 文件 ${cursor.scannedFiles} / '
        '曲目 ${cursor.foundTracks} / 清理 $removed'
        '${cueSegments == 0 ? "" : " / CUE 展开 $cueSegments 首"
            "（取代 $cueImagesHidden 个整轨）"}'
        '${coversIndexed == 0 ? "" : " / 封面 $coversIndexed 张"}'
        '${lyricsIndexed == 0 ? "" : " / 本地歌词 $lyricsIndexed 首"}',
      );
    }
    diag.section('扫描结束');

    return ScanOutcome(
      cursor: cursor,
      tracksIndexed: indexed,
      removedTracks: removed,
      playability: await _library.playabilitySummary(provider: provider),
      wasCancelled: cancelled,
      error: error,
    );
  }

  /// 挑出这个目录的专辑封面。**永不抛异常**。
  ///
  /// 封面和 CUE 一样是锦上添花：读不到、列不出、解析不了，都只让这张专辑
  /// 退回「没有封面」的样子（界面上是品牌渐变占位），绝不能让整次扫描失败。
  ///
  /// 两处请求节流：[artworkDirs] 里的子目录要用 [throttle] 逐个列，
  /// 走的和主遍历同一条限速逻辑 —— 否则「每个专辑目录多一次请求」会
  /// 绕过 3 QPS 的安全线。
  Future<AlbumCover?> _resolveCover({
    required CloudDriveAdapter adapter,
    required DriveProvider provider,
    required PendingDir dir,
    required List<DriveEntry> sameDir,
    required List<DriveEntry> artworkDirs,
    required Future<void> Function() throttle,
  }) async {
    final subImages = <String, List<DriveEntry>>{};

    // 同目录已经有一张「明确写着封面」的图时不再翻子目录：
    // 它的得分已经是理论最低分（见 AlbumCoverIndexer.hasNamedCover），
    // 子目录里的图赢不了，那几次列目录请求纯属白花。
    if (artworkDirs.isNotEmpty &&
        !AlbumCoverIndexer.hasNamedCover(sameDir)) {
      for (final sub in artworkDirs) {
        try {
          await throttle();
          final page = await adapter.listDirectory(
            dirId: sub.id,
            pageSize: policy.pageSize,
          );
          // 只取第一页：封面目录里放几百张图是不正常的，
          // 为它翻完所有页等于用一个坏命名习惯拖慢整次扫描。
          subImages[sub.name] = page.entries.where((e) => e.isFile).toList();
        } on DriveException catch (e) {
          diag.info('封面', '${sub.name}：列目录失败，跳过（${e.type.name}）');
        } catch (e) {
          diag.warn('封面', '${sub.name}：列目录抛出非预期异常', error: e);
        }
      }
    }

    final cover = coverIndexer.pick(
      provider: provider,
      dirPath: dir.path,
      sameDir: sameDir,
      artworkDirs: subImages,
    );
    if (cover == null) return null;

    diag.info(
      '封面',
      '${cover.dirPath}：用 "${cover.fileName}"'
      '${subImages.isEmpty ? "" : "（翻过 ${subImages.length} 个子目录）"}',
    );
    return cover;
  }

  /// 拼接目录展示路径，保证以 `/` 开头、以 `/` 结尾。
  static String _joinPath(String base, String name) {
    if (base.isEmpty) return '/$name/';
    if (base.endsWith('/')) return '$base$name/';
    return '$base/$name/';
  }
}
