import '../../core/utils/audio_formats.dart';
import '../../core/utils/image_formats.dart';
import '../entities/album_cover.dart';
import '../entities/drive_entry.dart';
import '../entities/drive_provider.dart';

/// 从候选图片里挑出一张当专辑封面。
///
/// 纯函数、不碰 IO，所以可以拿真实音乐包的文件名直接跑单测
/// （见 `test/domain/album_cover_indexer_test.dart`）。
///
/// 为什么需要「挑」而不是「拿第一张」：真实音乐包里同一个目录常有
/// `cover.jpg`、`back.jpg`、`disc1.jpg`、`扫描内页/01.jpg` 好几张图，
/// 随便取一张的话用户看到的封面有一半概率是封底或者碟面 —— 那比没有封面
/// 更糟，因为它看起来像是**读错了**。
class AlbumCoverIndexer {
  const AlbumCoverIndexer();

  /// 这个条目能不能拿来当封面。
  ///
  /// 0 字节的图片是坏文件，用它当封面只会得到一个永远加载不出来的卡片。
  /// 体积未知（`null`）不在此列 —— 网盘没返回体积不代表文件是空的。
  static bool isUsableImage(DriveEntry entry) {
    if (entry.isDirectory) return false;
    if (!isImageFile(entry.name, mimeType: entry.mimeType)) return false;
    if (entry.sizeBytes == 0) return false;
    return true;
  }

  /// 候选里是否已经有「明确写着封面」的图。
  ///
  /// 有的话就**不必再去列子目录**：同目录的 `cover.jpg` 得分是
  /// `0 * 10 + 0 = 0`，已经是最低分，子目录里最好的图也只能打 1 分。
  /// 一次扫描里省下的是「每个专辑目录多一次列目录请求」。
  static bool hasNamedCover(Iterable<DriveEntry> entries) => entries.any(
        (e) => isUsableImage(e) && coverNameRank(e.name) == kCoverRankNamed,
      );

  /// 候选来源的档位（越小越可信）。
  ///
  /// 位置与文件名是两个独立信号，合起来才是最终分：`Cover/front.jpg`
  /// （明确写了封面的子目录）应当赢过同目录的 `back.jpg`（同目录但明确是封底），
  /// 所以不能简单地「同目录永远优先」。
  static const int _tierSameDir = 0;
  static const int _tierCoverDir = 1;
  static const int _tierImageDir = 2;

  /// 挑一张封面。候选为空、或没有一张能用的图片时返回 `null`。
  ///
  /// [sameDir] 是与音频**同一个目录**下的条目，[artworkDirs] 是封面候选
  /// 子目录（`key` = 子目录名，如 `Cover` / `Artwork` / `Scans`）。
  ///
  /// [dirPath] 只用于写进返回值，必须是归一化后的目录路径。
  AlbumCover? pick({
    required DriveProvider provider,
    required String dirPath,
    required List<DriveEntry> sameDir,
    Map<String, List<DriveEntry>> artworkDirs = const {},
  }) {
    DriveEntry? best;
    var bestScore = 1 << 30;

    void consider(DriveEntry entry, int tier, bool fromCoverDir) {
      if (!isUsableImage(entry)) return;

      var rank = coverNameRank(entry.name);
      // 目录名已经说了「这里就是封面」，那里面叫 `01.jpg` 的图也比同目录的
      // 一张无名图更可信 —— 但不会盖过「明确写着封面」的名字。
      if (fromCoverDir && rank > kCoverRankHinted) rank = kCoverRankHinted;

      final score = rank * 10 + tier;
      // 取到局部变量再判：`best` 是在闭包里被赋值的，Dart 的类型提升
      // 对「被闭包捕获的可变局部变量」不生效，直接用会报
      // `DriveEntry?` 不能赋给 `DriveEntry`。
      final current = best;
      if (current != null) {
        if (score > bestScore) return;
        if (score == bestScore && !_beats(entry, current)) return;
      }
      best = entry;
      bestScore = score;
    }

    for (final e in sameDir) {
      consider(e, _tierSameDir, false);
    }
    artworkDirs.forEach((dirName, entries) {
      final coverDir = isCoverDirName(dirName);
      for (final e in entries) {
        consider(e, coverDir ? _tierCoverDir : _tierImageDir, coverDir);
      }
    });

    final picked = best;
    if (picked == null) return null;
    return AlbumCover(
      provider: provider,
      dirPath: normalizeDirPath(dirPath),
      fileId: picked.id,
      fileName: picked.name,
      sizeBytes: picked.sizeBytes,
    );
  }

  /// 同分时的胜负：体积大的赢（更可能是一张真正的封面而不是缩略图），
  /// 体积也一样就按文件名，保证结果**确定**（否则同一份曲库两次扫描可能
  /// 挑出不同的图，缓存与索引会来回抖）。
  static bool _beats(DriveEntry candidate, DriveEntry current) {
    final a = candidate.sizeBytes ?? 0;
    final b = current.sizeBytes ?? 0;
    if (a != b) return a > b;
    return candidate.name.compareTo(current.name) < 0;
  }
}
