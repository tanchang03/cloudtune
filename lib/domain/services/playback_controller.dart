import 'dart:async';

import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../adapters/audio_output.dart';
import '../adapters/cloud_drive_adapter.dart';
import '../adapters/library_repository.dart';
import '../entities/playability.dart';
import '../entities/stream_ticket.dart';
import '../entities/track.dart';
import 'playback_queue.dart';
import 'shuffle_engine.dart';
import 'ticket_cache.dart';

/// 播放事件类型。
enum PlaybackEventType {
  /// 成功开始播放
  started,

  /// 暂停
  paused,

  /// 恢复播放
  resumed,

  /// 跳过（不可播 / 直链反复失效 / 文件已删除）
  skipped,

  /// 播放失败，需要用户介入（例如授权失效）
  failed,

  /// 一首自然播完
  completed,

  /// 队列空了
  queueEmpty,
}

/// 播放事件。UI 订阅它来更新状态栏与提示。
class PlaybackEvent {
  const PlaybackEvent({
    required this.type,
    this.track,
    this.message,
    this.recovered = false,
  });

  final PlaybackEventType type;
  final Track? track;

  /// 面向用户的中文说明（失败/跳过时非空）
  final String? message;

  /// 本次播放是否经过「直链失效 → 重取直链 → 续播」自愈
  final bool recovered;

  bool get isProblem =>
      type == PlaybackEventType.skipped || type == PlaybackEventType.failed;

  @override
  String toString() => 'PlaybackEvent(${type.name}, '
      '${track?.name ?? "-"}${message == null ? "" : ", $message"}'
      '${recovered ? ", 已自愈" : ""})';
}

/// 播放引擎。
///
/// 负责「点一首歌到出声」之间的全部编排：
///
///   1. **取链**（带 [TicketCache]，避免反复消耗网盘配额）；
///   2. **装载并播放**，把直链必需的 `Cookie` 请求头带下去；
///   3. **直链失效自愈**：捕获 `403` / `412` 后作废缓存、重取直链、
///      **seek 回中断位置**继续播 —— 这是用户感知最强的一环，
///      否则每次续链都从头开始，一首歌永远听不完；
///   4. **运行时不可播的落库**：网盘返回超限码、或本机解码器解不开某个
///      编码（DSD 最典型）时标记该曲目不可播并跳过，避免随机播放每轮
///      都撞同一堵墙；
///   5. **播放统计落库**：供「少听优先」的随机权重使用。
///
/// ## 「播不出来」的处理原则
///
/// **能自愈就自愈，治不好就跳过，只有整个账号坏了才停。**
///
/// 用户点的是「播放」，不是「调试」—— 一首歌放不出来不该让整个队列卡死。
/// 所以除了下面两种情况，一律自动跳下一首：
///   - **授权失效**：后面每一首都会同样失败，跳歌只会烧光队列，
///     还把「该重新登录了」这件事藏起来；
///   - **网络错误 / 被限流**：不是这一首歌的毛病，跳歌解决不了，
///     限流时跳歌还会越跳越糟（每次跳过都要再打一次取链接口）。
///
/// 跳过的上限由 [maxConsecutiveSkips] 兜底：整个队列都播不了时会停下来
/// 报「连续跳过 N 首」，而不是无限刷接口。
///
/// 落库与否也是刻意的：**原因明确**的失败（解码不了 / 文件不存在 /
/// 超限）落库，免得反复撞墙；**原因不明**的失败只跳过不落库，
/// 免得一次偶发就把好文件永久拉黑。
///
/// 只依赖 [DriveAdapterRegistry] / [LibraryRepository] / [AudioOutput]
/// 三个抽象，因此整条链路都能在单元测试里覆盖。
class PlaybackController {
  PlaybackController({
    required DriveAdapterRegistry registry,
    required LibraryRepository library,
    required AudioOutput output,
    PlaybackQueue? queue,
    TicketCache? tickets,
    this.maxLinkRetries = 2,
    this.maxConsecutiveSkips = 5,
    DateTime Function()? clock,
  })  : _registry = registry,
        _library = library,
        _output = output,
        queue = queue ?? PlaybackQueue(),
        _tickets = tickets ?? TicketCache(),
        _clock = clock ?? DateTime.now {
    _failureSub = _output.failures.listen(_onFailure);
    _completedSub = _output.completedStream.listen((_) => _onCompleted());
    _positionSub = _output.positionStream.listen(_onPositionTick);
    _durationSub = _output.durationStream.listen(_onDurationTick);
  }

  final DriveAdapterRegistry _registry;
  final LibraryRepository _library;
  final AudioOutput _output;
  final TicketCache _tickets;
  final DateTime Function() _clock;

  /// 同一首曲目「直链失效 → 重取」的最大次数。
  ///
  /// 必须有上限：如果网盘侧就是一直拒绝（比如签名算法变了），
  /// 没有上限会变成无限重试，用户看到的是卡死。
  final int maxLinkRetries;

  /// 连续自动跳过的上限。防止「整个队列都不可播」时疯狂刷接口。
  final int maxConsecutiveSkips;

  final PlaybackQueue queue;

  late final StreamSubscription<PlaybackFailure> _failureSub;
  late final StreamSubscription<void> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;

  final _events = StreamController<PlaybackEvent>.broadcast();

  /// 对外广播的**曲目相对**位置与时长。
  ///
  /// 为什么不让 UI 直接听 `AudioOutput` 的那两个流：它们给的是
  /// **整轨文件内的绝对坐标**。照它们显示，点第 3 轨会看到进度条
  /// 从第 7 分钟开始、总时长是整张专辑的 72:18 —— 歌词更是全错
  /// （LRC 的时间戳是相对本首歌的，拿绝对位置去对会直接跳到末尾）。
  ///
  /// 这里**由控制器转一道**，把换算收在一个地方：界面（播放条、播放页、
  /// 歌词）只管拿相对值，不必各自记住「这条是不是 CUE 分段」。
  ///
  /// 用 broadcast 而不是把 `_output` 的流 `map` 出去：后者会让
  /// `AudioOutput` 那条流被订阅两次（控制器自己已经订阅过一次），
  /// 而平台播放器的流并不保证可以多订阅。
  final _trackPosition = StreamController<Duration>.broadcast();
  final _trackDuration = StreamController<Duration?>.broadcast();

  /// 每首曲目已用掉的自愈次数
  final Map<String, int> _linkRetries = {};

  var _consecutiveSkips = 0;
  var _handlingFailure = false;
  var _disposed = false;
  var _isPlaying = false;

  /// 当前音源是否已装载完成。
  ///
  /// **装载期间到达的位置 / 完成事件都属于上一个音源，必须丢弃。**
  /// 对整轨分段这是致命的：新曲目的 `cueEndMs` 可能只有 200493ms，
  /// 而旧音源残留的位置是 4300000ms —— 不挡住就会立刻误切下一首，
  /// 一首接一首地把整张专辑跳完。
  var _sourceReady = false;

  /// 当前曲目是否已经真正进到过本轨区间内。
  ///
  /// 这是挡残留事件的第二道闸门：只有先看到过「位置落在本轨区间内」，
  /// 后面「位置 ≥ 本轨终点」才可信。判据用 `位置 < 终点` 而不是
  /// `位置 ≥ 起点` —— 能造成误切的残留位置必然 ≥ 终点，用它当判据更严。
  var _enteredSegment = false;

  /// 播放事件流（广播）。UI 订阅它。
  Stream<PlaybackEvent> get events => _events.stream;

  Track? get current => queue.current;

  bool get isPlaying => _isPlaying;

  /// 曲目在**整轨文件内**的起点。独立文件为 0。
  Duration _startOf(Track track) =>
      Duration(milliseconds: track.cueStartMs ?? 0);

  /// 播放位置流 —— **相对本曲目**（分段已减掉本轨起点）。
  ///
  /// 界面（播放条进度、播放页进度条、歌词高亮）一律读这个，
  /// 不要去读 `AudioOutput.positionStream`（那是整轨内的绝对坐标）。
  Stream<Duration> get positionStream => _trackPosition.stream;

  /// 时长流 —— **相对本曲目**。分段给的是单轨时长，不是整轨时长。
  Stream<Duration?> get durationStream => _trackDuration.stream;

  /// 当前曲目的播放位置 —— **相对本曲目**。
  ///
  /// 对整轨切出的分段，播放器内部用的是「整轨文件内的绝对位置」
  /// （比如第 2 轨的 200493ms），而用户看到的应该是「本轨播到第几秒」。
  /// 换算收在这里，进度条与时间标签就不必各自记住「这条是不是分段」。
  Duration get position => _relativePosition(_output.position);

  /// 当前曲目的时长 —— **相对本曲目**。
  ///
  /// 分段取元数据里的单轨时长，而不是播放器报的整轨时长：后者会让进度条
  /// 显示「72:18」，可用户点的是 3 分 20 秒那一首，拖到一半就播完了。
  ///
  /// 单轨时长未知时（CUE 末轨要靠整轨时长补齐，而整轨时长可能缺失）
  /// 用播放器的整轨时长倒推 —— 总比让进度条瞎掉强。
  Duration? get duration => _relativeDuration(_output.duration);

  /// 绝对位置 → 曲目相对位置。负值是「还没进本轨」，按 0 显示。
  Duration _relativePosition(Duration absolute) {
    final track = queue.current;
    final p = absolute - (track == null ? Duration.zero : _startOf(track));
    return p.isNegative ? Duration.zero : p;
  }

  /// 播放器报的整轨时长 → 曲目相对时长。规则与 [duration] 完全一致。
  Duration? _relativeDuration(Duration? total) {
    final track = queue.current;
    if (track == null || !track.isCueSegment) return total;
    final own = track.duration;
    if (own != null) return own;
    if (total == null) return null;
    final left = total - _startOf(track);
    return left.isNegative ? null : left;
  }

  /// 当前正在进行的异步任务（失败自愈 / 播完自动续下一首），没有则为 `null`。
  ///
  /// 这些任务是由 [AudioOutput] 的事件流触发的，调用方（UI 的「正在续播…」
  /// 提示、单元测试）需要能等到它真正结束，而不是刚发起就以为好了。
  Future<void>? get pendingTask => _pendingTask;
  Future<void>? _pendingTask;

  // -------------------------------------------------------------------
  // 对外操作
  // -------------------------------------------------------------------

  /// 装载曲池。重新扫描或筛选后调用。
  ///
  /// [weights] 是「少听优先」随机权重的输入，来自 `LibraryRepository
  /// .shuffleCandidates()`。
  void setQueue(
    List<Track> tracks, {
    Map<String, ShuffleCandidate> weights = const {},
    bool keepCurrent = true,
  }) {
    queue.updateWeights(weights);
    queue.replaceTracks(tracks, keepCurrent: keepCurrent);
  }

  /// 直接播某一首。
  ///
  /// 队列里有它就定位过去；没有就把它单独放进队列（例如从搜索结果里点播）。
  Future<PlaybackEvent> playTrack(Track track) async {
    if (queue.contains(track.id)) {
      queue.jumpTo(track.id);
    } else {
      queue.replaceTracks([track]);
      queue.jumpTo(track.id);
    }
    return _loadAndPlay(track);
  }

  /// 下一首。
  Future<PlaybackEvent> next() async {
    final track = queue.next();
    if (track == null) {
      await _output.stop();
      _isPlaying = false;
      return _emit(const PlaybackEvent(type: PlaybackEventType.queueEmpty));
    }
    return _loadAndPlay(track);
  }

  /// 上一首。
  Future<PlaybackEvent> previous() async {
    final track = queue.previous();
    if (track == null) {
      return _emit(PlaybackEvent(
        type: PlaybackEventType.failed,
        track: queue.current,
        message: '已经是第一首了',
      ));
    }
    return _loadAndPlay(track);
  }

  Future<PlaybackEvent> pause() async {
    await _output.pause();
    _isPlaying = false;
    return _emit(PlaybackEvent(
      type: PlaybackEventType.paused,
      track: queue.current,
    ));
  }

  Future<PlaybackEvent> resume() async {
    if (queue.current == null) return next();
    await _output.play();
    _isPlaying = true;
    return _emit(PlaybackEvent(
      type: PlaybackEventType.resumed,
      track: queue.current,
    ));
  }

  /// 跳转到**相对本曲目**的位置。
  ///
  /// 对整轨分段，调用方（进度条）说的是「本轨第几秒」，播放器要的是
  /// 「整轨文件内的第几毫秒」—— 换算与夹取都收在这里。
  /// 夹到本轨时长是必须的：不夹的话拖到最右会把播放头送进下一轨的地盘，
  /// 用户看到的是「拖到底反而播了别的歌」。
  Future<void> seek(Duration position) {
    final track = queue.current;
    final offset = track == null ? Duration.zero : _startOf(track);
    final limit = duration;
    var p = position;
    if (p.isNegative) p = Duration.zero;
    if (limit != null && p > limit) p = limit;

    // 显式 seek 是「用户就是要听这一段」的确凿证据，直接认定已进入本轨。
    //
    // 不这么做会漏掉一个真实场景：刚装载完就把进度条拖到最右 —— 此时
    // 位置监听还没收到过任何「落在本轨区间内」的位置，[_enteredSegment]
    // 还是 false，于是「到达终点」会被当成上一首的残留事件丢掉，
    // 结果这一轨一路放到整轨结束，用户拖到底反而听到了后面几首。
    _enteredSegment = true;

    return _output.seek(offset + p);
  }

  /// 切换播放模式。切到随机时会重置本轮记录（见 [PlaybackQueue.setMode]）。
  void setMode(PlaybackMode mode) => queue.setMode(mode);

  /// 刷新随机权重（播放统计变化后调用，让「少听优先」立刻生效）。
  void updateWeights(Map<String, ShuffleCandidate> weights) {
    queue.updateWeights(weights);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _failureSub.cancel();
    await _completedSub.cancel();
    await _positionSub.cancel();
    await _durationSub.cancel();
    await _events.close();
    await _trackPosition.close();
    await _trackDuration.close();
    await _output.dispose();
  }

  // -------------------------------------------------------------------
  // 内部：装载与播放
  // -------------------------------------------------------------------

  /// 装载并播放。
  ///
  /// [from] 是**整轨文件内的绝对位置**（内部坐标），`null` 表示从头播 ——
  /// 对分段曲目「从头」指的是本轨起点 [Track.cueStartMs]，不是文件开头。
  /// 续链自愈会传一个具体的绝对位置（断点），因此这里不能把语义反过来。
  ///
  /// [forceRefreshTicket] 与 [countAsPlay] 刻意分开，不要合并成一个
  /// `isRecovery` 标志 —— 它们对应的场景不同：
  ///   - **续链**（直链失效）：必须绕过票据缓存（缓存的正是那张废票），
  ///     且不该再记一次播放；
  ///   - **单曲循环重播**：票据大概率还有效，应该走缓存省配额，
  ///     而且那确实是一次新的播放，要计数。
  Future<PlaybackEvent> _loadAndPlay(
    Track track, {
    Duration? from,
    bool forceRefreshTicket = false,
    bool countAsPlay = true,
  }) async {
    // 闸门先关：装载期间到达的位置 / 完成事件都属于上一个音源
    _sourceReady = false;
    _enteredSegment = false;

    final adapter = _registry.adapterFor(track.provider);
    if (adapter == null) {
      diag.error('播放', '${track.provider.displayName} 没有注册适配器，跳过');
      return _skip(track, '${track.provider.displayName} 尚未接入，无法播放');
    }

    diag.section('播放 ${track.name}');
    diag.info(
      '播放',
      'id=${track.id} 体积=${track.sizeBytes ?? "未知"} '
      '时长=${track.durationMs ?? "未知"} 扩展名=${track.extension}'
      '${track.isCueSegment ? " CUE第${track.cueTrackNo}轨"
          "（整轨内 ${track.cueStartMs}→${track.cueEndMs ?? "未知"}ms）" : ""}',
    );

    if (!adapter.capabilities.canResolveDirectLink) {
      diag.error('播放', '适配器声明不支持直链播放，跳过');
      await _library.markUnplayable(
        track.id,
        state: PlayabilityState.unsupportedByProvider,
        reason: '${track.provider.displayName} 未开放直链播放能力',
        now: _clock(),
      );
      // 必须移出队列：否则 next() 会绕回来又撞上同一首，白白空转一轮
      queue.removeTrack(track.id);
      return _skip(track, '${track.provider.displayName} 未开放直链播放能力');
    }

    final StreamTicketResult resolved;
    try {
      resolved = await _resolveTicket(
        adapter,
        track,
        forceRefresh: forceRefreshTicket,
      );
      diag.info(
        '播放',
        '取链完成${resolved.fromCache ? "（命中票据缓存）" : ""}',
      );
    } on DriveException catch (e) {
      return _handleResolveError(track, e);
    }

    final startAt = from ?? _startOf(track);

    try {
      // 装载阶段的失败必须在这里抛出（见 AudioOutput 的约定），
      // 否则播放统计会被错误地记上
      await _output.load(resolved.ticket, initialPosition: startAt);
      await _output.play();
    } on PlaybackLoadException catch (e) {
      // 装载阶段就发现播不了 —— 和播放中途失败走**同一个**决策函数，
      // 免得「解码器解不开」在两条路径上被判断成两件不同的事
      return _handlePlaybackFailure(track, e.failure);
    } on DriveException catch (e) {
      return _handleResolveError(track, e);
    } catch (e, st) {
      // 播放器抛了我们没归类出来的东西。**照样跳过**：用户点的是「播放」，
      // 一首歌放不出来不该让整个队列停在这里。
      // 但**不落库** —— 不知道原因就不给这首歌判死刑，免得一次偶发
      // 把好文件永久拉黑。
      diag.error('播放', '装载时抛出未归类异常，跳过但不落库', error: e, stackTrace: st);
      _tickets.invalidate(track.id);
      return _skip(track, '无法播放：$e');
    }

    _isPlaying = true;
    _consecutiveSkips = 0;
    // 新音源就绪，从现在起才接受位置 / 完成事件
    _sourceReady = true;
    diag.info('播放', '已开始播放');

    // 只有「真正开始播」才记一次播放统计。
    // 续链自愈不算新的一次播放，否则一首歌听一半会多算好几次。
    if (countAsPlay) {
      await _library.recordPlay(track.id, now: _clock());
    }

    return _emit(PlaybackEvent(
      type: PlaybackEventType.started,
      track: track,
      recovered: forceRefreshTicket,
    ));
  }

  /// 取直链：先查缓存，未命中才走网络。
  Future<StreamTicketResult> _resolveTicket(
    CloudDriveAdapter adapter,
    Track track, {
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = _tickets.get(track.id);
      if (cached != null) return StreamTicketResult(cached, fromCache: true);
    }
    final ticket = await adapter.resolveStream(track.remoteId);
    _tickets.put(track.id, ticket);
    return StreamTicketResult(ticket, fromCache: false);
  }

  /// 取链阶段的错误决策。
  ///
  /// 与 [_handlePlaybackFailure] 同一原则：**只有「整个账号/整条网络坏了」
  /// 才停下来**，其余情况一律跳过，让用户能接着听下去。
  Future<PlaybackEvent> _handleResolveError(
    Track track,
    DriveException e,
  ) async {
    diag.error(
      '播放',
      '取链失败，开始决策：type=${e.type.name} needsReauth=${e.needsReauth} '
      'http=${e.httpStatus ?? "-"} providerCode=${e.providerCode ?? "-"} '
      'message=${e.message}',
    );

    if (e.type == DriveErrorType.fileTooLarge) {
      diag.warn('播放', '决策：体积超限 → 落库标记 + 移出队列 + 跳过');
      // 运行时才发现超限：索引里的体积不准，或者网盘限制变了。
      // 落库标记，避免随机播放每轮都撞同一堵墙。
      await _library.markUnplayable(
        track.id,
        state: PlayabilityState.overLimit,
        reason: e.message,
        now: _clock(),
      );
      queue.removeTrack(track.id);
      _tickets.invalidate(track.id);
      return _skip(track, e.message);
    }

    if (e.needsReauth) {
      // 授权失效是**全局**问题：后面每一首都会以同样方式失败。
      // 跳歌只会把整个队列烧光，还把「该重新登录了」这件事藏起来 ——
      // 这是唯一一种「停下来」比「跳过去」正确的失败。
      diag.error('播放', '决策：授权失效 → 停止播放并提示重新登录（这是唯一会停下的分支）');
      _isPlaying = false;
      return _emit(PlaybackEvent(
        type: PlaybackEventType.failed,
        track: track,
        message: '${track.provider.displayName}授权已失效，请重新登录',
      ));
    }

    if (e.type == DriveErrorType.notFound) {
      diag.warn('播放', '决策：文件不存在 → 移出队列 + 跳过');
      queue.removeTrack(track.id);
      return _skip(track, '文件已不存在：${track.name}');
    }

    if (e.type == DriveErrorType.network ||
        e.type == DriveErrorType.rateLimited) {
      // 网络问题 / 被限流：不是这首歌的毛病。
      // 跳过没有意义（下一首同样取不到链），而且限流时跳歌会越跳越糟
      // —— 每一次跳过都要再打一次取链接口。
      diag.error('播放', '决策：网络/限流 → 停止（跳歌只会更糟）');
      _isPlaying = false;
      return _emit(PlaybackEvent(
        type: PlaybackEventType.failed,
        track: track,
        message: e.message,
      ));
    }

    // 其余取链错误（权限不足 / 响应异常 / 未归类）：**跳过而不是停下**。
    // 它们通常只是这一个文件的事，没必要让整个队列陪葬。
    // 不落库 —— 原因不明确，不轻易给一首歌判死刑。
    diag.warn('播放', '决策：其它取链错误 → 跳过但不落库');
    return _skip(track, e.message);
  }

  /// 跳过一首并自动接下一首。
  Future<PlaybackEvent> _skip(Track track, String reason) async {
    _consecutiveSkips++;
    diag.warn(
      '播放',
      '跳过「${track.name}」：$reason（连续第 $_consecutiveSkips 次，'
      '上限 $maxConsecutiveSkips）',
    );
    if (_consecutiveSkips > maxConsecutiveSkips) {
      diag.error('播放', '连续跳过超过上限，停止自动播放');
      _isPlaying = false;
      return _emit(PlaybackEvent(
        type: PlaybackEventType.failed,
        track: track,
        message: '连续跳过 $maxConsecutiveSkips 首，已停止自动播放',
      ));
    }

    _emit(PlaybackEvent(
      type: PlaybackEventType.skipped,
      track: track,
      message: reason,
    ));

    final nextTrack = queue.next();
    if (nextTrack == null) {
      _isPlaying = false;
      return _emit(const PlaybackEvent(type: PlaybackEventType.queueEmpty));
    }
    return _loadAndPlay(nextTrack);
  }

  // -------------------------------------------------------------------
  // 内部：异步失败自愈
  // -------------------------------------------------------------------

  Future<void> _onFailure(PlaybackFailure failure) async {
    if (_disposed || _handlingFailure) return;
    _handlingFailure = true;
    final task = _heal(failure);
    _pendingTask = task;
    try {
      await task;
    } finally {
      _handlingFailure = false;
      _pendingTask = null;
    }
  }

  /// 播放中途失败（来自 [AudioOutput.failures] 流）。
  Future<void> _heal(PlaybackFailure failure) async {
    final track = queue.current;
    if (track == null) return;
    await _handlePlaybackFailure(track, failure);
  }

  /// 「这首歌播不出来」的统一决策 —— **装载阶段与播放中途共用**。
  ///
  /// 原则：**能自愈就自愈，治不好就跳过，只有整个账号坏了才停。**
  ///
  /// 两条路径必须共用同一个函数，否则迟早走偏：以前装载阶段只把
  /// `unplayableSource` 翻译成异常、其余原样上抛，于是同一个「解码器
  /// 解不开」的错误，在装载阶段被当成未知异常**停住播放**，在播放中途
  /// 却被正确跳过。用户看到的就是「有的歌播不了会自动跳，有的会卡死」。
  Future<PlaybackEvent> _handlePlaybackFailure(
    Track track,
    PlaybackFailure failure,
  ) async {
    diag.error(
      '播放',
      '播放失败，开始决策：kind=${failure.kind.name} '
      'http=${failure.httpStatus ?? "-"} '
      'providerCode=${failure.providerCode ?? "-"} '
      'message=${failure.message}',
    );
    switch (failure.kind) {
      case PlaybackFailureKind.unplayableSource:
        // 本机解码器解不开（DSD 是最典型的）或网盘拒绝取链：
        // 重取一百次也没用，所以**落库标记**，否则随机播放每轮都会
        // 再撞一次同一堵墙。
        await _library.markUnplayable(
          track.id,
          state: PlayabilityState.decodeFailed,
          reason: failure.message,
          now: _clock(),
        );
        queue.removeTrack(track.id);
        _tickets.invalidate(track.id);
        return _skip(track, failure.message);

      case PlaybackFailureKind.notFound:
        queue.removeTrack(track.id);
        _tickets.invalidate(track.id);
        return _skip(track, '文件已不存在：${track.name}');

      case PlaybackFailureKind.linkExpired:
        // 唯一能自愈的一种：重取直链后 seek 回中断位置继续播
        return _recoverLink(track, failure);

      case PlaybackFailureKind.network:
        // 网络层问题，不是这首歌的毛病：跳歌解决不了，如实告诉用户
        _isPlaying = false;
        return _emit(PlaybackEvent(
          type: PlaybackEventType.failed,
          track: track,
          message: failure.message,
        ));

      case PlaybackFailureKind.unknown:
        // 没归类出来的毛病：**跳过，但不落库**。
        // 跳过是为了不让播放卡死；不落库是因为不知道原因，
        // 一次偶发错误不该让一首好歌永久变成「不可播」。
        return _skip(track, failure.message);
    }
  }

  /// 直链失效自愈：作废缓存 → 重取直链 → **seek 回中断位置**继续播。
  ///
  /// 返回本次处理的最终事件（续播成功是 `started`，重试用尽是 `skipped`），
  /// 以便和 [_handlePlaybackFailure] 的其它分支保持同一种返回类型。
  Future<PlaybackEvent> _recoverLink(
    Track track,
    PlaybackFailure failure,
  ) async {
    final used = _linkRetries[track.id] ?? 0;

    if (used >= maxLinkRetries) {
      _linkRetries.remove(track.id);
      _tickets.invalidate(track.id);
      return _skip(track, '直链反复失效（已重试 $used 次）：${failure.message}');
    }

    _linkRetries[track.id] = used + 1;
    _tickets.invalidate(track.id);

    // 关键：记住中断位置。不记住的话每次续链都从头播，
    // 一首长曲子只要跨过一次签名过期就永远听不完。
    //
    // ⚠️ 这里取的是 `_output.position`（**整轨文件内的绝对位置**），
    // 不是对外那个「相对本曲目」的 [position]。分段曲目续链时必须
    // 回到文件里的那个绝对点，回到「本轨第 83 秒」会变成回到文件开头。
    final resumeAt = _output.position;

    _emit(PlaybackEvent(
      type: PlaybackEventType.resumed,
      track: track,
      message: '直链已过期，正在续播',
    ));

    return _loadAndPlay(
      track,
      from: resumeAt,
      forceRefreshTicket: true,
      countAsPlay: false,
    );
  }

  Future<void> _onCompleted() async {
    if (_disposed || !_sourceReady) return;
    final task = _handleCompleted();
    _pendingTask = task;
    try {
      await task;
    } finally {
      _pendingTask = null;
    }
  }

  Future<void> _handleCompleted() async {
    final track = queue.current;
    if (track == null) return;
    // 收尾开始，先关闸门：接下来到新曲目装载完成为止，任何完成事件
    // 都属于这一首，不去重就会连跳两首。
    _sourceReady = false;
    _enteredSegment = false;
    await _advanceAfterTrackEnd(track);
  }

  /// 整轨绝对位置 → 先广播**曲目相对**位置（界面/歌词用），再做分段到点切歌。
  ///
  /// 分段到点逻辑用的是绝对坐标，所以这里把 [absolute] 原样交给 [_onPosition]，
  /// 而广播出去的是减掉本轨起点的相对值。
  void _onPositionTick(Duration absolute) {
    if (!_disposed) _trackPosition.add(_relativePosition(absolute));
    _onPosition(absolute);
  }

  /// 整轨时长 → 广播**曲目相对**时长（分段已是单轨时长，不广播整轨 72 分钟）。
  void _onDurationTick(Duration? total) {
    if (!_disposed) _trackDuration.add(_relativeDuration(total));
  }

  /// 位置变化：整轨分段「放到本轨终点就切下一首」。
  ///
  /// 为什么必须做这件事：一个 72 分钟的整轨文件，切成 15 首之后每首只有
  /// 三四分钟。不按 `cueEndMs` 切，用户点第 2 首会一路听完整张专辑 ——
  /// 那和不支持 CUE 没区别。
  ///
  /// [absolute] 是播放器报的**整轨文件内绝对位置**。
  Future<void> _onPosition(Duration absolute) async {
    if (_disposed || !_sourceReady || !_isPlaying) return;

    final track = queue.current;
    if (track == null || !track.isCueSegment) {
      _enteredSegment = false;
      return;
    }
    final end = track.cueEndMs;
    if (end == null) return; // 终点未知（整轨时长缺失），只能放到文件结束

    if (absolute.inMilliseconds < end) {
      // 位置落在本轨区间内 —— 从这一刻起「到达终点」才可信
      _enteredSegment = true;
      return;
    }
    if (!_enteredSegment) return; // 还没进过本轨，判定为上一首的残留事件

    _sourceReady = false;
    _enteredSegment = false;
    diag.info(
      '播放',
      '分段到点（${absolute.inMilliseconds}ms ≥ ${end}ms），切下一首',
    );

    final task = _advanceAfterTrackEnd(track);
    _pendingTask = task;
    try {
      await task;
    } finally {
      _pendingTask = null;
    }
  }

  /// 一首「结束」了 —— **自然播完与整轨分段到点共用**。
  ///
  /// 两条路径必须共用：对整轨的最后一轨，`cueEndMs` 恰好等于文件结尾，
  /// 位置监听与播放器的 completed 事件几乎同时到达；走同一段代码
  /// 才能靠 [_sourceReady] 一次性去重，否则会连跳两首。
  Future<void> _advanceAfterTrackEnd(Track track) async {
    _emit(PlaybackEvent(type: PlaybackEventType.completed, track: track));

    if (queue.mode == PlaybackMode.repeatOne) {
      // 重播走票据缓存：票据大概率还有效，没必要再消耗一次取链配额。
      // 对分段曲目，_loadAndPlay 会把播放头重新放回本轨起点。
      await _loadAndPlay(track);
      return;
    }
    await next();
  }

  PlaybackEvent _emit(PlaybackEvent event) {
    if (!_events.isClosed) _events.add(event);
    return event;
  }
}

/// 取链结果：区分「命中缓存」与「走了网络」，便于诊断与统计配额消耗。
class StreamTicketResult {
  const StreamTicketResult(this.ticket, {required this.fromCache});

  final StreamTicket ticket;

  /// `true` 表示命中票据缓存，没有消耗网盘取链配额
  final bool fromCache;

  @override
  String toString() => 'StreamTicketResult(${fromCache ? "缓存" : "网络"}, '
      '${ticket.redactedUrl})';
}
