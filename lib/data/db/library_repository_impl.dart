import 'package:drift/drift.dart';

import '../../core/utils/audio_formats.dart';
import '../../domain/adapters/library_repository.dart';
import '../../domain/entities/album_cover.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/cloud_account.dart';
import '../../domain/entities/drive_provider.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/playability.dart';
import '../../domain/entities/scan_cursor.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/playability_resolver.dart';
import '../../domain/services/shuffle_engine.dart';
import 'app_database.dart';
import 'scan_state_codec.dart';

/// 基于 Drift 的曲库仓储实现。
///
/// 几个刻意的设计选择：
///   1. **手写 SQL 而非 Query Builder**：关键字检索需要 `ESCAPE` 子句，
///      排序需要 `COLLATE NOCASE` + 稳定次序，这些用 builder 表达很别扭。
///      所有值都走绑定变量，动态部分只有列名与排序关键字（来自枚举）。
///   2. **upsert 不覆盖播放统计**：用 `ON CONFLICT DO UPDATE SET` 显式列出
///      要更新的列，`play_count` / `last_played_at` 不在其中 ——
///      否则每扫一次盘，用户的播放次数就归零。
///   3. **清理陈旧曲目用临时表**：`NOT IN (5000 个值)` 会撞上 SQLite 的
///      绑定变量上限，改用临时表 + 子查询，绑定变量恒为 1 个。
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);

  final AppDatabase _db;

  // -------------------------------------------------------------------
  // 曲目写入
  // -------------------------------------------------------------------

  /// upsert 时**显式列出**要覆盖的列。
  ///
  /// `play_count` / `last_played_at` 刻意不在列表里 —— 重复扫描必须保留
  /// 用户的播放统计，这是「少听优先」随机算法的输入。
  static const String _upsertTrackSql = '''
INSERT INTO tracks (
  id, provider_id, remote_id, name, parent_id, path, size_bytes, mime_type,
  modified_at, title, artist, album, duration_ms, cue_track_no, cue_start_ms,
  is_playable, playability_state, playability_note, indexed_at, first_seen_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  provider_id = excluded.provider_id,
  remote_id = excluded.remote_id,
  name = excluded.name,
  parent_id = excluded.parent_id,
  path = excluded.path,
  size_bytes = excluded.size_bytes,
  mime_type = excluded.mime_type,
  modified_at = excluded.modified_at,
  title = excluded.title,
  artist = excluded.artist,
  album = excluded.album,
  duration_ms = excluded.duration_ms,
  cue_track_no = excluded.cue_track_no,
  cue_start_ms = excluded.cue_start_ms,
  is_playable = excluded.is_playable,
  playability_state = excluded.playability_state,
  playability_note = excluded.playability_note,
  indexed_at = excluded.indexed_at
  -- first_seen_at 故意不更新：它只认第一次入库的时间
''';

  @override
  Future<void> upsertTracks(
    Iterable<Track> tracks, {
    required Capabilities capabilities,
    DateTime? now,
  }) async {
    final list = tracks.toList();
    if (list.isEmpty) return;
    final ts = now ?? DateTime.now();

    await _db.transaction(() async {
      for (final t in list) {
        final p = t.playability(capabilities);
        await _db.customInsert(
          _upsertTrackSql,
          variables: [
            Variable.withString(t.id),
            Variable.withString(t.provider.id),
            Variable.withString(t.remoteId),
            Variable.withString(t.name),
            _nullableString(t.parentId),
            _nullableString(t.path),
            _nullableInt(t.sizeBytes),
            _nullableString(t.mimeType),
            _nullableDateTime(t.modifiedAt),
            _nullableString(t.title),
            _nullableString(t.artist),
            _nullableString(t.album),
            _nullableInt(t.durationMs),
            _nullableInt(t.cueTrackNo),
            _nullableInt(t.cueStartMs),
            Variable.withBool(p.shouldAttempt),
            Variable.withString(p.state.name),
            _nullableString(p.reason),
            Variable.withDateTime(ts),
            Variable.withDateTime(ts),
          ],
        );
      }
    });
  }

  // -------------------------------------------------------------------
  // 曲目查询
  // -------------------------------------------------------------------

  @override
  Future<List<Track>> queryTracks([TrackQuery query = const TrackQuery()]) async {
    final where = <String>[];
    final vars = <Variable<Object>>[];

    if (query.provider != null) {
      where.add('provider_id = ?');
      vars.add(Variable.withString(query.provider!.id));
    }
    if (query.playableOnly == true) {
      where.add('is_playable = 1');
    } else if (query.playableOnly == false) {
      where.add('is_playable = 0');
    }
    if (query.favoritesOnly) {
      where.add('id IN (SELECT track_id FROM favorites)');
    }
    if (query.artist != null && query.artist!.isNotEmpty) {
      where.add('artist = ?');
      vars.add(Variable.withString(query.artist!));
    }
    if (query.album != null && query.album!.isNotEmpty) {
      where.add('album = ?');
      vars.add(Variable.withString(query.album!));
    }
    if (query.dirPath != null && query.dirPath!.isNotEmpty) {
      // `tracks.path` 是**展示路径**（带结尾斜杠，如 `/音乐/华语/`），而
      // 目录键是归一化的（`/音乐/华语`）。用 `rtrim` 在 SQL 里对齐两者，
      // 而不是让每个调用方自己记得「拼一个结尾斜杠」—— 少一个斜杠就
      // 查不到任何曲目，而且是静默的空列表。
      where.add("rtrim(path, '/') = ?");
      vars.add(Variable.withString(normalizeDirPath(query.dirPath!)));
    }

    final keyword = query.keyword?.trim() ?? '';
    if (keyword.isNotEmpty) {
      // ESCAPE '\' 让用户输入里的 % 和 _ 按字面匹配，而不是当通配符
      final pattern = '%${_escapeLike(keyword)}%';
      where.add(
        "(name LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' "
        "OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\' "
        "OR path LIKE ? ESCAPE '\\')",
      );
      for (var i = 0; i < 5; i++) {
        vars.add(Variable.withString(pattern));
      }
    }

    final sql = StringBuffer('SELECT * FROM tracks');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');
    sql.write(' ORDER BY ${_orderBy(query.sort)}');

    if (query.limit != null) {
      sql.write(' LIMIT ?');
      vars.add(Variable.withInt(query.limit!));
      if (query.offset > 0) {
        sql.write(' OFFSET ?');
        vars.add(Variable.withInt(query.offset));
      }
    } else if (query.offset > 0) {
      sql.write(' LIMIT -1 OFFSET ?');
      vars.add(Variable.withInt(query.offset));
    }

    final rows = await _db
        .customSelect(sql.toString(), variables: vars, readsFrom: {_db.tracks})
        .get();
    return rows.map(_rowToTrack).toList();
  }

  /// 排序 SQL。每个分支都追加 `id ASC` 保证稳定次序 ——
  /// 否则同艺术家的曲目在分页时可能重复或遗漏。
  ///
  /// ⚠️ `cue_track_no` 必须排在 `id` **前面**。一张整轨 CUE 切出的 N 段
  /// 共用同一个文件名，所以按名字排序时它们是并列的，真正决定次序的是
  /// 后面的兜底列。只写 `id ASC` 会退化成**字符串**比较：
  /// `...#c1 < ...#c10 < ...#c11 < ...#c2`，第 10 首会排到第 2 首前面。
  static String _orderBy(TrackSort sort) {
    switch (sort) {
      case TrackSort.nameAsc:
        return 'name COLLATE NOCASE ASC, cue_track_no ASC, id ASC';
      case TrackSort.artistAsc:
        return 'artist COLLATE NOCASE ASC, album COLLATE NOCASE ASC, '
            'name COLLATE NOCASE ASC, cue_track_no ASC, id ASC';
      case TrackSort.albumAsc:
        return 'album COLLATE NOCASE ASC, artist COLLATE NOCASE ASC, '
            'name COLLATE NOCASE ASC, cue_track_no ASC, id ASC';
      case TrackSort.sizeDesc:
        return 'size_bytes DESC, name COLLATE NOCASE ASC, '
            'cue_track_no ASC, id ASC';
      case TrackSort.sizeAsc:
        return 'size_bytes ASC, name COLLATE NOCASE ASC, '
            'cue_track_no ASC, id ASC';
      case TrackSort.recentlyIndexed:
        return 'indexed_at DESC, name COLLATE NOCASE ASC, '
            'cue_track_no ASC, id ASC';
      case TrackSort.recentlyModified:
        return 'modified_at DESC, name COLLATE NOCASE ASC, '
            'cue_track_no ASC, id ASC';
      case TrackSort.mostPlayed:
        return 'play_count DESC, name COLLATE NOCASE ASC, '
            'cue_track_no ASC, id ASC';
    }
  }

  /// 新歌判定条件（与 `newTracksCount` / `newTracks` 共用）。
  ///
  /// 一首歌「新」= 它第一次进库的时间晚于用户上次「看完新歌」的时间。
  /// `seenAt` 为 `null` 表示用户还没设过水位（这种情况由扫描服务在首次
  /// 成功扫描后写入「现在」，把它变成基线，所以这里不能让 `null` 把全库
  /// 都刷成新歌）。
  static void _appendNewSongsWhere(
    StringBuffer where,
    List<Variable<Object>> vars, {
    DriveProvider? provider,
    DateTime? seenAt,
  }) {
    where.write('first_seen_at IS NOT NULL');
    if (provider != null) {
      where.write(' AND provider_id = ?');
      vars.add(Variable.withString(provider.id));
    }
    if (seenAt != null) {
      where.write(' AND first_seen_at > ?');
      vars.add(Variable.withDateTime(seenAt));
    }
  }

  @override
  Future<int> newTracksCount({
    DriveProvider? provider,
    DateTime? seenAt,
  }) async {
    final where = StringBuffer();
    final vars = <Variable<Object>>[];
    _appendNewSongsWhere(where, vars, provider: provider, seenAt: seenAt);
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM tracks WHERE ${where.toString()}',
          variables: vars,
          readsFrom: {_db.tracks},
        )
        .getSingle();
    return row.read<int>('c');
  }

  @override
  Future<List<Track>> newTracks({
    DriveProvider? provider,
    DateTime? seenAt,
    int? limit,
  }) async {
    final where = StringBuffer();
    final vars = <Variable<Object>>[];
    _appendNewSongsWhere(where, vars, provider: provider, seenAt: seenAt);
    final sql = StringBuffer(
      'SELECT * FROM tracks WHERE ${where.toString()} '
      'ORDER BY first_seen_at DESC, id ASC',
    );
    if (limit != null) {
      sql.write(' LIMIT ?');
      vars.add(Variable.withInt(limit));
    }
    final rows = await _db
        .customSelect(sql.toString(), variables: vars, readsFrom: {_db.tracks})
        .get();
    return rows.map(_rowToTrack).toList();
  }

  /// 转义 LIKE 通配符，配合 `ESCAPE '\'` 使用。
  static String _escapeLike(String raw) => raw
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  @override
  Future<Track?> trackById(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM tracks WHERE id = ? LIMIT 1',
          variables: [Variable.withString(id)],
          readsFrom: {_db.tracks},
        )
        .get();
    return rows.isEmpty ? null : _rowToTrack(rows.first);
  }

  @override
  Future<int> countTracks({DriveProvider? provider, bool? playableOnly}) async {
    final where = <String>[];
    final vars = <Variable<Object>>[];
    if (provider != null) {
      where.add('provider_id = ?');
      vars.add(Variable.withString(provider.id));
    }
    if (playableOnly != null) {
      where.add('is_playable = ?');
      vars.add(Variable.withBool(playableOnly));
    }
    final sql = StringBuffer('SELECT COUNT(*) AS c FROM tracks');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');

    final row = await _db
        .customSelect(sql.toString(), variables: vars, readsFrom: {_db.tracks})
        .getSingle();
    return row.read<int>('c');
  }

  @override
  Future<void> deleteTracks(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      for (final chunk in _chunks(ids.toList(), 400)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        await _db.customStatement(
          'DELETE FROM tracks WHERE id IN ($placeholders)',
          chunk,
        );
      }
    });
  }

  @override
  Future<int> deleteTracksNotIn(DriveProvider provider, Set<String> keepIds) async {
    return _db.transaction(() async {
      // 临时表存「要保留的 ID」，避免 NOT IN 绑定变量过多撞上 SQLite 上限
      await _db.customStatement(
        'CREATE TEMP TABLE IF NOT EXISTS _keep_ids (id TEXT PRIMARY KEY)',
      );
      await _db.customStatement('DELETE FROM _keep_ids');

      for (final chunk in _chunks(keepIds.toList(), 400)) {
        final placeholders = List.filled(chunk.length, '(?)').join(',');
        await _db.customStatement(
          'INSERT OR IGNORE INTO _keep_ids (id) VALUES $placeholders',
          chunk,
        );
      }

      await _db.customStatement(
        'DELETE FROM tracks WHERE provider_id = ? '
        'AND id NOT IN (SELECT id FROM _keep_ids)',
        [provider.id],
      );

      final row = await _db
          .customSelect('SELECT changes() AS c')
          .getSingle();
      await _db.customStatement('DROP TABLE IF EXISTS _keep_ids');
      return row.read<int>('c');
    });
  }

  @override
  Future<void> clearProvider(DriveProvider provider) async {
    await (_db.delete(_db.tracks)..where((t) => t.providerId.equals(provider.id)))
        .go();
    await (_db.delete(_db.albumCovers)
          ..where((c) => c.providerId.equals(provider.id)))
        .go();
    // 歌词：曲目行已经被上面那条 DELETE 删掉，`trg_tracks_delete_lyrics`
    // 触发器其实已经清过一遍了。这里再删一次是**兜底**：老库升级上来时
    // 触发器可能是刚建的，而万一触发器因为任何原因没生效，残留的歌词行
    // 会让「歌词覆盖数」永远对不上曲目数 —— 一个查不出原因的脏数据。
    // 多一条 DELETE 的代价可以忽略，值得。
    await (_db.delete(_db.lyrics)
          ..where((l) => l.providerId.equals(provider.id)))
        .go();
    await (_db.delete(_db.favorites)).go();
    await (_db.delete(_db.playHistory)).go();
    await (_db.delete(_db.scanStates)
          ..where((s) => s.providerId.equals(provider.id)))
        .go();
    // ⚠️ `settings` 刻意**不在这里**：它是用户偏好而不是索引数据，
    // 清空曲库不该顺手把用户打开过的开关也关掉。
  }

  // -------------------------------------------------------------------
  // 专辑封面
  // -------------------------------------------------------------------

  /// 封面 upsert：主键是 `(provider_id, dir_path)`。
  ///
  /// 同一个目录换了封面图时**覆盖**而不是新增 —— 否则一个目录会攒下
  /// 历史上出现过的每一张图，而查询只按目录取一张，攒下来的那些
  /// 永远不会被用到，也永远不会被清掉。
  static const String _upsertCoverSql = '''
INSERT INTO album_covers (
  provider_id, dir_path, file_id, file_name, size_bytes, indexed_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(provider_id, dir_path) DO UPDATE SET
  file_id = excluded.file_id,
  file_name = excluded.file_name,
  size_bytes = excluded.size_bytes,
  indexed_at = excluded.indexed_at
''';

  @override
  Future<void> upsertAlbumCovers(
    Iterable<AlbumCover> covers, {
    DateTime? now,
  }) async {
    final list = covers.toList();
    if (list.isEmpty) return;
    final ts = now ?? DateTime.now();

    await _db.transaction(() async {
      for (final c in list) {
        await _db.customInsert(
          _upsertCoverSql,
          variables: [
            Variable.withString(c.provider.id),
            Variable.withString(c.dirPath),
            Variable.withString(c.fileId),
            Variable.withString(c.fileName),
            _nullableInt(c.sizeBytes),
            Variable.withDateTime(ts),
          ],
        );
      }
    });
  }

  @override
  Future<Map<String, AlbumCover>> albumCovers(DriveProvider provider) async {
    final rows = await _db
        .customSelect(
          'SELECT dir_path, file_id, file_name, size_bytes '
          'FROM album_covers WHERE provider_id = ?',
          variables: [Variable.withString(provider.id)],
          readsFrom: {_db.albumCovers},
        )
        .get();

    return {
      for (final r in rows)
        r.read<String>('dir_path'): AlbumCover(
          provider: provider,
          dirPath: r.read<String>('dir_path'),
          fileId: r.read<String>('file_id'),
          fileName: r.read<String>('file_name'),
          sizeBytes: r.readNullable<int>('size_bytes'),
        ),
    };
  }

  @override
  Future<int> deleteAlbumCoversNotIn(
    DriveProvider provider,
    Set<String> keepDirPaths,
  ) async {
    return _db.transaction(() async {
      await _db.customStatement(
        'CREATE TEMP TABLE IF NOT EXISTS _keep_dirs (dir_path TEXT PRIMARY KEY)',
      );
      await _db.customStatement('DELETE FROM _keep_dirs');

      for (final chunk in _chunks(keepDirPaths.toList(), 400)) {
        final placeholders = List.filled(chunk.length, '(?)').join(',');
        await _db.customStatement(
          'INSERT OR IGNORE INTO _keep_dirs (dir_path) VALUES $placeholders',
          chunk,
        );
      }

      await _db.customStatement(
        'DELETE FROM album_covers WHERE provider_id = ? '
        'AND dir_path NOT IN (SELECT dir_path FROM _keep_dirs)',
        [provider.id],
      );

      final row = await _db.customSelect('SELECT changes() AS c').getSingle();
      await _db.customStatement('DROP TABLE IF EXISTS _keep_dirs');
      return row.read<int>('c');
    });
  }

  @override
  Future<void> markUnplayable(
    String trackId, {
    required PlayabilityState state,
    String? reason,
    DateTime? now,
  }) async {
    await _db.customStatement(
      'UPDATE tracks SET is_playable = ?, playability_state = ?, '
      'playability_note = COALESCE(?, playability_note) WHERE id = ?',
      [
        // unknownSize 属于「乐观可播」，不该被标成不可播
        state.isAttemptable ? 1 : 0,
        state.name,
        reason,
        trackId,
      ],
    );
  }

  // -------------------------------------------------------------------
  // 歌词
  // -------------------------------------------------------------------

  /// 歌词 upsert。主键是 `track_id`。
  ///
  /// `content` 那一行是本语句的**关键**，不是随手写的：
  ///
  /// ```sql
  /// content = CASE
  ///   WHEN excluded.content IS NOT NULL THEN excluded.content
  ///   WHEN lyrics.file_id IS excluded.file_id THEN lyrics.content
  ///   ELSE NULL END
  /// ```
  ///
  /// 三种情形分别对应：
  ///   1. 新行带正文（播放时读到了）→ 用新的；
  ///   2. 新行没正文、但指的是**同一个文件**（扫描写引用）→ 保留库里已有的
  ///      正文。**少了这一支，用户每重扫一次盘就会丢掉全部已读歌词** ——
  ///      而重扫是最常见的操作；
  ///   3. 新行没正文、文件也换了（网盘上换了 `.lrc`，或来源从本地变成联网）
  ///      → 丢掉旧正文。那份正文描述的是另一个文件，留着只会显示错的歌词。
  ///
  /// `IS` 是 SQLite 的 null 安全等值比较 —— 联网歌词两边 `file_id` 都是
  /// `NULL`，用 `=` 会得到 `NULL`（即假），第 2 支就永远不生效。
  static const String _upsertLyricsSql = '''
INSERT INTO lyrics (
  track_id, provider_id, source_id, instrumental, content,
  file_id, file_name, size_bytes, indexed_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(track_id) DO UPDATE SET
  provider_id = excluded.provider_id,
  source_id = excluded.source_id,
  instrumental = excluded.instrumental,
  content = CASE
    WHEN excluded.content IS NOT NULL THEN excluded.content
    WHEN lyrics.file_id IS excluded.file_id THEN lyrics.content
    ELSE NULL END,
  file_id = excluded.file_id,
  file_name = excluded.file_name,
  size_bytes = excluded.size_bytes,
  indexed_at = excluded.indexed_at
''';

  @override
  Future<void> upsertLyrics(Iterable<Lyrics> lyrics, {DateTime? now}) async {
    final list = lyrics.toList();
    if (list.isEmpty) return;
    final ts = now ?? DateTime.now();

    await _db.transaction(() async {
      for (final l in list) {
        await _db.customInsert(
          _upsertLyricsSql,
          variables: [
            Variable.withString(l.trackId),
            Variable.withString(l.provider.id),
            Variable.withString(l.source.id),
            Variable.withBool(l.instrumental),
            _nullableString(l.content),
            _nullableString(l.fileId),
            _nullableString(l.fileName),
            _nullableInt(l.sizeBytes),
            Variable.withDateTime(ts),
          ],
        );
      }
    });
  }

  @override
  Future<Lyrics?> lyricsFor(String trackId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM lyrics WHERE track_id = ? LIMIT 1',
          variables: [Variable.withString(trackId)],
          readsFrom: {_db.lyrics},
        )
        .get();
    return rows.isEmpty ? null : _rowToLyrics(rows.first);
  }

  @override
  Future<void> deleteLyrics(Set<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await _db.transaction(() async {
      for (final chunk in _chunks(trackIds.toList(), 400)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        await _db.customStatement(
          'DELETE FROM lyrics WHERE track_id IN ($placeholders)',
          chunk,
        );
      }
    });
  }

  @override
  Future<int> lyricsCount({
    DriveProvider? provider,
    bool loadedOnly = false,
  }) async {
    final where = <String>[];
    final vars = <Variable<Object>>[];
    if (provider != null) {
      where.add('provider_id = ?');
      vars.add(Variable.withString(provider.id));
    }
    if (loadedOnly) where.add('content IS NOT NULL');

    final sql = StringBuffer('SELECT COUNT(*) AS c FROM lyrics');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');

    final row = await _db
        .customSelect(sql.toString(), variables: vars, readsFrom: {_db.lyrics})
        .getSingle();
    return row.read<int>('c');
  }

  @override
  Future<int> deleteLyricsNotIn(
    DriveProvider provider,
    Set<String> keepTrackIds,
  ) async {
    return _db.transaction(() async {
      await _db.customStatement(
        'CREATE TEMP TABLE IF NOT EXISTS _keep_lyrics (track_id TEXT PRIMARY KEY)',
      );
      await _db.customStatement('DELETE FROM _keep_lyrics');

      for (final chunk in _chunks(keepTrackIds.toList(), 400)) {
        final placeholders = List.filled(chunk.length, '(?)').join(',');
        await _db.customStatement(
          'INSERT OR IGNORE INTO _keep_lyrics (track_id) VALUES $placeholders',
          chunk,
        );
      }

      await _db.customStatement(
        'DELETE FROM lyrics WHERE provider_id = ? '
        'AND track_id NOT IN (SELECT track_id FROM _keep_lyrics)',
        [provider.id],
      );

      final row = await _db.customSelect('SELECT changes() AS c').getSingle();
      await _db.customStatement('DROP TABLE IF EXISTS _keep_lyrics');
      return row.read<int>('c');
    });
  }

  // -------------------------------------------------------------------
  // 收藏
  // -------------------------------------------------------------------

  @override
  Future<bool> isFavorite(String trackId) async {
    final row = await (_db.select(_db.favorites)
          ..where((f) => f.trackId.equals(trackId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> setFavorite(
    String trackId, {
    required bool value,
    DateTime? now,
  }) async {
    if (value) {
      await _db.into(_db.favorites).insert(
            FavoritesCompanion.insert(
              trackId: trackId,
              createdAt: now ?? DateTime.now(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (_db.delete(_db.favorites)
            ..where((f) => f.trackId.equals(trackId)))
          .go();
    }
  }

  @override
  Future<Set<String>> favoriteIds() async {
    final rows = await _db.select(_db.favorites).get();
    return rows.map((r) => r.trackId).toSet();
  }

  @override
  Future<int> favoriteCount() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM favorites')
        .getSingle();
    return row.read<int>('c');
  }

  // -------------------------------------------------------------------
  // 续扫状态
  // -------------------------------------------------------------------

  @override
  Future<ScanCursor?> loadScanCursor(DriveProvider provider) async {
    final row = await (_db.select(_db.scanStates)
          ..where((s) => s.providerId.equals(provider.id))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return ScanStateCodec.toCursor(row);
  }

  @override
  Future<void> saveScanCursor(ScanCursor cursor) async {
    await _db.into(_db.scanStates).insert(
          ScanStatesCompanion.insert(
            providerId: cursor.provider.id,
            rootId: cursor.rootId,
            rootPath: cursor.rootPath,
            pendingDirsJson: ScanStateCodec.encodePendingDirs(cursor.pendingDirs),
            currentDirJson: Value(ScanStateCodec.encodeCurrentDir(cursor.currentDir)),
            currentPageToken: Value(cursor.currentPageToken),
            stageId: cursor.stage.name,
            scannedDirs: Value(cursor.scannedDirs),
            scannedFiles: Value(cursor.scannedFiles),
            foundTracks: Value(cursor.foundTracks),
            totalBytes: Value(cursor.totalBytes),
            failedDirs: Value(cursor.failedDirs),
            lastError: Value(cursor.lastError),
            updatedAt: cursor.updatedAt,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> clearScanCursor(DriveProvider provider) async {
    await (_db.delete(_db.scanStates)
          ..where((s) => s.providerId.equals(provider.id)))
        .go();
  }

  // -------------------------------------------------------------------
  // 账号
  // -------------------------------------------------------------------

  @override
  Future<void> saveAccount(CloudAccount account, {DateTime? scannedAt}) async {
    await _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            providerId: account.provider.id,
            authModeId: account.authMode.id,
            userId: Value(account.userId),
            displayName: Value(account.displayName),
            avatarUrl: Value(account.avatarUrl),
            authorizedAt: account.authorizedAt,
            expiresAt: Value(account.expiresAt),
            storageUsedBytes: Value(account.storageUsedBytes),
            storageTotalBytes: Value(account.storageTotalBytes),
            memberLabel: Value(account.memberLabel),
            lastScannedAt: Value(scannedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<CloudAccount>> accounts() async {
    final rows = await _db.select(_db.accounts).get();
    final out = <CloudAccount>[];
    for (final r in rows) {
      final provider = DriveProvider.fromId(r.providerId);
      if (provider == null) continue;
      out.add(CloudAccount(
        provider: provider,
        authMode: AuthMode.fromId(r.authModeId) ?? AuthMode.manualCookie,
        authorizedAt: r.authorizedAt,
        userId: r.userId,
        displayName: r.displayName,
        avatarUrl: r.avatarUrl,
        expiresAt: r.expiresAt,
        storageUsedBytes: r.storageUsedBytes,
        storageTotalBytes: r.storageTotalBytes,
        memberLabel: r.memberLabel,
      ));
    }
    return out;
  }

  @override
  Future<void> removeAccount(DriveProvider provider) async {
    await (_db.delete(_db.accounts)
          ..where((a) => a.providerId.equals(provider.id)))
        .go();
  }

  // -------------------------------------------------------------------
  // 播放统计
  // -------------------------------------------------------------------

  @override
  Future<void> recordPlay(
    String trackId, {
    Duration played = Duration.zero,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    await _db.transaction(() async {
      await _db.customStatement(
        'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? '
        'WHERE id = ?',
        [ts.millisecondsSinceEpoch ~/ 1000, trackId],
      );
      await _db.into(_db.playHistory).insert(PlayHistoryCompanion.insert(
            trackId: trackId,
            playedAt: ts,
            playedSeconds: Value(played.inSeconds),
          ));
    });
  }

  @override
  Future<List<Track>> recentlyPlayed({int limit = 50}) async {
    final rows = await _db.customSelect(
      'SELECT t.* FROM tracks t '
      'INNER JOIN ('
      '  SELECT track_id, MAX(played_at) AS last_at FROM play_history '
      '  GROUP BY track_id ORDER BY last_at DESC LIMIT ?'
      ') h ON h.track_id = t.id '
      'ORDER BY h.last_at DESC',
      variables: [Variable.withInt(limit)],
      readsFrom: {_db.tracks, _db.playHistory},
    ).get();
    return rows.map(_rowToTrack).toList();
  }

  @override
  Future<Map<String, ShuffleCandidate>> shuffleCandidates({
    DriveProvider? provider,
    bool playableOnly = true,
  }) async {
    final where = <String>[];
    final vars = <Variable<Object>>[];
    if (provider != null) {
      where.add('provider_id = ?');
      vars.add(Variable.withString(provider.id));
    }
    if (playableOnly) where.add('is_playable = 1');

    final sql = StringBuffer(
      'SELECT id, play_count, last_played_at FROM tracks',
    );
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');

    final rows = await _db
        .customSelect(sql.toString(), variables: vars, readsFrom: {_db.tracks})
        .get();

    return {
      for (final r in rows)
        r.read<String>('id'): ShuffleCandidate(
          id: r.read<String>('id'),
          playCount: r.read<int>('play_count'),
          lastPlayedAt: _readDateTime(r, 'last_played_at'),
        ),
    };
  }

  // -------------------------------------------------------------------
  // 统计
  // -------------------------------------------------------------------

  @override
  Future<LibraryStats> stats({DriveProvider? provider}) async {
    final where = provider == null ? '' : ' WHERE provider_id = ?';
    final vars = provider == null
        ? const <Variable<Object>>[]
        : <Variable<Object>>[Variable.withString(provider.id)];

    final row = await _db.customSelect(
      '''
SELECT
  COUNT(*) AS track_count,
  COALESCE(SUM(CASE WHEN playability_state = 'playable' THEN 1 ELSE 0 END), 0) AS playable_count,
  COALESCE(SUM(CASE WHEN is_playable = 1 THEN 1 ELSE 0 END), 0) AS attemptable_count,
  COALESCE(SUM(CASE WHEN playability_state = 'overLimit' THEN 1 ELSE 0 END), 0) AS over_limit,
  COALESCE(SUM(CASE WHEN playability_state = 'unknownSize' THEN 1 ELSE 0 END), 0) AS unknown_size,
  COALESCE(SUM(COALESCE(size_bytes, 0)), 0) AS total_bytes,
  COALESCE(SUM(CASE WHEN is_playable = 1 THEN COALESCE(size_bytes, 0) ELSE 0 END), 0) AS playable_bytes,
  COUNT(DISTINCT CASE WHEN artist IS NOT NULL AND artist != '' THEN artist END) AS artist_count,
  COUNT(DISTINCT CASE WHEN album IS NOT NULL AND album != '' THEN album END) AS album_count
FROM tracks$where
''',
      variables: vars,
      readsFrom: {_db.tracks},
    ).getSingle();

    DateTime? lastScannedAt;
    if (provider != null) {
      final acc = await (_db.select(_db.accounts)
            ..where((a) => a.providerId.equals(provider.id))
            ..limit(1))
          .getSingleOrNull();
      lastScannedAt = acc?.lastScannedAt;
    }

    return LibraryStats(
      trackCount: row.read<int>('track_count'),
      playableCount: row.read<int>('playable_count'),
      attemptableCount: row.read<int>('attemptable_count'),
      overLimitCount: row.read<int>('over_limit'),
      unknownSizeCount: row.read<int>('unknown_size'),
      favoriteCount: await favoriteCount(),
      totalBytes: row.read<int>('total_bytes'),
      playableBytes: row.read<int>('playable_bytes'),
      artistCount: row.read<int>('artist_count'),
      albumCount: row.read<int>('album_count'),
      lastScannedAt: lastScannedAt,
    );
  }

  @override
  Future<PlayabilitySummary> playabilitySummary({DriveProvider? provider}) async {
    final where = provider == null ? '' : ' WHERE provider_id = ?';
    final vars = provider == null
        ? const <Variable<Object>>[]
        : <Variable<Object>>[Variable.withString(provider.id)];

    final row = await _db.customSelect(
      '''
SELECT
  COALESCE(SUM(CASE WHEN playability_state = 'playable' THEN 1 ELSE 0 END), 0) AS playable,
  COALESCE(SUM(CASE WHEN playability_state = 'overLimit' THEN 1 ELSE 0 END), 0) AS over_limit,
  COALESCE(SUM(CASE WHEN playability_state = 'unknownSize' THEN 1 ELSE 0 END), 0) AS unknown_size,
  COALESCE(SUM(CASE WHEN playability_state = 'notAudio' THEN 1 ELSE 0 END), 0) AS not_audio,
  COALESCE(SUM(CASE WHEN playability_state = 'unsupportedByProvider' THEN 1 ELSE 0 END), 0) AS unsupported,
  COALESCE(SUM(CASE WHEN is_playable = 1 THEN COALESCE(size_bytes, 0) ELSE 0 END), 0) AS playable_bytes,
  COALESCE(SUM(COALESCE(size_bytes, 0)), 0) AS total_bytes
FROM tracks$where
''',
      variables: vars,
      readsFrom: {_db.tracks},
    ).getSingle();

    return PlayabilitySummary(
      playable: row.read<int>('playable'),
      overLimit: row.read<int>('over_limit'),
      unknownSize: row.read<int>('unknown_size'),
      notAudio: row.read<int>('not_audio'),
      unsupported: row.read<int>('unsupported'),
      playableBytes: row.read<int>('playable_bytes'),
      totalBytes: row.read<int>('total_bytes'),
    );
  }

  // -------------------------------------------------------------------
  // 行 → 领域对象
  // -------------------------------------------------------------------

  Track _rowToTrack(QueryRow row) => Track(
        provider: DriveProvider.fromId(row.read<String>('provider_id')) ??
            DriveProvider.quark,
        remoteId: row.read<String>('remote_id'),
        name: row.read<String>('name'),
        parentId: row.readNullable<String>('parent_id'),
        path: row.readNullable<String>('path'),
        sizeBytes: row.readNullable<int>('size_bytes'),
        mimeType: row.readNullable<String>('mime_type'),
        modifiedAt: _readDateTime(row, 'modified_at'),
        title: row.readNullable<String>('title'),
        artist: row.readNullable<String>('artist'),
        album: row.readNullable<String>('album'),
        durationMs: row.readNullable<int>('duration_ms'),
        cueTrackNo: row.readNullable<int>('cue_track_no'),
        cueStartMs: row.readNullable<int>('cue_start_ms'),
        firstSeenAt: _readDateTime(row, 'first_seen_at'),
      );

  /// 行 → 歌词。
  ///
  /// `source_id` 认不出来时**丢弃整行**（返回 `null`）而不是退回本地：
  /// 一个认不出的来源意味着这行是老版本写的、语义未知，当成「没有歌词」
  /// 至少是安全的；当成「本地歌词」会让它去读一个不存在的文件。
  Lyrics? _rowToLyrics(QueryRow row) {
    final provider = DriveProvider.fromId(row.read<String>('provider_id'));
    final source = LyricsSource.fromId(row.read<String>('source_id'));
    if (provider == null || source == null) return null;
    return Lyrics(
      trackId: row.read<String>('track_id'),
      provider: provider,
      source: source,
      content: row.readNullable<String>('content'),
      fileId: row.readNullable<String>('file_id'),
      fileName: row.readNullable<String>('file_name'),
      sizeBytes: row.readNullable<int>('size_bytes'),
      instrumental: row.read<bool>('instrumental'),
    );
  }

  /// 兼容 Drift 的 DateTime 列与原始 int 秒。
  static DateTime? _readDateTime(QueryRow row, String column) {
    final v = row.data[column];
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static Variable<Object> _nullableString(String? v) => v == null
      ? const Variable<Object>(null)
      : Variable.withString(v);

  static Variable<Object> _nullableInt(int? v) => v == null
      ? const Variable<Object>(null)
      : Variable.withInt(v);

  static Variable<Object> _nullableDateTime(DateTime? v) => v == null
      ? const Variable<Object>(null)
      : Variable.withDateTime(v);

  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }
}
