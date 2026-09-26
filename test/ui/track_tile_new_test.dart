import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/settings_store.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/track_tile.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 曲目标题上的「新」标签回归测试。
///
/// 「新不新」完全由 [Track.firstSeenAt] 与水位 [newSongsSeenAtProvider] 决定：
///   - 水位为 `null`（升级后第一次启动、基线还没建立）→ 整库都不标新，
///     否则老用户一打开整库都是红点，毫无意义；
///   - `firstSeenAt` 晚于水位 → 标「新」；
///   - `firstSeenAt` 早于水位（已经看完这批新歌）→ 不标。
///
/// 这三个分支只有渲染出来才测得到，所以放 widget 测试。
void main() {
  final track = Track(
    provider: DriveProvider.quark,
    remoteId: 'a1',
    name: '新歌.flac',
    title: '新歌',
    artist: '某歌手',
    durationMs: 200000,
    firstSeenAt: DateTime(2026, 9, 25, 12, 0, 0),
  );

  /// 用假存储钉住水位，避免去碰真实数据库。
  Future<void> pumpTile(WidgetTester tester, {DateTime? watermark}) async {
    _FakeStore.seenAt = watermark;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWith((ref) => _FakeStore()),
          favoriteIdsProvider.overrideWith((ref) => <String>{}),
          playerProvider.overrideWith(_StubPlayer.new),
          playbackPositionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          playbackDurationProvider.overrideWith((ref) => Stream.value(null)),
          playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: TrackTile(
                track: track,
                capabilities: const Capabilities(provider: DriveProvider.quark),
                onPlay: () {},
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('水位未建立（null）：即使是新进库的歌也不标「新」', (tester) async {
    await pumpTile(tester, watermark: null);

    expect(
      find.text('新'),
      findsNothing,
      reason: '基线还没建立时如果标新，老用户升级后会看到整库红点，毫无意义',
    );
  });

  testWidgets('水位早于进库时间：标「新」', (tester) async {
    await pumpTile(tester, watermark: DateTime(2026, 9, 20));

    expect(find.text('新'), findsOneWidget);
  });

  testWidgets('水位晚于进库时间（已看完）：不标「新」', (tester) async {
    await pumpTile(tester, watermark: DateTime(2026, 9, 30));

    expect(find.text('新'), findsNothing);
  });
}

/// 把「新歌水位」钉成一个可控的值，不碰真实数据库。
class _FakeStore extends SettingsStore {
  _FakeStore() : super(AppDatabase(NativeDatabase.memory()));

  /// 由 pumpTile 在每次 pump 前设定，控制整轮测试里的水位。
  static DateTime? seenAt;

  @override
  Future<DateTime?> readDateTime(String key, {DateTime? fallback}) async => seenAt;

  @override
  Future<void> writeDateTime(String key, DateTime? value) async {
    seenAt = value;
  }
}

/// 当前播放行为空，避免实例化真实播放控制器。
class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
