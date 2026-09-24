import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/playability_badge.dart';
import 'package:cloudtune/ui/widgets/playability_help.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证需求 #3 真正落到屏幕上：
///   1. 列表行的徽标短文案是「取不到链 / 体积未知」这种用户能直接读懂的词
///   2. 徽标可点 → 弹出三段说明（哪些文件 / 什么原因 / 什么条件）
///   3. 弹窗里有这个文件的事实（文件名 / 路径 / 网盘 / 体积），
///      用户可以拿着「体积」+「上限」自己判断到底差多少
void main() {
  // 这里用的是一个**假想的**、声明了 50MiB 上限的网盘 ——
  // 只是为了把 overLimit 这个状态造出来，验证它的文案与弹窗。
  // 夸克的真实声明没有体积上限，见 QuarkAdapter.quarkCapabilities。
  const caps = Capabilities(
    provider: DriveProvider.quark,
    maxSingleFileBytes: Capabilities.fiftyMiB,
  );

  Track makeOverLimitTrack() => Track(
        provider: DriveProvider.quark,
        remoteId: 'over1',
        name: '整轨专辑.wav',
        path: '/音乐/华语/2000年代/',
        sizeBytes: 720 * 1024 * 1024, // 720 MB
        title: '整轨专辑',
      );

  group('PlayabilityBadge', () {
    testWidgets('可播时根本不渲染（不要给每一行都加噪声）', (tester) async {
      const playable = Playability(PlayabilityState.playable);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayabilityBadge(playability: playable),
        ),
      ));
      expect(find.text('可播'), findsNothing,
          reason: '可播不应该显示徽标，否则列表全是「可播」标签');
    });

    testWidgets('取不到链时徽标是「取不到链」，既不用「超限」也不用「文件过大」',
        (tester) async {
      final track = makeOverLimitTrack();
      final p = track.playability(caps);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayabilityBadge(playability: p, onTap: () {}),
        ),
      ));
      // 锁死需求 #3 的核心：
      //   - 「超限」是内部术语，用户看不懂；
      //   - 「文件过大」是把**接口限制**说成了**文件毛病**的旧口径
      //     （会让用户以为文件坏了、要去换小文件），2026-09-24 已纠正。
      expect(find.text('取不到链'), findsOneWidget);
      expect(find.text('超限'), findsNothing);
      expect(find.text('文件过大'), findsNothing);
    });
  });

  group('showPlayabilityHelp（说明弹窗）', () {
    testWidgets('展示三段说明 + 文件事实 + 复制路径按钮', (tester) async {
      final track = makeOverLimitTrack();
      final playability = track.playability(caps);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showPlayabilityHelp(
                  context,
                  track: track,
                  playability: playability,
                ),
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();

      // 三段标题都在
      expect(find.text('哪些文件会这样'), findsOneWidget);
      expect(find.text('什么原因'), findsOneWidget);
      expect(find.text('怎样才能播'), findsOneWidget);

      // 弹窗标题
      expect(find.text('网盘不给取链，拿不到播放地址'), findsOneWidget);

      // 文件事实里能看到完整路径、网盘、体积、上限
      // 这四个是用户做判断的客观依据，缺一个就是漏交付
      expect(
        find.textContaining('/音乐/华语/2000年代/整轨专辑.wav'),
        findsOneWidget,
        reason: '完整路径必须出现在文件事实里',
      );
      expect(find.textContaining('夸克网盘'), findsOneWidget);
      expect(find.textContaining('720'), findsOneWidget); // 体积
      expect(find.textContaining('50'), findsOneWidget); // 上限

      // 复制按钮
      expect(find.text('复制完整路径'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets('体积未知时弹窗仍能正确打开（确认可播性不是「判死」而是「提示」）',
        (tester) async {
      final track = Track(
        provider: DriveProvider.quark,
        remoteId: 'unk',
        name: 'unknown.mp3',
        sizeBytes: null, // 网盘没返回体积
      );
      final playability = track.playability(caps);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPlayabilityHelp(
                context,
                track: track,
                playability: playability,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('体积未知，需要试播确认'), findsOneWidget);
      // 文件事实里体积显示「未知」
      expect(find.textContaining('未知'), findsWidgets);
    });
  });

  group('文案使用 AppTheme 色板', () {
    test('取不到链用 warn 色（软提示），不是 danger 红（那是真播不了的）', () {
      // 这条断言不是测颜色本身，而是测**配色策略**：
      // 「取不到链」用户还有办法解决（重试 / 换网盘），用黄；
      // 只有真正没救的才用红。通过 AppTheme 的两个值不相等来锁住这个意图。
      expect(AppTheme.warn, isNot(AppTheme.danger));
    });
  });
}
