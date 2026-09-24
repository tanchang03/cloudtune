import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/playback_queue.dart';
import 'package:cloudtune/domain/services/shuffle_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String remoteId, {String? name}) => Track(
      provider: DriveProvider.quark,
      remoteId: remoteId,
      name: name ?? '$remoteId.flac',
      sizeBytes: 1024,
    );

List<Track> _tracks(int n) =>
    [for (var i = 0; i < n; i++) _t(i.toString())];

void main() {
  group('顺序模式', () {
    test('next 依次推进', () {
      final q = PlaybackQueue(tracks: _tracks(3));

      expect(q.current, isNull);
      expect(q.next()!.remoteId, '0');
      expect(q.next()!.remoteId, '1');
      expect(q.next()!.remoteId, '2');
    });

    test('播到末尾回到第一首（列表循环）', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      for (var i = 0; i < 3; i++) {
        q.next();
      }

      expect(q.next()!.remoteId, '0');
    });

    test('previous 回退到实际播过的上一首', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next(); // 0
      q.next(); // 1

      expect(q.previous()!.remoteId, '0');
    });

    test('没有历史时 previous 退回列表上一首，首首回到末尾', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.jumpTo('quark:1');

      expect(q.previous()!.remoteId, '0');
    });

    test('canGoPrevious 反映历史栈', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      expect(q.canGoPrevious, isFalse);

      q.next();
      expect(q.canGoPrevious, isFalse, reason: '只播过一首时无处可退');

      q.next();
      expect(q.canGoPrevious, isTrue);
    });

    test('连续两次跳到同一首不记历史（避免上一首原地踏步）', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.jumpTo('quark:1');
      q.jumpTo('quark:1');
      q.jumpTo('quark:1');

      expect(q.canGoPrevious, isFalse);
    });

    test('空队列 next / previous 返回 null', () {
      final q = PlaybackQueue();

      expect(q.isEmpty, isTrue);
      expect(q.next(), isNull);
      expect(q.previous(), isNull);
    });
  });

  group('单曲循环', () {
    test('next 永远返回当前曲', () {
      final q = PlaybackQueue(tracks: _tracks(3), mode: PlaybackMode.repeatOne);

      expect(q.next()!.remoteId, '0');
      expect(q.next()!.remoteId, '0');
      expect(q.next()!.remoteId, '0');
    });

    test('还没有当前曲时取第一首', () {
      final q = PlaybackQueue(tracks: _tracks(3), mode: PlaybackMode.repeatOne);

      expect(q.next()!.remoteId, '0');
      expect(q.currentId, 'quark:0');
    });
  });

  group('随机模式', () {
    test('一轮之内不重复', () {
      final q = PlaybackQueue(
        tracks: _tracks(5),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(7),
      );

      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        seen.add(q.next()!.id);
      }

      expect(seen.length, 5, reason: '一轮抽空之前不应重复');
    });

    test('一轮抽空后重洗，且首曲不与刚播完的重复', () {
      final q = PlaybackQueue(
        tracks: _tracks(4),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(3),
      );

      var last = '';
      for (var i = 0; i < 4; i++) {
        last = q.next()!.id;
      }

      // 第二轮的第一首
      final nextInNewRound = q.next()!.id;

      expect(nextInNewRound, isNot(last),
          reason: '重洗后首曲重复是最容易被用户察觉的「随机不随机」');
    });

    test('多轮下来覆盖全部曲目（不会有曲目永远抽不到）', () {
      final q = PlaybackQueue(
        tracks: _tracks(6),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(11),
      );

      final seen = <String>{};
      for (var i = 0; i < 60; i++) {
        seen.add(q.next()!.id);
      }

      expect(seen.length, 6);
    });

    test('少听优先：播放次数少的曲目在轮内位置更靠前', () {
      final q = PlaybackQueue(
        tracks: [_t('hot'), _t('cold'), _t('mid')],
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(42),
        weights: {
          'quark:hot': const ShuffleCandidate(id: 'quark:hot', playCount: 100),
          'quark:cold': const ShuffleCandidate(id: 'quark:cold', playCount: 0),
          'quark:mid': const ShuffleCandidate(id: 'quark:mid', playCount: 10),
        },
      );

      final positions = <String, List<int>>{'hot': [], 'cold': []};
      for (var round = 0; round < 200; round++) {
        for (var i = 0; i < 3; i++) {
          final t = q.next()!;
          positions[t.remoteId]?.add(i);
        }
      }

      double avg(List<int> xs) => xs.reduce((a, b) => a + b) / xs.length;

      expect(avg(positions['cold']!), lessThan(avg(positions['hot']!)),
          reason: '没听过的曲目应当更早被抽到，否则冷门永远沉底');
    });

    test('没有权重信息时仍能正常随机', () {
      final q = PlaybackQueue(
        tracks: _tracks(4),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(1),
      );

      expect(q.next(), isNotNull);
      expect(q.next(), isNotNull);
    });
  });

  group('模式切换', () {
    test('切到随机时清空本轮记录（否则会立刻重复刚播过的）', () {
      final q = PlaybackQueue(
        tracks: _tracks(3),
        shuffle: seededShuffleEngine(5),
      );
      q.next();
      q.next();

      q.setMode(PlaybackMode.shuffle);

      expect(q.playedInRound, isEmpty);
    });

    test('切到同一模式是空操作', () {
      final q = PlaybackQueue(
        tracks: _tracks(3),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(5),
      );
      q.next();

      final before = q.playedInRound;
      q.setMode(PlaybackMode.shuffle);

      expect(q.playedInRound, before);
    });

    test('顺序模式下 playedInRound 恒为空（不泄露随机状态）', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next();

      expect(q.playedInRound, isEmpty);
    });

    test('toggled 一次点击就在顺序与随机之间互切', () {
      expect(PlaybackMode.sequential.toggled, PlaybackMode.shuffle);
      expect(PlaybackMode.shuffle.toggled, PlaybackMode.sequential);
    });

    test('toggled 从单曲循环落回顺序播放', () {
      expect(
        PlaybackMode.repeatOne.toggled,
        PlaybackMode.sequential,
        reason: '单曲循环不是一种播放顺序；从它切出去应当回到顺序，'
            '而不是把用户留在单曲循环里再按一次才出来',
      );
    });

    test('切换播放模式不会丢掉当前曲（否则切一下随机就断播）', () {
      final q = PlaybackQueue(
        tracks: _tracks(3),
        shuffle: seededShuffleEngine(4),
      );
      q.jumpTo('quark:2');

      q.setMode(q.mode.toggled);
      expect(q.currentId, 'quark:2');
      expect(q.mode, PlaybackMode.shuffle);

      q.setMode(q.mode.toggled);
      expect(q.currentId, 'quark:2');
      expect(q.mode, PlaybackMode.sequential);
    });

    test('随机切回顺序后，next 立刻恢复成曲池次序（回归：顺序播放必须以当前列表顺序）', () {
      final q = PlaybackQueue(
        tracks: _tracks(4),
        shuffle: seededShuffleEngine(2),
      );
      q.jumpTo('quark:1');

      // 随机抽两首 —— 曲池本身不该被重排，随机的只是「抽哪一首」
      q.setMode(PlaybackMode.shuffle);
      q.next();
      q.next();

      q.setMode(PlaybackMode.sequential);
      final idx = q.tracks.indexWhere((t) => t.id == q.currentId);
      final expected = q.tracks[(idx + 1) % q.tracks.length].id;

      expect(
        q.next()!.id,
        expected,
        reason: '切回顺序播放必须沿用列表次序，而不是沿用随机抽签的结果',
      );
    });
  });

  group('曲池变更', () {
    test('replaceTracks 保留当前曲目（重新扫描后不打断播放）', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next(); // 0
      q.next(); // 1

      q.replaceTracks(_tracks(5));

      expect(q.currentId, 'quark:1');
      expect(q.length, 5);
    });

    test('replaceTracks 时当前曲目已消失则置空（不假装在播第一首）', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next();
      q.next(); // 1

      q.replaceTracks([_t('9')]);

      expect(q.currentId, isNull);
      expect(q.length, 1);
      expect(q.next()!.remoteId, '9', reason: '下一次取曲应从头开始');
    });

    test('replaceTracks(keepCurrent: false) 清空当前与历史', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next();
      q.next();

      q.replaceTracks(_tracks(3), keepCurrent: false);

      expect(q.canGoPrevious, isFalse);
      expect(q.currentId, isNull);
    });

    test('replaceTracks 不会顺手选中第一首（否则按播放会跳过第一首）', () {
      final q = PlaybackQueue();

      q.replaceTracks(_tracks(3));

      expect(q.currentId, isNull);
      expect(q.next()!.remoteId, '0');
    });

    test('replaceTracks 传入空列表不会崩', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next();

      q.replaceTracks([]);

      expect(q.isEmpty, isTrue);
      expect(q.currentId, isNull);
      expect(q.next(), isNull);
    });

    test('removeTrack 移除当前曲目后 current 为 null', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next(); // 0

      q.removeTrack('quark:0');

      expect(q.currentId, isNull);
      expect(q.length, 2);
      expect(q.contains('quark:0'), isFalse);
    });

    test('removeTrack 清掉历史里的曲目，previous 不会拿到已删的歌', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next(); // 0
      q.next(); // 1

      q.removeTrack('quark:0');

      expect(q.canGoPrevious, isFalse, reason: '历史里的已删曲目应被剔除');
      expect(q.previous()!.id, isNot('quark:0'));
    });

    test('removeTrack 同时清掉随机权重', () {
      final q = PlaybackQueue(
        tracks: _tracks(3),
        weights: {'quark:0': const ShuffleCandidate(id: 'quark:0', playCount: 5)},
      );

      q.removeTrack('quark:0');
      q.updateWeights({'quark:0': const ShuffleCandidate(id: 'quark:0')});

      expect(q.contains('quark:0'), isFalse);
    });
  });

  group('定位与查询', () {
    test('jumpTo 命中队列里的曲目', () {
      final q = PlaybackQueue(tracks: _tracks(3));

      expect(q.jumpTo('quark:2')!.remoteId, '2');
      expect(q.currentId, 'quark:2');
    });

    test('jumpTo 不存在的曲目返回 null 且不改变当前', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.jumpTo('quark:1');

      expect(q.jumpTo('quark:nope'), isNull);
      expect(q.currentId, 'quark:1');
    });

    test('trackById 与 contains', () {
      final q = PlaybackQueue(tracks: _tracks(3));

      expect(q.trackById('quark:1')!.remoteId, '1');
      expect(q.trackById('quark:9'), isNull);
      expect(q.contains('quark:1'), isTrue);
      expect(q.contains('quark:9'), isFalse);
    });

    test('tracks 是只读视图', () {
      final q = PlaybackQueue(tracks: _tracks(3));

      expect(() => q.tracks.add(_t('9')), throwsUnsupportedError);
    });

    test('reset 回到「一首都没播过」', () {
      final q = PlaybackQueue(tracks: _tracks(3));
      q.next();
      q.next();

      q.reset();

      expect(q.currentId, isNull);
      expect(q.canGoPrevious, isFalse);
    });

    test('updateWeights 会替换整份权重', () {
      final q = PlaybackQueue(
        tracks: _tracks(3),
        mode: PlaybackMode.shuffle,
        shuffle: seededShuffleEngine(9),
      );

      q.updateWeights({
        'quark:0': const ShuffleCandidate(id: 'quark:0', playCount: 0),
      });

      expect(q.next(), isNotNull);
    });
  });
}
