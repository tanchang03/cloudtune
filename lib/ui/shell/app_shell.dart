import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/drive_provider.dart';
import '../providers/auth_providers.dart';
import '../providers/library_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/player_bar.dart';

/// 应用外壳，1:1 对齐设计原型桌面端 `.desk-body` + `.playerbar`。
///
/// 宽屏：左侧 196px 侧边栏（品牌 / 导航带计数 / 网盘账号 / 底部设置）
///       + 右侧主区，最下方一条 74px 播放条横贯整个窗口。
/// 窄屏：退化成底部导航栏 + 播放条（原型移动端形态）。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// 与设计原型侧边栏一致的三个导航项 + 设置（设置固定在底部）。
  static const List<(IconData, String)> _destinations = [
    (Icons.library_music_outlined, '音乐库'),
    (Icons.favorite_outline, '我的喜欢'),
    (Icons.cloud_sync_outlined, '扫描'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppTheme.isWide(context)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: shell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlayerBar(),
            NavigationBar(
              backgroundColor: AppTheme.panel,
              surfaceTintColor: Colors.transparent,
              selectedIndex: shell.currentIndex.clamp(0, 3),
              onDestinationSelected: _go,
              destinations: [
                for (final (icon, label) in _destinations)
                  NavigationDestination(icon: Icon(icon), label: label),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _Sidebar(shell: shell),
                Expanded(child: shell),
              ],
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  void _go(int index) => shell.goBranch(
        index,
        // 再点一次当前项：回到该分支的初始页面（常见的「回顶」行为）
        initialLocation: index == shell.currentIndex,
      );
}

/// 196px 侧边栏。
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryCount = ref.watch(libraryTracksProvider).valueOrNull?.length;
    final favoritesCount =
        ref.watch(favoritesTracksProvider).valueOrNull?.length;
    final authorized =
        ref.watch(authControllerProvider).valueOrNull?.isAuthorized ?? false;
    final current = shell.currentIndex;

    return Container(
      width: AppTheme.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(right: BorderSide(color: AppTheme.line)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 16, 11, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 品牌区（原型 .sidebar .brand）
          const Padding(
            padding: EdgeInsets.only(left: 6, right: 6, bottom: 16),
            child: Row(
              children: [
                AppLogo(size: 27, radius: 8),
                SizedBox(width: 9),
                Text(
                  'CloudTune',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
              ],
            ),
          ),
          _NavItem(
            icon: AppShell._destinations[0].$1,
            label: AppShell._destinations[0].$2,
            count: libraryCount,
            selected: current == 0,
            onTap: () => shell.goBranch(0, initialLocation: current == 0),
          ),
          _NavItem(
            icon: AppShell._destinations[1].$1,
            label: AppShell._destinations[1].$2,
            count: favoritesCount,
            selected: current == 1,
            onTap: () => shell.goBranch(1, initialLocation: current == 1),
          ),
          _NavItem(
            icon: AppShell._destinations[2].$1,
            label: AppShell._destinations[2].$2,
            selected: current == 2,
            onTap: () => shell.goBranch(2, initialLocation: current == 2),
          ),
          const SizedBox(height: 14),
          // 分组标题（原型里是「网盘账号」）
          const Padding(
            padding: EdgeInsets.only(left: 11, bottom: 4),
            child: Text(
              '网盘账号',
              style: TextStyle(fontSize: 11, color: AppTheme.dim),
            ),
          ),
          for (final provider in DriveProvider.values)
            _DriveItem(
              provider: provider,
              status: _statusOf(provider, authorized),
              onTap: () => shell.goBranch(3, initialLocation: false),
            ),
          const Spacer(),
          _NavItem(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: current == 3,
            onTap: () => shell.goBranch(3, initialLocation: current == 3),
          ),
        ],
      ),
    );
  }

  /// 账号状态文案。夸克看真实授权态；其余两家适配器还没接入。
  static String _statusOf(DriveProvider provider, bool authorized) {
    if (provider == DriveProvider.quark) {
      return authorized ? '已连' : '未连';
    }
    return '未接';
  }
}

/// 导航项（原型 .nav-item）：选中态是主色 14% 底 + #a9c3ff 文字。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? AppTheme.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? const Color(0xFFA9C3FF) : AppTheme.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? const Color(0xFFA9C3FF) : AppTheme.muted,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: const TextStyle(fontSize: 11, color: AppTheme.dim),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 网盘账号行（原型里是「色点 + 名称 + 状态」）。
class _DriveItem extends StatelessWidget {
  const _DriveItem({
    required this.provider,
    required this.status,
    required this.onTap,
  });

  final DriveProvider provider;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final connected = status == '已连';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: connected
                        ? provider.brandColor
                        : provider.brandColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: connected ? AppTheme.text : AppTheme.muted,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: connected ? AppTheme.ok : AppTheme.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
