import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    applyVirtualTitleBar()

    super.awakeFromNib()
  }

  /// 抹掉系统标题栏，让窗口内容一路铺到最顶端。
  ///
  /// 三个开关各管一件事，缺一不可：
  ///   - `titlebarAppearsTransparent`：标题栏不再画自己的底色，
  ///     于是 Flutter 的内容能一直铺到窗口最顶端；
  ///   - `titleVisibility = .hidden`：不画窗口标题文字。
  ///     应用名字改由各页面自己的标题承担（如「音乐库」）——
  ///     顶部那条横条**故意什么都不画**，画了就像系统标题栏没去掉；
  ///   - `.fullSizeContentView`：内容视图铺满整个窗口（含标题栏那 32pt），
  ///     否则顶上会留一条我们画不到的空白。
  ///
  /// 注意红黄绿三个按钮**仍然浮在左上角**，位置由 AppKit 决定
  /// （实测 x 约 9..69、圆心距顶 16）。Flutter 侧靠
  /// `AppTheme.titleBarHeight = 32` 的顶部留白给它们让位 ——
  /// 那个值等于 `NSTitlebarView` 的实际高度，所以圆点正好落在留白中线。
  ///
  /// **刻意保留原生红黄绿三个按钮**：它们才是真正的窗口控制（关闭 / 最小化 /
  /// 缩放 / 全屏），自带悬停符号、辅助功能、双击标题栏缩放、键盘快捷键。
  /// 原型里的三个圆点只是 HTML 画不出原生按钮的替代品，真机上再画一遍
  /// 只会得到三个不能用的假按钮，还得自己补全屏和辅助功能。
  ///
  /// 同理**不打开 `isMovableByWindowBackground`**：标题栏区域本身就能拖动窗口
  /// （标题栏视图在内容视图之上），而打开那个开关会让 Flutter 视图上任意空白处
  /// 的拖拽都变成拖窗口，把列表滚动、进度条拖动这些手势一起抢掉。
  private func applyVirtualTitleBar() {
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    styleMask.insert(.fullSizeContentView)

    // macOS 11 起系统可能在标题栏与内容之间再画一条分隔线，
    // 会和我们虚拟标题栏自己的下边框叠成两条，关掉。
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
  }
}
