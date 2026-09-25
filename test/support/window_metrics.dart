import 'dart:ui' show Size;

/// 窗口的默认尺寸 —— 同时也是**允许的最小尺寸**。
///
/// 真正的源头是 `macos/Runner/Base.lproj/MainMenu.xib` 里的 `contentRect`；
/// 原生侧 `MainFlutterWindow.applyMinimumSize()` 从当前 frame 反算，
/// 也不写死数字。这个常量是**测试侧的镜像**，存在的意义只有一个：
/// 让「按最小尺寸渲染界面」和「核对 xib 没漂」这两件事用同一个数。
///
/// 谁在盯着它：
///   - `test/macos/min_window_size_test.dart` —— 核对 xib 的 `contentRect`
///     确实等于这个值，且原生侧用的是 `contentMinSize` 而不是 `minSize`；
///   - `test/ui/app_shell_layout_test.dart` —— 按这个尺寸渲染界面，
///     确认真的不溢出。
///
/// 两边都要，是因为下限设错在原生侧完全看不出来：把 `contentMinSize`
/// 设成 800 一样能构建、能运行、能拖动，只有把界面按那个尺寸渲染一遍
/// 才会发现挤爆了。
const Size kDefaultWindowSize = Size(1060, 754);
