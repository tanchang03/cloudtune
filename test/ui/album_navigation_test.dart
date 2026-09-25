import 'dart:typed_data';

import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/domain/entities/album_cover.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/library_grouping.dart';
import 'package:cloudtune/ui/pages/album_page.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/auth_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/router/app_router.dart';
import 'package:cloudtune/ui/shell/app_shell.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/album_grid.dart';
import 'package:cloudtune/ui/widgets/player_bar.dart';
import 'package:cloudtune/ui/widgets/track_explorer.dart';
import 'package:cloudtune/ui/widgets/track_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/window_metrics.dart';

/// 专辑视图的**导航接线**回归测试。
///
/// 卡片墙与详情页各自的渲染已经在 `layout_overflow_test.dart` 里覆盖了，
/// 但那里是**直接构造**这两个组件 —— 中间少了两段真实的接线：
///
///   1. `TrackExplorer` 切到「专辑」时渲染的到底是卡片墙还是曲目列表；
///   2. 卡片推送的地址能不能把**目录路径原样带回来**。
///
/// 第 2 条是最危险的一处。专辑键是目录路径：本身带 `/`，还要带中文、空格、
/// `[` `]`。编码与解析只要有一边不对称，`dir` 就会变成空串 ——
/// 用户看到的是「这张专辑现在是空的」，一个**看起来像数据问题**的显示 bug，
/// 而库里其实一首歌都没少。所以这里不 mock 路由，用真实 go_router 走一遍。
void main() {
  // 真实库里的两种形状：普通专辑，以及带空格与连字符的最长那类目录名
  const popDir = '/音乐/华语/周杰伦/叶惠美';
  const compDir = '/音乐/合辑/贵族音乐 - 睡眠轻音乐 钢琴与小提琴 雨夜催眠曲';
  const compTitle = '睡眠轻音乐 钢琴与小提琴 雨夜催眠曲';

  Track trackIn(String dir, String id, String title, String artist) => Track(
        provider: DriveProvider.quark,
        remoteId: id,
        name: '$title.flac',
        path: '$dir/',
        sizeBytes: 30 * 1024 * 1024,
        title: title,
        artist: artist,
        durationMs: 250000,
      );

  final tracksByDir = <String, List<Track>>{
    popDir: [
      trackIn(popDir, 'p1', '以父之名', '周杰伦'),
      trackIn(popDir, 'p2', '晴天', '周杰伦'),
    ],
    compDir: [
      trackIn(compDir, 'c1', '雨夜', '贵族音乐'),
      trackIn(compDir, 'c2', '催眠曲', '某位女声'),
    ],
  };

  final allTracks = [for (final list in tracksByDir.values) ...list];

  final tracksProvider =
      FutureProvider.autoDispose<List<Track>>((ref) async => allTracks);

  _FakeLibrary fakeLibrary() => _FakeLibrary(
        tracksByDir: tracksByDir,
        covers: {
          popDir: const AlbumCover(
            provider: DriveProvider.quark,
            dirPath: popDir,
            fileId: 'img-pop',
            fileName: 'cover.jpg',
            sizeBytes: 820 * 1024,
          ),
        },
      );

  /// 真实路由表要跑起来必须有「已授权」的账号，否则 `redirect` 会把我们
  /// 赶回 `/auth`。这里给一个最小账号，不碰任何网络。
  List<Override> commonOverrides() => [
        libraryProvider.overrideWithValue(fakeLibrary()),
        playerProvider.overrideWith(_StubPlayer.new),
        favoriteIdsProvider.overrideWith((ref) => <String>{}),
        // 字节一律给 null：测试里不解码真图（解码要 runAsync 才走得完）
        coverBytesProvider.overrideWith(
          (ref, cover) => Future<Uint8List?>.value(null),
        ),
        playbackPositionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
        playbackDurationProvider.overrideWith((ref) => Stream.value(null)),
        playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
      ];

  /// 推进若干帧。
  ///
  /// 刻意**不用 `pumpAndSettle`**：页面上只要有 `CircularProgressIndicator`
  /// 就是个永不结束的动画，`pumpAndSettle` 会一直等到超时。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('专辑视图的导航接线', () {
    /// 用**测试自己的路由表**渲染真实的 `TrackExplorer`，把 `push` 到的地址
    /// 记下来。生产路由表在下一个 group 里单独验。
    late List<Uri> opened;

    Future<void> pumpExplorer(
      WidgetTester tester, {
      Size size = const Size(1280, 800),
    }) async {
      opened = <Uri>[];

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: TrackExplorer(
                tracksProvider: tracksProvider,
                filterProvider: libraryFilterProvider,
                emptyTitle: '还没有曲目',
                emptyMessage: '先去扫描网盘',
              ),
            ),
          ),
          GoRoute(
            path: '/album',
            builder: (_, state) {
              opened.add(state.uri);
              return const Scaffold(body: Text('专辑详情页占位'));
            },
          ),
        ],
      );

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(),
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('默认是曲目列表，切到「专辑」才换成封面卡片墙', (tester) async {
      await pumpExplorer(tester);

      expect(
        find.byType(TrackGroupListView),
        findsOneWidget,
        reason: '「列表」是默认视图，不该一进来就是卡片墙',
      );
      expect(find.byType(AlbumGridView), findsNothing);

      await tester.tap(find.text(LibraryGroupMode.album.label));
      await settle(tester);

      expect(find.byType(AlbumGridView), findsOneWidget);
      expect(
        find.byType(TrackGroupListView),
        findsNothing,
        reason: '两个视图不能同时挂着 —— 会各画一份、还互相抢滚动',
      );
      // 列表头仍然在（搜索框 / 筛选 / 分组切换两种视图共用）
      expect(find.text('随机播放'), findsOneWidget);
    });

    testWidgets('点卡片推送 /album，目录路径经 query 原样带回', (tester) async {
      await pumpExplorer(tester);
      await tester.tap(find.text(LibraryGroupMode.album.label));
      await settle(tester);

      await tester.tap(find.text(compTitle));
      await settle(tester);

      expect(opened, hasLength(1), reason: '点一下只该跳一层');
      final uri = opened.single;
      expect(uri.path, '/album');
      expect(
        uri.queryParameters['dir'],
        compDir,
        reason: '目录路径带 `/`、中文、空格，编码与解析必须对称；'
            '拿回来是空串的话用户会看到「这张专辑现在是空的」',
      );
      expect(
        uri.queryParameters['title'],
        compTitle,
        reason: '专辑名要一起带过去 —— 卡片上的是消歧后的名字，详情页算不出来',
      );
    });

    testWidgets('点卡片上的播放键不会跳走：它是「直接放这张」', (tester) async {
      final player = _RecordingPlayer();
      final openedByCard = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWithValue(fakeLibrary()),
            playerProvider.overrideWith(() => player),
            favoriteIdsProvider.overrideWith((ref) => <String>{}),
            coverBytesProvider.overrideWith(
              (ref, cover) => Future<Uint8List?>.value(null),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: AlbumGridView(
                groups: LibraryGrouping.group(allTracks, LibraryGroupMode.album),
                onOpen: (group) => openedByCard.add(group.key),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      // 播放键悬停才可点（`IgnorePointer(ignoring: !visible)`），
      // 所以先把鼠标移到**卡片上**再点 —— 移到网格空白处是进不了卡片的
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('叶惠美')));
      await settle(tester);

      await tester.tap(find.byTooltip('播放这张专辑').first);
      await settle(tester);

      expect(player.plays, hasLength(1));
      expect(
        player.plays.single.queue,
        hasLength(2),
        reason: '队列是这一整张专辑',
      );
      expect(
        openedByCard,
        isEmpty,
        reason: '播放键是「放这张专辑」，不该同时把用户带进详情页',
      );
    });

    testWidgets('窄窗口下卡片墙不溢出', (tester) async {
      await pumpExplorer(tester, size: const Size(600, 800));
      await tester.tap(find.text(LibraryGroupMode.album.label));
      await settle(tester);

      expect(find.byType(AlbumGridView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('生产路由表的 /album 路由', () {
    /// 用窗口的**默认尺寸**（`kDefaultWindowSize`，也就是允许的最小尺寸）。
    ///
    /// 之前这里用的是 900 宽（窄屏外壳），目的是绕开侧栏品牌行那条溢出噪声：
    /// `AppLogo` 27 + 9 + `Text('CloudTune')` 在**测试字体**下要 164.3px、
    /// 可用只有 161px。测试字体每个字符都是满 em 方块（`'CloudTune'` 量出来
    /// 128.3px），真实字体 PingFang SC 下只有 ~78px。那条溢出已经修掉了
    /// （品牌名改成 `Expanded` + 省略号，见 `app_shell_layout_test.dart`），
    /// 所以现在可以按真实窗口尺寸来测，不用再退到窄屏。
    ///
    /// 另外：`/album` 是**顶级全屏路由**，它显示时外壳根本不在树上 ——
    /// 所以外壳走宽屏还是窄屏，与专辑详情页无关。专辑页自己的宽/窄分支
    /// 由 `layout_overflow_test.dart` 覆盖。
    Future<void> pumpApp(
      WidgetTester tester, {
      Size size = kDefaultWindowSize,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_StubAuth.new),
          ...commonOverrides(),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: container.read(routerProvider),
          ),
        ),
      );
      await settle(tester);
    }

    GoRouter routerOf(WidgetTester tester) {
      final scope = tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope),
      );
      return scope.container.read(routerProvider);
    }

    testWidgets('/album?dir=… 打开的就是那一张专辑', (tester) async {
      await pumpApp(tester);

      routerOf(tester).go(
        '/album?dir=${Uri.encodeComponent(compDir)}'
        '&title=${Uri.encodeComponent(compTitle)}',
      );
      await settle(tester);

      expect(find.byType(AlbumPage), findsOneWidget);
      expect(find.text(compTitle), findsOneWidget);
      expect(
        find.text('雨夜'),
        findsOneWidget,
        reason: '详情页按 dir 查曲目 —— 查不到就说明 query 参数没接上',
      );
      expect(find.text('催眠曲'), findsOneWidget);
      expect(find.text('2 首 · 8:20 · 60.0 MB'), findsOneWidget);
    });

    testWidgets('缺 dir 时不崩：显示空专辑而不是白屏', (tester) async {
      await pumpApp(tester);

      routerOf(tester).go('/album');
      await settle(tester);

      expect(find.byType(AlbumPage), findsOneWidget);
      expect(find.text('这张专辑现在是空的'), findsOneWidget);
      expect(
        find.byTooltip('返回'),
        findsOneWidget,
        reason: '空专辑页也得走得掉',
      );
    });

    /// 用户报的 bug：在专辑页点播放，页面上看不到播放栏，退回曲库才看到。
    ///
    /// 根因不是「播放栏画错了」，而是**这一页根本没有播放栏**：`/album` 是
    /// 顶级全屏路由，`AppShell` 不在树上，而播放栏是外壳的一部分。
    /// 所以断言要同时盯两头 —— 外壳确实不在（否则下面那条是外壳给的，
    /// 等于没测到），而播放栏确实在。
    testWidgets('播放栏在专辑页上也在 —— 外壳不在树上也照样有', (tester) async {
      await pumpApp(tester);

      routerOf(tester).go('/album?dir=${Uri.encodeComponent(compDir)}');
      await settle(tester);

      expect(find.byType(AlbumPage), findsOneWidget);
      expect(
        find.byType(AppShell),
        findsNothing,
        reason: '/album 是顶级全屏路由 —— 外壳不在树上，它的播放栏自然也没了',
      );
      expect(
        find.byType(PlayerBar),
        findsOneWidget,
        reason: '全屏页要自己挂播放栏。少了它，从这一页点播放就是'
            '「歌响了，但界面上找不到暂停键、进度和当前曲目」',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('播放栏贴在窗口最底边，不被内容顶走', (tester) async {
      await pumpApp(tester);

      routerOf(tester).go('/album?dir=${Uri.encodeComponent(compDir)}');
      await settle(tester);

      final windowHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final bar = tester.getRect(find.byType(PlayerBar));

      expect(bar.height, AppTheme.playerBarHeight);
      expect(
        bar.bottom,
        moreOrLessEquals(windowHeight, epsilon: 0.5),
        reason: '「固定在底部」意味着它的下沿就是窗口下沿；'
            '底下留出空隙说明它被内容挤上去了',
      );
    });
  });
}

/// 只实现这几个测试真的会用到的方法。
///
/// 其余成员交给 `noSuchMethod` —— 页面一旦去调它们，测试会立刻炸出来，
/// 比悄悄返回一个默认值安全得多（那会让「忘了接线」看起来像「功能正常」）。
class _FakeLibrary implements LibraryRepository {
  _FakeLibrary({required this.tracksByDir, this.covers = const {}});

  final Map<String, List<Track>> tracksByDir;
  final Map<String, AlbumCover> covers;

  @override
  Future<List<Track>> queryTracks([TrackQuery query = const TrackQuery()]) async {
    final dir = query.dirPath;
    if (dir != null) return tracksByDir[dir] ?? const [];
    return [for (final list in tracksByDir.values) ...list];
  }

  @override
  Future<Map<String, AlbumCover>> albumCovers(DriveProvider provider) async =>
      covers;

  @override
  Future<Set<String>> favoriteIds() async => <String>{};

  @override
  Future<LibraryStats> stats({DriveProvider? provider}) async =>
      LibraryStats.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 已授权的最小账号，让真实路由表的 `redirect` 放行到 `/library`。
class _StubAuth extends AuthController {
  @override
  Future<AuthState> build() async => AuthState(
        account: CloudAccount(
          provider: DriveProvider.quark,
          authMode: AuthMode.qrCode,
          authorizedAt: DateTime(2026, 9, 25),
          displayName: '测试账号',
        ),
      );
}

/// 记录 `playFrom` 的调用，用来断言「播放键放的是整张专辑」。
class _RecordingPlayer extends PlayerNotifier {
  final List<({List<Track> queue, Track start})> plays = [];

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playFrom(List<Track> tracks, Track selected) async {
    plays.add((queue: List.of(tracks), start: selected));
  }
}

class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
