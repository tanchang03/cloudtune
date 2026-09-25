import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/lrc.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/track.dart';
import '../providers/lyrics_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';

/// 播放页上的歌词区。
///
/// 四种「没有歌词可显示」的状态各有各的文案，**不能合并成一句「没有歌词」**：
///   - 还在查（联网时可能要等一两百毫秒）；
///   - 这首歌在网盘里就没有 `.lrc`（这是用户的曲库状况，不是故障）；
///   - 有 `.lrc` 但读出来是空的；
///   - 明确是纯音乐（LRCLIB 会这么标）。
///
/// 合并之后用户没法判断「该不该去补一份歌词」，而这恰恰是他唯一能做的动作。
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key, required this.track, this.onSeek});

  final Track track;

  /// 点某一行跳过去。为 `null` 表示不可跳（时长未知，或这份歌词没有时间轴）。
  final void Function(Duration at)? onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(lyricsProvider(track));

    return async.when(
      loading: () => const _Placeholder(
        icon: Icons.hourglass_empty,
        title: '正在获取歌词…',
      ),
      // LyricsResolver 永不抛异常，走到这里说明是别的意外（provider 被销毁
      // 之类）。显示成一句中性的话即可，不必把异常摊给用户。
      error: (e, _) => _Placeholder(
        icon: Icons.cloud_off_outlined,
        title: '歌词加载失败',
        message: '$e',
        color: scheme.onSurfaceVariant,
      ),
      data: (lyrics) => _body(scheme, lyrics),
    );
  }

  Widget _body(ColorScheme scheme, Lyrics? lyrics) {
    if (lyrics == null) {
      return _Placeholder(
        icon: Icons.lyrics_outlined,
        title: '暂无歌词',
        message: '这首歌在网盘里没有同名的 .lrc 文件。\n'
            '也可以在「设置 → 歌词」里开启联网获取。',
        color: scheme.onSurfaceVariant,
      );
    }

    if (lyrics.instrumental) {
      return const _Placeholder(
        icon: Icons.piano_outlined,
        title: '纯音乐',
        message: '这首歌没有歌词',
      );
    }

    final doc = lyrics.document;
    if (!doc.isNotEmpty) {
      return const _Placeholder(
        icon: Icons.lyrics_outlined,
        title: '歌词文件是空的',
        message: '网盘里那份 .lrc 读出来没有任何内容',
      );
    }

    if (!doc.isSynced) {
      // 没有时间轴就只能在旁边静态摆着 —— 说清楚这一点，
      // 否则用户会以为「歌词卡住了，不跟着走」。
      return _StaticLyrics(text: doc.plainText ?? '', lyrics: lyrics);
    }

    // key 绑在曲目上：换歌时 Flutter 直接换掉整个 State，
    // 滚动位置、每行的 GlobalKey、拖动标志全部自然重置。
    // 用 key 而不是在 `didUpdateWidget` 里手工清 —— 少一处「忘了清」的可能。
    return _SyncedLyrics(
      key: ValueKey('synced:${lyrics.trackId}'),
      doc: doc,
      lyrics: lyrics,
      onSeek: onSeek,
    );
  }
}

/// 有时间轴：按播放位置高亮当前行，点行跳转。
class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({
    super.key,
    required this.doc,
    required this.lyrics,
    required this.onSeek,
  });

  final LrcDocument doc;
  final Lyrics lyrics;
  final void Function(Duration at)? onSeek;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final _controller = ScrollController();

  /// 每行一个 key，用来让当前行滚进视野。
  ///
  /// 用 key + [Scrollable.ensureVisible] 而不是「行号 × 固定行高」算偏移：
  /// 歌词行长短差很多（一句 5 个字和一句 20 个字会折成不同的行数），
  /// 按固定行高算出来的位置会越滚越偏。
  final _keys = <int, GlobalKey>{};

  /// 上一次已经滚过去的高亮行号。**只是备忘**：不参与本帧渲染，
  /// 只用来避免「同一行反复滚」。所以可以在 build 里写它。
  int _lastIndex = -1;

  /// 用户正在手动拖动歌词，此时不要抢他的滚动位置
  bool _dragging = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollTo(int index) {
    // 放到 post-frame 里做：这时新的一帧已经布局完成，`currentContext`
    // 才拿得到（拿不到说明那一行还没被建出来，跳过即可 —— 下一帧还有机会）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keys[index]?.currentContext;
      if (ctx == null || !_controller.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        // 0.42 而不是 0.5：把当前行放在略高于正中处，下面留出的空间比上面多，
        // 视线顺着往下走更自然（卡拉OK 的字幕也偏上）。
        alignment: 0.42,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final index = widget.doc.lineIndexAt(position);

    if (index != _lastIndex) {
      _lastIndex = index;
      // 用户正在手动拖动时**不抢**位置 —— 否则想往上翻看歌词根本翻不动。
      if (index >= 0 && !_dragging) _scrollTo(index);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 拖动期间与松手后都要能区分出来：`dragDetails != null` 只说明
              // 这一条通知来自手指/滚轮，滚到头的回弹通知不带它。
              if (n is ScrollStartNotification) {
                _dragging = n.dragDetails != null;
              } else if (n is ScrollEndNotification) {
                _dragging = false;
              }
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.doc.lines.length,
              itemBuilder: (context, i) {
                final line = widget.doc.lines[i];
                return _LyricLine(
                  key: _keys.putIfAbsent(i, GlobalKey.new),
                  text: line.text,
                  active: i == index,
                  onTap: widget.onSeek == null
                      ? null
                      : () => widget.onSeek!(line.at),
                );
              },
            ),
          ),
        ),
        _SourceFootnote(lyrics: widget.lyrics),
      ],
    );
  }
}

/// 没有时间轴：整段静态展示，并说明它不会跟着走。
class _StaticLyrics extends StatelessWidget {
  const _StaticLyrics({required this.text, required this.lyrics});

  final String text;
  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        _SourceFootnote(lyrics: lyrics),
      ],
    );
  }
}

/// 一行歌词。
class _LyricLine extends StatelessWidget {
  const _LyricLine({
    super.key,
    required this.text,
    required this.active,
    this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 空行是「间奏」的常见写法，保留它才能让时间轴对得上，
    // 但显示一个占位高度即可（`SizedBox` 不会画出任何东西）。
    if (text.isEmpty) {
      return const SizedBox(height: 14);
    }

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: active ? 15 : 13.5,
          height: 1.5,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? AppTheme.text : AppTheme.dim,
        ),
      ),
    );

    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: body,
    );
  }
}

/// 歌词来源那一行小字。
///
/// 必须显示：联网歌词是用户自己打开的开关，而**本地与联网的可信度不一样**
/// （本地 `.lrc` 是用户自己放的，联网是第三方匹配的）。用户看到明显不对的
/// 歌词时，得能一眼看出「这是从哪儿来的」，才知道该去改哪一边。
class _SourceFootnote extends StatelessWidget {
  const _SourceFootnote({required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (lyrics.source) {
      LyricsSource.local => (
          Icons.description_outlined,
          '本地歌词${lyrics.fileName == null ? "" : " · ${lyrics.fileName}"}',
        ),
      LyricsSource.lrclib => (Icons.cloud_outlined, '歌词来自 LRCLIB（联网匹配）'),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 11, color: AppTheme.dim),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppTheme.dim),
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载中 / 没有歌词 / 纯音乐 —— 几种「没有歌词可显示」的状态。
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    this.message,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppTheme.dim),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tint),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: AppTheme.dim,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
