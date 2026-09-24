import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:cloudtune/ui/widgets/page_back_button.dart';
import 'package:cloudtune/ui/widgets/window_top_inset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 窗口顶部留白区。
///
/// 背景：系统标题栏已在 `macos/Runner/MainFlutterWindow.swift` 里抹成透明，
/// 窗口内容铺到最顶端；但红黄绿三个**原生按钮还浮在那里**，所以顶部必须
/// 留出一条空白给它们。这里钉住两件事：
///
///   1. **它什么都不画**。画了底色 / 下边框 / 文字，顶部就会变成「一条横条」，
///      看起来跟系统标题栏没去掉一样 —— 用户要的正是「没有标题栏」。
///      这条是需求的核心，不是审美偏好，所以用测试钉死。
///   2. 高度恒等于 [AppTheme.titleBarHeight]（实测对齐系统标题栏的 32pt），
///      任何窗口宽度和字号下都不许被撑高。
void main() {
  group('WindowTopInset（窗口顶部留白区）', () {
    /// 按真实用法渲染：留白区是内容列的第一项，下面是页面内容。
    Widget chromeLike() => Column(
          children: [
            const WindowTopInset(),
            const Expanded(child: SizedBox.expand()),
          ],
        );

    Future<void> pumpChrome(
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

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: chromeLike())),
      );
      await tester.pump();
    }

    testWidgets('什么都不画：没有文字、也没有底色或边框', (tester) async {
      await pumpChrome(tester);

      final inset = find.byType(WindowTopInset);

      expect(
        find.descendant(of: inset, matching: find.byType(Text)),
        findsNothing,
        reason: '顶部一旦出现文字，整条就会像「标题栏没去掉」——'
            '当前页名字由页面自己的大标题承担，不在这里重复',
      );
      expect(
        find.descendant(of: inset, matching: find.byType(DecoratedBox)),
        findsNothing,
        reason: '底色或下边框都会让顶部显出一条横条',
      );
    });

    testWidgets('高度就是令牌里的值（不许被任何东西撑高）', (tester) async {
      await pumpChrome(tester);

      expect(
        tester.getSize(find.byType(WindowTopInset)).height,
        AppTheme.titleBarHeight,
      );
    });

    testWidgets('窄窗口（420）下高度不变', (tester) async {
      await pumpChrome(tester, size: const Size(420, 640));

      expect(
        tester.getSize(find.byType(WindowTopInset)).height,
        AppTheme.titleBarHeight,
      );
    });

    testWidgets('系统字号 1.6 倍也不改变高度、不溢出', (tester) async {
      await pumpChrome(tester, textScale: 1.6);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(WindowTopInset)).height,
        AppTheme.titleBarHeight,
        reason: '留白区里没有文字，系统字号不该影响它',
      );
    });
  });

  group('PageBackButton（全屏页的返回入口）', () {
    testWidgets('放进工具行不溢出（播放页 / 授权浏览器页的真实用法）', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.fromLTRB(10, 6, 14, 0),
              child: Row(
                children: [
                  PageBackButton(),
                  Spacer(),
                  Text('我已登录'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
