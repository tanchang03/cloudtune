import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../core/error/drive_error.dart';
import '../../domain/adapters/cloud_drive_adapter.dart';
import '../../domain/entities/album_cover.dart';

/// 专辑封面字节的取用与缓存。
///
/// 封面图存在网盘上，而专辑视图一屏就有几十张卡片 —— 直接每次都去网盘取
/// 意味着每次滚动都在打接口，而夸克的取链接口是有 QPS 限制的（见
/// `TokenBucket`）。所以这里做两层缓存：
///
///   1. **内存 LRU**（[memoryEntries] 张）：同一屏来回滚动不再走 IO；
///   2. **磁盘缓存**（[cacheDirPath]）：重启应用后不必重新拉一遍。
///
/// 刻意**不做**的事：
///   - **不预取**。只有卡片真的出现在屏幕上才会取，用户没打开的专辑
///     一张图都不拉。
///   - **不缓存失败**（磁盘上）。网络抖动是暂时的，把「这张图取不到」
///     写进磁盘等于永久放弃它。失败只在**内存里记一个冷却期**
///     （[failureCooldown]），避免同一个坏图在一屏里被重试几十次。
///   - **不抛异常**。取不到封面只是「这张专辑没有封面」，界面上退回品牌
///     渐变占位即可，不该让专辑视图崩掉或弹错误。
class AlbumCoverCache {
  AlbumCoverCache({
    required DriveAdapterRegistry registry,
    required String cacheDirPath,
    this.memoryEntries = 24,
    this.maxCacheBytes = 256 * 1024 * 1024,
    this.maxCacheFiles = 600,
    this.trimEveryWrites = 200,
    this.failureCooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
  })  : _registry = registry,
        _dir = Directory(cacheDirPath),
        _clock = clock ?? DateTime.now;

  /// 单张封面的读取上限。超出就当作「这不是一张封面」放弃。
  ///
  /// 12MB 是刻意留宽的：一张 3000×3000 的扫描图完全可能有几 MB，而
  /// 按 512KB（`readFileBytes` 的默认值）去卡会把大量真实封面挡在门外。
  /// 同时它远低于夸克下载路由的 50MiB 上限，不会被接口侧拒绝。
  static const int maxCoverBytes = 12 * 1024 * 1024;

  final DriveAdapterRegistry _registry;
  final Directory _dir;
  final DateTime Function() _clock;

  /// 内存里最多留几张。24 张 ≈ 一屏多一点，再多就只是白占内存。
  final int memoryEntries;

  /// 磁盘缓存的总量上限（按文件体积累计）
  final int maxCacheBytes;

  /// 磁盘缓存的张数上限
  final int maxCacheFiles;

  /// 同一个封面取失败后的冷却期
  final Duration failureCooldown;

  /// 每写这么多张就检查一次缓存总量。
  ///
  /// **首次写盘也会检查**（`_writes == 1`）—— 那次检查的是上一次运行留下的
  /// 文件。只在启动时查一次是不够的：用户一次浏览几千张专辑，本次运行新增的
  /// 文件永远等不到「下次启动」就已经把磁盘占了。
  final int trimEveryWrites;

  /// 访问顺序表（`LinkedHashMap` 天然按插入顺序迭代，取用时重新插入即可当 LRU）
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();

  /// `cover.key` → 最近一次失败的时刻
  final Map<String, DateTime> _failed = {};

  /// 成功写盘的次数，用来决定何时清理
  int _writes = 0;

  /// 当前内存里缓存了几张（测试用）
  int get cachedInMemory => _memory.length;

  /// 取一张封面的字节。取不到返回 `null`（调用方回退占位）。
  Future<Uint8List?> load(AlbumCover cover) async {
    final key = cover.key;

    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit; // 重新插入 = 标记为最近使用
      return hit;
    }

    final failedAt = _failed[key];
    if (failedAt != null && _clock().difference(failedAt) < failureCooldown) {
      return null;
    }

    final file = _fileFor(cover);
    final fromDisk = await _readDisk(file);
    if (fromDisk != null) {
      _remember(key, fromDisk);
      return fromDisk;
    }

    return _fetch(cover, file);
  }

  /// 从网盘取字节，成功就顺手落盘。
  Future<Uint8List?> _fetch(AlbumCover cover, File file) async {
    final adapter = _registry.adapterFor(cover.provider);
    if (adapter == null) {
      // 未注册的网盘：不是错误，是「这个网盘现在不可用」。
      // 记进冷却期，免得每张卡片都再判一次。
      _failed[cover.key] = _clock();
      return null;
    }

    try {
      final bytes =
          await adapter.readFileBytes(cover.fileId, maxBytes: maxCoverBytes);
      if (bytes.isEmpty) {
        throw DriveException(
          type: DriveErrorType.network,
          message: '返回了 0 字节',
        );
      }
      _failed.remove(cover.key);
      _remember(cover.key, bytes);
      await _writeDisk(file, bytes);
      return bytes;
    } on DriveException catch (e) {
      // `unsupported` 是预期内的（不是每家网盘都提供读文件的能力），
      // 其余才是真的异常，日志级别区分开。
      if (e.type == DriveErrorType.unsupported) {
        diag.info('封面', '${cover.dirPath}：该网盘不支持读取文件内容，跳过');
      } else {
        diag.warn(
          '封面',
          '${cover.dirPath}：读取 "${cover.fileName}" 失败（${e.type.name}）'
          '${e.message}',
        );
      }
      _failed[cover.key] = _clock();
      return null;
    } catch (e) {
      diag.warn('封面', '${cover.dirPath}：读取抛出非预期异常', error: e);
      _failed[cover.key] = _clock();
      return null;
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  // -------------------------------------------------------------------
  // 磁盘
  // -------------------------------------------------------------------

  Future<Uint8List?> _readDisk(File file) async {
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        // 上次写到一半被杀（磁盘满、进程退出）留下的空文件。
        // 留着它会让这张封面**永远**是空的，所以直接删掉重取。
        await file.delete();
        return null;
      }
      return bytes;
    } catch (e) {
      // 读盘失败只意味着「这次没命中缓存」，去网盘取一次就好。
      // 但它说明磁盘有问题（权限、坏道），值得留在日志里。
      diag.warn('封面', '读缓存失败，改走网盘：${file.path}', error: e);
      return null;
    }
  }

  Future<void> _writeDisk(File file, Uint8List bytes) async {
    try {
      if (!await _dir.exists()) await _dir.create(recursive: true);
      // 先写临时文件再改名：直接写目标文件时，进程在写到一半被杀会留下
      // 一个**半张图**——JPEG 能解码出上半截，界面上就是一张撕裂的封面。
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);

      // 首次写盘时清一次（处理上次运行留下的文件），之后按写入张数周期性清。
      // 清理本身是 O(缓存文件数) 的 stat 遍历，不能每写一张都做。
      _writes++;
      if (_writes == 1 || (_writes % trimEveryWrites) == 0) {
        await _trim();
      }
    } catch (e) {
      // 磁盘缓存是**加速手段**，写不进去只影响下次启动的快慢，不该影响本次显示
      diag.warn('封面', '写缓存失败（不影响本次显示）：${file.path}', error: e);
    }
  }

  /// 缓存超量时按「最久未修改」淘汰。
  ///
  /// 按体积而不是只按张数：张数上限拦不住「600 张每张 10MB 的扫描图」
  /// 这种 6GB 的极端情况，而缓存是放在用户的应用支持目录里的。
  Future<void> _trim() async {
    try {
      if (!await _dir.exists()) return;
      final entries = <({File file, DateTime at, int size})>[];
      await for (final item in _dir.list()) {
        if (item is! File || item.path.endsWith('.part')) continue;
        try {
          final stat = await item.stat();
          entries.add((file: item, at: stat.modified, size: stat.size));
        } catch (_) {
          // 并发删除 / 权限问题：跳过这一条，不影响其余清理
        }
      }

      var total = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (entries.length <= maxCacheFiles && total <= maxCacheBytes) return;

      entries.sort((a, b) => a.at.compareTo(b.at)); // 最旧的在前
      var index = 0;
      while (index < entries.length &&
          (entries.length - index > maxCacheFiles || total > maxCacheBytes)) {
        final victim = entries[index++];
        total -= victim.size;
        try {
          await victim.file.delete();
        } catch (_) {
          // 删不掉就算了，下次启动再试
        }
      }
      diag.info(
        '封面',
        '缓存超量，清掉最旧的 $index 张（余 ${entries.length - index} 张 / '
        '${(total / 1024 / 1024).toStringAsFixed(1)}MB）',
      );
    } catch (e) {
      diag.warn('封面', '缓存清理失败（不影响使用）', error: e);
    }
  }

  /// 缓存文件名：`<provider>_<fileId>.<ext>`，人类可读，便于排查。
  File _fileFor(AlbumCover cover) {
    final ext = cover.extension.isEmpty ? 'img' : cover.extension;
    return File('${_dir.path}${Platform.pathSeparator}${_stemOf(cover)}.$ext');
  }

  static String _stemOf(AlbumCover cover) {
    final raw = cover.fileId;
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe == raw) return '${cover.provider.id}_$safe';
    // ID 里含需要转义的字符时补一段哈希：不补的话两个不同的 ID 可能被压成
    // 同一个文件名，结果是**这张专辑显示另一张专辑的封面** —— 而且完全
    // 看不出哪里错了。
    final hash = sha1.convert(utf8.encode(raw)).toString().substring(0, 10);
    return '${cover.provider.id}_${safe}_$hash';
  }
}
