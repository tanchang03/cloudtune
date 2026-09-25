import 'package:flutter/material.dart';

import '../../core/utils/audio_formats.dart';
import '../../domain/entities/drive_provider.dart';
import '../../domain/entities/playability.dart';

/// 设计令牌。
///
/// 全部色值取自设计原型 `prototype/index.html` 的 CSS 变量，做到 1:1 还原。
/// 页面里不写死颜色 —— 换肤与统一口径只改这一个文件。
class AppTheme {
  const AppTheme._();

  /// 字体：与设计稿一致（`-apple-system, "PingFang SC", "Microsoft YaHei"`）
  static const String fontFamily = 'PingFang SC';

  // ---- 背景与容器 ----
  static const Color bg = Color(0xFF0B0D12);
  static const Color panel = Color(0xFF141821);
  static const Color panel2 = Color(0xFF1B2130);
  static const Color panel3 = Color(0xFF232B3D);
  static const Color line = Color(0xFF2A3244);

  // ---- 文字 ----
  static const Color text = Color(0xFFE9EDF6);
  static const Color muted = Color(0xFF8B95AC);
  static const Color dim = Color(0xFF5D6780);

  // ---- 强调色（主渐变 #5b8cff → #a45cff）----
  static const Color accent = Color(0xFF5B8CFF);
  static const Color accent2 = Color(0xFFA45CFF);

  /// 品牌主渐变，用于按钮 / 封面 / 播放键
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  // ---- 网盘品牌色 ----
  static const Color quark = Color(0xFF4F8CFF);
  static const Color aliyun = Color(0xFF7C5CFF);
  static const Color baidu = Color(0xFF2FB3C9);

  // ---- 语义色 ----
  static const Color heart = Color(0xFFFF5C8A);
  static const Color ok = Color(0xFF3DDC97);
  static const Color warn = Color(0xFFFFB454);
  static const Color danger = Color(0xFFFF6B6B);

  /// CUE 分轨标记色（组头的「WAV · CUE 分轨」与「整轨连播」）。
  ///
  /// 单独开一个 token 而不是借用 [warn] / [accent] / [accent2]：
  ///   - [warn] 在本应用里是**状态**色（取不到链 / 体积未知），
  ///     借来标 CUE 会让用户把「这张专辑用了 CUE」误读成「这张专辑有问题」；
  ///   - [accent2] 是 DSD 的音质家族色，[accent] 是主操作色，
  ///     两者在曲目行里都已经有确定含义，挪到组头用会串味。
  ///
  /// CUE 是**结构**信息（这一组是由一张整轨切出来的），既不是状态也不是音质，
  /// 所以给它一个自己的、比 [warn] 更浅更偏金的值 —— 两者可能同屏出现
  /// （超限的整轨 WAV 在行内是 [warn] 徽标、组头是 CUE 标记），要能分辨。
  static const Color cue = Color(0xFFE5B567);

  // ---- 尺寸（设计稿像素值）----
  static const double sidebarWidth = 196;
  static const double playerBarHeight = 74;

  /// 窗口顶部**留白区**的高度（= 给原生红黄绿按钮让出的那一条）。
  ///
  /// 系统标题栏已经在 `macos/Runner/MainFlutterWindow.swift` 里抹成透明，
  /// 窗口内容铺到最顶端，但三个原生按钮还浮在左上角，所以要留出这一条。
  /// 这一条**什么都不画**（见 `WindowTopInset`）—— 画了就像系统标题栏没去掉。
  ///
  /// **取 32 而不是原型 `.winbar` 的 38**，理由是实测出来的，不是审美取舍：
  ///   - `NSTitlebarView` 的实际高度是 **32pt**，红黄绿按钮高 14、距顶 9..23，
  ///     即**圆心距顶 16**；
  ///   - 留白取 32 → 中线正好 16，圆点天然居中，不需要碰任何 AppKit 内部；
  ///   - 取原型的 38 → 中线 19，圆点会明显偏上 3px。
  ///
  /// 原型那个 38 是凭空定的（HTML 画不出原生标题栏，只能自己摆三个圆点），
  /// 真机上高度由原生按钮决定，跟着它走才对得上。
  static const double titleBarHeight = 32;

  /// 顶部留白区左边缘至少要让出的宽度。
  ///
  /// 实测：close x=9、mini x=32、zoom x=55，按钮宽 14 → 最右边缘 **69**；
  /// 再加原型 `.winbar .title` 的 12px 左外边距 = **81**。
  ///
  /// ⚠️ **当前没有使用者**：留白区是空的（见 `WindowTopInset`），
  /// 而页面内容整体在它下面，所以不需要水平避让。
  /// 保留它是因为「往顶部那一条里放任何东西」都必须先看这个数 ——
  /// 凭感觉给小了，内容就会压在绿色按钮上。
  static const double trafficLightInset = 81;

  static const double coverSize = 44;
  static const double coverRadius = 10;
  static const double sourceColWidth = 120;

  /// 「格式 · 品质」合并列宽。
  ///
  /// 装得下 `[FLAC] 无损 1411k` 这种最长组合（格式 chip ≈ 40 + 间隔 6 +
  /// 「未压缩 11290k」≈ 78）。格式与品质不拆成两列，是因为一行里已经有
  /// 封面 / 标题 / 来源 / 路径 / 大小 / 时长 / 收藏七段，再拆会挤到曲名只剩几个字。
  static const double qualityColWidth = 124;

  /// 「大小」列宽。最宽的一种是 `720.0 MB`（7 字符 + 单位），
  /// 再宽的文件会进位成 `1024 MB`，反而更短。
  static const double sizeColWidth = 70;

  /// 曲目行内各列之间的间距（原型 `.song` 的 `gap: 11px`）
  static const double rowGap = 11;

  /// 宽屏断点：≥1000 走桌面布局（侧边栏 + 底部播放条），否则走移动端布局。
  ///
  /// 侧边栏、曲目行、列表列头都读这一个判断，避免三处断点不一致导致
  /// 「侧栏还在、曲目行却挤成手机版」这类半套桌面布局。
  ///
  /// **为什么是 1000 而不是原型的 900**：桌面列表后来加了两列
  /// （「格式 · 品质」124 + 「大小」70 + 两个 11 的间隔 = 216），
  /// 900 宽时曲名只剩约 116px（不到 9 个汉字），已经读不出是哪首歌了。
  /// 抬到 1000 之后桌面端曲名回到 150px 以上；1000 以下走移动端布局 ——
  /// 全宽单列、路径与规格内嵌在标题下，反而比硬挤一张七列表更好读。
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1000;

  /// 设计稿为深色，浅色仅作兜底（保留可切换，但默认走深色）。
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent2,
      onSecondary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: isDark ? bg : const Color(0xFFF7F8FC),
      onSurface: isDark ? text : const Color(0xFF1A1D26),
      // 卡片/面板
      surfaceContainerHighest: isDark ? panel : const Color(0xFFEDEFF5),
      onSurfaceVariant: isDark ? muted : const Color(0xFF616B80),
      outline: isDark ? line : const Color(0xFFD6DAE4),
      outlineVariant: isDark ? panel3 : const Color(0xFFE4E7EF),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      // 背景交给 DesignBackground（深色底 + 两处光晕），
      // Scaffold 透过去才能看见光晕。
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
    );

    return base.copyWith(
      colorScheme: scheme,
      // 设计稿无 AppBar 阴影，纯色底
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: isDark ? panel : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // 设计稿控件偏紧凑
      visualDensity: VisualDensity.compact,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: _textTheme(scheme),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) => TextTheme(
        // 页面大标题（设计稿 19～22 / 660～680）
        headlineSmall: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
        // 歌曲标题 13.5 / 560
        titleSmall: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
        // 副标题（艺术家·专辑）11.5 muted
        bodySmall: TextStyle(
          fontSize: 11.5,
          color: scheme.onSurfaceVariant,
          fontFamily: fontFamily,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
        labelSmall: TextStyle(
          fontSize: 10.5,
          color: scheme.onSurfaceVariant,
          fontFamily: fontFamily,
        ),
      );
}

/// 设计稿页面底色：深色底 + 左上蓝 / 右上紫两处径向光晕。
///
/// 设计稿 body 上叠了两个 radial-gradient，这里用两层 Stack 还原。
class DesignBackground extends StatelessWidget {
  const DesignBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 左上蓝色光晕
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.75, -1.05),
                radius: 1.15,
                colors: [Color(0x1A5B8CFF), Colors.transparent],
                stops: [0, 0.6],
              ),
            ),
          ),
          // 右上紫色光晕
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.88, -1.0),
                radius: 1.0,
                colors: [Color(0x1AA45CFF), Colors.transparent],
                stops: [0, 0.6],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 可播性状态的展示文案与配色。
///
/// 刻意放在主题文件里，保证「同一个状态在任何页面都是同一种颜色」——
/// 用户对「这行能不能播」的直觉是靠一致性建立起来的。
///
/// 文案口径：说人话，并且**不要把接口的限制说成文件的毛病**。
/// 「超限」这种内部术语用户看不懂，一律改成「取不到链」这类能直接读懂的
/// 描述，并说清原因与条件。
extension PlayabilityVisuals on PlayabilityState {
  /// 徽标短文案（列表行内，4 字以内）
  String get badgeLabel => switch (this) {
        PlayabilityState.playable => '可播',
        PlayabilityState.overLimit => '取不到链',
        PlayabilityState.unknownSize => '体积未知',
        PlayabilityState.unsupportedByProvider => '不支持直链',
        PlayabilityState.notAudio => '非音频',
        PlayabilityState.decodeFailed => '解码失败',
      };

  /// 一句话解释「为什么播不了」，用于列表行的悬浮提示
  String get badgeHint => switch (this) {
        PlayabilityState.playable => '体积与格式都符合网盘在线播放要求',
        PlayabilityState.overLimit => '网盘的两条取链路由都没给出播放地址',
        PlayabilityState.unknownSize => '网盘没返回体积，点播时会先尝试一次',
        PlayabilityState.unsupportedByProvider => '该网盘未开放直链播放能力',
        PlayabilityState.notAudio => '扩展名与类型都不像音频文件',
        PlayabilityState.decodeFailed => '本机播放器解不开这个音频（编码不支持或文件损坏）',
      };

  /// ① **哪些文件**会进入这个状态
  String get explainWhat => switch (this) {
        PlayabilityState.playable => '体积在网盘上限以内、且本身就是音频的文件',
        PlayabilityState.overLimit =>
          '网盘拒绝签发播放地址的音频。最常踩到的是体积很大的整轨 WAV / DSF 等'
              '高码率文件，以及网盘临时限制了取链接口的时候',
        PlayabilityState.unknownSize => '网盘没有返回体积的音频文件',
        PlayabilityState.unsupportedByProvider => '该网盘下的所有文件',
        PlayabilityState.notAudio =>
          '扩展名和 MIME 都不是音频的文件（压缩包、图片、文档、视频等）',
        PlayabilityState.decodeFailed =>
          '本机播放器认不出编码的音频。最典型的是 DSD（`.dsf` / `.dff`）——'
              'macOS 自带的 AVFoundation 完全不支持这种编码；'
              '少数是容器头损坏的文件。它们都是**播过一次之后**才会被标记',
      };

  /// ② **什么原因**导致播不了
  String get explainWhy => switch (this) {
        PlayabilityState.playable => '网盘的在线取链接口能正常给它签发直链',
        PlayabilityState.overLimit =>
          '网盘的取链接口可能对单文件设了体积门槛，超出门槛就直接拒绝签发地址'
              '（夸克实测返回 code=23018）。这是**接口侧**的限制，'
              '不代表文件坏了，也不是播放器的问题',
        PlayabilityState.unknownSize =>
          '拿不到体积就没法提前判断是否超限，只能实际取一次链来确认',
        PlayabilityState.unsupportedByProvider =>
          '该网盘没有开放直链播放能力，在不把文件下载到本地的前提下无法播放',
        PlayabilityState.notAudio => '播放器只处理音频，非音频文件里没有可解码的音轨',
        PlayabilityState.decodeFailed =>
          '**不是网盘的问题**：网盘已经把播放地址正常给出来了，'
              '是本机的解码器读不懂这个编码，或者文件本身已经损坏。'
              '重试、换网络、换时间段都不会有变化 —— 它跟网速无关',
      };

  /// ③ **什么条件**下才能播
  String get explainHow => switch (this) {
        PlayabilityState.playable => '直接点播即可',
        PlayabilityState.overLimit =>
          '本应用对同一个文件会依次尝试两条取链路由（音频播放接口 → 下载直链接口），'
              '两条都被拒才会落到这里。可以稍后重试；若始终不行，'
              '说明该网盘的取链接口确实不给这个文件，改用没有这条限制的网盘即可',
        PlayabilityState.unknownSize => '直接点播即可确认，失败会自动跳过并在列表标注',
        PlayabilityState.unsupportedByProvider =>
          '等该网盘适配直链能力，或把文件放到已接入的网盘',
        PlayabilityState.notAudio =>
          '确认文件确实是音频（MP3 / FLAC / WAV / M4A / OGG 等常见格式）',
        PlayabilityState.decodeFailed =>
          '把音频转成 FLAC / MP3 / M4A 等常见编码后重新上传，'
              '或改用支持该格式的播放器（foobar2000、Audirvana 等）。'
              '本应用播不了 DSD 是解码器的能力边界，不是设置问题',
      };

  /// 说明弹窗的标题
  String get helpTitle => switch (this) {
        PlayabilityState.playable => '这首可以正常播放',
        PlayabilityState.overLimit => '网盘不给取链，拿不到播放地址',
        PlayabilityState.unknownSize => '体积未知，需要试播确认',
        PlayabilityState.unsupportedByProvider => '这个网盘暂不支持直链播放',
        PlayabilityState.notAudio => '这个文件不是音频',
        PlayabilityState.decodeFailed => '本机播放器解不开这个文件',
      };

  /// 该状态在给定配色方案下的强调色
  Color color(ColorScheme scheme) => switch (this) {
        PlayabilityState.playable => AppTheme.ok,
        // 「取不到链 / 体积未知」是**软提示**：用户还有办法解决，
        // 用警告黄而不是报错红 —— 红色留给真正播不了的两种情况。
        PlayabilityState.overLimit => AppTheme.warn,
        PlayabilityState.unknownSize => AppTheme.warn,
        _ => AppTheme.danger,
      };
}

/// 网盘品牌视觉：颜色、渐变、角标字母。
///
/// 颜色属于 UI 关注点，所以放在主题里做扩展，不动 `DriveProvider` 这个
/// 领域实体 —— 领域层不关心长什么样。
extension DriveProviderVisuals on DriveProvider {
  /// 品牌主色：夸克蓝 / 阿里紫 / 百度青
  Color get brandColor => switch (this) {
        DriveProvider.quark => AppTheme.quark,
        DriveProvider.aliyun => AppTheme.aliyun,
        DriveProvider.baidu => AppTheme.baidu,
      };

  /// 品牌色深一档，用于渐变的收尾端（取自原型 .dlogo / .cover）
  Color get brandDark => switch (this) {
        DriveProvider.quark => const Color(0xFF2F6BE0),
        DriveProvider.aliyun => const Color(0xFF5A3AD6),
        DriveProvider.baidu => const Color(0xFF1D8EA6),
      };

  /// 封面 / logo 的品牌渐变（原型统一用 135°）
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [brandColor, brandDark],
      );

  /// 封面右下角的来源角标字母：Q / A / B
  String get badgeLetter => switch (this) {
        DriveProvider.quark => 'Q',
        DriveProvider.aliyun => 'A',
        DriveProvider.baidu => 'B',
      };
}

/// 音质家族的展示口径：家族词、配色、悬停说明。
///
/// 与 [PlayabilityVisuals] 同一套路 —— 分类逻辑在
/// `core/utils/audio_formats.dart`（纯函数、可测），长什么样在这里。
extension AudioQualityVisuals on AudioQuality {
  /// 列表里显示的家族词。两个字的占多数，好和格式 chip 并排。
  String get label => switch (this) {
        AudioQuality.dsd => 'DSD',
        AudioQuality.lossless => '无损',
        AudioQuality.uncompressed => '未压缩',
        AudioQuality.lossy => '有损',
        AudioQuality.surround => '环绕',
        AudioQuality.unknown => '未知',
      };

  /// 格式 chip 的描边与文字色。
  ///
  /// 分档即配色：DSD 紫 → 无损蓝 → 未压缩青 → 环绕绿，**有损刻意用最弱的灰**。
  /// 灰不是「差」，是「普通」—— 让它安静地待在后面，无损与 DSD 才会自己跳出来。
  Color get color => switch (this) {
        AudioQuality.dsd => AppTheme.accent2,
        AudioQuality.lossless => AppTheme.accent,
        AudioQuality.uncompressed => AppTheme.baidu,
        AudioQuality.surround => AppTheme.ok,
        AudioQuality.lossy => AppTheme.dim,
        AudioQuality.unknown => AppTheme.dim,
      };

  /// 悬停说明。**必须讲清码率是算出来的**，否则用户会拿它当文件里的官方规格
  /// 去和别的软件对账，对不上就会以为是本应用读错了。
  String get hint => switch (this) {
        AudioQuality.dsd => 'DSD（1bit 高采样）· 码率是按「体积 ÷ 时长」算出的平均值',
        AudioQuality.lossless =>
          '无损压缩（FLAC / APE / ALAC 等）· 码率是按「体积 ÷ 时长」算出的平均值，'
              '数字越大说明采样率或位深越高',
        AudioQuality.uncompressed =>
          '未压缩 PCM（WAV / AIFF）· 码率是按「体积 ÷ 时长」算出的平均值，'
              '通常约 1411k（CD 规格）',
        AudioQuality.lossy =>
          '有损压缩 · 码率是按「体积 ÷ 时长」算出的平均值：'
              '约 320k 是高品质，128k 以下会明显损失细节',
        AudioQuality.surround => '多声道封装（DTS / AC3 / MKA），多为影视伴音',
        AudioQuality.unknown => '扩展名认不出编码方式，无法判断是否有损',
      };
}

/// 把字节数格式化成人类可读的字符串。
///
/// 网盘返回的体积动辄十亿字节，直接展示数字没人看得懂。
///
/// ⚠️ **界面用的是这一个**，不是 `core/utils/format.dart` 里的同名函数 ——
/// 那个永远保留 1 位小数（`729.7 MB`），这个在 ≥100 时不留小数（`730 MB`）。
/// 少一位是刻意的：体积列要跟「格式 / 品质」「时长」并排，
/// `729.7 MB` 比 `730 MB` 宽出一截，十亿字节级的数字又到处都是。
String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '未知';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 把平均码率格式化成列表里那一小串数字：`1411k` / `11.3M`。
///
/// 刻意**不写 `kbps`** —— 列表里空间只够几个字符，而这一列里出现的数字
/// 全是码率，单位靠悬停说明交代即可。超过 10000k 换 `M`（DSD256 是 11290k），
/// 否则 DSD 那几档会变成 5 位数，把「格式 · 品质」列撑开。
///
/// 传 `null`（体积或时长缺失）时返回 `null`，调用方据此只显示家族词。
String? formatBitrate(int? kbps) {
  if (kbps == null || kbps <= 0) return null;
  if (kbps < 10000) return '${kbps}k';
  return '${(kbps / 1000).toStringAsFixed(1)}M';
}

/// 把时长格式化成 `m:ss` 或 `h:mm:ss`。
///
/// ⚠️ **界面用的是这一个**，不是 `core/utils/format.dart` 里的同名函数 ——
/// 两者输出并不一致：那个分钟补零（`08:20`）、`Duration.zero` 给 `00:00`、
/// 负数带 `-` 前缀；这个不补零、零值给 `--:--`。新增代码要格式化时长时
/// 用这里的，否则同一个界面里会同时出现 `8:20` 与 `08:20` 两种写法。
///
/// 不足一小时**不补分钟零**（`8:20` 而不是 `08:20`）：列表里时长是扫视用的，
/// 少一位数字就少一点横向占用；超过一小时才补（`1:08:20`），
/// 否则 `1:8:20` 会与 `11:8:20` 分不清。
String formatDuration(Duration? duration) {
  if (duration == null || duration <= Duration.zero) return '--:--';
  final total = duration.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
