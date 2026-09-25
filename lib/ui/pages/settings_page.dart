import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../data/remote/quark/quark_adapter.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/library_providers.dart';
import '../providers/lyrics_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/clear_library.dart';
import '../widgets/page_header.dart';

/// 设置页：账号、网盘能力、曲库统计、清空曲库。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final account = auth.valueOrNull?.account;
    final stats = ref.watch(libraryStatsProvider).valueOrNull;
    final caps = QuarkAdapter.quarkCapabilities;
    final scheme = Theme.of(context).colorScheme;

    // 联网歌词：开关状态 + 覆盖数。两个都是异步读库，没读完就按「还没数」显示。
    final network = ref.watch(lyricsNetworkEnabledProvider);
    final networkEnabled = network.valueOrNull ?? false;
    final networkBusy = network.isLoading;
    final lyricsStats = ref.watch(lyricsStatsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const PageHeader(
              title: '设置',
              hint: '所有数据仅存储于本机 · 不上传文件、播放记录或授权凭证',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                children: [
          _Section(title: '夸克账号', children: [
            if (account == null)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('尚未授权'),
                subtitle: const Text('登录后才能扫描与播放网盘里的音乐'),
                trailing: FilledButton(
                  onPressed: () => context.go('/auth'),
                  child: const Text('去授权'),
                ),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(account.label),
                subtitle: Text(
                  '${account.authMode.displayName} · 授权于 ${_fmt(account.authorizedAt)}',
                ),
                trailing: TextButton(
                  onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                  child: const Text('退出登录'),
                ),
              ),
              if (account.hasStorageInfo)
                _InfoRow(
                  label: '容量',
                  value: '${formatBytes(account.storageUsedBytes)} / '
                      '${formatBytes(account.storageTotalBytes)}',
                ),
              if (account.memberLabel != null)
                _InfoRow(label: '会员', value: account.memberLabel!),
            ],
          ]),
          _Section(title: '夸克网盘能力', children: [
            _InfoRow(label: '列目录遍历', value: caps.canListDirectory ? '支持' : '不支持'),
            _InfoRow(label: '关键词搜索', value: caps.canSearch ? '支持' : '不支持'),
            _InfoRow(label: '直链播放', value: caps.canResolveDirectLink ? '支持' : '不支持'),
            _InfoRow(label: '直链需带请求头', value: caps.directLinkNeedsHeaders ? '需要 (Cookie)' : '不需要'),
            _InfoRow(
              label: '播放取链上限',
              // 这里显示的是**播放取链**的上限。夸克为「无限制」是准确的：
              // 50MiB 那条是 /file/download（下载路由）的限制，
              // 播放走 /file/audioplay，实测 774MB 的文件也能拿到直链。
              value: caps.maxSingleFileBytes == null
                  ? '无限制'
                  : formatBytes(caps.maxSingleFileBytes),
            ),
            _InfoRow(label: '进度拖动 (Range)', value: caps.supportsRangeRequests ? '支持' : '不支持'),
          ]),
          _Section(title: '曲库数据', children: [
            if (stats == null || stats.isEmpty)
              const _InfoRow(label: '状态', value: '尚未扫描')
            else ...[
              _InfoRow(label: '曲目总数', value: '${stats.trackCount}'),
              _InfoRow(label: '确认可播', value: '${stats.playableCount}'),
              _InfoRow(label: '可尝试播放', value: '${stats.attemptableCount}'),
              _InfoRow(label: '收藏', value: '${stats.favoriteCount}'),
              _InfoRow(label: '总体积', value: formatBytes(stats.totalBytes)),
            ],
          ]),
          _Section(title: '歌词', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: networkEnabled,
              // 设置还没从库里读出来时先不给点：一个「点下去不知道会变成什么」
              // 的开关，比等一下更让人不放心。
              onChanged: networkBusy
                  ? null
                  : (v) => ref
                      .read(lyricsNetworkEnabledProvider.notifier)
                      .setEnabled(v),
              title: const Text('联网获取歌词', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '默认关闭。本地没有 .lrc 时，拿曲名/艺术家/专辑/时长到 LRCLIB 匹配',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            // 合规说明。三件事必须说清楚，缺一条都算没交代：
            //   ① 默认是关的（不打开就不会有任何联网行为）；
            //   ② 联网时**只发曲目元数据**，不发文件、不发播放记录、不发凭证；
            //   ③ 取到的歌词正文会落在本机索引库里（这是本应用唯一一处
            //      把第三方文本写进本地库的地方）。
            Text(
              '联网歌词默认关闭。开启后，播放一首本地没有 .lrc 的歌时，'
              '会把这首歌的曲名、艺术家、专辑名与时长发给 LRCLIB'
              '（一个公开的歌词库，无需注册）。'
              '不会上传网盘文件、播放记录或授权凭证；'
              '匹配到的歌词正文会存进本机索引库，退出后仍在，'
              '关闭本开关只是不再发起新的匹配。',
              style: TextStyle(
                fontSize: 11,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (lyricsStats == null)
              const _InfoRow(label: '歌词', value: '统计中…')
            else if (lyricsStats.isEmpty)
              const _InfoRow(label: '歌词', value: '尚未发现（先扫描一次曲库）')
            else ...[
              _InfoRow(label: '有歌词', value: '${lyricsStats.total} 首'),
              _InfoRow(label: '正文已就绪', value: '${lyricsStats.loaded} 首'),
              if (lyricsStats.pending > 0)
                _InfoRow(
                  label: '',
                  value: '另有 ${lyricsStats.pending} 首已找到 .lrc，'
                      '正文会在第一次播放时读取',
                ),
            ],
          ]),
          _Section(title: '操作', children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('清空曲库'),
              subtitle: const Text('删除本地索引（含收藏与播放历史），不影响网盘文件'),
              trailing: TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () => confirmAndClearLibrary(context, ref),
                child: const Text('清空'),
              ),
            ),
          ]),
          _Section(title: '排查', children: [
            _InfoRow(
              label: '凭证落盘',
              // 降级是**静默**发生的：界面看起来已登录，凭证其实只在内存里。
              // 放在设置页顶部显眼处，是为了让「每次打开都要重新登录」
              // 这类现象有个当场可查的解释。
              value: ref.watch(credentialStoreProvider).isDegraded
                  ? '否 · 安全存储不可用，重启后需重新登录'
                  : '是',
            ),
            _InfoRow(label: '沙箱容器', value: diag.isSandboxed ? '是' : '否'),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('诊断日志'),
              subtitle: Text(
                diag.filePath ?? '日志目录不可写，本次仅内存日志',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => context.push('/diagnostics'),
            ),
          ]),
          _Section(title: '关于', children: const [
            _InfoRow(label: '应用', value: '云韵 CloudTune'),
            _InfoRow(label: '跨网盘', value: '夸克已接入，阿里/百度规划中'),
            _InfoRow(label: '构建', value: 'Flutter 3.29 · macOS'),
            _LegalNotice(),
          ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// 法律声明。
///
/// `docs/03` §5 要求「授权页显著位置声明本应用为第三方独立客户端」，
/// 授权页已有（见 `auth_page.dart` 的 `_Footnote`）；这里再放一份，
/// 是为了让用户不必回到授权页也能随时查到使用边界。
///
/// 三句话各自对应一条风险，不要删改其中任何一条：
///   ① 切断「冒充官方/暗示背书」的认定可能；
///   ② 说明数据流向，回应隐私关切；
///   ③ 如实告知账号风险由使用者承担。
class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '本应用为第三方独立客户端，与夸克、阿里云盘、百度网盘官方均无关联，'
        '未获其授权或认可。仅用于播放你自己网盘中的文件；'
        '所有数据（含授权凭证）只存本机，不上传任何服务器。'
        '使用第三方客户端可能违反网盘服务协议并导致账号受限，该风险由使用者自行承担。',
        style: TextStyle(fontSize: 11, height: 1.7, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
