import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/cloud_account.dart';
import '../../domain/entities/drive_provider.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';

/// 授权页。
///
/// 夸克没有开放平台 `client_id`，所以主链路是「打开登录页 → 用户正常登录 →
/// 抓取本次会话凭证」；手动粘贴 Cookie 作为兜底。
class AuthPage extends ConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(authControllerProvider).valueOrNull ?? const AuthState();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            children: [
              const _Header(),
              const SizedBox(height: 28),
              if (state.error != null) ...[
                _Banner(
                  icon: Icons.error_outline,
                  color: scheme.error,
                  text: state.error!,
                ),
                const SizedBox(height: 16),
              ],
              if (state.storageDegraded) ...[
                _Banner(
                  icon: Icons.warning_amber_outlined,
                  color: scheme.tertiary,
                  text: '系统安全存储不可用，凭证只保留在内存里：'
                      '本次会话有效，退出应用后需要重新授权。',
                ),
                const SizedBox(height: 16),
              ],
              _QuarkCard(state: state),
              const SizedBox(height: 12),
              const _PlannedCard(provider: DriveProvider.aliyun),
              const SizedBox(height: 12),
              const _PlannedCard(provider: DriveProvider.baidu),
              const SizedBox(height: 28),
              _Footnote(scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 原型 .hero .big：64×64 圆角 20，品牌渐变 + 品牌音符
        const AppLogo(size: 64, radius: 20),
        const SizedBox(height: 18),
        const Text(
          '连接你的网盘',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '授权后即可把网盘里的音乐聚合成一个音乐库，'
          '在线直连播放 —— 不下载、不搬家。',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.7,
            color: AppTheme.muted,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.6, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuarkCard extends ConsumerWidget {
  const _QuarkCard({required this.state});

  final AuthState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final account = state.account;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProviderAvatar(provider: DriveProvider.quark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DriveProvider.quark.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account == null ? '未授权' : '已授权',
                        style: TextStyle(
                          fontSize: 12,
                          color: account == null
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (account == null)
              ..._unauthorized(context, ref, scheme)
            else
              ..._authorized(context, ref, scheme, account),
          ],
        ),
      ),
    );
  }

  List<Widget> _unauthorized(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    return [
      Text(
        '推荐用「扫码登录」：打开夸克 App 扫二维码并确认即可，全程不接触账号密码。'
        '凭证只写入系统钥匙串，不会落到数据库或日志里。',
        style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: state.busy ? null : () => context.push('/auth/qr'),
          icon: const Icon(Icons.qr_code_2, size: 18),
          label: const Text('扫码登录'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: state.busy ? null : () => context.push('/auth/browser'),
          icon: const Icon(Icons.login, size: 18),
          label: const Text('浏览器登录授权'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: state.busy ? null : () => _promptManualCookie(context, ref),
          icon: const Icon(Icons.content_paste, size: 18),
          label: const Text('手动粘贴 Cookie'),
        ),
      ),
    ];
  }

  List<Widget> _authorized(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    CloudAccount account,
  ) {
    return [
      _InfoRow(label: '账号', value: account.label),
      if (account.memberLabel != null)
        _InfoRow(label: '会员', value: account.memberLabel!),
      if (account.hasStorageInfo)
        _InfoRow(
          label: '容量',
          value: '${formatBytes(account.storageUsedBytes)}'
              ' / ${formatBytes(account.storageTotalBytes)}',
        ),
      _InfoRow(label: '授权方式', value: account.authMode.displayName),
      _InfoRow(label: '授权时间', value: _formatTime(account.authorizedAt)),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  state.busy ? null : () => context.push('/auth/browser'),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新登录'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextButton.icon(
              onPressed: state.busy
                  ? null
                  : () => ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('退出登录'),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _promptManualCookie(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴夸克 Cookie'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '在已登录夸克的浏览器里打开开发者工具 → Network → 任意请求 → '
                '复制请求头里的 Cookie 整段粘贴进来。关键字段是 __pus 与 __puus。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '__pus=...; __puus=...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('授权'),
          ),
        ],
      ),
    );

    final raw = controller.text.trim();
    controller.dispose();
    if (confirmed != true || raw.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final credential = ref
          .read(manualAuthorizerProvider)
          .parse(DriveProvider.quark, raw);
      final error =
          await ref.read(authControllerProvider.notifier).authorize(credential);
      if (error != null) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// 尚未接入的网盘。明确说明「为什么没有」比直接隐藏更有用。
class _PlannedCard extends StatelessWidget {
  const _PlannedCard({required this.provider});

  final DriveProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ProviderAvatar(provider: provider, dimmed: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '适配器待实现 · ${provider.notes}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, height: 1.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Chip(
              label: const Text('规划中', style: TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({required this.provider, this.dimmed = false});

  final DriveProvider provider;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: dimmed
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  provider.brandColor.withValues(alpha: 0.35),
                  provider.brandDark.withValues(alpha: 0.35),
                ],
              )
            : provider.brandGradient,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        provider.badgeLetter,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.3,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // 这段是**法律声明**，不是普通说明文案：docs/03 §5 要求「授权页显著位置
    // 声明本应用为第三方独立客户端，与各网盘官方无关联」。它同时承担三件事：
    // ① 切断「冒充官方」的认定可能；② 说明数据流向（只存本机）以回应隐私关切；
    // ③ 如实告知取链走的是未公开接口，可能失效。改文案前先想清楚这三条。
    return Text(
      '本应用为第三方独立客户端，与夸克官方无关联、未获其授权或认可。'
      '登录在夸克官方页面完成，凭证只从本应用自己的会话读取、仅存本机钥匙串，'
      '不上传任何服务器。取链使用夸克客户端的未公开接口，可能随官方调整随时失效；'
      '请仅用于播放你自己网盘中的文件。',
      style: TextStyle(fontSize: 11, height: 1.7, color: scheme.onSurfaceVariant),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
