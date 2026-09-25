import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../../core/utils/lrc.dart';
import '../../core/utils/text_encoding.dart';
import '../../data/lyrics/lrclib_client.dart';
import '../adapters/cloud_drive_adapter.dart';
import '../adapters/library_repository.dart';
import '../entities/drive_provider.dart';
import '../entities/lyrics.dart';
import '../entities/track.dart';

/// 单份歌词的读取上限。
///
/// 歌词是几 KB 的文本，512KB 已经宽到离谱 —— 但它同时是
/// `readFileBytes` 的默认值，写出来是为了**明确这不是随手取的默认值**：
/// 真正要防的是「网盘上那个 `.lrc` 其实是个几十 MB 的其它文件」，
/// 而按上限截断拿到半份歌词，比读崩掉好。
const int kMaxLyricsBytes = 512 * 1024;

/// 在**播放时**把一首歌的歌词解析出来。
///
/// 三段来源，按代价从低到高：
///   1. **本地索引库**里已经有正文 → 直接返回（一次 SQL 读，无网络）；
///   2. 扫描时**发现过**本地 `.lrc` 但正文还没读 → 现在去读（一次小请求）；
///   3. 都没有、且用户**明确开启**了联网歌词 → 去 LRCLIB 查。
///
/// 为什么不在扫描阶段就把正文读下来：夸克的列目录/读文件接口有 QPS 限制，
/// 一个几千张专辑的曲库会因此多出几千次请求，而其中大部分歌词可能永远
/// 没人看。播放时读则是「用户真的要看这首」时才花这一次代价。
///
/// **永不抛异常**：歌词是锦上添花，读不到只该让界面显示「暂无歌词」，
/// 绝不能让播放流程出问题。
class LyricsResolver {
  LyricsResolver({
    required LibraryRepository library,
    required DriveAdapterRegistry registry,
    required LrclibClient lrclib,
  })  : _library = library,
        _registry = registry,
        _lrclib = lrclib;

  final LibraryRepository _library;
  final DriveAdapterRegistry _registry;
  final LrclibClient _lrclib;

  /// 解析 [track] 的歌词。没有就返回 `null`。
  ///
  /// [allowNetwork] 由调用方从设置里读出来传进来（默认关闭）。
  /// 刻意做成参数而不是在这里读设置：本类因此不依赖任何 UI 层的状态，
  /// 单测可以直接把两种情形都跑一遍。
  Future<Lyrics?> resolve(Track track, {required bool allowNetwork}) async {
    final cached = await _lyricsFor(track.id);

    // 1) 已经有正文
    if (cached != null && cached.content != null) return cached;

    // 2) 本地已定位、正文没读 —— 现在读
    final fileId = cached?.fileId;
    if (cached != null && cached.source == LyricsSource.local && fileId != null) {
      final read = await _readLocal(track.provider, fileId);
      final text = read.text;
      if (text != null) {
        final filled = cached.copyWith(content: text);
        await _save([filled]);
        diag.info(
          '歌词',
          '${track.displayTitle}：读到本地歌词（${text.length} 字）',
        );
        return filled;
      }
      if (read.gone) {
        // 文件在网盘上没了、或者给不出任何歌词（空文件 / 只有标签）。
        // 把这行删掉，否则每次播放都会白试一次；下次扫描发现它回来了
        // 会重新记上 —— 这也正是「文件后来才补上内容」能自愈的原因。
        diag.info('歌词', '${track.displayTitle}：本地歌词文件给不出内容，清掉引用');
        await _delete(track.id);
      }
      // 其余失败（网络抖动、超时）保留引用，下次播放再试
    }

    // 3) 联网
    if (!allowNetwork) return null;
    return _fetchRemote(track);
  }

  // -------------------------------------------------------------------
  // 本地
  // -------------------------------------------------------------------

  /// 读一份本地 `.lrc`。
  ///
  /// `text` 非空即成功（一定是**解析得出内容**的文本）。`text` 为 `null`
  /// 表示没读到，此时看 `gone`：
  ///   - `gone == true`：这个文件**给不出歌词**（不存在 / 0 字节 /
  ///     只有 `[ti:]` 之类的标签）→ 调用方应当清掉引用；
  ///   - `gone == false`：暂时性失败（网盘不支持读、网络抖动）→ 保留引用，
  ///     下次播放再试。
  ///
  /// 这个区分是必要的：把所有失败都当成「文件没了」会在一次网络抖动之后
  /// 把用户全部本地歌词的引用删掉，而下一次扫描才会重新发现它们。
  Future<({String? text, bool gone})> _readLocal(
    DriveProvider provider,
    String fileId,
  ) async {
    final adapter = _registry.adapterFor(provider);
    if (adapter == null) return (text: null, gone: false);

    List<int> bytes;
    try {
      bytes = await adapter.readFileBytes(fileId, maxBytes: kMaxLyricsBytes);
    } on DriveException catch (e) {
      if (e.type == DriveErrorType.notFound) {
        return (text: null, gone: true);
      }
      diag.info('歌词', '读本地歌词失败（${e.type.name}）${e.message}');
      return (text: null, gone: false);
    } catch (e) {
      diag.warn('歌词', '读本地歌词抛出非预期异常', error: e);
      return (text: null, gone: false);
    }

    if (bytes.isEmpty) return (text: null, gone: true);

    // 中文歌词和 CUE 一样大量是 GBK（中文 Windows 上的歌词下载器写的），
    // 所以走同一套「先严格 UTF-8、失败再 GBK」的判定。
    final raw = decodeTextBytes(bytes);

    // 解析一次，确认它真的能给出歌词再落库。
    //
    // ⚠️ 解析不出内容时**清掉引用**，而不是记一条「空正文」了事。
    // 空正文一旦落库，即使网盘上那个文件后来补上了内容，upsert 也会因为
    // 「fileId 没变」而把空正文留住 —— 用户就永远卡在「没有歌词」上了，
    // 而且**没有任何操作能自愈**（重扫也不会）。清掉引用则下次扫描会重新
    // 发现它，代价只是白读一次几 KB 的文本。
    if (parseLrc(raw).isEmpty) {
      diag.info('歌词', '本地歌词文件里没有任何可用内容（${bytes.length}B）');
      return (text: null, gone: true);
    }
    return (text: raw, gone: false);
  }

  // -------------------------------------------------------------------
  // 联网
  // -------------------------------------------------------------------

  Future<Lyrics?> _fetchRemote(Track track) async {
    final ms = track.durationMs;
    final result = await _lrclib.lookup(
      trackName: track.displayTitle,
      artistName: track.displayArtist,
      albumName: track.album,
      // 时长未知就传 null —— 传一个乱猜的会让本来查得到的曲子变成 404
      // （见 LrclibClient 的注释）。这里**不做任何兜底猜测**。
      durationSeconds: ms == null ? null : ms ~/ 1000,
    );
    if (result == null || !result.isUseful) return null;

    final lyrics = Lyrics(
      trackId: track.id,
      provider: track.provider,
      source: LyricsSource.lrclib,
      content: result.text,
      instrumental: result.instrumental,
    );
    await _save([lyrics]);
    diag.info('歌词', '${track.displayTitle}：联网取到歌词 $lyrics');
    return lyrics;
  }

  // -------------------------------------------------------------------
  // 仓储访问（全部吞掉异常）
  // -------------------------------------------------------------------

  Future<Lyrics?> _lyricsFor(String trackId) async {
    try {
      return await _library.lyricsFor(trackId);
    } catch (e) {
      diag.warn('歌词', '读歌词索引失败', error: e);
      return null;
    }
  }

  Future<void> _save(List<Lyrics> lyrics) async {
    try {
      await _library.upsertLyrics(lyrics);
    } catch (e) {
      // 落库失败只影响「下次还要再读一次」，本次显示照常
      diag.warn('歌词', '歌词落库失败（不影响本次显示）', error: e);
    }
  }

  Future<void> _delete(String trackId) async {
    try {
      await _library.deleteLyrics({trackId});
    } catch (e) {
      diag.warn('歌词', '清歌词引用失败', error: e);
    }
  }
}
