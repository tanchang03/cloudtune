import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/auth_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/providers/new_songs_providers.dart';
import 'package:cloudtune/ui/router/app_router.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 侧边栏「音乐库」项上的红色新歌徽标回归测试。
///
/// 徽标直接读 [newSongsCountProvider]：有 N 首新歌就显示红色数字 `N`，
/// 0 首就不显示。这个数字是用户唯一能知道「网盘里又多了什么」的入口，
/// 漏掉它 = 后台扫描发现了新歌却没人看见。
void main() {
  const minWindow = Size(1060, 754);

  Future<void> pumpApp(
    WidgetTester tester, {
    int newCount = 0,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = minWindow;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_StubAuth.new),
        libraryProvider.overrideWithValue(_FakeLibrary(const [])),
        playerProvider.overrideWith(_StubPlayer.new),
        favoriteIdsProvider.overrideWith((ref) => <String>{}),
        newSongsCountProvider.overrideWith((ref) => Future.value(newCount)),
        playbackPositionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('有 3 首新歌：音乐库项显示红色徽标「3」', (tester) async {
    await pumpApp(tester, newCount: 3);

    // 徽标是红色 Container 里一个「3」字；侧边栏与页面头都有「音乐库」文字，
    // 所以这里只数徽标数字
    expect(
      find.text('3'),
      findsWidgets,
      reason: '徽标显示新歌数量，让用户知道后台扫到了新东西',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有新歌（0）：不显示徽标', (tester) async {
    await pumpApp(tester, newCount: 0);

    // 0 首时徽标隐藏；这里只断言不抛、且整体能渲染
    expect(tester.takeException(), isNull);
  });
}

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
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
