import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/adapters/library_repository.dart';
import '../../domain/entities/album_cover.dart';
import '../../domain/entities/drive_provider.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../../domain/services/playability_resolver.dart';
import '../../domain/services/shuffle_engine.dart';
import 'app_providers.dart';

/// 曲库列表的可见范围。
///
/// 刻意**不提供「不可播」这一档**：本应用已经改用 `/file/audioplay` 取链，
/// 绝大多数文件都能播，专门给用户一个「不可播」清单只会让人以为文件坏了。
/// 真正取不到地址的极少数曲目，行内徽标会说明原因（点开有解释），
/// 扫描页的「可播性体检」也照旧统计 —— 但不做成一个浏览分类。
enum LibraryScope {
  all('全部', null),
  playable('可播', true);

  const LibraryScope(this.label, this.playableOnly);

  final String label;

  /// 传给 `TrackQuery.playableOnly`：`null` 表示不限
  final bool? playableOnly;
}

/// 曲库当前接入的网盘。
///
/// 目前只有夸克，但**不要在页面里直接写 `DriveProvider.quark`** ——
/// 曲库查询、专辑封面查询、专辑详情页都要用同一个值，
/// 散落的字面量在接第二家网盘时会变成「有的地方改了有的地方没改」。
const DriveProvider kLibraryProvider = DriveProvider.quark;

/// 曲库筛选条件（纯 UI 态，不落库）。
class LibraryFilter {
  const LibraryFilter({
    this.keyword = '',
    this.scope = LibraryScope.all,
    this.sort = TrackSort.nameAsc,
    this.group = LibraryGroupMode.none,
    this.favoritesOnly = false,
  });

  final String keyword;
  final LibraryScope scope;
  final TrackSort sort;

  /// 浏览方式（平铺 / 按艺术家 / 按专辑）。
  ///
  /// 它是**视图态**而不是查询条件 —— [toQuery] 不会用到它，
  /// 分组在渲染前由 `LibraryGrouping` 现算。放在这里只是为了
  /// 曲库页与收藏页各自独立地记住自己的选择。
  final LibraryGroupMode group;

  final bool favoritesOnly;

  LibraryFilter copyWith({
    String? keyword,
    LibraryScope? scope,
    TrackSort? sort,
    LibraryGroupMode? group,
    bool? favoritesOnly,
  }) {
    return LibraryFilter(
      keyword: keyword ?? this.keyword,
      scope: scope ?? this.scope,
      sort: sort ?? this.sort,
      group: group ?? this.group,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }

  /// 转成仓储层查询条件。
  TrackQuery toQuery() {
    final trimmed = keyword.trim();
    return TrackQuery(
      provider: kLibraryProvider,
      keyword: trimmed.isEmpty ? null : trimmed,
      playableOnly: scope.playableOnly,
      favoritesOnly: favoritesOnly,
      sort: sort,
      // 单机音乐库规模有限，一次性取回即可；真到十万级再改成分页加载
      limit: 2000,
    );
  }
}

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void setKeyword(String value) => state = state.copyWith(keyword: value);

  void setScope(LibraryScope scope) => state = state.copyWith(scope: scope);

  void setSort(TrackSort sort) => state = state.copyWith(sort: sort);

  void setGroup(LibraryGroupMode group) => state = state.copyWith(group: group);

  void reset() => state = const LibraryFilter();
}

/// 收藏页专用：默认只看收藏，其余筛选能力与曲库页一致。
class FavoritesFilterNotifier extends LibraryFilterNotifier {
  @override
  LibraryFilter build() => const LibraryFilter(favoritesOnly: true);
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
  LibraryFilterNotifier.new,
);

final favoritesFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
  FavoritesFilterNotifier.new,
);

/// 曲库列表。
final libraryTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return ref.watch(libraryProvider).queryTracks(filter.toQuery());
});

/// 收藏列表。
final favoritesTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) {
  final filter = ref.watch(favoritesFilterProvider);
  return ref.watch(libraryProvider).queryTracks(filter.toQuery());
});

/// 收藏曲目 id 集合。
///
/// 刻意**不随曲库列表失效**：切换收藏只需要重算这一个集合，
/// 不必把整张列表重新查一遍。
final favoriteIdsProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(libraryProvider).favoriteIds(),
);

final libraryStatsProvider = FutureProvider.autoDispose<LibraryStats>(
  (ref) => ref.watch(libraryProvider).stats(provider: kLibraryProvider),
);

final playabilitySummaryProvider =
    FutureProvider.autoDispose<PlayabilitySummary>(
  (ref) =>
      ref.watch(libraryProvider).playabilitySummary(provider: kLibraryProvider),
);

// ---------------------------------------------------------------------------
// 专辑封面
// ---------------------------------------------------------------------------

/// 全部专辑封面，按**目录路径**索引 —— 与 `TrackGroup.key`（专辑分组时）
/// 是同一个键，所以卡片墙能直接 `covers[group.key]` 取到。
///
/// 一次查全表（几百行）而不是每张卡片查一次：专辑网格一屏就有几十张卡片，
/// 逐个查会把「渲染一屏」变成几十次 SQL。曲库规模有限，一次取回更划算。
final albumCoversProvider = FutureProvider.autoDispose<Map<String, AlbumCover>>(
  (ref) => ref.watch(libraryProvider).albumCovers(kLibraryProvider),
);

/// 一张封面的字节。取不到是 `null`（调用方回退占位），不是错误。
///
/// family 的键是 [AlbumCover] 本身，它的 `==` 基于 `provider:fileId` ——
/// 同一张图被两张专辑引用时只会取一次。
final coverBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, AlbumCover>(
  (ref, cover) => ref.watch(albumCoverCacheProvider).load(cover),
);

/// 某张专辑（目录）的全部曲目，按文件名 / CUE 轨号排序。
///
/// 用**目录**而不是专辑名去查：专辑名是从目录名猜的，两张同名专辑
/// （`... [16B-44.1kHz]` 与 `... [24B-48kHz]`）会混在一起，
/// 而用户点开的显然是其中一张。
final albumTracksProvider =
    FutureProvider.autoDispose.family<List<Track>, String>((ref, dirPath) {
  return ref.watch(libraryProvider).queryTracks(
        TrackQuery(
          provider: kLibraryProvider,
          dirPath: dirPath,
          limit: 2000,
        ),
      );
});

/// 随机播放权重（播放次数 / 最近播放时间）。
final shuffleWeightsProvider =
    FutureProvider.autoDispose<Map<String, ShuffleCandidate>>(
  (ref) => ref.watch(libraryProvider).shuffleCandidates(),
);

/// 收藏的读写入口。
///
/// 写成 provider 而不是直接调仓储，是为了把「改完要刷新哪些 provider」
/// 这件事收在一处 —— 散落在各个页面里迟早会漏掉某一个。
class FavoriteActions {
  FavoriteActions(this._ref);

  final Ref _ref;

  Future<void> toggle(String trackId, {required bool value}) async {
    await _ref.read(libraryProvider).setFavorite(trackId, value: value);
    _ref.invalidate(favoriteIdsProvider);
    _ref.invalidate(favoritesTracksProvider);
    _ref.invalidate(libraryStatsProvider);
  }
}

final favoriteActionsProvider =
    Provider<FavoriteActions>(FavoriteActions.new);
