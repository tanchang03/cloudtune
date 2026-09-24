import 'package:cloudtune/core/diagnostics/diag_log.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/library_grouping.dart';
import 'package:cloudtune/ui/pages/diagnostics_page.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/playback_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
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
}

/// 固定状态的播放器，避免测试里去碰真实的播放引擎。
class _StubPlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}
