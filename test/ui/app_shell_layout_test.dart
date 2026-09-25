import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/domain/entities/album_cover.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/auth_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/router/app_router.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/window_metrics.dart';

/// 窗口尺寸下限的回归测试。
///
/// 界面是按桌面宽度排的（左侧 196pt 侧栏 + 主区），所以**窗口不允许被拖到比
/// 默认尺寸更小**。下限本身在原生侧设（`MainFlutterWindow.applyMinimumSize`，
/// 由 `test/macos/min_window_size_test.dart` 守），这里守的是另一半：
/// **在允许的最小尺寸下，界面真的不溢出**。
///
/// 两边都要测，是因为下限设错在原生侧完全看不出来 —— 把 `contentMinSize`
/// 设成 800 一样能构建、能运行，只有把界面按那个尺寸渲染一遍才会发现挤爆了。
void main() {
  // 窗口的默认尺寸，也就是允许的最小尺寸。定义在 `test/support/window_metrics.dart`，
  // 与原生侧守卫测试共用同一个数 —— 分头写两份字面量的话，改 xib 时只会有
  // 一边失败，另一边会拿着过期尺寸继续「通过」。
  const minWindow = kDefaultWindowSize;

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

  const popDir = '/音乐/华语/周杰伦/叶惠美';

  final tracks = [
    trackIn(popDir, 'p1', '以父之名', '周杰伦'),
    trackIn(popDir, 'p2', '晴天', '周杰伦'),
  ];

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = minWindow,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_StubAuth.new),
        libraryProvider.overrideWithValue(_FakeLibrary(tracks)),
        playerProvider.overrideWith(_StubPlayer.new),
        favoriteIdsProvider.overrideWith((ref) => <String>{}),
        playbackPositionProvider
            .overrideWith((ref) => Stream.value(Duration.zero)),
        playbackDurationProvider.overrideWith((ref) => Stream.value(null)),
        playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
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
    // 刻意不用 `pumpAndSettle`：启动页有个永不结束的进度圈
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('窗口最小尺寸下的外壳布局', () {
    testWidgets('默认尺寸（1060×754）：宽屏外壳不溢出', (tester) async {
      await pumpApp(tester);

      expect(
        find.byType(AppLogo),
        findsOneWidget,
        reason: '1060 宽 ≥ 宽屏断点 1000，走的应该是带侧栏的宽屏外壳',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '这是允许的最小窗口 —— 如果这里就挤爆了，下限设小了',
      );
    });

    testWidgets('系统字号 1.6 倍：侧栏品牌名省略而不是撑破侧栏', (tester) async {
      await pumpApp(tester, textScale: 1.6);

      // 品牌行总宽 = 侧栏 196 − 容器内边距 11×2 − 右边框 1 − 品牌内边距 6×2 = 161。
      // 这一行里 logo 和间距是固定的，品牌名能拿到的只有剩下的那点。
      const rowBudget = AppTheme.sidebarWidth - 11 * 2 - 1 - 6 * 2;
      const fixed = 27.0 /* AppLogo */ + 9.0 /* SizedBox */;
      expect(
        tester.getSize(find.text('CloudTune')).width,
        lessThanOrEqualTo(rowBudget - fixed),
        reason: '侧栏宽度写死，品牌名是这一行里唯一能伸缩的东西。'
            '没有 Expanded + 省略号的话，放大字号时文字会按自己的自然宽度'
            '（测试字体下 203.8px）铺开，把这一行顶出去',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '品牌行溢出会把侧栏撑宽，连带把主区挤窄',
      );
    });

    testWidgets('窄于下限（900）时退成窄屏外壳，也不溢出', (tester) async {
      await pumpApp(tester, size: const Size(900, 800));

      expect(
        find.byType(AppLogo),
        findsNothing,
        reason: '窄屏外壳是底部导航栏，没有侧栏',
      );
      expect(tester.takeException(), isNull);
    });
  });
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

class _FakeLibrary implements LibraryRepository {
  _FakeLibrary(this.tracks);

  final List<Track> tracks;

  @override
  Future<List<Track>> queryTracks([TrackQuery query = const TrackQuery()]) async =>
      query.dirPath == null ? tracks : const [];

  @override
  Future<Map<String, AlbumCover>> albumCovers(DriveProvider provider) async =>
      const {};

  @override
  Future<Set<String>> favoriteIds() async => <String>{};

  @override
  Future<LibraryStats> stats({DriveProvider? provider}) async =>
      LibraryStats.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
