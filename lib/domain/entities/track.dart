import '../../core/utils/audio_formats.dart';
import '../services/playability_resolver.dart';
import 'capabilities.dart';
import 'drive_entry.dart';
import 'drive_provider.dart';
import 'playability.dart';

/// 统一曲目模型。
///
/// 三家网盘的文件都归一到这一个结构。播放引擎、索引库、UI 只认 [Track]，
/// 不认任何网盘的私有字段。
///
/// **等价性约定**：`==` / `hashCode` 基于 [id]，也就是「同一个网盘上、
/// 同一段音频」。这样曲目可以安全地放进 `Set` 做去重、放进 `Map` 做收藏索引。
/// 要判断元数据是否变化，用 [hasSameMetadataAs]。
///
/// ⚠️ 用 [id] 而不是 `(provider, remoteId)`：一张整轨 CUE 切出的 N 段
/// **共用同一个 `remoteId`**（都要指向那个真实 WAV 才能取流），只比
/// `remoteId` 会让它们互相相等 —— 进 `Set` 会被去重成一条、进 `Map`
/// 会互相覆盖。对非分段的普通曲目，两者等价（[id] 就是两者拼出来的），
/// 所以这个改动不会动到任何既有曲目的身份。
class Track {
  Track({
    required this.provider,
    required this.remoteId,
    required this.name,
    this.parentId,
    this.path,
    this.sizeBytes,
    this.mimeType,
    this.modifiedAt,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.cueTrackNo,
    this.cueStartMs,
  });

  /// 从网盘原始节点构造。
  ///
  /// [path] 由扫描器在遍历时按栈拼出（网盘接口通常不返回完整路径）。
  ///
  /// ⚠️ [entry] **必须是文件**。搜索接口会返回目录（夸克实测），
  /// 调用方必须先过滤 `entry.isFile`。
  factory Track.fromEntry({
    required DriveEntry entry,
    required DriveProvider provider,
    String? path,
  }) {
    assert(!entry.isDirectory, '不能把目录转成曲目：${entry.name}');
    final guessed = guessTitleArtist(entry.name);
    return Track(
      provider: provider,
      remoteId: entry.id,
      name: entry.name,
      parentId: entry.parentId,
      path: path ?? entry.path,
      sizeBytes: entry.sizeBytes,
      mimeType: entry.mimeType,
      modifiedAt: entry.modifiedAt,
      // 文件名解析出的结果先落库，后续接入标签读取时可覆盖
      title: guessed.title,
      artist: guessed.artist,
      // 时长直接来自网盘元数据（夸克列目录就带 `duration`），
      // 不必为了显示一个 mm:ss 去把每个文件都下载/试播一遍
      durationMs: entry.durationMs,
    );
  }

  /// 从一张「整轨」里切出的一段（CUE 分轨）。
  ///
  /// 刻意做成命名构造而不是让调用方自己拼字段：**`id` 的后缀规则就在这里**，
  /// 把 `cueTrackNo` / `cueStartMs` 与 `id` 的耦合收在一个地方，
  /// 别处就不会出现「拼出了 id 却忘了带上轨号」这种错。
  ///
  /// 除身份与元数据外的一切（`remoteId` / `name` / `sizeBytes` / `mimeType` /
  /// `path`）都**继承自整轨文件**，理由：
  ///   - `remoteId` 是取流的键，必须仍指向那个真实的 WAV，否则播不了；
  ///   - `name` 决定格式识别与可播性判定，必须保留真实扩展名（`.wav`）；
  ///   - `sizeBytes` 保留整轨体积 —— 「这一轨占多少字节」在整轨里根本没有
  ///     答案（那一段不是一个文件），只有整轨体积是真实存在的数。
  ///
  /// ⚠️ 于是 [sizeBytes] 与 [durationMs] **不是同一层的东西**：前者属于整轨，
  /// 后者属于本轨。把它们直接相除（`averageBitrateKbps`）等于用整张专辑的
  /// 体积除以一首歌的时长，会算出 24000kbps 这种离谱的数。凡是要同时用
  /// 这两个字段的地方，都必须先把**整轨总时长**还原出来（见 [imageOf]）——
  /// UI 侧走 `TrackTile.imageDurationMs`。
  factory Track.cueSegment({
    required Track source,
    required int trackNo,
    required int startMs,
    int? durationMs,
    String? title,
    String? artist,
    String? album,
  }) =>
      Track(
        provider: source.provider,
        remoteId: source.remoteId,
        name: source.name,
        parentId: source.parentId,
        path: source.path,
        sizeBytes: source.sizeBytes,
        mimeType: source.mimeType,
        modifiedAt: source.modifiedAt,
        title: title,
        artist: artist ?? source.artist,
        album: album ?? source.album,
        durationMs: durationMs,
        cueTrackNo: trackNo,
        cueStartMs: startMs,
      );

  /// 由同一张整轨切出的若干段，还原出**整轨文件本身**（[Track.cueSegment] 的逆操作）。
  ///
  /// 需要它的场景是分组头的「整轨连播」：分段是**扫描时**切出来的，整轨那一行
  /// 已经从索引里删掉了（见 `CueIndexResult.replacedImageIds`），要播整轨
  /// 只能就地还原，不能指望库里还有它。
  ///
  /// [segments] 必须**全部来自同一张整轨**（`remoteId` 相同），否则返回 `null`。
  /// 不做「悄悄挑一张来还原」这种兜底：一张 2CD 合辑落在同一个分组里就是两张
  /// 整轨，挑错了用户点「整轨连播」只会听到 CD1，还会以为是 bug。
  /// 调用方应先按 `remoteId` 分组（`TrackGroup.cueImages` 就是这么做的）。
  ///
  /// 还原出的时长取**所有分段终点的最大值**：分段是首尾相接切的（前一段的终点
  /// 就是后一段的起点），而最后一轨的终点在扫描时被补成了整轨文件的真实时长，
  /// 所以这个最大值就是整轨总时长。推不出来时留 `null`（界面显示 `--:--`）。
  static Track? imageOf(List<Track> segments) {
    Track? source;
    var endMs = 0;
    for (final s in segments) {
      if (!s.isCueSegment) return null;
      source ??= s;
      if (s.remoteId != source.remoteId) return null;
      final end = s.cueEndMs;
      if (end != null && end > endMs) endMs = end;
    }
    if (source == null) return null;

    return Track(
      provider: source.provider,
      remoteId: source.remoteId,
      name: source.name,
      parentId: source.parentId,
      path: source.path,
      sizeBytes: source.sizeBytes,
      mimeType: source.mimeType,
      modifiedAt: source.modifiedAt,
      // 刻意**不给 title**：整轨的展示名就该是文件名推出来的那个。
      // CUE 里的 TITLE 是**专辑**名，拿它当整轨的曲名会串味。
      artist: source.artist,
      album: source.album,
      durationMs: endMs > 0 ? endMs : null,
    );
  }

  final DriveProvider provider;

  /// 网盘侧文件 ID
  final String remoteId;

  /// 原始文件名（含扩展名）
  final String name;

  final String? parentId;

  /// 所在目录的展示路径，如 `/音乐/华语/`
  final String? path;

  final int? sizeBytes;
  final String? mimeType;
  final DateTime? modifiedAt;

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// CUE 里的音轨号（1 起）。**非空即表示这条曲目的身份/元数据有 CUE 参与**：
  /// 要么是整轨切出来的一段，要么是分轨文件被 CUE 覆盖了曲名。
  /// UI 的分组头标记（「CUE 分轨」）读的就是它。
  final int? cueTrackNo;

  /// 在整轨文件内的起点（毫秒）。**只有整轨切出来的一段才有值**，
  /// 独立文件恒为 `null`。
  ///
  /// 与 [cueTrackNo] 是两个概念，别混用：前者回答「这条曲目从哪儿开始播」，
  /// 后者回答「这条曲目是哪一轨」。一个多文件 CUE 专辑的每一条都满足
  /// 「有轨号」，但都不满足「有起点」。
  final int? cueStartMs;

  /// 是否是**整轨切出来的一段**（相对于独立文件）。
  ///
  /// 这是 [id] 加后缀的唯一判据，也是播放引擎「放到 [cueEndMs] 就切歌」
  /// 的判据。注意 `startMs == 0` 也是合法的分段起点，所以判据是
  /// **非空**而不是「大于 0」。
  bool get isCueSegment => cueStartMs != null;

  /// 这条曲目是否由 CUE 参与确定（整轨分段，或分轨元数据增强）。
  bool get isFromCue => cueTrackNo != null;

  /// 分段在整轨文件内的终点（毫秒）。
  ///
  /// 由「起点 + 本轨时长」推出，而不是单独存一列 —— 时长本来就是
  /// `durationMs` 的语义，多存一份终点只会多一个可能自相矛盾的字段。
  /// 时长未知时返回 `null`（此时无法自动切歌）。
  int? get cueEndMs {
    final start = cueStartMs;
    final d = durationMs;
    if (start == null || d == null || d <= 0) return null;
    return start + d;
  }

  /// 全局唯一主键，同时作为本地索引库主键。
  ///
  /// 形如 `quark:8f3a...`；整轨分段的曲目带轨号后缀，形如
  /// `quark:8f3a...#c3` —— 一张整轨切出的 N 段共用同一个 `remoteId`，
  /// 必须靠后缀才能各自成为独立主键（否则收藏/播放次数会互相覆盖）。
  ///
  /// ⚠️ 后缀**只由 [isCueSegment] 决定**，不能用 [isFromCue]：分轨增强的
  /// 曲目是货真价实的独立文件，给它们加后缀等于凭空改掉已有主键，
  /// 用户之前收藏的那条会变成孤儿。
  String get id => isCueSegment
      ? '${provider.id}:$remoteId#c$cueTrackNo'
      : '${provider.id}:$remoteId';

  /// 小写扩展名（不含点），无扩展名返回空串
  String get extension => extensionOf(name);

  /// 是否为高解析格式（DSD / WAV / AIFF 等）
  bool get isHighResFormat => isHighRes(name);

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// 展示用标题：优先元数据，退化到文件名解析结果
  late final ({String title, String? artist}) _guessed = guessTitleArtist(name);

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    // 分段曲目若 CUE 里没写曲名，退到「第 N 轨」远比退到整轨文件名有用：
    // 整轨文件名在同一张专辑里 N 条完全一样，用户根本分不清点的是哪一首。
    final no = cueTrackNo;
    if (isCueSegment && no != null) return '第 $no 轨';
    return _guessed.title;
  }

  /// 轨号标签，如 `第 3 轨`。非 CUE 曲目返回 `null`。
  String? get cueTrackLabel {
    final no = cueTrackNo;
    return no == null ? null : '第 $no 轨';
  }

  String? get displayArtist {
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    return _guessed.artist;
  }

  /// 完整网盘路径：`所在目录 + 文件名`。
  ///
  /// 用户要拿着它去网盘里定位文件（或在网盘客户端里搜索），
  /// 所以这里给的是**可直接复制使用的完整位置**，而不是只有目录。
  String get fullPath {
    final dir = path?.trim() ?? '';
    if (dir.isEmpty) return name;
    return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
  }

  /// 展示用副标题：`艺术家 · 专辑`，都没有则退回所在目录名
  String get displaySubtitle {
    final parts = <String>[];
    final a = displayArtist;
    if (a != null && a.isNotEmpty) parts.add(a);
    final al = album?.trim();
    if (al != null && al.isNotEmpty) parts.add(al);
    if (parts.isEmpty) {
      final p = path?.trim() ?? '';
      if (p.isNotEmpty) {
        final segs = p.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) parts.add(segs.last);
      }
    }
    return parts.join(' · ');
  }

  /// 判定可播性。业务规则见 [resolvePlayability]。
  Playability playability(Capabilities capabilities) => resolvePlayability(
        fileName: name,
        capabilities: capabilities,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
      );

  /// 元数据是否与另一条相同（不比较身份）。
  ///
  /// 用于扫描时判断「这条曲目是否需要写库」，避免无谓的 UPDATE。
  ///
  /// ⚠️ CUE 两个字段必须参与比较：漏掉的话，「同一张整轨换了份 CUE
  /// （轨号/起点变了）」会被判成「没变化」而**跳过写库**，
  /// 索引里就一直是旧的分轨点。
  bool hasSameMetadataAs(Track other) =>
      name == other.name &&
      sizeBytes == other.sizeBytes &&
      parentId == other.parentId &&
      path == other.path &&
      modifiedAt == other.modifiedAt &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      durationMs == other.durationMs &&
      cueTrackNo == other.cueTrackNo &&
      cueStartMs == other.cueStartMs;

  Track copyWith({
    String? name,
    String? parentId,
    String? path,
    int? sizeBytes,
    String? mimeType,
    DateTime? modifiedAt,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    int? cueTrackNo,
    int? cueStartMs,
  }) {
    return Track(
      provider: provider,
      remoteId: remoteId,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      cueTrackNo: cueTrackNo ?? this.cueTrackNo,
      cueStartMs: cueStartMs ?? this.cueStartMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, "$name", ${sizeBytes ?? "-"}B)';
}
