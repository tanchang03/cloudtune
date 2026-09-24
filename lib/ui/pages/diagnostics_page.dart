import 'package:flutter/material.dart';

import '../../core/diagnostics/diag_log.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import '../widgets/page_back_button.dart';
import '../widgets/page_header.dart';

/// 诊断日志页。
///
/// 存在的理由：release 模式**没有控制台**。用户说「播不了」时，能拿到的
/// 只有一句口头描述，而真正的分界线（凭证有没有读到、HTTP 通不通、
/// 网盘给了什么业务码、播放器为什么拒收）全在进程内部。
/// 这个页面把这些事实摊开给用户看，也让他能一键复制出来。
///
/// 刻意不做的事：
///   - **不删日志文件**。「清空」只清内存里这份显示用的缓冲 ——
///     文件是取证材料，要删让用户自己去访达删，免得手滑毁掉现场。
///   - **不做日志分级过滤**。日志量本来就不大（一次播放几十行），
///     加过滤器反而会让人漏掉关键的那一行。
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final ScrollController _scroll = ScrollController();

  /// 是否自动跟随最新一行。用户往上翻时自动关掉，翻回底部再打开。
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _follow) setState(() => _follow = atBottom);
  }

  void _scrollToBottomSoon() {
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              title: '诊断日志',
              hint: 'release 模式看不到控制台，这里把关键链路的事实落成可复制的文本',
              actions: [
                const PageBackButton(),
                ValueListenableBuilder<int>(
                  valueListenable: diag.revision,
                  builder: (context, _, __) => TextButton.icon(
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('复制全部'),
                    onPressed: diag.lines.isEmpty
                        ? null
                        : () => copyText(
                              context,
                              diag.dump(),
                              label: '已复制 ${diag.lines.length} 行日志',
                            ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('清空显示'),
                  onPressed: () => diag.clearBuffer(),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: _LogFileCard(),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: diag.revision,
                builder: (context, _, __) {
                  final lines = diag.lines;
                  if (lines.isEmpty) {
                    return const Center(
                      child: Text(
                        '还没有日志。\n去播放一首歌，或者重新扫描一次，再回来这里。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.dim),
                      ),
                    );
                  }
                  _scrollToBottomSoon();
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                    itemCount: lines.length,
                    itemBuilder: (context, i) => _LogLine(
                      text: lines[i],
                      onTap: () => copyText(context, lines[i], label: '已复制该行'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日志文件位置与运行环境摘要。
///
/// 这一段是**给用户看的第一眼**：日志到底写去哪了、当前是不是跑在沙箱里。
/// 这两个事实决定了「为什么同一个 app 换个 build 就行为不一样」。
class _LogFileCard extends StatelessWidget {
  const _LogFileCard();

  @override
  Widget build(BuildContext context) {
    final path = diag.filePath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 14, color: AppTheme.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  path ?? '日志目录不可写，本次仅保留内存日志',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.muted,
                    height: 1.4,
                  ),
                ),
              ),
              if (path != null)
                TextButton(
                  onPressed: () => copyText(context, path, label: '已复制路径'),
                  child: const Text('复制路径', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '沙箱容器：${diag.isSandboxed ? "是" : "否"}'
            '${diag.isSandboxed ? "（数据目录被重定向，与未沙箱的 build 不共享曲库）" : ""}',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: diag.isSandboxed ? AppTheme.warn : AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行日志。级别用颜色区分，长行自动折行。
class _LogLine extends StatelessWidget {
  const _LogLine({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: const ['PingFang SC'],
            fontSize: 10.5,
            height: 1.5,
            color: _colorFor(text),
          ),
        ),
      ),
    );
  }

  static Color _colorFor(String line) {
    if (line.contains(' ERROR ')) return AppTheme.danger;
    if (line.contains(' WARN ')) return AppTheme.warn;
    // 分段标题高亮，方便肉眼把「一次播放」切成块
    if (line.contains('[分段]')) return AppTheme.accent;
    return AppTheme.muted;
  }
}
