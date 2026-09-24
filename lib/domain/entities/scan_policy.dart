/// 扫描策略。
///
/// 全盘遍历会打网盘接口，配额与风控都是真实约束。这里把「扫多深、扫多少、
/// 多快、跳过什么」集中成一份可测试的配置，而不是散落在扫描器里。
class ScanPolicy {
  const ScanPolicy({
    this.maxDepth = 12,
    this.maxDirectories = 5000,
    this.pageSize = 50,
    this.minRequestInterval = const Duration(milliseconds: 350),
    this.audioOnly = true,
    this.skipHiddenDirs = true,
    this.skipDirNames = defaultSkipDirNames,
  });

  /// 最大递归深度。超过则不再入队子目录。
  final int maxDepth;

  /// 单次扫描最多列的目录数。防止误选根目录后把整个盘拖死。
  final int maxDirectories;

  /// 每次列目录请求的条目数
  final int pageSize;

  /// 相邻两次列目录请求的最小间隔。
  ///
  /// 夸克实测约 3 QPS 安全，因此默认 350ms（≈2.9 QPS）。
  final Duration minRequestInterval;

  /// 只索引音频文件（非音频仅计数，不落库）
  final bool audioOnly;

  /// 跳过隐藏目录（以 `.` 开头）
  final bool skipHiddenDirs;

  /// 明确跳过的目录名（小写比较）
  final Set<String> skipDirNames;

  /// 常见系统/回收站目录，扫了纯属浪费配额
  static const Set<String> defaultSkipDirNames = {
    '.git',
    '.svn',
    '.trash',
    '.recycle',
    '.thumbnails',
    r'$recycle.bin',
    'system volume information',
    'node_modules',
    '__pycache__',
    '.ds_store',
    'lost+found',
  };

  /// 是否允许进入某个子目录。
  ///
  /// [childDepth] 是子目录相对根目录的深度（根目录为 0，其子目录为 1）。
  bool shouldEnterDir(String name, int childDepth) {
    if (childDepth > maxDepth) return false;
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (skipHiddenDirs && lower.startsWith('.')) return false;
    if (skipDirNames.contains(lower)) return false;
    return true;
  }

  /// 是否已达目录数上限，应停止入队新目录。
  ///
  /// [scannedDirs] 是**已完成**的目录数，[queuedDirs] 是**队列里待扫**的目录数。
  ///
  /// ⚠️ 必须把队列也算进来。只看已完成数会有一个真实漏洞：一个含上万个子目录
  /// 的目录会在单次遍历里把它们全部入队（那时 `scannedDirs` 还是 0），
  /// 上限形同虚设，`maxDirectories` 就防不住「误选根目录把整个盘拖死」。
  bool reachedDirLimit(int scannedDirs, {int queuedDirs = 0}) =>
      scannedDirs + queuedDirs >= maxDirectories;

  /// 队列里排队的目录是否也应因深度被丢弃。
  bool shouldKeepQueuedDir(int depth) => depth <= maxDepth;

  ScanPolicy copyWith({
    int? maxDepth,
    int? maxDirectories,
    int? pageSize,
    Duration? minRequestInterval,
    bool? audioOnly,
    bool? skipHiddenDirs,
    Set<String>? skipDirNames,
  }) {
    return ScanPolicy(
      maxDepth: maxDepth ?? this.maxDepth,
      maxDirectories: maxDirectories ?? this.maxDirectories,
      pageSize: pageSize ?? this.pageSize,
      minRequestInterval: minRequestInterval ?? this.minRequestInterval,
      audioOnly: audioOnly ?? this.audioOnly,
      skipHiddenDirs: skipHiddenDirs ?? this.skipHiddenDirs,
      skipDirNames: skipDirNames ?? this.skipDirNames,
    );
  }

  @override
  String toString() => 'ScanPolicy(depth<=$maxDepth, dirs<=$maxDirectories, '
      'page=$pageSize, interval=${minRequestInterval.inMilliseconds}ms)';
}
