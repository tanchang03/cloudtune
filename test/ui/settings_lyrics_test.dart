import 'dart:async';

import 'package:cloudtune/domain/adapters/library_repository.dart';
import 'package:cloudtune/ui/pages/settings_page.dart';
import 'package:cloudtune/ui/providers/auth_providers.dart';
import 'package:cloudtune/ui/providers/library_providers.dart';
import 'package:cloudtune/ui/providers/lyrics_providers.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置页「歌词」分区的回归测试。
///
/// 联网歌词是本应用**唯一一处会把曲目信息发到第三方**的功能，也是唯一一处
/// 把第三方文本写进本地索引库的地方。所以这个开关有三条必须守住的口径，
/// 任何一条破了都比「歌词显示不出来」严重：
///
///   1. **默认关闭** —— 不看文档就装上，也绝不会有任何联网行为；
///   2. **开关状态是从库里读出来的**，不是写死的默认值 —— 否则界面上显示
///      「关」，实际却在联网匹配；
///   3. **界面要如实交代发了什么、存了什么**（合规说明那段文字）。
///
/// 这三条只有渲染出来才测得到，所以放在 widget 测试里，而不是只测 provider。
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required _FakeNetworkSetting network,
    AsyncValue<LyricsStats> stats = const AsyncData(LyricsStats(
      total: 120,
      loaded: 40,
    )),
    Size size = const Size(1060, 754),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 未授权状态：`AuthController.build()` 会去读凭证存储并开数据库。
          authControllerProvider.overrideWith(_StubAuth.new),
          libraryStatsProvider.overrideWith(
            (ref) async => const LibraryStats(
              trackCount: 0,
              playableCount: 0,
              attemptableCount: 0,
              overLimitCount: 0,
              unknownSizeCount: 0,
              favoriteCount: 0,
              totalBytes: 0,
              playableBytes: 0,
              artistCount: 0,
              albumCount: 0,
            ),
          ),
          lyricsNetworkEnabledProvider.overrideWith(() => network),
          lyricsStatsProvider.overrideWith((ref) async => stats.valueOrNull!),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsPage(),
        ),
      ),
    );
    // 设置与统计都是异步读库，多推几帧让它们落地
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Switch switchOf(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch));

  testWidgets('默认关闭：开关是关的，且文案写明「默认关闭」', (tester) async {
    await pumpSettings(tester, network: _FakeNetworkSetting(false));

    expect(switchOf(tester).value, isFalse);
    expect(
      find.textContaining('默认关闭'),
      findsWidgets,
      reason: '联网是本应用唯一一处对外发数据的功能，默认必须关着，'
          '而且要让用户看得出来这是默认状态',
    );
  });

  testWidgets('点开关 → 落到设置里（不是只改界面）', (tester) async {
    final network = _FakeNetworkSetting(false);
    await pumpSettings(tester, network: network);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(network.writes, [true], reason: '只改界面不落库，下次启动又会变回关');
    expect(switchOf(tester).value, isTrue);
  });

  testWidgets('设置还没读出来时不给点：不留「点下去不知道会变成什么」的开关',
      (tester) async {
    final network = _FakeNetworkSetting(false, loading: true);
    await pumpSettings(tester, network: network);

    expect(
      switchOf(tester).onChanged,
      isNull,
      reason: '开关的初值来自库；没读出来就让人点，等于让他猜现在到底是开还是关',
    );
  });

  testWidgets('合规说明交代了「发什么、存什么」', (tester) async {
    await pumpSettings(tester, network: _FakeNetworkSetting(false));

    expect(
      find.textContaining('不会上传网盘文件、播放记录或授权凭证'),
      findsOneWidget,
      reason: '这是用户唯一能知道「联网到底发了什么」的地方，缺一句就是没交代',
    );
    expect(
      find.textContaining('存进本机索引库'),
      findsOneWidget,
      reason: '歌词正文是本应用唯一写入本地库的第三方文本，必须写明',
    );
  });

  testWidgets('覆盖数：有歌词与「正文已就绪」分开显示，并说明差值去哪了',
      (tester) async {
    await pumpSettings(tester, network: _FakeNetworkSetting(false));

    expect(find.text('有歌词'), findsOneWidget);
    expect(find.text('120 首'), findsOneWidget);
    expect(find.text('正文已就绪'), findsOneWidget);
    expect(find.text('40 首'), findsOneWidget);
    expect(
      find.textContaining('另有 80 首已找到 .lrc，正文会在第一次播放时读取'),
      findsOneWidget,
      reason: '扫描只记引用、正文等第一次播放才读（见 LyricsResolver）。'
          '不给这句解释，用户会以为这 80 首是坏了',
    );
  });

  testWidgets('一首歌词都没有时不报 0，而是提示先扫描', (tester) async {
    await pumpSettings(
      tester,
      network: _FakeNetworkSetting(false),
      stats: const AsyncData(LyricsStats(total: 0, loaded: 0)),
    );

    expect(find.text('尚未发现（先扫描一次曲库）'), findsOneWidget);
    expect(find.text('有歌词'), findsNothing);
  });

  testWidgets('设置页整体不溢出（新增分区后）', (tester) async {
    await pumpSettings(tester, network: _FakeNetworkSetting(false));

    expect(tester.takeException(), isNull);
  });
}

/// 记下 `setEnabled` 的调用，避免测试去碰真实数据库。
class _FakeNetworkSetting extends LyricsNetworkSetting {
  _FakeNetworkSetting(this.initial, {this.loading = false});

  final bool initial;
  final bool loading;

  final List<bool> writes = [];

  @override
  Future<bool> build() async {
    if (loading) {
      // 模拟「设置还没从库里读出来」
      return await Completer<bool>().future;
    }
    return initial;
  }

  @override
  Future<void> setEnabled(bool value) async {
    writes.add(value);
    state = AsyncData(value);
  }
}

/// 未授权状态，避免去读凭证存储与网盘适配器。
class _StubAuth extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState();
}
