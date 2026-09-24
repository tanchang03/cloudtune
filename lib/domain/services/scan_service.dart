import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../../core/utils/audio_formats.dart';
import '../adapters/cloud_drive_adapter.dart';
import '../adapters/library_repository.dart';
import '../entities/drive_entry.dart';
import '../entities/drive_provider.dart';
import '../entities/scan_cursor.dart';
import '../entities/scan_policy.dart';
import '../entities/track.dart';
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
    this.policy = const ScanPolicy(),
    DateTime Function()? clock,
  })  : _registry = registry,
        _library = library,
        _clock = clock ?? DateTime.now;

  final DriveAdapterRegistry _registry;
  final LibraryRepository _library;
  final ScanPolicy policy;
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
    var indexed = 0;
    var removed = 0;
    var cancelled = false;
    String? error;

    // 节流计数：游标批量落盘 / 进度批量推送，避免 700+ 次 SQLite 写与 UI 重建。
    var pagesSinceCursorFlush = 0;
    var pagesSinceEmit = 0;

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

        var pageToken = cursor.currentPageToken;
        var dirFailed = false;

        while (true) {
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
              if (!isAudioFile(entry.name, mimeType: entry.mimeType)) continue;
              final track = Track.fromEntry(
                entry: entry,
                provider: provider,
                path: dir.path,
              );
              buffer.add(track);
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

          // 「还有下一页」时按策略节流，把请求速率压到安全线、
          // 避免把整机 CPU 顶满。`minRequestInterval` 之前是写了没人用的死配置。
          if (policy.minRequestInterval > Duration.zero) {
            await Future.delayed(policy.minRequestInterval);
          }
        }

        // 当前目录处理完毕
        cursor = cursor.copyWith(
          clearCurrentDir: true,
          clearPageToken: true,
          scannedDirs: dirFailed ? cursor.scannedDirs : cursor.scannedDirs + 1,
          updatedAt: _clock(),
        );
        if (buffer.isNotEmpty) {
          await _library.upsertTracks(buffer,
              capabilities: capabilities, now: _clock());
          indexed += buffer.length;
          buffer.clear();
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
      if (seenIds.isNotEmpty) {
        removed = await _library.deleteTracksNotIn(provider, seenIds);
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
        '曲目 ${cursor.foundTracks} / 清理 $removed',
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

  /// 拼接目录展示路径，保证以 `/` 开头、以 `/` 结尾。
  static String _joinPath(String base, String name) {
    if (base.isEmpty) return '/$name/';
    if (base.endsWith('/')) return '$base$name/';
    return '$base/$name/';
  }
}
