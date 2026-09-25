import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/pages/player_page.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/lyrics_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/player_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 进度条可拖拽的回归测试。
///
/// 这里钉住的是两类**用户直接感知**的缺陷。它们都不会让别的单测变红，
/// 只会让「进度条拖不动」：
///
///   1. **命中区只有 4px**（就是细条的视觉高度）—— 鼠标几乎点不中；
///   2. **宽度取错对象** —— 原先用 `context.findRenderObject()`，拿到的是
///      整行（含两侧时间文本），于是 `dx / width` 恒小于真实比例，
///      拖到最右边也只跳到中途。
///
/// 所以断言不能只看「有没有调用 seek」，必须看**seek 到哪儿**。
void main() {
  const total = Duration(minutes: 4);

  Track makeTrack({int? durationMs}) => Track(
        provider: DriveProvider.quark,
        remoteId: 'seek1',
        name: '测试曲目.flac',
        path: '/音乐/测试/',
        sizeBytes: 40 * 1024 * 1024,
        title: '测试曲目',
        artist: '测试艺术家',
        durationMs: durationMs,
      );

  final withDuration = makeTrack(durationMs: total.inMilliseconds);
  final withoutDuration = makeTrack();

  /// 记录下发的 seek，避免去碰真实的播放引擎。
  final seeks = <Duration>[];

  Future<void> pumpWidgetUnderTest(
    WidgetTester tester,
    Widget child, {
    required Track? current,
    Duration? streamedDuration,
    Size size = const Size(1280, 900),
  }) async {
    seeks.clear();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(() => _RecordingPlayer(current, seeks)),
          playbackPositionProvider
              .overrideWith((ref) => Stream.value(const Duration(seconds: 30))),
          playbackDurationProvider
              .overrideWith((ref) => Stream<Duration?>.value(streamedDuration)),
          playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
          favoriteIdsProvider.overrideWith((ref) => <String>{}),
          // 播放页带着歌词区，它默认会去读本地索引库。这里只测进度条，
          // 直接给个「没有歌词」，免得测试牵扯到数据库。
          lyricsProvider.overrideWith((ref, track) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      ),
    );
    // 推两帧：`Stream.value` 的首次投递要走一个微任务，一帧还落不了地
    await tester.pump();
    await tester.pump();
  }

  /// 底栏那条进度条：`PlayerBar` 里唯一带横向拖拽手势的东西。
  final seekBar = find.descendant(
    of: find.byType(PlayerBar),
    matching: find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onHorizontalDragUpdate != null,
    ),
  );

  /// 拖到「条子宽度」的 [fraction] 处并松手。
  Future<void> dragTo(WidgetTester tester, double fraction) async {
    final rect = tester.getRect(seekBar);
    final gesture =
        await tester.startGesture(rect.centerLeft + const Offset(2, 0));
    await gesture
        .moveTo(Offset(rect.left + rect.width * fraction, rect.center.dy));
    await gesture.up();
    await tester.pump();
  }

  group('底栏进度条（PlayerBar）', () {
    testWidgets('细条视觉上只有 4px，但命中区必须够厚', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );

      final rect = tester.getRect(seekBar);
      expect(
        rect.height,
        greaterThanOrEqualTo(16),
        reason: '命中区等于细条本身的 4px 时鼠标几乎点不中 —— '
            '用户看到的现象就是「进度条拖不动」',
      );
      expect(
        rect.height,
        lessThan(32),
        reason: '命中区变厚不该把视觉上的细条也撑粗',
      );
    });

    testWidgets('拖到 75% 处 → seek 到总时长的 75%', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );
      await dragTo(tester, 0.75);

      expect(seeks, hasLength(1));
      expect(
        seeks.single.inMilliseconds,
        closeTo(total.inMilliseconds * 0.75, total.inMilliseconds * 0.01),
        reason: '宽度若取成整行（含两侧时间文本），比例会恒小于真实值，'
            '拖到最右边也够不到尾部',
      );
    });

    testWidgets('拖到最右端 → 跳到总时长', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );
      await dragTo(tester, 0.999);

      expect(
        seeks.single.inMilliseconds,
        closeTo(total.inMilliseconds, total.inMilliseconds * 0.01),
      );
    });

    testWidgets('单击条子 25% 处 → 直接跳过去', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );

      final rect = tester.getRect(seekBar);
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await tester.pump();

      expect(seeks, hasLength(1));
      expect(
        seeks.single.inMilliseconds,
        closeTo(total.inMilliseconds * 0.25, total.inMilliseconds * 0.02),
      );
    });

    testWidgets('拖动过程不下发 seek，只在松手时下发一次', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );

      final rect = tester.getRect(seekBar);
      final gesture =
          await tester.startGesture(rect.centerLeft + const Offset(2, 0));
      for (final f in [0.3, 0.6, 0.9]) {
        await gesture.moveTo(Offset(rect.left + rect.width * f, rect.center.dy));
        await tester.pump();
      }
      expect(
        seeks,
        isEmpty,
        reason: '夸克直链每次 seek 都要重新拉流，逐帧下发会把网络和播放器一起打爆',
      );

      await gesture.up();
      await tester.pump();
      expect(seeks, hasLength(1));
    });

    testWidgets('拖动时左侧时间跟着手指走，不被播放位置流拽回', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: withDuration,
        streamedDuration: total,
      );

      // 播放位置流给的是 30s（`m:ss` 格式，分钟不补零），拖到一半后应显示 2:00
      expect(find.text('0:30'), findsOneWidget);

      final rect = tester.getRect(seekBar);
      final gesture =
          await tester.startGesture(rect.centerLeft + const Offset(2, 0));
      await gesture.moveTo(Offset(rect.left + rect.width * 0.5, rect.center.dy));
      await tester.pump();

      expect(
        find.text('2:00'),
        findsOneWidget,
        reason: '拖动期间若还读播放位置，手指刚拖到的位置会被拽回去',
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('没有曲目时不可拖（也不该崩）', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerBar(),
        current: null,
        streamedDuration: null,
      );

      expect(tester.takeException(), isNull);
      expect(
        seekBar,
        findsNothing,
        reason: '没有曲目就没有可跳的目标，不该留着能拖的手势',
      );
    });
  });

  group('全屏播放页进度条（Slider）', () {
    Slider sliderOf(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider));

    testWidgets('播放器报不出时长时用曲目元数据兜底，进度条仍可拖', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerPage(),
        current: withDuration,
        streamedDuration: null,
      );

      final slider = sliderOf(tester);
      expect(
        slider.onChanged,
        isNotNull,
        reason: '只认播放器声明的时长，遇到报不出时长的文件（DSF 等）'
            '进度条会被整条禁用 —— 现象同样是「拖不动」',
      );
      expect(slider.max, total.inMilliseconds.toDouble());
    });

    testWidgets('拖到中点松手 → seek 到一半', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerPage(),
        current: withDuration,
        streamedDuration: total,
      );

      final rect = tester.getRect(find.byType(Slider));
      final gesture =
          await tester.startGesture(rect.centerLeft + const Offset(4, 0));
      await gesture.moveTo(rect.center);
      await gesture.up();
      await tester.pump();

      expect(seeks, hasLength(1));
      expect(
        seeks.single.inMilliseconds,
        closeTo(total.inMilliseconds / 2, total.inMilliseconds * 0.08),
      );
    });

    testWidgets('时长完全未知时禁用而不是崩', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const PlayerPage(),
        current: withoutDuration,
        streamedDuration: null,
      );

      expect(tester.takeException(), isNull);
      expect(
        sliderOf(tester).onChanged,
        isNull,
        reason: '时长未知就无从把「拖到哪儿」换算成时间，只能禁用',
      );
    });
  });
}

/// 固定状态的播放器，`seek` 只记录不下发。
class _RecordingPlayer extends PlayerNotifier {
  _RecordingPlayer(this.track, this.seeks);

  final Track? track;
  final List<Duration> seeks;

  @override
  PlayerState build() => PlayerState(current: track);

  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}
