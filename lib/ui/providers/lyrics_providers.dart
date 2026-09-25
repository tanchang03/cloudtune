import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../data/db/settings_store.dart';
import '../../data/lyrics/lrclib_client.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/lyrics_resolver.dart';
import 'app_providers.dart';

/// LRCLIB 客户端。
///
/// 与网盘适配器共用同一个 [httpClientProvider]：它已经带上了超时、
/// 「非 2xx 不抛异常」与诊断日志，没有理由为歌词另起一套。
final lrclibClientProvider = Provider<LrclibClient>(
  (ref) => LrclibClient(http: ref.watch(httpClientProvider)),
);

/// 播放时的歌词解析器。
final lyricsResolverProvider = Provider<LyricsResolver>(
  (ref) => LyricsResolver(
    library: ref.watch(libraryProvider),
    registry: ref.watch(adapterRegistryProvider),
    lrclib: ref.watch(lrclibClientProvider),
  ),
);

/// 「联网获取歌词」开关。**默认关闭**，用户明确打开后才生效。
///
/// 用 [AsyncNotifier] 而不是同步的 `Notifier`：取值要读一次数据库，
/// 而「读完了没有」这件事必须能被界面区分 —— 一个同步的 `Notifier` 只能
/// 先给个默认值再偷偷改掉，那会让开关在界面上闪一下。
class LyricsNetworkSetting extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return await ref
          .watch(settingsStoreProvider)
          .readBool(SettingKeys.lyricsNetworkEnabled);
    } catch (e) {
      // 拿不到设置（库没打开、测试里没注入）时**按默认（关闭）处理**。
      // 联网歌词是默认关闭的能力，退回关闭永远是对的；
      // 而让一个读设置失败把播放界面搞崩是完全不成比例的。
      diag.warn('歌词', '读联网歌词设置失败，按默认（关闭）处理', error: e);
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    // 先等 build 完成，再改状态。
    //
    // 反过来的顺序（先乐观地 `state = AsyncData(value)` 再写库）有个真实后果：
    // 如果这时候 build 的异步读还没回来，它**拿到的是写之前的旧值**，
    // 回来之后会把我们刚设的状态又盖回旧值 —— 用户看到的现象是
    // 「开关点开了，一松手自己又弹回去」，而库里其实已经写成了新值。
    // 界面与存储就此不一致，且只有重启才能纠正。
    try {
      await future;
    } catch (e) {
      // build 内部已经兜住异常（读不到设置就返回 false），这里只是为了
      // 万一它抛出来时不要让赋值被跳过
      diag.warn('歌词', '等待联网歌词设置初始化失败', error: e);
    }
    try {
      await ref
          .read(settingsStoreProvider)
          .writeBool(SettingKeys.lyricsNetworkEnabled, value: value);
    } catch (e) {
      diag.warn('歌词', '写联网歌词设置失败', error: e);
    }
    // 写库失败也照样更新状态：这次会话里用户看到的就是他点的那样，
    // 下次启动会退回默认值 —— 而不是「点了没反应」。
    state = AsyncData(value);
    diag.info('歌词', '联网获取歌词已${value ? "开启" : "关闭"}');
  }
}

final lyricsNetworkEnabledProvider =
    AsyncNotifierProvider<LyricsNetworkSetting, bool>(
  LyricsNetworkSetting.new,
);

/// 某首曲目的歌词。**播放时才算**。
///
/// family 的键是 [Track] 本身（它的 `==` 基于 `id`），所以切歌时 Riverpod
/// 会自动为新的曲目建一个实例，旧的随 `autoDispose` 走掉。
///
/// 这一层刻意**不缓存到 provider 之外**：歌词的缓存就是数据库里那一行，
/// provider 只是「当前这首」的视图。离开播放页再回来会重新查一次库 ——
/// 一次带主键的 SQL 读，代价可以忽略，换来的是「读到的永远是最新的」。
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, Track>(
  (ref, track) {
    // 联网开关是**依赖**而不是快照：用户在看播放页时把开关打开，
    // 这一首应当立刻重算（从「没歌词」变成去联网查）。
    final allowNetwork =
        ref.watch(lyricsNetworkEnabledProvider).valueOrNull ?? false;
    return ref
        .watch(lyricsResolverProvider)
        .resolve(track, allowNetwork: allowNetwork);
  },
);

/// 歌词覆盖情况，给设置页看。
class LyricsStats {
  const LyricsStats({required this.total, required this.loaded});

  /// 索引里有歌词记录的曲目数（本地 `.lrc` 引用 + 联网取到的）。
  final int total;

  /// 其中**正文已经在本地**、下次播放不用再取的那些。
  final int loaded;

  /// 已找到 `.lrc`、但正文要等第一次播放时才去读的那部分。
  int get pending => total - loaded;

  bool get isEmpty => total == 0;
}

/// 歌词统计。两个数字读的是同一张表，只是口径不同。
///
/// 为什么要分开显示：「有歌词」和「能立刻显示歌词」不是一回事 ——
/// 扫描只记「哪首歌对应哪个 `.lrc`」，正文是第一次播放时才读的
/// （见 `LyricsResolver`）。只报一个总数，用户会以为全部都能立刻看到。
final lyricsStatsProvider = FutureProvider.autoDispose<LyricsStats>((ref) async {
  final library = ref.watch(libraryProvider);
  return LyricsStats(
    total: await library.lyricsCount(),
    loaded: await library.lyricsCount(loadedOnly: true),
  );
});
