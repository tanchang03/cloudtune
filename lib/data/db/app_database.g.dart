// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, TrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cueTrackNoMeta = const VerificationMeta(
    'cueTrackNo',
  );
  @override
  late final GeneratedColumn<int> cueTrackNo = GeneratedColumn<int>(
    'cue_track_no',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cueStartMsMeta = const VerificationMeta(
    'cueStartMs',
  );
  @override
  late final GeneratedColumn<int> cueStartMs = GeneratedColumn<int>(
    'cue_start_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPlayableMeta = const VerificationMeta(
    'isPlayable',
  );
  @override
  late final GeneratedColumn<bool> isPlayable = GeneratedColumn<bool>(
    'is_playable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_playable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _playabilityStateMeta = const VerificationMeta(
    'playabilityState',
  );
  @override
  late final GeneratedColumn<String> playabilityState = GeneratedColumn<String>(
    'playability_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('playable'),
  );
  static const VerificationMeta _playabilityNoteMeta = const VerificationMeta(
    'playabilityNote',
  );
  @override
  late final GeneratedColumn<String> playabilityNote = GeneratedColumn<String>(
    'playability_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _indexedAtMeta = const VerificationMeta(
    'indexedAt',
  );
  @override
  late final GeneratedColumn<DateTime> indexedAt = GeneratedColumn<DateTime>(
    'indexed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    providerId,
    remoteId,
    name,
    parentId,
    path,
    sizeBytes,
    mimeType,
    modifiedAt,
    title,
    artist,
    album,
    durationMs,
    cueTrackNo,
    cueStartMs,
    isPlayable,
    playabilityState,
    playabilityNote,
    playCount,
    lastPlayedAt,
    indexedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('cue_track_no')) {
      context.handle(
        _cueTrackNoMeta,
        cueTrackNo.isAcceptableOrUnknown(
          data['cue_track_no']!,
          _cueTrackNoMeta,
        ),
      );
    }
    if (data.containsKey('cue_start_ms')) {
      context.handle(
        _cueStartMsMeta,
        cueStartMs.isAcceptableOrUnknown(
          data['cue_start_ms']!,
          _cueStartMsMeta,
        ),
      );
    }
    if (data.containsKey('is_playable')) {
      context.handle(
        _isPlayableMeta,
        isPlayable.isAcceptableOrUnknown(data['is_playable']!, _isPlayableMeta),
      );
    }
    if (data.containsKey('playability_state')) {
      context.handle(
        _playabilityStateMeta,
        playabilityState.isAcceptableOrUnknown(
          data['playability_state']!,
          _playabilityStateMeta,
        ),
      );
    }
    if (data.containsKey('playability_note')) {
      context.handle(
        _playabilityNoteMeta,
        playabilityNote.isAcceptableOrUnknown(
          data['playability_note']!,
          _playabilityNoteMeta,
        ),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('indexed_at')) {
      context.handle(
        _indexedAtMeta,
        indexedAt.isAcceptableOrUnknown(data['indexed_at']!, _indexedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_indexedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      providerId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}provider_id'],
          )!,
      remoteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}remote_id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      cueTrackNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cue_track_no'],
      ),
      cueStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cue_start_ms'],
      ),
      isPlayable:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_playable'],
          )!,
      playabilityState:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}playability_state'],
          )!,
      playabilityNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playability_note'],
      ),
      playCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}play_count'],
          )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      ),
      indexedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}indexed_at'],
          )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class TrackRow extends DataClass implements Insertable<TrackRow> {
  /// 形如 `quark:8f3a...`
  final String id;

  /// 网盘标识（`DriveProvider.id`）
  final String providerId;

  /// 网盘侧文件 ID
  final String remoteId;

  /// 原始文件名（含扩展名）
  final String name;

  /// 父目录 ID
  final String? parentId;

  /// 所在目录展示路径，如 `/音乐/华语/`
  final String? path;
  final int? sizeBytes;
  final String? mimeType;
  final DateTime? modifiedAt;

  /// 元数据标题（扫描时由文件名解析，将来可由标签读取覆盖）
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// CUE 里的音轨号（1 起）。非空表示这条曲目由 CUE 参与确定。
  ///
  /// 冗余存一份而不是从 `id` 的后缀解析：`id` 的后缀规则只对整轨分段生效，
  /// 分轨增强的曲目没有后缀却也需要轨号（界面要显示「第 3 轨」、
  /// 分组头要显示「CUE 分轨」）。解析字符串当数据用，迟早会踩到。
  final int? cueTrackNo;

  /// 在整轨文件内的起点（毫秒）。只有整轨切出来的一段才有值。
  ///
  /// 播放引擎靠它 `seek` 到本轨起点、并在 `起点 + durationMs` 处切歌。
  /// 不单独存终点：终点恒等于「起点 + 时长」，多存一列只会多一个
  /// 可能自相矛盾的字段。
  final int? cueStartMs;

  /// **冗余存储的可播性快照**。
  ///
  /// 本可由 `sizeBytes` 与网盘能力实时算出，但冗余一份能让
  /// 「只列可播曲目」这类查询走索引而不是全表扫描。
  /// 代价：网盘能力变化（例如 50MB 上限被取消）时必须**重新扫描**来刷新。
  final bool isPlayable;

  /// `PlayabilityState.name`。
  ///
  /// 单独存一份是为了让统计能区分「明确超限」与「体积未知（乐观可播）」——
  /// 只靠 `isPlayable` 布尔会把两者混为一谈，而它们对用户的含义完全不同。
  final String playabilityState;

  /// 超出体积上限的具体原因（面向用户，可直接展示）
  final String? playabilityNote;

  /// 历史播放次数 —— 随机播放「少听优先」加权的依据
  final int playCount;
  final DateTime? lastPlayedAt;

  /// 本条记录被索引的时间
  final DateTime indexedAt;
  const TrackRow({
    required this.id,
    required this.providerId,
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
    required this.isPlayable,
    required this.playabilityState,
    this.playabilityNote,
    required this.playCount,
    this.lastPlayedAt,
    required this.indexedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['provider_id'] = Variable<String>(providerId);
    map['remote_id'] = Variable<String>(remoteId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(modifiedAt);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || cueTrackNo != null) {
      map['cue_track_no'] = Variable<int>(cueTrackNo);
    }
    if (!nullToAbsent || cueStartMs != null) {
      map['cue_start_ms'] = Variable<int>(cueStartMs);
    }
    map['is_playable'] = Variable<bool>(isPlayable);
    map['playability_state'] = Variable<String>(playabilityState);
    if (!nullToAbsent || playabilityNote != null) {
      map['playability_note'] = Variable<String>(playabilityNote);
    }
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    map['indexed_at'] = Variable<DateTime>(indexedAt);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      providerId: Value(providerId),
      remoteId: Value(remoteId),
      name: Value(name),
      parentId:
          parentId == null && nullToAbsent
              ? const Value.absent()
              : Value(parentId),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      sizeBytes:
          sizeBytes == null && nullToAbsent
              ? const Value.absent()
              : Value(sizeBytes),
      mimeType:
          mimeType == null && nullToAbsent
              ? const Value.absent()
              : Value(mimeType),
      modifiedAt:
          modifiedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(modifiedAt),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      artist:
          artist == null && nullToAbsent ? const Value.absent() : Value(artist),
      album:
          album == null && nullToAbsent ? const Value.absent() : Value(album),
      durationMs:
          durationMs == null && nullToAbsent
              ? const Value.absent()
              : Value(durationMs),
      cueTrackNo:
          cueTrackNo == null && nullToAbsent
              ? const Value.absent()
              : Value(cueTrackNo),
      cueStartMs:
          cueStartMs == null && nullToAbsent
              ? const Value.absent()
              : Value(cueStartMs),
      isPlayable: Value(isPlayable),
      playabilityState: Value(playabilityState),
      playabilityNote:
          playabilityNote == null && nullToAbsent
              ? const Value.absent()
              : Value(playabilityNote),
      playCount: Value(playCount),
      lastPlayedAt:
          lastPlayedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(lastPlayedAt),
      indexedAt: Value(indexedAt),
    );
  }

  factory TrackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackRow(
      id: serializer.fromJson<String>(json['id']),
      providerId: serializer.fromJson<String>(json['providerId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      path: serializer.fromJson<String?>(json['path']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      modifiedAt: serializer.fromJson<DateTime?>(json['modifiedAt']),
      title: serializer.fromJson<String?>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      cueTrackNo: serializer.fromJson<int?>(json['cueTrackNo']),
      cueStartMs: serializer.fromJson<int?>(json['cueStartMs']),
      isPlayable: serializer.fromJson<bool>(json['isPlayable']),
      playabilityState: serializer.fromJson<String>(json['playabilityState']),
      playabilityNote: serializer.fromJson<String?>(json['playabilityNote']),
      playCount: serializer.fromJson<int>(json['playCount']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
      indexedAt: serializer.fromJson<DateTime>(json['indexedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'providerId': serializer.toJson<String>(providerId),
      'remoteId': serializer.toJson<String>(remoteId),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'path': serializer.toJson<String?>(path),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'mimeType': serializer.toJson<String?>(mimeType),
      'modifiedAt': serializer.toJson<DateTime?>(modifiedAt),
      'title': serializer.toJson<String?>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int?>(durationMs),
      'cueTrackNo': serializer.toJson<int?>(cueTrackNo),
      'cueStartMs': serializer.toJson<int?>(cueStartMs),
      'isPlayable': serializer.toJson<bool>(isPlayable),
      'playabilityState': serializer.toJson<String>(playabilityState),
      'playabilityNote': serializer.toJson<String?>(playabilityNote),
      'playCount': serializer.toJson<int>(playCount),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
      'indexedAt': serializer.toJson<DateTime>(indexedAt),
    };
  }

  TrackRow copyWith({
    String? id,
    String? providerId,
    String? remoteId,
    String? name,
    Value<String?> parentId = const Value.absent(),
    Value<String?> path = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<DateTime?> modifiedAt = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<int?> cueTrackNo = const Value.absent(),
    Value<int?> cueStartMs = const Value.absent(),
    bool? isPlayable,
    String? playabilityState,
    Value<String?> playabilityNote = const Value.absent(),
    int? playCount,
    Value<DateTime?> lastPlayedAt = const Value.absent(),
    DateTime? indexedAt,
  }) => TrackRow(
    id: id ?? this.id,
    providerId: providerId ?? this.providerId,
    remoteId: remoteId ?? this.remoteId,
    name: name ?? this.name,
    parentId: parentId.present ? parentId.value : this.parentId,
    path: path.present ? path.value : this.path,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
    title: title.present ? title.value : this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    cueTrackNo: cueTrackNo.present ? cueTrackNo.value : this.cueTrackNo,
    cueStartMs: cueStartMs.present ? cueStartMs.value : this.cueStartMs,
    isPlayable: isPlayable ?? this.isPlayable,
    playabilityState: playabilityState ?? this.playabilityState,
    playabilityNote:
        playabilityNote.present ? playabilityNote.value : this.playabilityNote,
    playCount: playCount ?? this.playCount,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    indexedAt: indexedAt ?? this.indexedAt,
  );
  TrackRow copyWithCompanion(TracksCompanion data) {
    return TrackRow(
      id: data.id.present ? data.id.value : this.id,
      providerId:
          data.providerId.present ? data.providerId.value : this.providerId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      path: data.path.present ? data.path.value : this.path,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      cueTrackNo:
          data.cueTrackNo.present ? data.cueTrackNo.value : this.cueTrackNo,
      cueStartMs:
          data.cueStartMs.present ? data.cueStartMs.value : this.cueStartMs,
      isPlayable:
          data.isPlayable.present ? data.isPlayable.value : this.isPlayable,
      playabilityState:
          data.playabilityState.present
              ? data.playabilityState.value
              : this.playabilityState,
      playabilityNote:
          data.playabilityNote.present
              ? data.playabilityNote.value
              : this.playabilityNote,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      lastPlayedAt:
          data.lastPlayedAt.present
              ? data.lastPlayedAt.value
              : this.lastPlayedAt,
      indexedAt: data.indexedAt.present ? data.indexedAt.value : this.indexedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('remoteId: $remoteId, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('cueTrackNo: $cueTrackNo, ')
          ..write('cueStartMs: $cueStartMs, ')
          ..write('isPlayable: $isPlayable, ')
          ..write('playabilityState: $playabilityState, ')
          ..write('playabilityNote: $playabilityNote, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('indexedAt: $indexedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    providerId,
    remoteId,
    name,
    parentId,
    path,
    sizeBytes,
    mimeType,
    modifiedAt,
    title,
    artist,
    album,
    durationMs,
    cueTrackNo,
    cueStartMs,
    isPlayable,
    playabilityState,
    playabilityNote,
    playCount,
    lastPlayedAt,
    indexedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.id == this.id &&
          other.providerId == this.providerId &&
          other.remoteId == this.remoteId &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.path == this.path &&
          other.sizeBytes == this.sizeBytes &&
          other.mimeType == this.mimeType &&
          other.modifiedAt == this.modifiedAt &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.cueTrackNo == this.cueTrackNo &&
          other.cueStartMs == this.cueStartMs &&
          other.isPlayable == this.isPlayable &&
          other.playabilityState == this.playabilityState &&
          other.playabilityNote == this.playabilityNote &&
          other.playCount == this.playCount &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.indexedAt == this.indexedAt);
}

class TracksCompanion extends UpdateCompanion<TrackRow> {
  final Value<String> id;
  final Value<String> providerId;
  final Value<String> remoteId;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<String?> path;
  final Value<int?> sizeBytes;
  final Value<String?> mimeType;
  final Value<DateTime?> modifiedAt;
  final Value<String?> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<int?> durationMs;
  final Value<int?> cueTrackNo;
  final Value<int?> cueStartMs;
  final Value<bool> isPlayable;
  final Value<String> playabilityState;
  final Value<String?> playabilityNote;
  final Value<int> playCount;
  final Value<DateTime?> lastPlayedAt;
  final Value<DateTime> indexedAt;
  final Value<int> rowid;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.providerId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.path = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.cueTrackNo = const Value.absent(),
    this.cueStartMs = const Value.absent(),
    this.isPlayable = const Value.absent(),
    this.playabilityState = const Value.absent(),
    this.playabilityNote = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.indexedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String id,
    required String providerId,
    required String remoteId,
    required String name,
    this.parentId = const Value.absent(),
    this.path = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.cueTrackNo = const Value.absent(),
    this.cueStartMs = const Value.absent(),
    this.isPlayable = const Value.absent(),
    this.playabilityState = const Value.absent(),
    this.playabilityNote = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    required DateTime indexedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       providerId = Value(providerId),
       remoteId = Value(remoteId),
       name = Value(name),
       indexedAt = Value(indexedAt);
  static Insertable<TrackRow> custom({
    Expression<String>? id,
    Expression<String>? providerId,
    Expression<String>? remoteId,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<String>? path,
    Expression<int>? sizeBytes,
    Expression<String>? mimeType,
    Expression<DateTime>? modifiedAt,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<int>? cueTrackNo,
    Expression<int>? cueStartMs,
    Expression<bool>? isPlayable,
    Expression<String>? playabilityState,
    Expression<String>? playabilityNote,
    Expression<int>? playCount,
    Expression<DateTime>? lastPlayedAt,
    Expression<DateTime>? indexedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (providerId != null) 'provider_id': providerId,
      if (remoteId != null) 'remote_id': remoteId,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (path != null) 'path': path,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (mimeType != null) 'mime_type': mimeType,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (cueTrackNo != null) 'cue_track_no': cueTrackNo,
      if (cueStartMs != null) 'cue_start_ms': cueStartMs,
      if (isPlayable != null) 'is_playable': isPlayable,
      if (playabilityState != null) 'playability_state': playabilityState,
      if (playabilityNote != null) 'playability_note': playabilityNote,
      if (playCount != null) 'play_count': playCount,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (indexedAt != null) 'indexed_at': indexedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? id,
    Value<String>? providerId,
    Value<String>? remoteId,
    Value<String>? name,
    Value<String?>? parentId,
    Value<String?>? path,
    Value<int?>? sizeBytes,
    Value<String?>? mimeType,
    Value<DateTime?>? modifiedAt,
    Value<String?>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<int?>? durationMs,
    Value<int?>? cueTrackNo,
    Value<int?>? cueStartMs,
    Value<bool>? isPlayable,
    Value<String>? playabilityState,
    Value<String?>? playabilityNote,
    Value<int>? playCount,
    Value<DateTime?>? lastPlayedAt,
    Value<DateTime>? indexedAt,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      remoteId: remoteId ?? this.remoteId,
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
      isPlayable: isPlayable ?? this.isPlayable,
      playabilityState: playabilityState ?? this.playabilityState,
      playabilityNote: playabilityNote ?? this.playabilityNote,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      indexedAt: indexedAt ?? this.indexedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (cueTrackNo.present) {
      map['cue_track_no'] = Variable<int>(cueTrackNo.value);
    }
    if (cueStartMs.present) {
      map['cue_start_ms'] = Variable<int>(cueStartMs.value);
    }
    if (isPlayable.present) {
      map['is_playable'] = Variable<bool>(isPlayable.value);
    }
    if (playabilityState.present) {
      map['playability_state'] = Variable<String>(playabilityState.value);
    }
    if (playabilityNote.present) {
      map['playability_note'] = Variable<String>(playabilityNote.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (indexedAt.present) {
      map['indexed_at'] = Variable<DateTime>(indexedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('remoteId: $remoteId, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('cueTrackNo: $cueTrackNo, ')
          ..write('cueStartMs: $cueStartMs, ')
          ..write('isPlayable: $isPlayable, ')
          ..write('playabilityState: $playabilityState, ')
          ..write('playabilityNote: $playabilityNote, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('indexedAt: $indexedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts
    with TableInfo<$AccountsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authModeIdMeta = const VerificationMeta(
    'authModeId',
  );
  @override
  late final GeneratedColumn<String> authModeId = GeneratedColumn<String>(
    'auth_mode_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorizedAtMeta = const VerificationMeta(
    'authorizedAt',
  );
  @override
  late final GeneratedColumn<DateTime> authorizedAt = GeneratedColumn<DateTime>(
    'authorized_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageUsedBytesMeta = const VerificationMeta(
    'storageUsedBytes',
  );
  @override
  late final GeneratedColumn<int> storageUsedBytes = GeneratedColumn<int>(
    'storage_used_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageTotalBytesMeta = const VerificationMeta(
    'storageTotalBytes',
  );
  @override
  late final GeneratedColumn<int> storageTotalBytes = GeneratedColumn<int>(
    'storage_total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberLabelMeta = const VerificationMeta(
    'memberLabel',
  );
  @override
  late final GeneratedColumn<String> memberLabel = GeneratedColumn<String>(
    'member_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastScannedAtMeta = const VerificationMeta(
    'lastScannedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScannedAt =
      GeneratedColumn<DateTime>(
        'last_scanned_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    providerId,
    authModeId,
    userId,
    displayName,
    avatarUrl,
    authorizedAt,
    expiresAt,
    storageUsedBytes,
    storageTotalBytes,
    memberLabel,
    lastScannedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('auth_mode_id')) {
      context.handle(
        _authModeIdMeta,
        authModeId.isAcceptableOrUnknown(
          data['auth_mode_id']!,
          _authModeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authModeIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('authorized_at')) {
      context.handle(
        _authorizedAtMeta,
        authorizedAt.isAcceptableOrUnknown(
          data['authorized_at']!,
          _authorizedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorizedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('storage_used_bytes')) {
      context.handle(
        _storageUsedBytesMeta,
        storageUsedBytes.isAcceptableOrUnknown(
          data['storage_used_bytes']!,
          _storageUsedBytesMeta,
        ),
      );
    }
    if (data.containsKey('storage_total_bytes')) {
      context.handle(
        _storageTotalBytesMeta,
        storageTotalBytes.isAcceptableOrUnknown(
          data['storage_total_bytes']!,
          _storageTotalBytesMeta,
        ),
      );
    }
    if (data.containsKey('member_label')) {
      context.handle(
        _memberLabelMeta,
        memberLabel.isAcceptableOrUnknown(
          data['member_label']!,
          _memberLabelMeta,
        ),
      );
    }
    if (data.containsKey('last_scanned_at')) {
      context.handle(
        _lastScannedAtMeta,
        lastScannedAt.isAcceptableOrUnknown(
          data['last_scanned_at']!,
          _lastScannedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {providerId};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      providerId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}provider_id'],
          )!,
      authModeId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}auth_mode_id'],
          )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      authorizedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}authorized_at'],
          )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      storageUsedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}storage_used_bytes'],
      ),
      storageTotalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}storage_total_bytes'],
      ),
      memberLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_label'],
      ),
      lastScannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scanned_at'],
      ),
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String providerId;

  /// `AuthMode.id`
  final String authModeId;
  final String? userId;
  final String? displayName;
  final String? avatarUrl;
  final DateTime authorizedAt;
  final DateTime? expiresAt;
  final int? storageUsedBytes;
  final int? storageTotalBytes;

  /// 会员标识，如 `SUPER_VIP`
  final String? memberLabel;

  /// 最近一次扫描完成时间
  final DateTime? lastScannedAt;
  const AccountRow({
    required this.providerId,
    required this.authModeId,
    this.userId,
    this.displayName,
    this.avatarUrl,
    required this.authorizedAt,
    this.expiresAt,
    this.storageUsedBytes,
    this.storageTotalBytes,
    this.memberLabel,
    this.lastScannedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider_id'] = Variable<String>(providerId);
    map['auth_mode_id'] = Variable<String>(authModeId);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['authorized_at'] = Variable<DateTime>(authorizedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || storageUsedBytes != null) {
      map['storage_used_bytes'] = Variable<int>(storageUsedBytes);
    }
    if (!nullToAbsent || storageTotalBytes != null) {
      map['storage_total_bytes'] = Variable<int>(storageTotalBytes);
    }
    if (!nullToAbsent || memberLabel != null) {
      map['member_label'] = Variable<String>(memberLabel);
    }
    if (!nullToAbsent || lastScannedAt != null) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt);
    }
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      providerId: Value(providerId),
      authModeId: Value(authModeId),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      displayName:
          displayName == null && nullToAbsent
              ? const Value.absent()
              : Value(displayName),
      avatarUrl:
          avatarUrl == null && nullToAbsent
              ? const Value.absent()
              : Value(avatarUrl),
      authorizedAt: Value(authorizedAt),
      expiresAt:
          expiresAt == null && nullToAbsent
              ? const Value.absent()
              : Value(expiresAt),
      storageUsedBytes:
          storageUsedBytes == null && nullToAbsent
              ? const Value.absent()
              : Value(storageUsedBytes),
      storageTotalBytes:
          storageTotalBytes == null && nullToAbsent
              ? const Value.absent()
              : Value(storageTotalBytes),
      memberLabel:
          memberLabel == null && nullToAbsent
              ? const Value.absent()
              : Value(memberLabel),
      lastScannedAt:
          lastScannedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(lastScannedAt),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      providerId: serializer.fromJson<String>(json['providerId']),
      authModeId: serializer.fromJson<String>(json['authModeId']),
      userId: serializer.fromJson<String?>(json['userId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      authorizedAt: serializer.fromJson<DateTime>(json['authorizedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      storageUsedBytes: serializer.fromJson<int?>(json['storageUsedBytes']),
      storageTotalBytes: serializer.fromJson<int?>(json['storageTotalBytes']),
      memberLabel: serializer.fromJson<String?>(json['memberLabel']),
      lastScannedAt: serializer.fromJson<DateTime?>(json['lastScannedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'providerId': serializer.toJson<String>(providerId),
      'authModeId': serializer.toJson<String>(authModeId),
      'userId': serializer.toJson<String?>(userId),
      'displayName': serializer.toJson<String?>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'authorizedAt': serializer.toJson<DateTime>(authorizedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'storageUsedBytes': serializer.toJson<int?>(storageUsedBytes),
      'storageTotalBytes': serializer.toJson<int?>(storageTotalBytes),
      'memberLabel': serializer.toJson<String?>(memberLabel),
      'lastScannedAt': serializer.toJson<DateTime?>(lastScannedAt),
    };
  }

  AccountRow copyWith({
    String? providerId,
    String? authModeId,
    Value<String?> userId = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    DateTime? authorizedAt,
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<int?> storageUsedBytes = const Value.absent(),
    Value<int?> storageTotalBytes = const Value.absent(),
    Value<String?> memberLabel = const Value.absent(),
    Value<DateTime?> lastScannedAt = const Value.absent(),
  }) => AccountRow(
    providerId: providerId ?? this.providerId,
    authModeId: authModeId ?? this.authModeId,
    userId: userId.present ? userId.value : this.userId,
    displayName: displayName.present ? displayName.value : this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    authorizedAt: authorizedAt ?? this.authorizedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    storageUsedBytes:
        storageUsedBytes.present
            ? storageUsedBytes.value
            : this.storageUsedBytes,
    storageTotalBytes:
        storageTotalBytes.present
            ? storageTotalBytes.value
            : this.storageTotalBytes,
    memberLabel: memberLabel.present ? memberLabel.value : this.memberLabel,
    lastScannedAt:
        lastScannedAt.present ? lastScannedAt.value : this.lastScannedAt,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      providerId:
          data.providerId.present ? data.providerId.value : this.providerId,
      authModeId:
          data.authModeId.present ? data.authModeId.value : this.authModeId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      authorizedAt:
          data.authorizedAt.present
              ? data.authorizedAt.value
              : this.authorizedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      storageUsedBytes:
          data.storageUsedBytes.present
              ? data.storageUsedBytes.value
              : this.storageUsedBytes,
      storageTotalBytes:
          data.storageTotalBytes.present
              ? data.storageTotalBytes.value
              : this.storageTotalBytes,
      memberLabel:
          data.memberLabel.present ? data.memberLabel.value : this.memberLabel,
      lastScannedAt:
          data.lastScannedAt.present
              ? data.lastScannedAt.value
              : this.lastScannedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('providerId: $providerId, ')
          ..write('authModeId: $authModeId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('authorizedAt: $authorizedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('storageUsedBytes: $storageUsedBytes, ')
          ..write('storageTotalBytes: $storageTotalBytes, ')
          ..write('memberLabel: $memberLabel, ')
          ..write('lastScannedAt: $lastScannedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    authModeId,
    userId,
    displayName,
    avatarUrl,
    authorizedAt,
    expiresAt,
    storageUsedBytes,
    storageTotalBytes,
    memberLabel,
    lastScannedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.providerId == this.providerId &&
          other.authModeId == this.authModeId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.authorizedAt == this.authorizedAt &&
          other.expiresAt == this.expiresAt &&
          other.storageUsedBytes == this.storageUsedBytes &&
          other.storageTotalBytes == this.storageTotalBytes &&
          other.memberLabel == this.memberLabel &&
          other.lastScannedAt == this.lastScannedAt);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> providerId;
  final Value<String> authModeId;
  final Value<String?> userId;
  final Value<String?> displayName;
  final Value<String?> avatarUrl;
  final Value<DateTime> authorizedAt;
  final Value<DateTime?> expiresAt;
  final Value<int?> storageUsedBytes;
  final Value<int?> storageTotalBytes;
  final Value<String?> memberLabel;
  final Value<DateTime?> lastScannedAt;
  final Value<int> rowid;
  const AccountsCompanion({
    this.providerId = const Value.absent(),
    this.authModeId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.authorizedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.storageUsedBytes = const Value.absent(),
    this.storageTotalBytes = const Value.absent(),
    this.memberLabel = const Value.absent(),
    this.lastScannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String providerId,
    required String authModeId,
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    required DateTime authorizedAt,
    this.expiresAt = const Value.absent(),
    this.storageUsedBytes = const Value.absent(),
    this.storageTotalBytes = const Value.absent(),
    this.memberLabel = const Value.absent(),
    this.lastScannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : providerId = Value(providerId),
       authModeId = Value(authModeId),
       authorizedAt = Value(authorizedAt);
  static Insertable<AccountRow> custom({
    Expression<String>? providerId,
    Expression<String>? authModeId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<DateTime>? authorizedAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? storageUsedBytes,
    Expression<int>? storageTotalBytes,
    Expression<String>? memberLabel,
    Expression<DateTime>? lastScannedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (providerId != null) 'provider_id': providerId,
      if (authModeId != null) 'auth_mode_id': authModeId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (authorizedAt != null) 'authorized_at': authorizedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (storageUsedBytes != null) 'storage_used_bytes': storageUsedBytes,
      if (storageTotalBytes != null) 'storage_total_bytes': storageTotalBytes,
      if (memberLabel != null) 'member_label': memberLabel,
      if (lastScannedAt != null) 'last_scanned_at': lastScannedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? providerId,
    Value<String>? authModeId,
    Value<String?>? userId,
    Value<String?>? displayName,
    Value<String?>? avatarUrl,
    Value<DateTime>? authorizedAt,
    Value<DateTime?>? expiresAt,
    Value<int?>? storageUsedBytes,
    Value<int?>? storageTotalBytes,
    Value<String?>? memberLabel,
    Value<DateTime?>? lastScannedAt,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      providerId: providerId ?? this.providerId,
      authModeId: authModeId ?? this.authModeId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      authorizedAt: authorizedAt ?? this.authorizedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      storageUsedBytes: storageUsedBytes ?? this.storageUsedBytes,
      storageTotalBytes: storageTotalBytes ?? this.storageTotalBytes,
      memberLabel: memberLabel ?? this.memberLabel,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (authModeId.present) {
      map['auth_mode_id'] = Variable<String>(authModeId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (authorizedAt.present) {
      map['authorized_at'] = Variable<DateTime>(authorizedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (storageUsedBytes.present) {
      map['storage_used_bytes'] = Variable<int>(storageUsedBytes.value);
    }
    if (storageTotalBytes.present) {
      map['storage_total_bytes'] = Variable<int>(storageTotalBytes.value);
    }
    if (memberLabel.present) {
      map['member_label'] = Variable<String>(memberLabel.value);
    }
    if (lastScannedAt.present) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('providerId: $providerId, ')
          ..write('authModeId: $authModeId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('authorizedAt: $authorizedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('storageUsedBytes: $storageUsedBytes, ')
          ..write('storageTotalBytes: $storageTotalBytes, ')
          ..write('memberLabel: $memberLabel, ')
          ..write('lastScannedAt: $lastScannedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, FavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [trackId, createdAt, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  FavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRow(
      trackId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}track_id'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      sortOrder:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sort_order'],
          )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class FavoriteRow extends DataClass implements Insertable<FavoriteRow> {
  final String trackId;
  final DateTime createdAt;

  /// 用户手动排序位（越小越前）
  final int sortOrder;
  const FavoriteRow({
    required this.trackId,
    required this.createdAt,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<String>(trackId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      trackId: Value(trackId),
      createdAt: Value(createdAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory FavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRow(
      trackId: serializer.fromJson<String>(json['trackId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<String>(trackId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  FavoriteRow copyWith({
    String? trackId,
    DateTime? createdAt,
    int? sortOrder,
  }) => FavoriteRow(
    trackId: trackId ?? this.trackId,
    createdAt: createdAt ?? this.createdAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  FavoriteRow copyWithCompanion(FavoritesCompanion data) {
    return FavoriteRow(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRow(')
          ..write('trackId: $trackId, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(trackId, createdAt, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRow &&
          other.trackId == this.trackId &&
          other.createdAt == this.createdAt &&
          other.sortOrder == this.sortOrder);
}

class FavoritesCompanion extends UpdateCompanion<FavoriteRow> {
  final Value<String> trackId;
  final Value<DateTime> createdAt;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.trackId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String trackId,
    required DateTime createdAt,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       createdAt = Value(createdAt);
  static Insertable<FavoriteRow> custom({
    Expression<String>? trackId,
    Expression<DateTime>? createdAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (createdAt != null) 'created_at': createdAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? trackId,
    Value<DateTime>? createdAt,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      trackId: trackId ?? this.trackId,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('trackId: $trackId, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScanStatesTable extends ScanStates
    with TableInfo<$ScanStatesTable, ScanStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootIdMeta = const VerificationMeta('rootId');
  @override
  late final GeneratedColumn<String> rootId = GeneratedColumn<String>(
    'root_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootPathMeta = const VerificationMeta(
    'rootPath',
  );
  @override
  late final GeneratedColumn<String> rootPath = GeneratedColumn<String>(
    'root_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pendingDirsJsonMeta = const VerificationMeta(
    'pendingDirsJson',
  );
  @override
  late final GeneratedColumn<String> pendingDirsJson = GeneratedColumn<String>(
    'pending_dirs_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentDirJsonMeta = const VerificationMeta(
    'currentDirJson',
  );
  @override
  late final GeneratedColumn<String> currentDirJson = GeneratedColumn<String>(
    'current_dir_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentPageTokenMeta = const VerificationMeta(
    'currentPageToken',
  );
  @override
  late final GeneratedColumn<String> currentPageToken = GeneratedColumn<String>(
    'current_page_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stageIdMeta = const VerificationMeta(
    'stageId',
  );
  @override
  late final GeneratedColumn<String> stageId = GeneratedColumn<String>(
    'stage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scannedDirsMeta = const VerificationMeta(
    'scannedDirs',
  );
  @override
  late final GeneratedColumn<int> scannedDirs = GeneratedColumn<int>(
    'scanned_dirs',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scannedFilesMeta = const VerificationMeta(
    'scannedFiles',
  );
  @override
  late final GeneratedColumn<int> scannedFiles = GeneratedColumn<int>(
    'scanned_files',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _foundTracksMeta = const VerificationMeta(
    'foundTracks',
  );
  @override
  late final GeneratedColumn<int> foundTracks = GeneratedColumn<int>(
    'found_tracks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failedDirsMeta = const VerificationMeta(
    'failedDirs',
  );
  @override
  late final GeneratedColumn<int> failedDirs = GeneratedColumn<int>(
    'failed_dirs',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    providerId,
    rootId,
    rootPath,
    pendingDirsJson,
    currentDirJson,
    currentPageToken,
    stageId,
    scannedDirs,
    scannedFiles,
    foundTracks,
    totalBytes,
    failedDirs,
    lastError,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('root_id')) {
      context.handle(
        _rootIdMeta,
        rootId.isAcceptableOrUnknown(data['root_id']!, _rootIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rootIdMeta);
    }
    if (data.containsKey('root_path')) {
      context.handle(
        _rootPathMeta,
        rootPath.isAcceptableOrUnknown(data['root_path']!, _rootPathMeta),
      );
    } else if (isInserting) {
      context.missing(_rootPathMeta);
    }
    if (data.containsKey('pending_dirs_json')) {
      context.handle(
        _pendingDirsJsonMeta,
        pendingDirsJson.isAcceptableOrUnknown(
          data['pending_dirs_json']!,
          _pendingDirsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pendingDirsJsonMeta);
    }
    if (data.containsKey('current_dir_json')) {
      context.handle(
        _currentDirJsonMeta,
        currentDirJson.isAcceptableOrUnknown(
          data['current_dir_json']!,
          _currentDirJsonMeta,
        ),
      );
    }
    if (data.containsKey('current_page_token')) {
      context.handle(
        _currentPageTokenMeta,
        currentPageToken.isAcceptableOrUnknown(
          data['current_page_token']!,
          _currentPageTokenMeta,
        ),
      );
    }
    if (data.containsKey('stage_id')) {
      context.handle(
        _stageIdMeta,
        stageId.isAcceptableOrUnknown(data['stage_id']!, _stageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stageIdMeta);
    }
    if (data.containsKey('scanned_dirs')) {
      context.handle(
        _scannedDirsMeta,
        scannedDirs.isAcceptableOrUnknown(
          data['scanned_dirs']!,
          _scannedDirsMeta,
        ),
      );
    }
    if (data.containsKey('scanned_files')) {
      context.handle(
        _scannedFilesMeta,
        scannedFiles.isAcceptableOrUnknown(
          data['scanned_files']!,
          _scannedFilesMeta,
        ),
      );
    }
    if (data.containsKey('found_tracks')) {
      context.handle(
        _foundTracksMeta,
        foundTracks.isAcceptableOrUnknown(
          data['found_tracks']!,
          _foundTracksMeta,
        ),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('failed_dirs')) {
      context.handle(
        _failedDirsMeta,
        failedDirs.isAcceptableOrUnknown(data['failed_dirs']!, _failedDirsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {providerId};
  @override
  ScanStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanStateRow(
      providerId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}provider_id'],
          )!,
      rootId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}root_id'],
          )!,
      rootPath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}root_path'],
          )!,
      pendingDirsJson:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}pending_dirs_json'],
          )!,
      currentDirJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_dir_json'],
      ),
      currentPageToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_page_token'],
      ),
      stageId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}stage_id'],
          )!,
      scannedDirs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}scanned_dirs'],
          )!,
      scannedFiles:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}scanned_files'],
          )!,
      foundTracks:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}found_tracks'],
          )!,
      totalBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}total_bytes'],
          )!,
      failedDirs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}failed_dirs'],
          )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $ScanStatesTable createAlias(String alias) {
    return $ScanStatesTable(attachedDatabase, alias);
  }
}

class ScanStateRow extends DataClass implements Insertable<ScanStateRow> {
  final String providerId;
  final String rootId;
  final String rootPath;

  /// BFS 队列（JSON 数组，元素形如 `{"id":..,"path":..,"depth":..}`）
  final String pendingDirsJson;

  /// 当前正在扫的目录（JSON 对象，可为空）
  final String? currentDirJson;

  /// 当前目录的下一页游标
  final String? currentPageToken;

  /// `ScanStage.name`
  final String stageId;
  final int scannedDirs;
  final int scannedFiles;
  final int foundTracks;
  final int totalBytes;
  final int failedDirs;
  final String? lastError;
  final DateTime updatedAt;
  const ScanStateRow({
    required this.providerId,
    required this.rootId,
    required this.rootPath,
    required this.pendingDirsJson,
    this.currentDirJson,
    this.currentPageToken,
    required this.stageId,
    required this.scannedDirs,
    required this.scannedFiles,
    required this.foundTracks,
    required this.totalBytes,
    required this.failedDirs,
    this.lastError,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider_id'] = Variable<String>(providerId);
    map['root_id'] = Variable<String>(rootId);
    map['root_path'] = Variable<String>(rootPath);
    map['pending_dirs_json'] = Variable<String>(pendingDirsJson);
    if (!nullToAbsent || currentDirJson != null) {
      map['current_dir_json'] = Variable<String>(currentDirJson);
    }
    if (!nullToAbsent || currentPageToken != null) {
      map['current_page_token'] = Variable<String>(currentPageToken);
    }
    map['stage_id'] = Variable<String>(stageId);
    map['scanned_dirs'] = Variable<int>(scannedDirs);
    map['scanned_files'] = Variable<int>(scannedFiles);
    map['found_tracks'] = Variable<int>(foundTracks);
    map['total_bytes'] = Variable<int>(totalBytes);
    map['failed_dirs'] = Variable<int>(failedDirs);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScanStatesCompanion toCompanion(bool nullToAbsent) {
    return ScanStatesCompanion(
      providerId: Value(providerId),
      rootId: Value(rootId),
      rootPath: Value(rootPath),
      pendingDirsJson: Value(pendingDirsJson),
      currentDirJson:
          currentDirJson == null && nullToAbsent
              ? const Value.absent()
              : Value(currentDirJson),
      currentPageToken:
          currentPageToken == null && nullToAbsent
              ? const Value.absent()
              : Value(currentPageToken),
      stageId: Value(stageId),
      scannedDirs: Value(scannedDirs),
      scannedFiles: Value(scannedFiles),
      foundTracks: Value(foundTracks),
      totalBytes: Value(totalBytes),
      failedDirs: Value(failedDirs),
      lastError:
          lastError == null && nullToAbsent
              ? const Value.absent()
              : Value(lastError),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScanStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanStateRow(
      providerId: serializer.fromJson<String>(json['providerId']),
      rootId: serializer.fromJson<String>(json['rootId']),
      rootPath: serializer.fromJson<String>(json['rootPath']),
      pendingDirsJson: serializer.fromJson<String>(json['pendingDirsJson']),
      currentDirJson: serializer.fromJson<String?>(json['currentDirJson']),
      currentPageToken: serializer.fromJson<String?>(json['currentPageToken']),
      stageId: serializer.fromJson<String>(json['stageId']),
      scannedDirs: serializer.fromJson<int>(json['scannedDirs']),
      scannedFiles: serializer.fromJson<int>(json['scannedFiles']),
      foundTracks: serializer.fromJson<int>(json['foundTracks']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      failedDirs: serializer.fromJson<int>(json['failedDirs']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'providerId': serializer.toJson<String>(providerId),
      'rootId': serializer.toJson<String>(rootId),
      'rootPath': serializer.toJson<String>(rootPath),
      'pendingDirsJson': serializer.toJson<String>(pendingDirsJson),
      'currentDirJson': serializer.toJson<String?>(currentDirJson),
      'currentPageToken': serializer.toJson<String?>(currentPageToken),
      'stageId': serializer.toJson<String>(stageId),
      'scannedDirs': serializer.toJson<int>(scannedDirs),
      'scannedFiles': serializer.toJson<int>(scannedFiles),
      'foundTracks': serializer.toJson<int>(foundTracks),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'failedDirs': serializer.toJson<int>(failedDirs),
      'lastError': serializer.toJson<String?>(lastError),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScanStateRow copyWith({
    String? providerId,
    String? rootId,
    String? rootPath,
    String? pendingDirsJson,
    Value<String?> currentDirJson = const Value.absent(),
    Value<String?> currentPageToken = const Value.absent(),
    String? stageId,
    int? scannedDirs,
    int? scannedFiles,
    int? foundTracks,
    int? totalBytes,
    int? failedDirs,
    Value<String?> lastError = const Value.absent(),
    DateTime? updatedAt,
  }) => ScanStateRow(
    providerId: providerId ?? this.providerId,
    rootId: rootId ?? this.rootId,
    rootPath: rootPath ?? this.rootPath,
    pendingDirsJson: pendingDirsJson ?? this.pendingDirsJson,
    currentDirJson:
        currentDirJson.present ? currentDirJson.value : this.currentDirJson,
    currentPageToken:
        currentPageToken.present
            ? currentPageToken.value
            : this.currentPageToken,
    stageId: stageId ?? this.stageId,
    scannedDirs: scannedDirs ?? this.scannedDirs,
    scannedFiles: scannedFiles ?? this.scannedFiles,
    foundTracks: foundTracks ?? this.foundTracks,
    totalBytes: totalBytes ?? this.totalBytes,
    failedDirs: failedDirs ?? this.failedDirs,
    lastError: lastError.present ? lastError.value : this.lastError,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScanStateRow copyWithCompanion(ScanStatesCompanion data) {
    return ScanStateRow(
      providerId:
          data.providerId.present ? data.providerId.value : this.providerId,
      rootId: data.rootId.present ? data.rootId.value : this.rootId,
      rootPath: data.rootPath.present ? data.rootPath.value : this.rootPath,
      pendingDirsJson:
          data.pendingDirsJson.present
              ? data.pendingDirsJson.value
              : this.pendingDirsJson,
      currentDirJson:
          data.currentDirJson.present
              ? data.currentDirJson.value
              : this.currentDirJson,
      currentPageToken:
          data.currentPageToken.present
              ? data.currentPageToken.value
              : this.currentPageToken,
      stageId: data.stageId.present ? data.stageId.value : this.stageId,
      scannedDirs:
          data.scannedDirs.present ? data.scannedDirs.value : this.scannedDirs,
      scannedFiles:
          data.scannedFiles.present
              ? data.scannedFiles.value
              : this.scannedFiles,
      foundTracks:
          data.foundTracks.present ? data.foundTracks.value : this.foundTracks,
      totalBytes:
          data.totalBytes.present ? data.totalBytes.value : this.totalBytes,
      failedDirs:
          data.failedDirs.present ? data.failedDirs.value : this.failedDirs,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanStateRow(')
          ..write('providerId: $providerId, ')
          ..write('rootId: $rootId, ')
          ..write('rootPath: $rootPath, ')
          ..write('pendingDirsJson: $pendingDirsJson, ')
          ..write('currentDirJson: $currentDirJson, ')
          ..write('currentPageToken: $currentPageToken, ')
          ..write('stageId: $stageId, ')
          ..write('scannedDirs: $scannedDirs, ')
          ..write('scannedFiles: $scannedFiles, ')
          ..write('foundTracks: $foundTracks, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('failedDirs: $failedDirs, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    rootId,
    rootPath,
    pendingDirsJson,
    currentDirJson,
    currentPageToken,
    stageId,
    scannedDirs,
    scannedFiles,
    foundTracks,
    totalBytes,
    failedDirs,
    lastError,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanStateRow &&
          other.providerId == this.providerId &&
          other.rootId == this.rootId &&
          other.rootPath == this.rootPath &&
          other.pendingDirsJson == this.pendingDirsJson &&
          other.currentDirJson == this.currentDirJson &&
          other.currentPageToken == this.currentPageToken &&
          other.stageId == this.stageId &&
          other.scannedDirs == this.scannedDirs &&
          other.scannedFiles == this.scannedFiles &&
          other.foundTracks == this.foundTracks &&
          other.totalBytes == this.totalBytes &&
          other.failedDirs == this.failedDirs &&
          other.lastError == this.lastError &&
          other.updatedAt == this.updatedAt);
}

class ScanStatesCompanion extends UpdateCompanion<ScanStateRow> {
  final Value<String> providerId;
  final Value<String> rootId;
  final Value<String> rootPath;
  final Value<String> pendingDirsJson;
  final Value<String?> currentDirJson;
  final Value<String?> currentPageToken;
  final Value<String> stageId;
  final Value<int> scannedDirs;
  final Value<int> scannedFiles;
  final Value<int> foundTracks;
  final Value<int> totalBytes;
  final Value<int> failedDirs;
  final Value<String?> lastError;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ScanStatesCompanion({
    this.providerId = const Value.absent(),
    this.rootId = const Value.absent(),
    this.rootPath = const Value.absent(),
    this.pendingDirsJson = const Value.absent(),
    this.currentDirJson = const Value.absent(),
    this.currentPageToken = const Value.absent(),
    this.stageId = const Value.absent(),
    this.scannedDirs = const Value.absent(),
    this.scannedFiles = const Value.absent(),
    this.foundTracks = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.failedDirs = const Value.absent(),
    this.lastError = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanStatesCompanion.insert({
    required String providerId,
    required String rootId,
    required String rootPath,
    required String pendingDirsJson,
    this.currentDirJson = const Value.absent(),
    this.currentPageToken = const Value.absent(),
    required String stageId,
    this.scannedDirs = const Value.absent(),
    this.scannedFiles = const Value.absent(),
    this.foundTracks = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.failedDirs = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : providerId = Value(providerId),
       rootId = Value(rootId),
       rootPath = Value(rootPath),
       pendingDirsJson = Value(pendingDirsJson),
       stageId = Value(stageId),
       updatedAt = Value(updatedAt);
  static Insertable<ScanStateRow> custom({
    Expression<String>? providerId,
    Expression<String>? rootId,
    Expression<String>? rootPath,
    Expression<String>? pendingDirsJson,
    Expression<String>? currentDirJson,
    Expression<String>? currentPageToken,
    Expression<String>? stageId,
    Expression<int>? scannedDirs,
    Expression<int>? scannedFiles,
    Expression<int>? foundTracks,
    Expression<int>? totalBytes,
    Expression<int>? failedDirs,
    Expression<String>? lastError,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (providerId != null) 'provider_id': providerId,
      if (rootId != null) 'root_id': rootId,
      if (rootPath != null) 'root_path': rootPath,
      if (pendingDirsJson != null) 'pending_dirs_json': pendingDirsJson,
      if (currentDirJson != null) 'current_dir_json': currentDirJson,
      if (currentPageToken != null) 'current_page_token': currentPageToken,
      if (stageId != null) 'stage_id': stageId,
      if (scannedDirs != null) 'scanned_dirs': scannedDirs,
      if (scannedFiles != null) 'scanned_files': scannedFiles,
      if (foundTracks != null) 'found_tracks': foundTracks,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (failedDirs != null) 'failed_dirs': failedDirs,
      if (lastError != null) 'last_error': lastError,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanStatesCompanion copyWith({
    Value<String>? providerId,
    Value<String>? rootId,
    Value<String>? rootPath,
    Value<String>? pendingDirsJson,
    Value<String?>? currentDirJson,
    Value<String?>? currentPageToken,
    Value<String>? stageId,
    Value<int>? scannedDirs,
    Value<int>? scannedFiles,
    Value<int>? foundTracks,
    Value<int>? totalBytes,
    Value<int>? failedDirs,
    Value<String?>? lastError,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ScanStatesCompanion(
      providerId: providerId ?? this.providerId,
      rootId: rootId ?? this.rootId,
      rootPath: rootPath ?? this.rootPath,
      pendingDirsJson: pendingDirsJson ?? this.pendingDirsJson,
      currentDirJson: currentDirJson ?? this.currentDirJson,
      currentPageToken: currentPageToken ?? this.currentPageToken,
      stageId: stageId ?? this.stageId,
      scannedDirs: scannedDirs ?? this.scannedDirs,
      scannedFiles: scannedFiles ?? this.scannedFiles,
      foundTracks: foundTracks ?? this.foundTracks,
      totalBytes: totalBytes ?? this.totalBytes,
      failedDirs: failedDirs ?? this.failedDirs,
      lastError: lastError ?? this.lastError,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (rootId.present) {
      map['root_id'] = Variable<String>(rootId.value);
    }
    if (rootPath.present) {
      map['root_path'] = Variable<String>(rootPath.value);
    }
    if (pendingDirsJson.present) {
      map['pending_dirs_json'] = Variable<String>(pendingDirsJson.value);
    }
    if (currentDirJson.present) {
      map['current_dir_json'] = Variable<String>(currentDirJson.value);
    }
    if (currentPageToken.present) {
      map['current_page_token'] = Variable<String>(currentPageToken.value);
    }
    if (stageId.present) {
      map['stage_id'] = Variable<String>(stageId.value);
    }
    if (scannedDirs.present) {
      map['scanned_dirs'] = Variable<int>(scannedDirs.value);
    }
    if (scannedFiles.present) {
      map['scanned_files'] = Variable<int>(scannedFiles.value);
    }
    if (foundTracks.present) {
      map['found_tracks'] = Variable<int>(foundTracks.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (failedDirs.present) {
      map['failed_dirs'] = Variable<int>(failedDirs.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanStatesCompanion(')
          ..write('providerId: $providerId, ')
          ..write('rootId: $rootId, ')
          ..write('rootPath: $rootPath, ')
          ..write('pendingDirsJson: $pendingDirsJson, ')
          ..write('currentDirJson: $currentDirJson, ')
          ..write('currentPageToken: $currentPageToken, ')
          ..write('stageId: $stageId, ')
          ..write('scannedDirs: $scannedDirs, ')
          ..write('scannedFiles: $scannedFiles, ')
          ..write('foundTracks: $foundTracks, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('failedDirs: $failedDirs, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayHistoryTable extends PlayHistory
    with TableInfo<$PlayHistoryTable, PlayHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playedSecondsMeta = const VerificationMeta(
    'playedSeconds',
  );
  @override
  late final GeneratedColumn<int> playedSeconds = GeneratedColumn<int>(
    'played_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, trackId, playedAt, playedSeconds];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    if (data.containsKey('played_seconds')) {
      context.handle(
        _playedSecondsMeta,
        playedSeconds.isAcceptableOrUnknown(
          data['played_seconds']!,
          _playedSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayHistoryRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      trackId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}track_id'],
          )!,
      playedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}played_at'],
          )!,
      playedSeconds:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}played_seconds'],
          )!,
    );
  }

  @override
  $PlayHistoryTable createAlias(String alias) {
    return $PlayHistoryTable(attachedDatabase, alias);
  }
}

class PlayHistoryRow extends DataClass implements Insertable<PlayHistoryRow> {
  final int id;
  final String trackId;
  final DateTime playedAt;

  /// 实际播放时长（秒）。用于将来做「跳过率」统计。
  final int playedSeconds;
  const PlayHistoryRow({
    required this.id,
    required this.trackId,
    required this.playedAt,
    required this.playedSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<String>(trackId);
    map['played_at'] = Variable<DateTime>(playedAt);
    map['played_seconds'] = Variable<int>(playedSeconds);
    return map;
  }

  PlayHistoryCompanion toCompanion(bool nullToAbsent) {
    return PlayHistoryCompanion(
      id: Value(id),
      trackId: Value(trackId),
      playedAt: Value(playedAt),
      playedSeconds: Value(playedSeconds),
    );
  }

  factory PlayHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<String>(json['trackId']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
      playedSeconds: serializer.fromJson<int>(json['playedSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<String>(trackId),
      'playedAt': serializer.toJson<DateTime>(playedAt),
      'playedSeconds': serializer.toJson<int>(playedSeconds),
    };
  }

  PlayHistoryRow copyWith({
    int? id,
    String? trackId,
    DateTime? playedAt,
    int? playedSeconds,
  }) => PlayHistoryRow(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    playedAt: playedAt ?? this.playedAt,
    playedSeconds: playedSeconds ?? this.playedSeconds,
  );
  PlayHistoryRow copyWithCompanion(PlayHistoryCompanion data) {
    return PlayHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
      playedSeconds:
          data.playedSeconds.present
              ? data.playedSeconds.value
              : this.playedSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryRow(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playedAt: $playedAt, ')
          ..write('playedSeconds: $playedSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trackId, playedAt, playedSeconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayHistoryRow &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.playedAt == this.playedAt &&
          other.playedSeconds == this.playedSeconds);
}

class PlayHistoryCompanion extends UpdateCompanion<PlayHistoryRow> {
  final Value<int> id;
  final Value<String> trackId;
  final Value<DateTime> playedAt;
  final Value<int> playedSeconds;
  const PlayHistoryCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.playedAt = const Value.absent(),
    this.playedSeconds = const Value.absent(),
  });
  PlayHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String trackId,
    required DateTime playedAt,
    this.playedSeconds = const Value.absent(),
  }) : trackId = Value(trackId),
       playedAt = Value(playedAt);
  static Insertable<PlayHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? trackId,
    Expression<DateTime>? playedAt,
    Expression<int>? playedSeconds,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (playedAt != null) 'played_at': playedAt,
      if (playedSeconds != null) 'played_seconds': playedSeconds,
    });
  }

  PlayHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? trackId,
    Value<DateTime>? playedAt,
    Value<int>? playedSeconds,
  }) {
    return PlayHistoryCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      playedAt: playedAt ?? this.playedAt,
      playedSeconds: playedSeconds ?? this.playedSeconds,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    if (playedSeconds.present) {
      map['played_seconds'] = Variable<int>(playedSeconds.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playedAt: $playedAt, ')
          ..write('playedSeconds: $playedSeconds')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $ScanStatesTable scanStates = $ScanStatesTable(this);
  late final $PlayHistoryTable playHistory = $PlayHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    accounts,
    favorites,
    scanStates,
    playHistory,
  ];
}

typedef $$TracksTableCreateCompanionBuilder =
    TracksCompanion Function({
      required String id,
      required String providerId,
      required String remoteId,
      required String name,
      Value<String?> parentId,
      Value<String?> path,
      Value<int?> sizeBytes,
      Value<String?> mimeType,
      Value<DateTime?> modifiedAt,
      Value<String?> title,
      Value<String?> artist,
      Value<String?> album,
      Value<int?> durationMs,
      Value<int?> cueTrackNo,
      Value<int?> cueStartMs,
      Value<bool> isPlayable,
      Value<String> playabilityState,
      Value<String?> playabilityNote,
      Value<int> playCount,
      Value<DateTime?> lastPlayedAt,
      required DateTime indexedAt,
      Value<int> rowid,
    });
typedef $$TracksTableUpdateCompanionBuilder =
    TracksCompanion Function({
      Value<String> id,
      Value<String> providerId,
      Value<String> remoteId,
      Value<String> name,
      Value<String?> parentId,
      Value<String?> path,
      Value<int?> sizeBytes,
      Value<String?> mimeType,
      Value<DateTime?> modifiedAt,
      Value<String?> title,
      Value<String?> artist,
      Value<String?> album,
      Value<int?> durationMs,
      Value<int?> cueTrackNo,
      Value<int?> cueStartMs,
      Value<bool> isPlayable,
      Value<String> playabilityState,
      Value<String?> playabilityNote,
      Value<int> playCount,
      Value<DateTime?> lastPlayedAt,
      Value<DateTime> indexedAt,
      Value<int> rowid,
    });

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cueTrackNo => $composableBuilder(
    column: $table.cueTrackNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cueStartMs => $composableBuilder(
    column: $table.cueStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPlayable => $composableBuilder(
    column: $table.isPlayable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playabilityState => $composableBuilder(
    column: $table.playabilityState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playabilityNote => $composableBuilder(
    column: $table.playabilityNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cueTrackNo => $composableBuilder(
    column: $table.cueTrackNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cueStartMs => $composableBuilder(
    column: $table.cueStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPlayable => $composableBuilder(
    column: $table.isPlayable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playabilityState => $composableBuilder(
    column: $table.playabilityState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playabilityNote => $composableBuilder(
    column: $table.playabilityNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cueTrackNo => $composableBuilder(
    column: $table.cueTrackNo,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cueStartMs => $composableBuilder(
    column: $table.cueStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPlayable => $composableBuilder(
    column: $table.isPlayable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playabilityState => $composableBuilder(
    column: $table.playabilityState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playabilityNote => $composableBuilder(
    column: $table.playabilityNote,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get indexedAt =>
      $composableBuilder(column: $table.indexedAt, builder: (column) => column);
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          TrackRow,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (TrackRow, BaseReferences<_$AppDatabase, $TracksTable, TrackRow>),
          TrackRow,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<DateTime?> modifiedAt = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> cueTrackNo = const Value.absent(),
                Value<int?> cueStartMs = const Value.absent(),
                Value<bool> isPlayable = const Value.absent(),
                Value<String> playabilityState = const Value.absent(),
                Value<String?> playabilityNote = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<DateTime> indexedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                providerId: providerId,
                remoteId: remoteId,
                name: name,
                parentId: parentId,
                path: path,
                sizeBytes: sizeBytes,
                mimeType: mimeType,
                modifiedAt: modifiedAt,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                cueTrackNo: cueTrackNo,
                cueStartMs: cueStartMs,
                isPlayable: isPlayable,
                playabilityState: playabilityState,
                playabilityNote: playabilityNote,
                playCount: playCount,
                lastPlayedAt: lastPlayedAt,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String providerId,
                required String remoteId,
                required String name,
                Value<String?> parentId = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<DateTime?> modifiedAt = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> cueTrackNo = const Value.absent(),
                Value<int?> cueStartMs = const Value.absent(),
                Value<bool> isPlayable = const Value.absent(),
                Value<String> playabilityState = const Value.absent(),
                Value<String?> playabilityNote = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                required DateTime indexedAt,
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                providerId: providerId,
                remoteId: remoteId,
                name: name,
                parentId: parentId,
                path: path,
                sizeBytes: sizeBytes,
                mimeType: mimeType,
                modifiedAt: modifiedAt,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                cueTrackNo: cueTrackNo,
                cueStartMs: cueStartMs,
                isPlayable: isPlayable,
                playabilityState: playabilityState,
                playabilityNote: playabilityNote,
                playCount: playCount,
                lastPlayedAt: lastPlayedAt,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      TrackRow,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (TrackRow, BaseReferences<_$AppDatabase, $TracksTable, TrackRow>),
      TrackRow,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String providerId,
      required String authModeId,
      Value<String?> userId,
      Value<String?> displayName,
      Value<String?> avatarUrl,
      required DateTime authorizedAt,
      Value<DateTime?> expiresAt,
      Value<int?> storageUsedBytes,
      Value<int?> storageTotalBytes,
      Value<String?> memberLabel,
      Value<DateTime?> lastScannedAt,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> providerId,
      Value<String> authModeId,
      Value<String?> userId,
      Value<String?> displayName,
      Value<String?> avatarUrl,
      Value<DateTime> authorizedAt,
      Value<DateTime?> expiresAt,
      Value<int?> storageUsedBytes,
      Value<int?> storageTotalBytes,
      Value<String?> memberLabel,
      Value<DateTime?> lastScannedAt,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authModeId => $composableBuilder(
    column: $table.authModeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get authorizedAt => $composableBuilder(
    column: $table.authorizedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storageUsedBytes => $composableBuilder(
    column: $table.storageUsedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storageTotalBytes => $composableBuilder(
    column: $table.storageTotalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberLabel => $composableBuilder(
    column: $table.memberLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScannedAt => $composableBuilder(
    column: $table.lastScannedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authModeId => $composableBuilder(
    column: $table.authModeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get authorizedAt => $composableBuilder(
    column: $table.authorizedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storageUsedBytes => $composableBuilder(
    column: $table.storageUsedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storageTotalBytes => $composableBuilder(
    column: $table.storageTotalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberLabel => $composableBuilder(
    column: $table.memberLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScannedAt => $composableBuilder(
    column: $table.lastScannedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authModeId => $composableBuilder(
    column: $table.authModeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get authorizedAt => $composableBuilder(
    column: $table.authorizedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get storageUsedBytes => $composableBuilder(
    column: $table.storageUsedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get storageTotalBytes => $composableBuilder(
    column: $table.storageTotalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memberLabel => $composableBuilder(
    column: $table.memberLabel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastScannedAt => $composableBuilder(
    column: $table.lastScannedAt,
    builder: (column) => column,
  );
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          AccountRow,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> providerId = const Value.absent(),
                Value<String> authModeId = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<DateTime> authorizedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int?> storageUsedBytes = const Value.absent(),
                Value<int?> storageTotalBytes = const Value.absent(),
                Value<String?> memberLabel = const Value.absent(),
                Value<DateTime?> lastScannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                providerId: providerId,
                authModeId: authModeId,
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                authorizedAt: authorizedAt,
                expiresAt: expiresAt,
                storageUsedBytes: storageUsedBytes,
                storageTotalBytes: storageTotalBytes,
                memberLabel: memberLabel,
                lastScannedAt: lastScannedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String providerId,
                required String authModeId,
                Value<String?> userId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                required DateTime authorizedAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int?> storageUsedBytes = const Value.absent(),
                Value<int?> storageTotalBytes = const Value.absent(),
                Value<String?> memberLabel = const Value.absent(),
                Value<DateTime?> lastScannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                providerId: providerId,
                authModeId: authModeId,
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                authorizedAt: authorizedAt,
                expiresAt: expiresAt,
                storageUsedBytes: storageUsedBytes,
                storageTotalBytes: storageTotalBytes,
                memberLabel: memberLabel,
                lastScannedAt: lastScannedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      AccountRow,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (AccountRow, BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$FavoritesTableCreateCompanionBuilder =
    FavoritesCompanion Function({
      required String trackId,
      required DateTime createdAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$FavoritesTableUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<String> trackId,
      Value<DateTime> createdAt,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          FavoriteRow,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (
            FavoriteRow,
            BaseReferences<_$AppDatabase, $FavoritesTable, FavoriteRow>,
          ),
          FavoriteRow,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                trackId: trackId,
                createdAt: createdAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackId,
                required DateTime createdAt,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                trackId: trackId,
                createdAt: createdAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      FavoriteRow,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (
        FavoriteRow,
        BaseReferences<_$AppDatabase, $FavoritesTable, FavoriteRow>,
      ),
      FavoriteRow,
      PrefetchHooks Function()
    >;
typedef $$ScanStatesTableCreateCompanionBuilder =
    ScanStatesCompanion Function({
      required String providerId,
      required String rootId,
      required String rootPath,
      required String pendingDirsJson,
      Value<String?> currentDirJson,
      Value<String?> currentPageToken,
      required String stageId,
      Value<int> scannedDirs,
      Value<int> scannedFiles,
      Value<int> foundTracks,
      Value<int> totalBytes,
      Value<int> failedDirs,
      Value<String?> lastError,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ScanStatesTableUpdateCompanionBuilder =
    ScanStatesCompanion Function({
      Value<String> providerId,
      Value<String> rootId,
      Value<String> rootPath,
      Value<String> pendingDirsJson,
      Value<String?> currentDirJson,
      Value<String?> currentPageToken,
      Value<String> stageId,
      Value<int> scannedDirs,
      Value<int> scannedFiles,
      Value<int> foundTracks,
      Value<int> totalBytes,
      Value<int> failedDirs,
      Value<String?> lastError,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ScanStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootId => $composableBuilder(
    column: $table.rootId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootPath => $composableBuilder(
    column: $table.rootPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingDirsJson => $composableBuilder(
    column: $table.pendingDirsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentDirJson => $composableBuilder(
    column: $table.currentDirJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentPageToken => $composableBuilder(
    column: $table.currentPageToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stageId => $composableBuilder(
    column: $table.stageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scannedDirs => $composableBuilder(
    column: $table.scannedDirs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scannedFiles => $composableBuilder(
    column: $table.scannedFiles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get foundTracks => $composableBuilder(
    column: $table.foundTracks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedDirs => $composableBuilder(
    column: $table.failedDirs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScanStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootId => $composableBuilder(
    column: $table.rootId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootPath => $composableBuilder(
    column: $table.rootPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingDirsJson => $composableBuilder(
    column: $table.pendingDirsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentDirJson => $composableBuilder(
    column: $table.currentDirJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentPageToken => $composableBuilder(
    column: $table.currentPageToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stageId => $composableBuilder(
    column: $table.stageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scannedDirs => $composableBuilder(
    column: $table.scannedDirs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scannedFiles => $composableBuilder(
    column: $table.scannedFiles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get foundTracks => $composableBuilder(
    column: $table.foundTracks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedDirs => $composableBuilder(
    column: $table.failedDirs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScanStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rootId =>
      $composableBuilder(column: $table.rootId, builder: (column) => column);

  GeneratedColumn<String> get rootPath =>
      $composableBuilder(column: $table.rootPath, builder: (column) => column);

  GeneratedColumn<String> get pendingDirsJson => $composableBuilder(
    column: $table.pendingDirsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentDirJson => $composableBuilder(
    column: $table.currentDirJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentPageToken => $composableBuilder(
    column: $table.currentPageToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stageId =>
      $composableBuilder(column: $table.stageId, builder: (column) => column);

  GeneratedColumn<int> get scannedDirs => $composableBuilder(
    column: $table.scannedDirs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scannedFiles => $composableBuilder(
    column: $table.scannedFiles,
    builder: (column) => column,
  );

  GeneratedColumn<int> get foundTracks => $composableBuilder(
    column: $table.foundTracks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failedDirs => $composableBuilder(
    column: $table.failedDirs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ScanStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanStatesTable,
          ScanStateRow,
          $$ScanStatesTableFilterComposer,
          $$ScanStatesTableOrderingComposer,
          $$ScanStatesTableAnnotationComposer,
          $$ScanStatesTableCreateCompanionBuilder,
          $$ScanStatesTableUpdateCompanionBuilder,
          (
            ScanStateRow,
            BaseReferences<_$AppDatabase, $ScanStatesTable, ScanStateRow>,
          ),
          ScanStateRow,
          PrefetchHooks Function()
        > {
  $$ScanStatesTableTableManager(_$AppDatabase db, $ScanStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ScanStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ScanStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ScanStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> providerId = const Value.absent(),
                Value<String> rootId = const Value.absent(),
                Value<String> rootPath = const Value.absent(),
                Value<String> pendingDirsJson = const Value.absent(),
                Value<String?> currentDirJson = const Value.absent(),
                Value<String?> currentPageToken = const Value.absent(),
                Value<String> stageId = const Value.absent(),
                Value<int> scannedDirs = const Value.absent(),
                Value<int> scannedFiles = const Value.absent(),
                Value<int> foundTracks = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> failedDirs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanStatesCompanion(
                providerId: providerId,
                rootId: rootId,
                rootPath: rootPath,
                pendingDirsJson: pendingDirsJson,
                currentDirJson: currentDirJson,
                currentPageToken: currentPageToken,
                stageId: stageId,
                scannedDirs: scannedDirs,
                scannedFiles: scannedFiles,
                foundTracks: foundTracks,
                totalBytes: totalBytes,
                failedDirs: failedDirs,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String providerId,
                required String rootId,
                required String rootPath,
                required String pendingDirsJson,
                Value<String?> currentDirJson = const Value.absent(),
                Value<String?> currentPageToken = const Value.absent(),
                required String stageId,
                Value<int> scannedDirs = const Value.absent(),
                Value<int> scannedFiles = const Value.absent(),
                Value<int> foundTracks = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> failedDirs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ScanStatesCompanion.insert(
                providerId: providerId,
                rootId: rootId,
                rootPath: rootPath,
                pendingDirsJson: pendingDirsJson,
                currentDirJson: currentDirJson,
                currentPageToken: currentPageToken,
                stageId: stageId,
                scannedDirs: scannedDirs,
                scannedFiles: scannedFiles,
                foundTracks: foundTracks,
                totalBytes: totalBytes,
                failedDirs: failedDirs,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScanStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanStatesTable,
      ScanStateRow,
      $$ScanStatesTableFilterComposer,
      $$ScanStatesTableOrderingComposer,
      $$ScanStatesTableAnnotationComposer,
      $$ScanStatesTableCreateCompanionBuilder,
      $$ScanStatesTableUpdateCompanionBuilder,
      (
        ScanStateRow,
        BaseReferences<_$AppDatabase, $ScanStatesTable, ScanStateRow>,
      ),
      ScanStateRow,
      PrefetchHooks Function()
    >;
typedef $$PlayHistoryTableCreateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      required String trackId,
      required DateTime playedAt,
      Value<int> playedSeconds,
    });
typedef $$PlayHistoryTableUpdateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      Value<String> trackId,
      Value<DateTime> playedAt,
      Value<int> playedSeconds,
    });

class $$PlayHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playedSeconds => $composableBuilder(
    column: $table.playedSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playedSeconds => $composableBuilder(
    column: $table.playedSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  GeneratedColumn<int> get playedSeconds => $composableBuilder(
    column: $table.playedSeconds,
    builder: (column) => column,
  );
}

class $$PlayHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayHistoryTable,
          PlayHistoryRow,
          $$PlayHistoryTableFilterComposer,
          $$PlayHistoryTableOrderingComposer,
          $$PlayHistoryTableAnnotationComposer,
          $$PlayHistoryTableCreateCompanionBuilder,
          $$PlayHistoryTableUpdateCompanionBuilder,
          (
            PlayHistoryRow,
            BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryRow>,
          ),
          PlayHistoryRow,
          PrefetchHooks Function()
        > {
  $$PlayHistoryTableTableManager(_$AppDatabase db, $PlayHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$PlayHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$PlayHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$PlayHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
                Value<int> playedSeconds = const Value.absent(),
              }) => PlayHistoryCompanion(
                id: id,
                trackId: trackId,
                playedAt: playedAt,
                playedSeconds: playedSeconds,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trackId,
                required DateTime playedAt,
                Value<int> playedSeconds = const Value.absent(),
              }) => PlayHistoryCompanion.insert(
                id: id,
                trackId: trackId,
                playedAt: playedAt,
                playedSeconds: playedSeconds,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayHistoryTable,
      PlayHistoryRow,
      $$PlayHistoryTableFilterComposer,
      $$PlayHistoryTableOrderingComposer,
      $$PlayHistoryTableAnnotationComposer,
      $$PlayHistoryTableCreateCompanionBuilder,
      $$PlayHistoryTableUpdateCompanionBuilder,
      (
        PlayHistoryRow,
        BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryRow>,
      ),
      PlayHistoryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$ScanStatesTableTableManager get scanStates =>
      $$ScanStatesTableTableManager(_db, _db.scanStates);
  $$PlayHistoryTableTableManager get playHistory =>
      $$PlayHistoryTableTableManager(_db, _db.playHistory);
}
