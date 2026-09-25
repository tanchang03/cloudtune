import 'dart:async';

import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/lyrics.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/pages/player_page.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/lyrics_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/album_art.dart';
import 'package:cloudtune/ui/widgets/lyrics_panel.dart';
import 'package:cloudtune/ui/widgets/window_top_inset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 歌词界面的回归测试。
///
/// 这里钉住的是三类**只有渲染出来才测得到**的缺陷：
///   1. 「没有歌词」被合并成一句话 —— 用户分不清「网盘里没有」和
///      「有文件但读出来是空的」，而这两种情况他要做的动作完全不同；
///   2. 高亮行算错（比如用「最接近的一行」而不是「最后一个已开始的行」），
///      表现为「歌词总是快半句」；
///   3. 换歌没重置 —— 新歌沿用上一首的行号/滚动位置，歌词停在半空中。
///
/// 歌词正文本身怎么来的（本地 / 联网 / 懒加载）由
/// `test/domain/lyrics_resolver_test.dart` 覆盖，这里不重复。
void main() {
  // 四行，每 10 秒一行。第 15 秒应当高亮第 2 行（"故事的小黄花"）。
  const synced = '[00:00.00]晴天\n'
      '[00:10.00]故事的小黄花\n'
      '[00:20.00]从出生那年就飘着\n'
      '[00:30.00]童年的荡秋千';

  // 没有时间轴：只能静态展示
  const unsynced = '故事的小黄花\n从出生那年就飘着';

  final track = Track(
    provider: DriveProvider.quark,
    remoteId: 'sky',
    name: '周杰伦 - 晴天.flac',
    path: '/音乐/华语/叶惠美/',
    sizeBytes: 30 * 1024 * 1024,
    title: '晴天',
    artist: '周杰伦',
    durationMs: 269000,
  );

  Lyrics local(String content, {String? fileName}) => Lyrics(
        trackId: track.id,
        provider: DriveProvider.quark,
        source: LyricsSource.local,
        content: content,
        fileName: fileName,
      );

  Lyrics remote(String content) => Lyrics(
        trackId: track.id,
        provider: DriveProvider.quark,
        source: LyricsSource.lrclib,
        content: content,
      );

  /// 挂上歌词面板。
  ///
  /// [value] 给 `null` 表示「查不到歌词」；给 [Completer] 可以卡在加载态。
  Future<void> pumpPanel(
    WidgetTester tester, {
    required Track forTrack,
    required Future<Lyrics?> value,
    Duration position = const Duration(seconds: 15),
    void Function(Duration)? onSeek,
    Size size = const Size(1060, 754),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lyricsProvider.overrideWith((ref, arg) => value),
          playbackPositionProvider.overrideWith((ref) => Stream.value(position)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LyricsPanel(track: forTrack, onSeek: onSeek),
          ),
        ),
      ),
    );
    // 歌词是一次异步查询，多推几帧让它落地。
    // 不用 `pumpAndSettle`：加载态里的占位不会停，它会一直等下去。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// 找到某个 Text 的**显式**样式。
  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  group('四种「没有歌词可显示」的状态各有各的文案', () {
    testWidgets('还在查：显示正在获取，不说「没有歌词」', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Completer<Lyrics?>().future, // 永不完成
      );

      expect(find.text('正在获取歌词…'), findsOneWidget);
      expect(find.text('暂无歌词'), findsNothing);
    });

    testWidgets('网盘里就没有 .lrc：提示可以去设置里开联网', (tester) async {
      await pumpPanel(tester, forTrack: track, value: Future.value());

      expect(find.text('暂无歌词'), findsOneWidget);
      expect(
        find.textContaining('设置 → 歌词'),
        findsOneWidget,
        reason: '「暂无歌词」本身没说该怎么办，用户会以为这功能坏了',
      );
    });

    testWidgets('纯音乐：不显示「暂无歌词」，也不用去联网', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(
          Lyrics(
            trackId: track.id,
            provider: DriveProvider.quark,
            source: LyricsSource.lrclib,
            instrumental: true,
          ),
        ),
      );

      expect(find.text('纯音乐'), findsOneWidget);
      expect(
        find.text('暂无歌词'),
        findsNothing,
        reason: '纯音乐是一个确定的答案，说「没找到」会误导用户去补歌词',
      );
    });

    testWidgets('有文件但读出来是空的：说清楚是文件空，不是没找到', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(local('[ti:晴天]\n[ar:周杰伦]')),
      );

      expect(find.text('歌词文件是空的'), findsOneWidget);
      expect(find.text('暂无歌词'), findsNothing);
    });
  });

  group('有时间轴：跟着播放位置高亮', () {
    Future<void> pumpSynced(WidgetTester tester,
            {void Function(Duration)? onSeek}) =>
        pumpPanel(
          tester,
          forTrack: track,
          value: Future.value(local(synced, fileName: '晴天.lrc')),
          onSeek: onSeek,
        );

    testWidgets('第 15 秒高亮第 2 行（最后一个已开始的行）', (tester) async {
      await pumpSynced(tester);

      // 15s 落在 10s 与 20s 之间 → 高亮"故事的小黄花"（而不是最接近的 20s 那行）
      expect(styleOf(tester, '故事的小黄花').fontSize, 15);
      expect(styleOf(tester, '从出生那年就飘着').fontSize, 13.5);
    });

    testWidgets('高亮行的字重与颜色都和别的行不同', (tester) async {
      await pumpSynced(tester);

      final active = styleOf(tester, '故事的小黄花');
      final idle = styleOf(tester, '童年的荡秋千');

      expect(active.fontWeight, FontWeight.w600);
      expect(idle.fontWeight, FontWeight.w400);
      expect(active.color, AppTheme.text);
      expect(idle.color, AppTheme.dim);
    });

    testWidgets('还没到第一行时没有任何高亮行（间奏期间不该亮第 1 行）', (tester) async {
      // 第一行刻意放在 5s：0s 时 `lineIndexAt` 返回 -1，
      // 界面必须一行都不亮，而不是「默认高亮第一行」。
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(local('[00:05.00]晴天\n[00:10.00]故事的小黄花')),
        position: Duration.zero,
      );

      expect(styleOf(tester, '晴天').fontSize, 13.5);
      expect(styleOf(tester, '故事的小黄花').fontSize, 13.5);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 15,
        ),
        findsNothing,
        reason: '前奏还没唱就把第一行点亮，等于提前剧透歌词',
      );
    });

    testWidgets('点某一行 → 跳到那一行的时刻', (tester) async {
      final seeks = <Duration>[];
      await pumpSynced(tester, onSeek: seeks.add);

      await tester.tap(find.text('童年的荡秋千'));
      await tester.pump();

      expect(seeks, [const Duration(seconds: 30)]);
    });

    testWidgets('不可跳时不给点击：不留「点了没反应」的控件', (tester) async {
      await pumpSynced(tester); // onSeek 为 null

      expect(
        find.descendant(
          of: find.byType(LyricsPanel),
          matching: find.byType(InkWell),
        ),
        findsNothing,
        reason: '时长未知时歌词行点得动却什么也不发生，比不能点更难解释',
      );
    });
  });

  group('没有时间轴：静态展示并说明它不跟着走', () {
    testWidgets('整段摆出来，来源脚注仍在', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(local(unsynced, fileName: '晴天.lrc')),
      );

      expect(find.text(unsynced), findsOneWidget);
      expect(find.textContaining('本地歌词'), findsOneWidget);
      expect(
        find.byType(ListView),
        findsNothing,
        reason: '没有时间轴就不该按行铺开 —— 那会让人以为它会跟着走',
      );
    });
  });

  group('来源脚注', () {
    testWidgets('本地歌词带上文件名', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(local(synced, fileName: '晴天.lrc')),
      );

      expect(find.text('本地歌词 · 晴天.lrc'), findsOneWidget);
      expect(find.textContaining('LRCLIB'), findsNothing);
    });

    testWidgets('联网歌词必须写明来自 LRCLIB', (tester) async {
      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(remote(synced)),
      );

      expect(
        find.text('歌词来自 LRCLIB（联网匹配）'),
        findsOneWidget,
        reason: '联网是第三方匹配的，用户看到明显不对的歌词时得知道该改哪一边',
      );
    });
  });

  group('换歌', () {
    Track other() => Track(
          provider: DriveProvider.quark,
          remoteId: 'other',
          name: '周杰伦 - 稻香.flac',
          path: '/音乐/华语/魔杰座/',
          title: '稻香',
          artist: '周杰伦',
          durationMs: 223000,
        );

    testWidgets('歌词区整体重建：key 跟着曲目走', (tester) async {
      final second = other();

      await pumpPanel(
        tester,
        forTrack: track,
        value: Future.value(local(synced)),
      );
      expect(find.byKey(ValueKey('synced:${track.id}')), findsOneWidget);

      // 换歌：同一个面板组件换了一首曲子
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lyricsProvider.overrideWith((ref, arg) => Future.value(
                  Lyrics(
                    trackId: second.id,
                    provider: DriveProvider.quark,
                    source: LyricsSource.local,
                    content: synced,
                  ),
                )),
            playbackPositionProvider
                .overrideWith((ref) => Stream.value(const Duration(seconds: 15))),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: LyricsPanel(track: second)),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.byKey(ValueKey('synced:${second.id}')),
        findsOneWidget,
        reason: 'key 不变就意味着滚动位置与每行 GlobalKey 被下一首沿用 —— '
            '新歌的歌词会停在上一首滚到的地方',
      );
      expect(find.byKey(ValueKey('synced:${track.id}')), findsNothing);
    });
  });

  // 播放页：封面与歌词的位置关系 + 不溢出。
  //
  // 播放页是**顶层全屏路由**（没有侧栏、也没有播放条），高度就是整个窗口；
  // 窗口最小 1060×754 是硬下限（见 `MainFlutterWindow.applyMinimumSize`），
  // 所以这一档是歌词区能拿到的最矮情况，必须在这里断言不溢出。
  group('播放页挂上歌词区', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required Track current,
      required Future<Lyrics?> lyrics,
      Duration? streamedDuration,
      Size size = const Size(1060, 754),
      double textScale = 1.0,
      String? notice,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith(() => _StubPlayer(current, notice: notice)),
            playbackPositionProvider
                .overrideWith((ref) => Stream.value(const Duration(seconds: 15))),
            playbackDurationProvider.overrideWith(
              (ref) => Stream<Duration?>.value(streamedDuration),
            ),
            playbackPlayingProvider.overrideWith((ref) => Stream.value(true)),
            favoriteIdsProvider.overrideWith((ref) => <String>{}),
            lyricsProvider.overrideWith((ref, arg) => lyrics),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Column(
              children: [
                WindowTopInset(),
                Expanded(child: PlayerPage()),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('宽屏：歌词在封面右侧（不是挤在封面下面）', (tester) async {
      await pumpPage(
        tester,
        current: track,
        lyrics: Future.value(local(synced, fileName: '晴天.lrc')),
      );

      final art = tester.getRect(find.byType(AlbumArt));
      final panel = tester.getRect(find.byType(LyricsPanel));

      expect(
        panel.left,
        greaterThanOrEqualTo(art.right),
        reason: '宽屏时封面居中会左右各空出三百多像素，歌词塞在封面下面只有约 190px，'
            '「滚动播出」在那么矮的高度里不成立',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('最小窗口（1060×754）不溢出', (tester) async {
      await pumpPage(
        tester,
        current: track,
        lyrics: Future.value(local(synced, fileName: '晴天.lrc')),
        size: const Size(1060, 754),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: '这是窗口下限，再矮的情况不会出现 —— 这里溢出就是真溢出',
      );
    });

    testWidgets('窄窗口（700×800）退回居中一列，也不溢出', (tester) async {
      await pumpPage(
        tester,
        current: track,
        lyrics: Future.value(local(synced, fileName: '晴天.lrc')),
        size: const Size(700, 800),
      );

      final art = tester.getRect(find.byType(AlbumArt));
      final panel = tester.getRect(find.byType(LyricsPanel));
      expect(panel.top, greaterThanOrEqualTo(art.bottom), reason: '窄屏改为上下叠放');
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统字号 1.6 倍也不溢出', (tester) async {
      await pumpPage(
        tester,
        current: track,
        lyrics: Future.value(local(synced, fileName: '晴天.lrc')),
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
    });

    // 最坏的一档：窄屏（歌词叠在封面下面）+ 放大字号 + 顶上还有一条提示。
    // 三者叠加时固定内容本身就快占满整页了，歌词区会被压到几乎没有 ——
    // 这一档能过，才说明「叠放」这条路径真的有兜底，而不是刚好够放。
    testWidgets('窄屏 + 1.6 倍字号 + 提示条：也不溢出', (tester) async {
      await pumpPage(
        tester,
        current: track,
        lyrics: Future.value(local(synced, fileName: '晴天.lrc')),
        size: const Size(700, 800),
        textScale: 1.6,
        notice: '正在尝试下一首：直链已过期',
      );

      expect(tester.takeException(), isNull);
      // 不溢出还不够：被压成 0 高度也算「不溢出」，而那时歌词等于没有。
      // 实测这一档是 97px（约 3 行）—— 挤，但仍然看得见。
      expect(
        tester.getRect(find.byType(LyricsPanel)).height,
        greaterThan(0),
        reason: '最坏的一档里歌词区不该被压没；压没了这条测试也会是绿的',
      );
    });

    testWidgets('时长未知时歌词行不可点（与进度条禁用同一口径）', (tester) async {
      final noDuration = Track(
        provider: DriveProvider.quark,
        remoteId: 'nodur',
        name: '未知时长.flac',
        path: '/音乐/',
        title: '未知时长',
      );

      await pumpPage(
        tester,
        current: noDuration,
        lyrics: Future.value(
          Lyrics(
            trackId: noDuration.id,
            provider: DriveProvider.quark,
            source: LyricsSource.local,
            content: synced,
          ),
        ),
        streamedDuration: null,
      );

      expect(
        find.descendant(
          of: find.byType(LyricsPanel),
          matching: find.byType(InkWell),
        ),
        findsNothing,
        reason: '进度条都拖不动，歌词却点得动、点完什么也不发生',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// 固定在指定曲目上的播放器，避免去碰真实的播放引擎。
class _StubPlayer extends PlayerNotifier {
  _StubPlayer(this.track, {this.notice});

  final Track track;
  final String? notice;

  @override
  PlayerState build() => PlayerState(current: track, notice: notice);
}
