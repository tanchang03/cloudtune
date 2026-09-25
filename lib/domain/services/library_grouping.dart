import '../../core/utils/audio_formats.dart';
import '../entities/track.dart';

/// 曲库列表的浏览方式。
///
/// 分组只是**视图层**的事：它不改写数据库里的 `title` / `artist` / `album`，
/// 而是在渲染前对当前这一批曲目做一次目录级推断。
/// 好处是换网盘、改命名习惯时不需要重扫，也不需要数据库迁移。
enum LibraryGroupMode {
  /// 平铺，一行一首（默认）
  none('列表', '组'),

  /// 按艺术家聚合
  artist('艺术家', '位艺术家'),

  /// 按专辑聚合
  album('专辑', '张专辑');

  const LibraryGroupMode(this.label, this.groupNoun);

  /// 切换控件上的按钮文案
  final String label;

  /// 组数的量词，用来拼「23 位艺术家」「47 张专辑」
  final String groupNoun;
}

/// 一组曲目（一位艺术家 / 一张专辑）。
class TrackGroup {
  const TrackGroup({
    required this.key,
    required this.title,
    required this.tracks,
  });

  /// 稳定标识。专辑分组用**目录路径**，艺术家分组用艺术家名。
  ///
  /// 用目录路径而不是专辑名当键，是因为一个目录 = 一张专辑这件事
  /// 永远成立；而专辑名是从目录名猜的，猜歪了也不会让曲目串组。
  final String key;

  /// 展示名
  final String title;

  final List<Track> tracks;

  int get length => tracks.length;

  /// 组内由 CUE 整轨切出的分段（按列表顺序）。
  List<Track> get cueSegments => LibraryGrouping.cueSegmentsOf(tracks);

  /// 组内是否含 CUE 整轨分段 —— 组头的「CUE 分轨」标记读它。
  bool get hasCueSegments => tracks.any((t) => t.isCueSegment);

  /// 组内的整轨文件（按出现顺序去重）——「整轨连播」的播放队列。
  List<Track> get cueImages => LibraryGrouping.cueImagesOf(tracks);

  /// 整轨 id（`remoteId`）→ 整轨总时长（毫秒）。分段行的体积/码率换算要用它。
  Map<String, int> get cueImageDurations =>
      LibraryGrouping.cueImageDurationsOf(tracks);

  @override
  String toString() => 'TrackGroup("$title", ${tracks.length} 首)';
}

/// 一条曲目推断出的展示元数据。
class DerivedMetadata {
  const DerivedMetadata({required this.title, this.artist, this.album});

  final String title;
  final String? artist;
  final String? album;
}

/// 曲目列表分组服务。
///
/// 纯函数、不依赖 Flutter，因此可以拿真实曲库的目录名直接跑单元测试
/// （见 `test/domain/library_grouping_test.dart`）。
class LibraryGrouping {
  const LibraryGrouping._();

  static const String unknownArtist = '未知艺术家';
  static const String unknownAlbum = '未知专辑';

  /// 平铺模式下唯一的那个组。
  static const String flatKey = '__all__';

  /// 对整个列表做一次目录级元数据推断，返回 `trackId → 元数据`。
  ///
  /// 关键点：**先按目录聚合，再逐目录推断命名约定**。同一个目录里的文件
  /// 是判断 `艺术家 - 曲名` 还是 `曲名 - 艺术家` 的唯一依据。
  static Map<String, DerivedMetadata> deriveMetadata(List<Track> tracks) {
    final byDir = <String, List<Track>>{};
    for (final t in tracks) {
      byDir.putIfAbsent(dirOf(t), () => <Track>[]).add(t);
    }

    final out = <String, DerivedMetadata>{};
    byDir.forEach((dir, list) {
      final style = detectNameStyle(list.map((t) => t.name));
      final folder = lastPathSegment(dir);
      final hint = folderArtistHint(folder);
      final album = folderAlbumName(folder) ?? unknownAlbum;

      for (final track in list) {
        final parsed = splitTrackName(track.name, style);
        // 曲名里同样会带 `[无损音质]`、`臻品母带` 这类尾巴，一并清掉；
        // 清空说明整个名字都是噪声，那就退回原始文件名，别给用户一个空标题
        final cleanedTitle = cleanDisplayName(parsed.title);
        out[track.id] = DerivedMetadata(
          title: cleanedTitle.isEmpty ? track.name : cleanedTitle,
          // 文件名解析优先；合辑目录（`群星 - 古惑仔最强精选集`）里
          // 目录名的艺术家提示是「群星」，不能盖掉每首歌真正的演唱者
          artist: _nonEmpty(parsed.artist) ??
              _nonEmpty(track.artist) ??
              _nonEmpty(hint),
          // 库里还没写入过专辑标签，将来接入标签读取后以标签为准
          album: _nonEmpty(track.album) ?? album,
        );
      }
    });
    return out;
  }

  /// 把曲目按 [mode] 分组。
  ///
  /// [metadata] 可复用已经算好的推断结果；不传则现场算一次。
  /// [LibraryGroupMode.none] 会返回只含一个组的列表，组名是空的 ——
  /// 让调用方用同一套渲染路径，不必分叉。
  static List<TrackGroup> group(
    List<Track> tracks,
    LibraryGroupMode mode, {
    Map<String, DerivedMetadata>? metadata,
  }) {
    if (mode == LibraryGroupMode.none || tracks.isEmpty) {
      return [TrackGroup(key: flatKey, title: '', tracks: tracks)];
    }

    final meta = metadata ?? deriveMetadata(tracks);
    final buckets = <String, List<Track>>{};
    final labels = <String, String>{};

    for (final track in tracks) {
      final m = meta[track.id];
      final String key;
      final String label;

      switch (mode) {
        case LibraryGroupMode.artist:
          final artist = _nonEmpty(m?.artist) ?? unknownArtist;
          key = artist;
          label = artist;
        case LibraryGroupMode.album:
          key = dirOf(track);
          label = _nonEmpty(m?.album) ?? unknownAlbum;
        case LibraryGroupMode.none:
          continue; // 上面已提前返回
      }

      buckets.putIfAbsent(key, () => <Track>[]).add(track);
      labels[key] = label;
    }

    final titles = _disambiguate(labels);
    final groups = [
      for (final entry in buckets.entries)
        TrackGroup(
          key: entry.key,
          title: titles[entry.key] ?? '',
          tracks: entry.value,
        ),
    ];
    // 中文按码位排序（不是拼音），但稳定、可预期，且与「排序」菜单无关 ——
    // 分组内曲目的顺序仍然沿用用户在排序菜单里的选择
    groups.sort((a, b) => a.title.compareTo(b.title));
    return groups;
  }

  /// 曲目所在目录（归一化，不带结尾斜杠）。
  static String dirOf(Track track) => normalizeDirPath(track.path);

  /// 同名专辑消歧，保证返回的每个标题都唯一。
  ///
  /// 高清音乐库常有 `... [16B-44.1kHz][Q]` 与 `... [24B-48kHz][Q]` 两个目录，
  /// 它们清洗后是同一个专辑名。直接并列会出现两个一模一样的分组标题，
  /// 所以先补上目录里的音质标记。
  ///
  /// 但音质标记本身也可能撞车 —— 真实库里就有两个目录都带 `[香港首版]`
  /// （同一次演唱会的两份不同来源）。这种时候退化成加序号，
  /// 宁可标题朴素一点，也不能让用户看到两个分不出区别的分组。
  static Map<String, String> _disambiguate(Map<String, String> labels) {
    final counts = <String, int>{};
    for (final label in labels.values) {
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final out = <String, String>{};
    final used = <String>{};
    final seen = <String, int>{};

    labels.forEach((key, label) {
      if ((counts[label] ?? 0) <= 1) {
        out[key] = label;
        used.add(label);
        return;
      }

      final tag = _qualityTag(lastPathSegment(key));
      var candidate = tag == null ? label : '$label · $tag';
      while (used.contains(candidate)) {
        final index = (seen[label] ?? 1) + 1;
        seen[label] = index;
        candidate = '$label ($index)';
      }
      used.add(candidate);
      out[key] = candidate;
    });
    return out;
  }

  /// 抽出目录名里方括号内的音质标记，如 `[16B-44.1kHz]`。
  ///
  /// 单字符标记（`[Q]`）不算 —— 它区分不了任何东西。
  static String? _qualityTag(String folderName) {
    final tags = RegExp(r'[\[【]([^\]】]*)[\]】]')
        .allMatches(folderName)
        .where((m) => (m.group(1) ?? '').trim().length > 2)
        .map((m) => m.group(0)!)
        .toList();
    return tags.isEmpty ? null : tags.join();
  }

  static String? _nonEmpty(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  // -------------------------------------------------------------------
  // CUE 整轨（视图层只读这几个派生值，不自己遍历分段）
  // -------------------------------------------------------------------

  /// 一批曲目里由 CUE 整轨切出的分段（按传入顺序）。
  static List<Track> cueSegmentsOf(List<Track> tracks) =>
      [for (final t in tracks) if (t.isCueSegment) t];

  /// 一批曲目里出现过的整轨文件（按首次出现顺序去重）。
  ///
  /// 分段是扫描时切出来的，整轨那一行已经被删掉，所以这里靠 [Track.imageOf]
  /// 就地还原。**先按 `remoteId` 分组再逐张还原**：一张 2CD 合辑（按艺术家
  /// 分组时很常见）在一个分组里就是两张整轨，连播时 CD1 放完接 CD2 ——
  /// 正是用户点「整轨连播」时想要的。
  static List<Track> cueImagesOf(List<Track> tracks) {
    final byImage = <String, List<Track>>{};
    for (final t in tracks) {
      if (t.isCueSegment) byImage.putIfAbsent(t.remoteId, () => []).add(t);
    }
    final images = <Track>[];
    for (final segments in byImage.values) {
      final image = Track.imageOf(segments);
      if (image != null) images.add(image);
    }
    return images;
  }

  /// 整轨 id（`remoteId`）→ 整轨总时长（毫秒）。
  ///
  /// 分段的 `sizeBytes` 是整轨体积、`durationMs` 是本轨时长，算码率/摊体积
  /// 都必须先知道整轨总时长 —— 见 `TrackTile.imageDurationMs`。
  /// 拿不到时长的整轨不进这个表，调用方按「未知」处理。
  static Map<String, int> cueImageDurationsOf(List<Track> tracks) {
    final out = <String, int>{};
    for (final image in cueImagesOf(tracks)) {
      final d = image.durationMs;
      if (d != null) out[image.remoteId] = d;
    }
    return out;
  }
}
