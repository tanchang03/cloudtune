import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 全屏页左上角的返回入口。
///
/// 系统标题栏被抹掉之后，`Scaffold.appBar` 会显得像「第二条标题栏」——
/// 顶上一条虚拟标题栏，下面再压一条 56px 的 AppBar，很挤。
/// 所以全屏页不再用 AppBar，改用它：一个不带底色的图标按钮，
/// 高度比 AppBar 矮，把纵向空间还给内容。
class PageBackButton extends StatelessWidget {
  const PageBackButton({
    super.key,
    this.icon = Icons.arrow_back,
    this.tooltip = '返回',
  });

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon),
        onPressed: () => context.pop(),
      ),
    );
  }
}
