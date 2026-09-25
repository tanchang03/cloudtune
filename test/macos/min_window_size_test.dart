import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../support/window_metrics.dart';

/// 解析 xib 里某个 `<rect>` 的宽高。
///
/// 故意不引 plist 解析依赖 —— 理由同 `entitlements_test.dart`：这个文件
/// 由 Xcode 生成、结构固定，按 `<rect key="…" …/>` 抓就够可靠，
/// 为一条断言拉一个依赖不划算。
///
/// 注意 xib 是 XML 属性序**不保证**的，所以先把整个标签的属性串抓出来，
/// 再逐个属性读 —— 不能要求 `key` 紧跟 `<rect`。
({double width, double height})? parseRect(String xml, String key) {
  final tag = RegExp(r'<rect\s+([^/>]+)/>');
  final keyPattern = RegExp('key="${RegExp.escape(key)}"');

  for (final m in tag.allMatches(xml)) {
    final attrs = m.group(1)!;
    if (!keyPattern.hasMatch(attrs)) continue;

    double? read(String name) {
      final a = RegExp('$name="([0-9.]+)"').firstMatch(attrs);
      return a == null ? null : double.tryParse(a.group(1)!);
    }

    final w = read('width');
    final h = read('height');
    if (w == null || h == null) return null;
    return (width: w, height: h);
  }
  return null;
}

/// 窗口尺寸下限的**原生侧**守卫。
///
/// 下限这件事横跨三层，任何一层单独测都测不完整：
///   1. `MainMenu.xib` 的 `contentRect` —— 默认尺寸，也是最小尺寸的来源；
///   2. `MainFlutterWindow.swift` —— 把 (1) 变成 AppKit 的 `contentMinSize`；
///   3. 界面本身在 (1) 那个尺寸下不溢出 —— 由 `test/ui/app_shell_layout_test.dart` 守。
///
/// 这个文件守 (1) 和 (2)。为什么 (2) 值得测：`contentMinSize` 写成常量、
/// 写成 `.zero`、或者误用 `minSize`，**全都照样构建、照样运行**，
/// 只有真的去拖窗口才会发现问题 —— 那已经是手工测试的范畴了。
void main() {
  final xibFile = File('macos/Runner/Base.lproj/MainMenu.xib');
  final swiftFile = File('macos/Runner/MainFlutterWindow.swift');

  late String xib;
  late String swift;

  setUpAll(() {
    xib = xibFile.readAsStringSync();
    swift = swiftFile.readAsStringSync();
  });

  group('解析器自身', () {
    test('能读出 width/height，且不依赖属性顺序', () {
      expect(
        parseRect('<rect key="contentRect" x="0" y="0" width="10" height="20"/>',
            'contentRect'),
        (width: 10, height: 20),
      );
      expect(
        parseRect('<rect width="10" key="contentRect" height="20"/>',
            'contentRect'),
        (width: 10, height: 20),
      );
    });

    test('键名不匹配时返回 null，不会串到别的 rect', () {
      const xml = '<rect key="frame" width="1" height="2"/>';
      expect(parseRect(xml, 'contentRect'), isNull);
    });
  });

  group('xib 里的默认尺寸', () {
    test('contentRect 就是测试里钉的那个尺寸', () {
      final rect = parseRect(xib, 'contentRect');
      expect(rect, isNotNull, reason: 'xib 里找不到 contentRect，窗口默认尺寸的源头没了');

      // 这里失败通常意味着**默认尺寸改了**：改 xib 是对的，但要同时把
      // `kDefaultWindowSize` 改掉 —— 否则界面会按旧尺寸做布局回归，
      // 而真实下限已经是新值，等于测了个不存在的窗口。
      expect(
        Size(rect!.width, rect.height),
        kDefaultWindowSize,
        reason: 'xib 的 contentRect 与 test/support/window_metrics.dart 不一致',
      );
    });

    test('窗口是 resizable 的，否则「不允许更小」无从谈起', () {
      // 不可缩放的窗口本来就没法变小，下限设了也是摆设；
      // 更糟的是这条如果悄悄变成 NO，下面的约束测试会全绿但毫无意义。
      expect(
        RegExp(r'<windowStyleMask[^/]*resizable="YES"').hasMatch(xib),
        isTrue,
        reason: '窗口不可缩放时，最小尺寸的约束就是个摆设',
      );
    });

    test('窗口类是我们自己的 MainFlutterWindow', () {
      // 如果窗口换回普通 NSWindow，`MainFlutterWindow.swift` 里的
      // `awakeFromNib` 就不会被调用，下限静默失效。
      expect(
        RegExp(r'<window[^>]*customClass="MainFlutterWindow"').hasMatch(xib),
        isTrue,
        reason: '窗口不是 MainFlutterWindow 的话，下面的 Swift 约束根本不会生效',
      );
    });
  });

  group('原生侧的最小尺寸约束', () {
    test('awakeFromNib 里确实调用了 applyMinimumSize', () {
      final awake = RegExp(
        r'override func awakeFromNib\(\)\s*\{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(swift);
      expect(awake, isNotNull, reason: '找不到 awakeFromNib 的实现');
      expect(
        awake!.group(1),
        contains('applyMinimumSize()'),
        reason: '定义了不调用，等于没设',
      );
    });

    test('用 contentMinSize 而不是 minSize', () {
      // `minSize` 约束的是**窗口 frame**（含标题栏那一段）。默认尺寸
      // 1060×754 是 contentRect 的值，把它当 frame 上限设进去，
      // 内容区会比预期矮一截。
      expect(
        RegExp(r'contentMinSize\s*=').hasMatch(swift),
        isTrue,
        reason: '约束内容区要用 contentMinSize',
      );
      expect(
        RegExp(r'(?<![A-Za-z])minSize\s*=').hasMatch(swift),
        isFalse,
        reason: 'minSize 约束的是含标题栏的 frame，会算错高度',
      );
    });

    test('最小尺寸从当前 frame 反算，不写死数字', () {
      // 写死成 NSSize(width: 1060, height: 754) 也能跑，但那样 xib 和
      // Swift 就成了两个独立的真值来源 —— 以后改 xib 默认尺寸，
      // 最小尺寸会留在旧值上，只在小窗口下才暴露。
      expect(
        swift,
        contains('contentRect(forFrameRect: frame).size'),
        reason: '应当从 frame 反算，让默认尺寸只有 xib 一个源头',
      );
    });

    test('没有踩 contentMinSize = .zero 这个哨兵值', () {
      // AppKit 里 `.zero` 不是「最小为 0」，而是「用系统默认」，
      // 那个值比我们想要的**小**，等于约束没设。
      expect(
        RegExp(r'contentMinSize\s*=\s*(\.zero|NSSize\.zero|CGSize\.zero)')
            .hasMatch(swift),
        isFalse,
        reason: '.zero 在 AppKit 里表示「交给系统默认」，不是「最小为零」',
      );
    });

    test('applyMinimumSize 是 private，不往外暴露', () {
      expect(
        RegExp(r'private func applyMinimumSize\(\)').hasMatch(swift),
        isTrue,
      );
    });
  });
}
