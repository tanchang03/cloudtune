import 'dart:typed_data';

import 'package:cloudtune/core/diagnostics/diag_log.dart';
import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/domain/entities/album_cover.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/library_grouping.dart';
import 'package:cloudtune/ui/pages/album_page.dart';
import 'package:cloudtune/ui/pages/diagnostics_page.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/album_art.dart';
import 'package:cloudtune/ui/widgets/album_grid.dart';
import 'package:cloudtune/ui/widgets/page_header.dart';
import 'package:cloudtune/ui/widgets/player_bar.dart';
import 'package:cloudtune/ui/widgets/playability_badge.dart';
import 'package:cloudtune/ui/widgets/playability_help.dart';
import 'package:cloudtune/ui/widgets/track_explorer.dart';
import 'package:cloudtune/ui/widgets/track_list.dart';
import 'package:cloudtune/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 布局溢出回归测试。
///
/// Flutter 在 debug 下会把「BOTTOM OVERFLOWED BY n PIXELS」的黄黑条纹画到界面上，
/// 那**不是调试开关，是真实缺陷**：内容比容器高，超出的部分只是被裁掉了。
/// 用户看到黄条纹 = 有一块内容他永远看不到。
///
/// 所以这里逐个渲染真实组件，断言「没有任何异常上报」。
/// 溢出会经 `FlutterError.reportError` 抛给测试框架，被 `takeException()` 拿到。
///
/// 关键背景：本工程字体是 `PingFang SC`，行高系数 **1.4**。
/// 凡是「容器高度写死 + 里面放文字」的地方都必须按 1.4 算，
/// 按 1.2 估就会差出 1~4px —— 正好是这次黄条纹的量级。
void main() {
  const caps = Capabilities(
    provider: DriveProvider.quark,
    maxSingleFileBytes: Capabilities.fiftyMiB,
  );

  /// 取一帧后把异常取出来。null 表示这一帧没有任何布局/绘制问题。
  Object? drain(WidgetTester tester) => tester.takeException();

  Future<void> pumpApp(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 800),
    double textScale = 1.0,
    /// 额外的 provider 覆盖。默认这一套只够渲染曲目行；
    /// 专辑视图还要拿到封面与某张专辑的曲目，所以留了这个口子。
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    // 用平台层覆盖系统字号，比手搓 MediaQueryData 安全
    // （后者默认 size 为 0，会把 Scaffold 的布局带偏）
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_StubPlayer.new),
          playbackPositionProvider
              .overrideWith((ref) => Stream.value(const Duration(seconds: 37))),
          playbackDurationProvider.overrideWith(
            (ref) => Stream.value(const Duration(minutes: 4, seconds: 12)),
          ),
          playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
          favoriteIdsProvider.overrideWith((ref) => <String>{}),
          ...extra,
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  group('诊断日志页（长日志行与长路径都不能溢出）', () {
    /// 造一条接近真实的超长日志行：直链、请求头、体积全都在里面。
    void fillLog(int count) {
      diag.clearBuffer();
      for (var i = 0; i < count; i++) {
        diag.info(
          '取链',
          '路由 audioplay 签发票据：https://cdn.example.com/'
          '${'x' * 120}?token=<redacted>，声明体积=811679948，'
          '随票据请求头=Cookie,Referer,User-Agent,Accept-Language，'
          '过期=2026-09-24 13:00:00.000',
        );
      }
    }

    testWidgets('空日志：不溢出', (tester) async {
      diag.clearBuffer();
      await pumpApp(tester, const DiagnosticsPage(), size: const Size(900, 600));
      expect(drain(tester), isNull);
    });

    testWidgets('满屏长行 + 窄窗口：不溢出', (tester) async {
      fillLog(40);
      await pumpApp(tester, const DiagnosticsPage(), size: const Size(820, 600));
      expect(
        drain(tester),
        isNull,
        reason: '日志行没有折行约束的话，窄窗口下横向就会溢出',
      );
    });

    testWidgets('系统字号放大后页头的三个按钮仍不溢出', (tester) async {
      fillLog(3);
      await pumpApp(
        tester,
        const DiagnosticsPage(),
        size: const Size(760, 600),
        textScale: 1.6,
      );
      expect(drain(tester), isNull);
    });

    testWidgets('ERROR 行带长异常文本也不溢出', (tester) async {
      diag.clearBuffer();
      diag.error(
        '播放器',
        '装载失败（原始异常）',
        error: 'PlatformException(-11800, The operation could not be completed, '
            'AVFoundationErrorDomain: 无法打开该文件)',
      );
      diag.error(
        '钥匙串',
        '读取 cloudtune.cred.quark 失败',
        error: 'errSecMissingEntitlement(-34018): A required entitlement is '
            'missing from the application signature',
      );
      await pumpApp(tester, const DiagnosticsPage(), size: const Size(820, 600));
      expect(drain(tester), isNull);
    });
  });

  group('PageHeader（页头高度必须由内容决定）', () {
    /// 按页面里的真实用法渲染：页头是内容列的第一项，下面是滚动区。
    /// 曾经它被塞进 `Scaffold.appBar` 并写死高度 76，带 hint 时溢出 2.0px。
    Widget pageLike(String? hint) => Column(
          children: [
            PageHeader(title: '音乐库', hint: hint),
            const Expanded(child: SizedBox.expand()),
          ],
        );

    testWidgets('只有标题：不溢出', (tester) async {
      await pumpApp(tester, pageLike(null));
      expect(drain(tester), isNull);
    });

    testWidgets('带 hint：必须装得下标题 + 说明（回归：曾溢出 2.0px）', (tester) async {
      await pumpApp(
        tester,
        pageLike('444 首 · 239 首确认可播 · 37.2 GB · 索引存于本机'),
      );
      expect(
        drain(tester),
        isNull,
        reason: '19px 标题(PingFang 行高 1.4 ≈ 26.6) + 5 + 11.5px 说明(≈16.1) '
            '+ 上下内边距 30 = 77.7 —— 写死 76 就会溢出，所以高度不能写死',
      );
    });

    testWidgets('hint 折成两行也不溢出', (tester) async {
      await pumpApp(
        tester,
        pageLike('按目录逐层遍历并识别音频文件，每页都会落库 —— 中途退出也不会丢进度，'
            '下次可以从断点继续，不需要从头再扫一遍'),
        size: const Size(700, 800), // 窄窗口逼它折行
      );
      expect(drain(tester), isNull);
    });

    testWidgets('用户把系统字号放大后也不溢出', (tester) async {
      await pumpApp(
        tester,
        pageLike('所有数据仅存储于本机 · 不上传文件、播放记录或授权凭证'),
        textScale: 1.6,
      );
      expect(
        drain(tester),
        isNull,
        reason: '任何写死高度的页头都会在这里炸 —— 这是它必须自适应高度的根本原因',
      );
    });

    testWidgets('带 actions（排序按钮）时仍不溢出', (tester) async {
      await pumpApp(
        tester,
        Column(
          children: [
            PageHeader(
              title: '音乐库',
              hint: '444 首 · 239 首确认可播',
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.sort)),
              ],
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      );
      expect(drain(tester), isNull);
    });
  });

  group('PlayabilityBadge', () {
    testWidgets('紧凑模式（列表行内）不溢出', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: PlayabilityBadge(
            playability: const Playability(PlayabilityState.overLimit),
            dense: true,
            onTap: () {},
          ),
        ),
      );
      expect(drain(tester), isNull);
    });
  });

  group('TrackTile（44px 封面 + 三行文字）', () {
    testWidgets('宽屏：标题/副标题/路径三行不超过封面高度', (tester) async {
      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 't1',
        name: '凤凰传奇 - 奇迹世界.flac',
        path: '/音乐/华语/凤凰传奇/',
        sizeBytes: 62 * 1024 * 1024,
        title: '奇迹世界',
        artist: '凤凰传奇',
        album: '最炫民族风',
        durationMs: 260000,
      );

      await pumpApp(
        tester,
        TrackTile(track: track, capabilities: caps, onPlay: () {}),
        size: const Size(1280, 800),
      );
      expect(drain(tester), isNull);
    });

    testWidgets('窄屏：路径降级成第三行后仍不溢出', (tester) async {
      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 't2',
        name: '凤凰传奇 - 奇迹世界.flac',
        path: '/音乐/华语/凤凰传奇/',
        sizeBytes: 62 * 1024 * 1024,
        title: '奇迹世界',
        artist: '凤凰传奇',
      );

      await pumpApp(
        tester,
        TrackTile(track: track, capabilities: caps, onPlay: () {}),
        size: const Size(600, 800),
      );
      expect(drain(tester), isNull);
    });

    testWidgets('窄屏：格式 / 品质 / 大小 三项都压进副标题，一项都不能丢', (tester) async {
      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 't3',
        name: '凤凰传奇 - 奇迹世界.flac',
        path: '/音乐/华语/凤凰传奇/',
        sizeBytes: 62 * 1024 * 1024,
        title: '奇迹世界',
        artist: '凤凰传奇',
        durationMs: 260000,
      );

      await pumpApp(
        tester,
        TrackTile(track: track, capabilities: caps, onPlay: () {}),
        size: const Size(600, 800),
      );
      expect(drain(tester), isNull);
      // 62MiB ÷ 260s ≈ 2000kbps
      expect(
        find.text('凤凰传奇 · FLAC 无损 2000k · 62.0 MB'),
        findsOneWidget,
        reason: '窄屏没有独立列，这三项只能靠副标题，丢一项就是丢了功能',
      );
    });

    testWidgets('窄屏：拿不到体积就不写「未知」，副标题不留噪声', (tester) async {
      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 't4',
        name: '凤凰传奇 - 奇迹世界.flac',
        path: '/音乐/华语/凤凰传奇/',
        title: '奇迹世界',
        artist: '凤凰传奇',
      );

      await pumpApp(
        tester,
        TrackTile(track: track, capabilities: caps, onPlay: () {}),
        size: const Size(600, 800),
      );
      expect(drain(tester), isNull);
      expect(find.text('凤凰传奇 · FLAC 无损'), findsOneWidget);
    });
  });

  group('TrackListView（列头 + 行，列宽必须对齐）', () {
    final tracks = [
      Track(
        provider: DriveProvider.quark,
        remoteId: 'a',
        name: '很长的文件名用来测试省略号是否生效 - 现场版.flac',
        path: '/音乐/华语/一个相当长的目录名/子目录/',
        sizeBytes: 48 * 1024 * 1024,
        title: '很长的文件名用来测试省略号是否生效',
        artist: '某位艺术家',
        durationMs: 305000,
      ),
      Track(
        provider: DriveProvider.quark,
        remoteId: 'b',
        name: '整轨.wav',
        path: '/音乐/',
        sizeBytes: 720 * 1024 * 1024,
        durationMs: 3600000,
      ),
      // 网盘没刮削出元数据的那些：体积和时长都拿不到。
      // 它们会走「未知」和 `--:--` 两条分支，宽度必须和正常行一样，
      // 否则同一列表里两种行的列会对不齐。
      Track(
        provider: DriveProvider.quark,
        remoteId: 'c',
        name: '01. 还有.dsf',
        // 目录名刻意不叫「DSD」：副标题在没有艺术家时会退回目录名，
        // 叫 DSD 的话会和品质列的家族词撞成两个同名 Text，断言就测不准了
        path: '/音乐/高解析收藏/',
        title: '还有',
      ),
    ];

    Future<void> pumpList(
      WidgetTester tester, {
      Size size = const Size(1280, 800),
      double textScale = 1.0,
    }) async {
      await pumpApp(
        tester,
        TrackListView(tracks: tracks, capabilities: caps),
        size: size,
        textScale: textScale,
      );
    }

    testWidgets('宽屏（1280）下列头与曲目行都不溢出', (tester) async {
      await pumpList(tester);
      expect(drain(tester), isNull);
    });

    testWidgets('正好卡在宽屏断点（1000）上也不溢出', (tester) async {
      // 加了「格式 · 品质」与「大小」两列之后，1000 是七列同时出现的最窄情况。
      // 断点从 900 抬到 1000 就是为了这一档：900 时曲名只剩约 116px。
      await pumpList(tester, size: const Size(1000, 800));
      expect(drain(tester), isNull, reason: '断点这一档是列最挤的地方');
    });

    testWidgets('断点以下（999）自动退回窄屏布局，不硬挤七列', (tester) async {
      await pumpList(tester, size: const Size(999, 800));
      expect(drain(tester), isNull);
    });

    testWidgets('系统字号 1.6 倍也不溢出', (tester) async {
      await pumpList(tester, textScale: 1.6);
      expect(drain(tester), isNull);
    });

    testWidgets('新增的两列：列头与曲目行严格同宽同起点', (tester) async {
      await pumpList(tester);

      /// 列头一行 + 3 条曲目 = 4 个同宽的盒子。
      /// 用宽度找而不是用文案找，是因为要找的正是「两处读的是不是同一个令牌」。
      Finder colsOf(double w) =>
          find.byWidgetPredicate((x) => x is SizedBox && x.width == w);

      for (final entry in {
        '格式 / 品质': AppTheme.qualityColWidth,
        '大小': AppTheme.sizeColWidth,
      }.entries) {
        final cols = colsOf(entry.value);
        expect(
          cols,
          findsNWidgets(4),
          reason: '「${entry.key}」列应有 列头 1 + 曲目 3 个盒子',
        );

        final head = tester.getRect(cols.at(0));
        for (var i = 1; i < 4; i++) {
          final row = tester.getRect(cols.at(i));
          expect(
            row.left,
            closeTo(head.left, 0.01),
            reason: '第 $i 行「${entry.key}」列的左边缘与列头不一致 —— '
                '列头文字会歪在别的列上面',
          );
          expect(row.width, closeTo(head.width, 0.01));
        }
      }
    });

    testWidgets('规格列真的画出了「格式 + 家族 + 码率」', (tester) async {
      await pumpList(tester);

      // 48MiB / 305s ≈ 1320kbps，是无损 flac
      expect(find.text('FLAC'), findsOneWidget);
      expect(find.text('无损 1320k'), findsOneWidget);
      // 720MiB / 3600s ≈ 1678kbps，WAV 未压缩
      expect(find.text('WAV'), findsOneWidget);
      expect(find.text('未压缩 1678k'), findsOneWidget);
      // 没有体积也没有时长 → 只显示家族词，不留半截空格
      expect(find.text('DSF'), findsOneWidget, reason: '格式 chip');
      expect(find.text('DSD'), findsOneWidget, reason: '家族词，后面没有码率');
    });

    testWidgets('体积未知时「大小」列写「未知」，不是 0 B', (tester) async {
      await pumpList(tester);
      expect(
        find.text('未知'),
        findsOneWidget,
        reason: '0 B 会让人以为是个空文件；「未知」才是诚实的',
      );
    });
  });

  group('PlayerBar（写死 74px 的底栏）', () {
    testWidgets('74px 装得下封面/文字/按钮/进度条', (tester) async {
      await pumpApp(
        tester,
        const PlayerBar(),
        size: const Size(1280, 800),
      );
      expect(drain(tester), isNull, reason: '74px 底栏是最容易溢出的地方');
    });

    testWidgets('窄窗口（1024）下也不溢出', (tester) async {
      await pumpApp(
        tester,
        const PlayerBar(),
        size: const Size(1024, 800),
      );
      expect(drain(tester), isNull);
    });

    // 播放栏这一行全是写死的宽度（封面 44 + 曲目块 190 + 控制区约 208 +
    // 三处 16 间距 + 两侧 18 内边距 = 526），再叠上进度条两端的时间文本，
    // 600 宽实测溢出 59px。窄窗口必须主动让位，否则「全屏页挂播放栏」
    // 在窄窗口下会把页面顶破 —— 专辑详情页 600 宽那条测试就是这么暴露的。
    //
    // `pumpApp` 把位置覆盖成 37s、时长覆盖成 4:12，所以两端文本是
    // `0:37` / `4:12`（`formatDuration` 的口径，见 `app_theme.dart`）。
    testWidgets('窄窗口（600）下收曲目块、砍掉进度条两端的时间', (tester) async {
      await pumpApp(tester, const PlayerBar(), size: const Size(600, 800));

      expect(
        drain(tester),
        isNull,
        reason: '不让位的话这一行在 600 宽下溢出 59px',
      );
      for (final label in ['0:37', '4:12']) {
        expect(
          find.descendant(
            of: find.byType(PlayerBar),
            matching: find.text(label),
          ),
          findsNothing,
          reason: '窄窗口先放下最不关键的信息：细条本身已经表达了进度，'
              '而两个时间文本占的宽度和曲目块是一个量级',
        );
      }
    });

    testWidgets('宽窗口（1280）下时间文本照常显示', (tester) async {
      await pumpApp(tester, const PlayerBar(), size: const Size(1280, 800));

      for (final label in ['0:37', '4:12']) {
        expect(
          find.descendant(
            of: find.byType(PlayerBar),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: '让位只发生在窄窗口 —— 常规宽度下不该牺牲信息',
        );
      }
    });
  });

  // 说明弹窗的文案是中文长段落，且会随产品口径调整而变长。
  // 它曾经在 600px 高的窗口里溢出 15px（改文案时踩到），
  // 所以这里把「窗口矮 / 字号大」两种情况都变成断言。
  group('PlayabilityHelp 弹窗（文案变长也不能顶破窗口）', () {
    Future<void> openHelp(
      WidgetTester tester, {
      Size size = const Size(1280, 800),
      double textScale = 1.0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 'over1',
        name: '整轨专辑.wav',
        path: '/音乐/华语/2000年代/',
        sizeBytes: 720 * 1024 * 1024,
        title: '整轨专辑',
      );
      final playability = track.playability(caps);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showPlayabilityHelp(
                  context,
                  track: track,
                  playability: playability,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('1280x800 不溢出', (tester) async {
      await openHelp(tester);
      expect(drain(tester), isNull);
    });

    testWidgets('窗口很矮（1280x600）也不溢出 —— 说明段落必须可滚动', (tester) async {
      await openHelp(tester, size: const Size(1280, 600));
      expect(drain(tester), isNull, reason: '矮窗口下说明段落应滚动，而不是画出黄黑条纹');
    });

    testWidgets('系统字号 1.6 倍也不溢出', (tester) async {
      await openHelp(tester, textScale: 1.6);
      expect(drain(tester), isNull);
    });
  });

  // 组头一行里同时有「可省略的专辑名」和两个定宽元素（曲目数、播放按钮）。
  // 中文专辑名可以很长 —— 真实库里就有
  // `贵族音乐深度睡眠 & 贵族音乐 - 睡眠轻音乐 钢琴与小提琴 雨夜催眠曲`，
  // 所以这里把宽窗口、窄窗口、放大字号三种情况都变成断言。
  group('TrackGroupListView（组头 + 组内曲目行）', () {
    TrackGroup makeGroup(String title, List<Track> tracks) =>
        TrackGroup(key: title, title: title, tracks: tracks);

    Track makeTrack(String id, String name) => Track(
          provider: DriveProvider.quark,
          remoteId: id,
          name: name,
          path: '/音乐/华语/',
          sizeBytes: 40 * 1024 * 1024,
          title: name,
          artist: '某位艺术家',
          durationMs: 250000,
        );

    final groups = [
      makeGroup(
        '贵族音乐深度睡眠 & 贵族音乐 - 睡眠轻音乐 钢琴与小提琴 雨夜催眠曲',
        [makeTrack('a', '雨夜'), makeTrack('b', '催眠曲')],
      ),
      makeGroup('爱 (2025 Remastered) · [16B-44.1kHz][Q]', [
        makeTrack('c', '蝴蝶飞呀'),
      ]),
      // 平铺模式传进来的「无标题组」不画组头，也必须不溢出
      makeGroup('', [makeTrack('d', '无分组曲目')]),
    ];

    testWidgets('宽屏：列头 + 组头 + 曲目行都不溢出', (tester) async {
      await pumpApp(
        tester,
        TrackGroupListView(groups: groups, capabilities: caps),
        size: const Size(1280, 800),
      );
      expect(drain(tester), isNull);
    });

    testWidgets('窄屏：长专辑名省略而不是撑破', (tester) async {
      await pumpApp(
        tester,
        TrackGroupListView(groups: groups, capabilities: caps),
        size: const Size(600, 800),
      );
      expect(drain(tester), isNull);
    });

    testWidgets('系统字号 1.6 倍也不溢出', (tester) async {
      await pumpApp(
        tester,
        TrackGroupListView(groups: groups, capabilities: caps),
        textScale: 1.6,
      );
      expect(
        drain(tester),
        isNull,
        reason: '组头高度由内容决定，放大字号只会让它变高，不该顶破容器',
      );
    });
  });

  // 列表头并排两个播放入口（随机播放 / 顺序播放），左边还有「N 首 · M 张专辑」。
  // 这是整页唯一一处「一个可伸缩文本 + 两个定宽按钮」的行，窄窗口和放大字号
  // 都会先在这里顶破，所以三种情况都变成断言。
  group('TrackExplorer（搜索框 + 筛选行 + 列表头）', () {
    Track makeTrack(int i) => Track(
          provider: DriveProvider.quark,
          remoteId: 't$i',
          name: '曲目 $i.flac',
          path: '/音乐/华语/',
          sizeBytes: 40 * 1024 * 1024,
          title: '曲目 $i',
          artist: '某位艺术家',
          durationMs: 250000,
        );

    final tracks = [for (var i = 0; i < 12; i++) makeTrack(i)];

    // 用测试自己的 provider，避免去碰真实仓储
    final tracksProvider =
        FutureProvider.autoDispose<List<Track>>((ref) async => tracks);

    Future<void> pumpExplorer(
      WidgetTester tester, {
      Size size = const Size(1280, 800),
      double textScale = 1.0,
    }) async {
      await pumpApp(
        tester,
        TrackExplorer(
          tracksProvider: tracksProvider,
          filterProvider: libraryFilterProvider,
          emptyTitle: '还没有曲目',
          emptyMessage: '先去扫描网盘',
        ),
        size: size,
        textScale: textScale,
      );
      // 曲目是一次异步查询，多推一帧让它落地 —— 否则测到的是 loading 圈，
      // 而 loading 圈永远不会溢出，测试会「假绿」
      await tester.pump();
    }

    testWidgets('宽屏：「N 首」与两个播放入口同行不溢出', (tester) async {
      await pumpExplorer(tester);

      expect(find.text('随机播放'), findsOneWidget);
      expect(find.text('顺序播放'), findsOneWidget);
      expect(drain(tester), isNull);
    });

    testWidgets('窄窗口（700）下两个按钮都不被挤出行外', (tester) async {
      await pumpExplorer(tester, size: const Size(700, 800));

      expect(find.text('顺序播放'), findsOneWidget);
      expect(drain(tester), isNull);
    });

    testWidgets('系统字号 1.6 倍也不溢出', (tester) async {
      await pumpExplorer(tester, textScale: 1.6);
      expect(drain(tester), isNull);
    });
  });
  // 方案 A：CUE 在界面上**只体现于组头**（`WAV · CUE 分轨` 标记 + 「整轨连播」），
  // 组内每一行都是普通曲目行 —— 能点、能收藏、能随机，这才是 CUE 支持的意义。
  //
  // 这里同时守住一条容易写错的口径：分段的 `sizeBytes` 是**整轨体积**、
  // `durationMs` 是**本轨时长**，直接相除会算出离谱的码率。所以下面用
  // 真实的整轨数据（765145628B / 4338000ms = 1411kbps，CD 规格）当基准。
  group('CUE 分轨（方案 A：组头体现 + 普通曲目行）', () {
    // 库里真实存在的那张整轨：72:18、729.7 MB、CD 规格 1411kbps
    const imageName = '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav';
    const imageBytes = 765145628;
    const imageMs = 4338000;

    // 刻意**不**声明体积上限：夸克播放走 audioplay，不受 download 的 50MiB 限制，
    // 所以这张 729.7 MB 的整轨在真实能力声明下是可播的（见 Capabilities 的注释）
    const quarkCaps = Capabilities(provider: DriveProvider.quark);

    Track imageFile({
      String remoteId = 'wav765',
      String name = imageName,
    }) =>
        Track(
          provider: DriveProvider.quark,
          remoteId: remoteId,
          name: name,
          path: '/音乐/华语/精选到无朋友/',
          sizeBytes: imageBytes,
          mimeType: 'audio/wav',
          durationMs: imageMs,
          artist: '李克勤',
          album: '精选到无朋友',
        );

    Track seg({
      required int no,
      required int startMs,
      int? durationMs,
      String? title,
      String imageId = 'wav765',
      String name = imageName,
    }) =>
        Track.cueSegment(
          source: imageFile(remoteId: imageId, name: name),
          trackNo: no,
          startMs: startMs,
          durationMs: durationMs,
          title: title,
        );

    /// 三轨、首尾相接、**末轨终点正好等于整轨总时长** —— 与真实 CUE 一致：
    /// 扫描时末轨的终点会被补成整轨文件的真实时长（见 `CueIndexer._expandImage`），
    /// 所以「所有分段终点的最大值」才能还原出整轨总时长。
    List<Track> cueAlbum() => [
          seg(no: 1, startMs: 0, durationMs: 200493, title: '红日'),
          seg(no: 2, startMs: 200493, durationMs: 219507, title: '月半小夜曲'),
          seg(no: 3, startMs: 420000, durationMs: 3918000, title: '护花使者'),
        ];

    TrackGroup cueGroup() => TrackGroup(
          key: '/音乐/华语/精选到无朋友/',
          title: '李克勤 - 精选到无朋友',
          tracks: cueAlbum(),
        );

    TrackGroup plainGroup() => TrackGroup(
          key: '/音乐/华语/晴天/',
          title: '周杰伦 - 叶惠美',
          tracks: [
            Track(
              provider: DriveProvider.quark,
              remoteId: 'p1',
              name: '周杰伦 - 晴天.flac',
              path: '/音乐/华语/晴天/',
              sizeBytes: 30 * 1024 * 1024,
              title: '晴天',
              artist: '周杰伦',
              durationMs: 269000,
            ),
          ],
        );

    Future<void> pumpGroups(
      WidgetTester tester,
      List<TrackGroup> groups, {
      Size size = const Size(1280, 800),
      double textScale = 1.0,
      _RecordingPlayer? player,
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
            playerProvider.overrideWith(() => player ?? _RecordingPlayer()),
            playbackPositionProvider
                .overrideWith((ref) => Stream.value(Duration.zero)),
            playbackDurationProvider.overrideWith((ref) => Stream.value(null)),
            playbackPlayingProvider.overrideWith((ref) => Stream.value(false)),
            favoriteIdsProvider.overrideWith((ref) => <String>{}),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: TrackGroupListView(
                groups: groups,
                capabilities: quarkCaps,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('组头标出「WAV · CUE 分轨」，并给出「整轨连播」入口', (tester) async {
      await pumpGroups(tester, [cueGroup()]);

      expect(find.text('李克勤 - 精选到无朋友'), findsOneWidget);
      expect(
        find.text('WAV · CUE 分轨'),
        findsOneWidget,
        reason: '组头是 CUE 唯一的「显形」处，不标出来用户不知道这 2 首从哪来的',
      );
      expect(find.text('整轨连播'), findsOneWidget);
      // 曲目数按**分段数**算，不是按网盘文件数
      expect(find.text('3 首'), findsOneWidget);
      expect(find.byTooltip('播放这一组'), findsOneWidget);
      expect(drain(tester), isNull);
    });

    testWidgets('普通专辑的组头不会凭空多出 CUE 标记', (tester) async {
      await pumpGroups(tester, [plainGroup()]);

      expect(find.text('WAV · CUE 分轨'), findsNothing);
      expect(find.text('整轨连播'), findsNothing);
      expect(drain(tester), isNull);
    });

    testWidgets('分段行显示 CUE 轨号与曲名（组内就是普通曲目行）', (tester) async {
      await pumpGroups(tester, [cueGroup()]);

      expect(find.text('01'), findsOneWidget, reason: '轨号来自 CUE，文件名推不出来');
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      expect(find.text('红日'), findsOneWidget);
      expect(find.text('月半小夜曲'), findsOneWidget);
      expect(drain(tester), isNull);
    });

    testWidgets('CUE 没写曲名时标题就是「第 N 轨」，不再重复一个轨号前缀', (tester) async {
      await pumpGroups(tester, [
        TrackGroup(key: 'k', title: '无题专辑', tracks: [
          seg(no: 7, startMs: 0, durationMs: 1000),
        ]),
      ]);

      expect(find.text('第 7 轨'), findsOneWidget);
      expect(
        find.text('07'),
        findsNothing,
        reason: '「07」和「第 7 轨」是同一句话说两遍',
      );
    });

    testWidgets('分段码率按整轨算：1411k 而不是拿整轨体积除以本轨时长', (tester) async {
      await pumpGroups(tester, [cueGroup()]);

      // 765145628B × 8 ÷ 4338000ms = 1411kbps（CD 规格）
      expect(
        find.text('未压缩 1411k'),
        findsNWidgets(3),
        reason: '若按本轨时长算会得出 30.5M / 27.8M 这种离谱值',
      );
      expect(find.text('WAV'), findsNWidgets(3));
    });

    testWidgets('分段行不显示整轨体积（729.7 MB 一个都不该出现）', (tester) async {
      await pumpGroups(tester, [cueGroup()]);

      expect(
        find.text('729.7 MB'),
        findsNothing,
        reason: '每行都写整轨体积，用户会以为这一首就有 729.7 MB',
      );
      expect(
        find.textContaining(' MB'),
        findsNWidgets(3),
        reason: '三行各自摊出本轨体积，而不是都没有体积',
      );
    });

    testWidgets('「整轨连播」给的队列是整轨文件本身，不是切出来的分段', (tester) async {
      final player = _RecordingPlayer();
      await pumpGroups(tester, [cueGroup()], player: player);

      await tester.tap(find.text('整轨连播'));
      await tester.pump();

      expect(player.plays, hasLength(1));
      final play = player.plays.single;
      expect(play.queue, hasLength(1), reason: '一张整轨就是一个播放项');
      expect(play.queue.single.remoteId, 'wav765');
      expect(
        play.queue.single.isCueSegment,
        isFalse,
        reason: '连播的必须是整轨本身，否则又要按 CUE 切一遍，等于没连',
      );
      expect(play.queue.single.durationMs, imageMs);
      expect(play.start, play.queue.single);
    });

    testWidgets('2CD 合辑在一个分组里：整轨连播的队列是两张整轨', (tester) async {
      final player = _RecordingPlayer();
      await pumpGroups(tester, [
        TrackGroup(key: 'k', title: '演唱会现场', tracks: [
          seg(no: 1, startMs: 0, durationMs: 1000, title: 'A1'),
          seg(no: 2, startMs: 1000, durationMs: 1000, title: 'A2'),
          seg(
            no: 1,
            startMs: 0,
            durationMs: 2000,
            title: 'B1',
            imageId: 'wav766',
            name: '李克勤.-.[精选到无朋友 CD2](2014)[WAV].wav',
          ),
        ]),
      ], player: player);

      await tester.tap(find.text('整轨连播'));
      await tester.pump();

      expect(player.plays.single.queue, hasLength(2));
      expect(
        player.plays.single.queue.map((t) => t.remoteId).toList(),
        ['wav765', 'wav766'],
        reason: 'CD1 放完接 CD2 —— 正是「连播」两个字的意思',
      );
    });

    testWidgets('窄窗口（600）下组头不溢出：CUE 标记 + 曲目数 + 两个按钮挤在一行', (tester) async {
      await pumpGroups(tester, [cueGroup()], size: const Size(600, 800));
      expect(drain(tester), isNull);
    });

    testWidgets('窄窗口 + 系统字号 1.6 倍：CUE 标记也不撑破组头', (tester) async {
      await pumpGroups(
        tester,
        [cueGroup()],
        size: const Size(600, 800),
        textScale: 1.6,
      );
      expect(
        drain(tester),
        isNull,
        reason: '组头这一行同时有「可省略的专辑名」和四个定宽元素，是最挤的地方',
      );
    });

    testWidgets('窄屏没有独立的体积列，副标题里给的也是摊出来的本轨体积', (tester) async {
      await pumpGroups(
        tester,
        [cueGroup()],
        size: const Size(600, 800),
      );

      expect(find.text('729.7 MB'), findsNothing);
      expect(find.textContaining('李克勤 · WAV 未压缩 1411k'), findsNWidgets(3));
      expect(drain(tester), isNull);
    });
  });

  // 专辑视图：封面卡片墙 + 专辑详情页。
  //
  // 卡片墙与列表视图拿的是**同一批 `TrackGroup`**，但渲染路径完全不同：
  // 卡片是「正方形封面 + 两行文字」，卡片高度与宽度是绑死的
  // （见 `AlbumGridView._captionHeight`）；详情页是「大封面 + 信息列 +
  // 三个按钮」的一行。两处都是新写的，所以宽 / 窄 / 放大字号都要断言。
  //
  // 这里刻意走真实的 `LibraryGrouping.group(...)` 而不是手搓 `TrackGroup`：
  // 卡片墙靠 `covers[group.key]` 取封面，而 `key` 是 `dirOf(track.path)`
  // 归一化后的**目录路径**（`track.path` 带结尾斜杠）。手搓组会把这个
  // 约定测掉 —— 而那正是「封面张冠李戴」的唯一可能来源。
  group('专辑视图（封面卡片墙 + 专辑详情页）', () {
    const popDir = '/音乐/华语/周杰伦/叶惠美';
    const cueDir = '/音乐/华语/李克勤/精选到无朋友';
    // 真实库里最长的那类目录名，用来验证卡片文字单行省略
    const compDir = '/音乐/合辑/贵族音乐 - 睡眠轻音乐 钢琴与小提琴 雨夜催眠曲';

    Track trackIn(
      String dir,
      String id, {
      String? title,
      String? artist,
      int sizeBytes = 30 * 1024 * 1024,
      int durationMs = 250000,
    }) =>
        Track(
          provider: DriveProvider.quark,
          remoteId: id,
          name: '${title ?? id}.flac',
          path: '$dir/',
          sizeBytes: sizeBytes,
          title: title,
          artist: artist,
          durationMs: durationMs,
        );

    /// CD 规格整轨：765145628B / 1:12:18，CUE 分段从它切出来
    Track cueImage() => Track(
          provider: DriveProvider.quark,
          remoteId: 'wav-1',
          name: '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav',
          path: '$cueDir/',
          sizeBytes: 765145628,
          mimeType: 'audio/wav',
          durationMs: 4338000,
          artist: '李克勤',
          album: '精选到无朋友',
        );

    Track cueSeg(int no, int startMs, int durationMs, String title) =>
        Track.cueSegment(
          source: cueImage(),
          trackNo: no,
          startMs: startMs,
          durationMs: durationMs,
          title: title,
        );

    final allTracks = <Track>[
      trackIn(popDir, 'p1', title: '以父之名', artist: '周杰伦'),
      trackIn(popDir, 'p2', title: '晴天', artist: '周杰伦'),
      cueSeg(1, 0, 200493, '红日'),
      // 末轨的终点被补成整轨的真实时长（见 `CueIndexer._expandImage`），
      // 所以两段相加正好等于整轨总时长 4338000ms
      cueSeg(2, 200493, 4137507, '月半小夜曲'),
      // 合辑：两位不同的演唱者 → 副标题必须是「合辑」
      trackIn(compDir, 'c1', title: '雨夜', artist: '贵族音乐'),
      trackIn(compDir, 'c2', title: '催眠曲', artist: '某位女声'),
    ];

    List<TrackGroup> groups() =>
        LibraryGrouping.group(allTracks, LibraryGroupMode.album);

    List<Track> tracksOf(String dir) =>
        [for (final t in allTracks) if (LibraryGrouping.dirOf(t) == dir) t];

    AlbumCover coverOf(String dir, String fileId) => AlbumCover(
          provider: DriveProvider.quark,
          dirPath: dir,
          fileId: fileId,
          fileName: 'cover.jpg',
          sizeBytes: 820 * 1024,
        );

    /// 只有两张专辑有封面：CUE 那张刻意留空，用来验证占位图这条路。
    Map<String, AlbumCover> covers() => {
          popDir: coverOf(popDir, 'img-pop'),
          compDir: coverOf(compDir, 'img-comp'),
        };

    Map<String, List<Track>> tracksByDir() =>
        {for (final d in [popDir, cueDir, compDir]) d: tracksOf(d)};

    /// 渲染卡片墙，返回「谁真的去取了封面字节」。
    ///
    /// 取图是**懒加载**的：扫描只记路径，卡片显示时才取。这条断言守的就是
    /// 这个设计 —— 若哪天有人在扫描阶段就把图下下来，这里会立刻发现
    /// （`requested` 在 pump 之前就非空），而不是等用户抱怨扫描变慢。
    Future<List<AlbumCover>> pumpGrid(
      WidgetTester tester, {
      Size size = const Size(1280, 800),
      double textScale = 1.0,
      Map<String, AlbumCover>? coverMap,
      _RecordingPlayer? player,
      void Function(TrackGroup group)? onOpen,
    }) async {
      final requested = <AlbumCover>[];
      await pumpApp(
        tester,
        AlbumGridView(groups: groups(), onOpen: onOpen ?? (_) {}),
        size: size,
        textScale: textScale,
        extra: [
          libraryProvider.overrideWithValue(
            _FakeLibrary(covers: coverMap ?? covers(), tracksByDir: tracksByDir()),
          ),
          // 字节一律给 null：测试里不解码真图（解码要 runAsync 才走得完），
          // 而「取不到」本来就是占位图那条路
          coverBytesProvider.overrideWith((ref, cover) {
            requested.add(cover);
            return Future<Uint8List?>.value(null);
          }),
          playerProvider.overrideWith(() => player ?? _StubPlayer()),
        ],
      );
      // 封面是一次异步查询，多推一帧让它落地 —— 否则测到的是「一张封面
      // 都没有」的那一帧，占位图断言会假绿
      await tester.pump();
      return requested;
    }

    Future<void> pumpAlbumPage(
      WidgetTester tester, {
      required String dirPath,
      String? title,
      Size size = const Size(1280, 800),
      double textScale = 1.0,
      Map<String, List<Track>>? byDir,
      _RecordingPlayer? player,
    }) async {
      await pumpApp(
        tester,
        AlbumPage(dirPath: dirPath, albumTitle: title),
        size: size,
        textScale: textScale,
        extra: [
          libraryProvider.overrideWithValue(
            _FakeLibrary(covers: covers(), tracksByDir: byDir ?? tracksByDir()),
          ),
          coverBytesProvider.overrideWith(
            (ref, cover) => Future<Uint8List?>.value(null),
          ),
          playerProvider.overrideWith(() => player ?? _StubPlayer()),
        ],
      );
      await tester.pump();
    }

    testWidgets('每张专辑一张卡片：专辑名 +「艺术家 · N 首」', (tester) async {
      await pumpGrid(tester);

      expect(find.text('叶惠美'), findsOneWidget);
      expect(find.text('周杰伦 · 2 首'), findsOneWidget);
      expect(find.text('精选到无朋友'), findsOneWidget);
      expect(find.text('李克勤 · 2 首'), findsOneWidget);
      expect(
        find.text('睡眠轻音乐 钢琴与小提琴 雨夜催眠曲'),
        findsOneWidget,
        reason: '专辑名从目录名推断（`艺术家 - 专辑`），卡片上必须给出来',
      );
      expect(drain(tester), isNull);
    });

    testWidgets('CUE 角标只出现在整轨切出来的那张专辑上', (tester) async {
      await pumpGrid(tester);

      expect(
        find.text('CUE'),
        findsOneWidget,
        reason: '方案 A 里 CUE 的信息原本挂在分组头上，卡片墙没有分组头了，'
            '角标是这条信息唯一的落点',
      );
    });

    testWidgets('合辑不把第一首的演唱者当整张专辑的艺术家', (tester) async {
      await pumpGrid(tester);

      expect(find.text('合辑 · 2 首'), findsOneWidget);
      expect(
        find.text('贵族音乐 · 2 首'),
        findsNothing,
        reason: '合辑里每首歌的人都不同，写第一首的名字会让用户以为分组串了',
      );
    });

    testWidgets('点卡片回传的是那张专辑：键是目录路径，不是专辑名', (tester) async {
      final opened = <TrackGroup>[];
      await pumpGrid(tester, onOpen: opened.add);

      await tester.tap(find.text('叶惠美'));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(
        opened.single.key,
        popDir,
        reason: '详情页按目录取曲目 —— 专辑名是从目录名猜的，同名专辑会混在一起',
      );
    });

    testWidgets('卡片按需取封面：有封面引用的才取，没有的不发请求', (tester) async {
      final requested = await pumpGrid(tester);

      expect(
        requested.map((c) => c.fileId).toSet(),
        {'img-pop', 'img-comp'},
        reason: '扫描只记路径，字节在卡片显示时才取；'
            '没有封面引用的专辑不该产生任何请求',
      );
    });

    testWidgets('取不到字节时退回占位图，不报错也不留空白', (tester) async {
      await pumpGrid(tester);

      expect(find.byType(Image), findsNothing);
      expect(
        find.byType(AlbumArt),
        findsNWidgets(3),
        reason: '占位图常驻：字节到位但还没解码出第一帧的那一两帧不能是空白',
      );
      expect(drain(tester), isNull);
    });

    testWidgets('列数跟着窗口变：1280 是 7 列，600 是 3 列', (tester) async {
      SliverGridDelegateWithFixedCrossAxisCount delegateOf(WidgetTester t) =>
          t.widget<GridView>(find.byType(GridView)).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;

      await pumpGrid(tester, size: const Size(1280, 800));
      expect(delegateOf(tester).crossAxisCount, 7);

      await pumpGrid(tester, size: const Size(600, 800));
      expect(
        delegateOf(tester).crossAxisCount,
        3,
        reason: '固定列数会让窗口一窄卡片就被压扁',
      );
      expect(drain(tester), isNull);
    });

    testWidgets('窄窗口（600）下卡片不溢出', (tester) async {
      await pumpGrid(tester, size: const Size(600, 800));
      expect(drain(tester), isNull);
    });

    testWidgets('系统字号 1.6 倍也不溢出（卡片高度按 TextScaler 算）', (tester) async {
      await pumpGrid(tester, textScale: 1.6);
      expect(
        drain(tester),
        isNull,
        reason: '文字区高度与卡片宽度无关，写死 childAspectRatio 就会在这里溢出',
      );
    });

    testWidgets('窄窗口 + 系统字号 1.6 倍：超长专辑名省略而不是撑破卡片', (tester) async {
      await pumpGrid(tester, size: const Size(600, 800), textScale: 1.6);
      expect(drain(tester), isNull);
    });

    testWidgets('详情页：大封面 + 专辑名 + 统计行 + 曲目行', (tester) async {
      await pumpAlbumPage(tester, dirPath: popDir, title: '叶惠美');

      expect(find.text('叶惠美'), findsOneWidget);
      expect(
        find.text('周杰伦'),
        findsNWidgets(3),
        reason: '页头一行（专辑的艺术家）+ 两行曲目行的艺术家列',
      );
      expect(
        // 分钟不补零：界面走的是 `app_theme.dart` 里的 `formatDuration`
        // （`format.dart` 里同名那个补零，但没有任何 UI 在用，见文件末尾注释）
        find.text('2 首 · 8:20 · 60.0 MB'),
        findsOneWidget,
        reason: '曲目数 / 时长 / 体积三项都拿得到时都要给出来',
      );
      expect(find.text('播放全部'), findsOneWidget);
      expect(find.text('随机播放'), findsOneWidget);
      expect(
        find.text('晴天'),
        findsOneWidget,
        reason: '详情页的「组头」就是上面那块，组内仍然是普通曲目行',
      );
      expect(
        find.byTooltip('返回'),
        findsOneWidget,
        reason: '返回键常驻在内容之外 —— 加载中 / 出错时也要能退出去',
      );
      expect(drain(tester), isNull);
    });

    testWidgets('详情页的统计行不把 CUE 分段的整轨体积重复相加', (tester) async {
      await pumpAlbumPage(tester, dirPath: cueDir, title: '精选到无朋友');

      expect(
        // 体积 ≥100 时不留小数：界面走 `app_theme.dart` 的 `formatBytes`，
        // 所以是 `730 MB` 而不是 `729.7 MB`（见该函数的注释）
        find.text('2 首 · 1:12:18 · 730 MB'),
        findsOneWidget,
        reason: '两段各自带着整轨体积 765145628B，直接相加会变成 1.4 GB',
      );
    });

    testWidgets('详情页：CUE 专辑给出「整轨连播」，队列是整轨本身', (tester) async {
      final player = _RecordingPlayer();
      await pumpAlbumPage(
        tester,
        dirPath: cueDir,
        title: '精选到无朋友',
        player: player,
      );

      expect(find.text('WAV · CUE 分轨'), findsOneWidget);
      await tester.tap(find.text('整轨连播'));
      await tester.pump();

      expect(player.plays, hasLength(1));
      expect(player.plays.single.queue, hasLength(1));
      expect(player.plays.single.queue.single.remoteId, 'wav-1');
      expect(
        player.plays.single.queue.single.isCueSegment,
        isFalse,
        reason: '连播的必须是整轨本身，否则又要按 CUE 切一遍，等于没连',
      );
    });

    testWidgets('详情页：普通专辑不凭空多出「整轨连播」', (tester) async {
      await pumpAlbumPage(tester, dirPath: popDir, title: '叶惠美');

      expect(find.text('整轨连播'), findsNothing);
      expect(find.text('WAV · CUE 分轨'), findsNothing);
    });

    testWidgets('详情页：专辑空了显示空状态，返回键仍在', (tester) async {
      await pumpAlbumPage(
        tester,
        dirPath: '/音乐/华语/已删除的专辑',
        title: '已删除的专辑',
        byDir: const {},
      );

      expect(find.text('这张专辑现在是空的'), findsOneWidget);
      expect(
        find.byTooltip('返回'),
        findsOneWidget,
        reason: '空专辑页如果走不掉，用户只能重启应用',
      );
      expect(drain(tester), isNull);
    });

    testWidgets('详情页窄窗口（600）下信息列不溢出', (tester) async {
      await pumpAlbumPage(
        tester,
        dirPath: compDir,
        title: '睡眠轻音乐 钢琴与小提琴 雨夜催眠曲',
        size: const Size(600, 800),
      );
      expect(drain(tester), isNull);
    });

    testWidgets('详情页系统字号 1.6 倍也不溢出（三个按钮换行而不是挤出去）', (tester) async {
      await pumpAlbumPage(
        tester,
        dirPath: cueDir,
        title: '精选到无朋友',
        size: const Size(760, 800),
        textScale: 1.6,
      );
      expect(drain(tester), isNull);
    });
  });
}

/// 只实现专辑视图用到的两个方法：`albumCovers` 与 `queryTracks`。
///
/// 其余成员交给 `noSuchMethod` —— 页面一旦真的去调它们，测试会立刻炸出来，
/// 比悄悄返回一个默认值安全得多。
class _FakeLibrary implements LibraryRepository {
  _FakeLibrary({this.covers = const {}, this.tracksByDir = const {}});

  final Map<String, AlbumCover> covers;
  final Map<String, List<Track>> tracksByDir;

  @override
  Future<Map<String, AlbumCover>> albumCovers(DriveProvider provider) async =>
      covers;

  @override
  Future<List<Track>> queryTracks([TrackQuery query = const TrackQuery()]) async {
    final dir = query.dirPath;
    if (dir == null) return const [];
    return tracksByDir[dir] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记录 `playFrom` 的调用，用来断言「整轨连播」给的队列到底是什么。
class _RecordingPlayer extends PlayerNotifier {
  final List<({List<Track> queue, Track start})> plays = [];

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playFrom(List<Track> tracks, Track selected) async {
    plays.add((queue: List.of(tracks), start: selected));
  }
}

/// 固定状态的播放器，避免测试里去碰真实的播放引擎。
class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
