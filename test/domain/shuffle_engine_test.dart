import 'dart:math';

import 'package:cloudtune/domain/services/shuffle_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shuffleIds', () {
    test('空列表与单元素列表原样返回', () {
      final e = ShuffleEngine(random: Random(1));
      expect(e.shuffleIds([]), isEmpty);
      expect(e.shuffleIds(['a']), ['a']);
    });

    test('返回的是同多重集合（不丢不重）', () {
      final ids = List.generate(50, (i) => 'id$i');
      final out = ShuffleEngine(random: Random(7)).shuffleIds(ids);
      expect(out.length, ids.length);
      expect(out.toSet(), ids.toSet());
    });

    test('不修改入参', () {
      final ids = ['a', 'b', 'c', 'd'];
      final copy = List<String>.from(ids);
      ShuffleEngine(random: Random(3)).shuffleIds(ids);
      expect(ids, copy);
    });

    test('固定种子下结果确定（可复现）', () {
      final ids = List.generate(20, (i) => 'id$i');
      final a = ShuffleEngine(random: Random(42)).shuffleIds(ids);
      final b = ShuffleEngine(random: Random(42)).shuffleIds(ids);
      expect(a, b);
    });

    test('确实打乱了顺序（不是恒等排列）', () {
      final ids = List.generate(100, (i) => 'id$i');
      final out = ShuffleEngine(random: Random(9)).shuffleIds(ids);
      expect(out, isNot(ids));
    });

    test('avoidFirst 保证首曲不是上一首（多种子穷举）', () {
      final ids = ['a', 'b', 'c', 'd', 'e'];
      for (var seed = 0; seed < 300; seed++) {
        final out = ShuffleEngine(random: Random(seed)).shuffleIds(ids, avoidFirst: 'a');
        expect(out.first, isNot('a'), reason: 'seed=$seed 时首曲仍为 a');
        expect(out.toSet(), ids.toSet());
      }
    });

    test('avoidFirst 在单元素时无法规避，仍正常返回', () {
      final out = ShuffleEngine(random: Random(1)).shuffleIds(['a'], avoidFirst: 'a');
      expect(out, ['a']);
    });

    test('关闭 avoidImmediateRepeat 后不再规避', () {
      final ids = ['a', 'b'];
      var sawAFirst = false;
      for (var seed = 0; seed < 100; seed++) {
        final out = ShuffleEngine(random: Random(seed), avoidImmediateRepeat: false)
            .shuffleIds(ids, avoidFirst: 'a');
        if (out.first == 'a') sawAFirst = true;
      }
      expect(sawAFirst, isTrue);
    });
  });

  group('weightOf — 少听优先', () {
    final e = ShuffleEngine(random: Random(1));

    test('播放次数为 0 时权重为 1', () {
      expect(e.weightOf(const ShuffleCandidate(id: 'a')), 1.0);
    });

    test('播放次数反比递减', () {
      expect(e.weightOf(const ShuffleCandidate(id: 'a', playCount: 1)), closeTo(0.5, 1e-9));
      expect(e.weightOf(const ShuffleCandidate(id: 'a', playCount: 9)), closeTo(0.1, 1e-9));
    });

    test('权重恒大于 0（冷门不会永久沉底）', () {
      expect(e.weightOf(const ShuffleCandidate(id: 'a', playCount: 10000)), greaterThan(0));
    });

    test('负数播放次数按 0 处理', () {
      expect(e.weightOf(const ShuffleCandidate(id: 'a', playCount: -5)), 1.0);
    });

    test('24 小时内听过 → 权重 ×0.2', () {
      final now = DateTime(2026, 9, 23, 12);
      final w = e.weightOf(
        ShuffleCandidate(id: 'a', lastPlayedAt: now.subtract(const Duration(hours: 2))),
        now: now,
      );
      expect(w, closeTo(0.2, 1e-9));
    });

    test('7 天内听过 → 权重 ×0.6', () {
      final now = DateTime(2026, 9, 23, 12);
      final w = e.weightOf(
        ShuffleCandidate(id: 'a', lastPlayedAt: now.subtract(const Duration(days: 3))),
        now: now,
      );
      expect(w, closeTo(0.6, 1e-9));
    });

    test('超过 7 天无惩罚', () {
      final now = DateTime(2026, 9, 23, 12);
      final w = e.weightOf(
        ShuffleCandidate(id: 'a', lastPlayedAt: now.subtract(const Duration(days: 30))),
        now: now,
      );
      expect(w, closeTo(1.0, 1e-9));
    });

    test('未来时间（时钟漂移）不产生惩罚也不崩', () {
      final now = DateTime(2026, 9, 23, 12);
      final w = e.weightOf(
        ShuffleCandidate(id: 'a', lastPlayedAt: now.add(const Duration(hours: 5))),
        now: now,
      );
      expect(w, 1.0);
    });
  });

  group('weightedShuffle', () {
    test('空集返回空，单元素原样返回', () {
      final e = ShuffleEngine(random: Random(1));
      expect(e.weightedShuffle(const []), isEmpty);
      expect(e.weightedShuffle(const [ShuffleCandidate(id: 'only')]), ['only']);
    });

    test('每个 id 恰好出现一次', () {
      final cands = List.generate(30, (i) => ShuffleCandidate(id: 'id$i', playCount: i % 5));
      final out = ShuffleEngine(random: Random(11)).weightedShuffle(cands);
      expect(out.length, 30);
      expect(out.toSet().length, 30);
    });

    test('avoidFirst 生效（多种子穷举）', () {
      final cands = List.generate(6, (i) => ShuffleCandidate(id: 'id$i'));
      for (var seed = 0; seed < 300; seed++) {
        final out = ShuffleEngine(random: Random(seed))
            .weightedShuffle(cands, avoidFirst: 'id0');
        expect(out.first, isNot('id0'), reason: 'seed=$seed');
        expect(out.toSet().length, 6);
      }
    });

    test('少听的曲目更常出现在前部（统计验证）', () {
      // 一首听了 50 次，一首从没听过；跑 2000 次看谁更常排第一
      final cands = [
        const ShuffleCandidate(id: 'hot', playCount: 50),
        const ShuffleCandidate(id: 'cold'),
        const ShuffleCandidate(id: 'warm', playCount: 3),
      ];
      var coldFirst = 0;
      var hotFirst = 0;
      for (var seed = 0; seed < 2000; seed++) {
        final out = ShuffleEngine(random: Random(seed)).weightedShuffle(cands);
        if (out.first == 'cold') coldFirst++;
        if (out.first == 'hot') hotFirst++;
      }
      expect(coldFirst, greaterThan(hotFirst * 5),
          reason: '少听优先未生效：cold=$coldFirst hot=$hotFirst');
    });

    test('全部权重为极小值时仍能返回完整排列（无死循环）', () {
      final cands = List.generate(
        10,
        (i) => ShuffleCandidate(id: 'id$i', playCount: 100000),
      );
      final out = ShuffleEngine(random: Random(5)).weightedShuffle(cands);
      expect(out.length, 10);
      expect(out.toSet().length, 10);
    });
  });

  group('pickNext', () {
    final e = ShuffleEngine(random: Random(2));

    test('空集返回 null', () {
      expect(e.pickNext(const []), isNull);
    });

    test('单元素直接返回', () {
      expect(e.pickNext(const [ShuffleCandidate(id: 'a')]), 'a');
    });

    test('排除集内的 id 永不被选中', () {
      final cands = List.generate(5, (i) => ShuffleCandidate(id: 'id$i'));
      for (var seed = 0; seed < 300; seed++) {
        final picked = ShuffleEngine(random: Random(seed)).pickNext(
          cands,
          exclude: {'id0', 'id1', 'id2', 'id3'},
        );
        expect(picked, 'id4');
      }
    });

    test('排除集覆盖全部时仍返回一首（退化为允许重复）', () {
      final cands = [const ShuffleCandidate(id: 'a'), const ShuffleCandidate(id: 'b')];
      final picked = e.pickNext(cands, exclude: {'a', 'b'});
      expect(picked, isNotNull);
      expect(['a', 'b'], contains(picked));
    });
  });

  group('nextInRound — 一轮不重复', () {
    test('连续取 3 次恰好覆盖 3 首，互不重复', () {
      final cands = [
        const ShuffleCandidate(id: 'a'),
        const ShuffleCandidate(id: 'b'),
        const ShuffleCandidate(id: 'c'),
      ];
      final engine = ShuffleEngine(random: Random(17));
      var played = <String>{};
      final picked = <String>[];
      for (var i = 0; i < 3; i++) {
        final r = engine.nextInRound(cands, played: played);
        expect(r.nextId, isNotNull);
        picked.add(r.nextId!);
        played = r.played;
      }
      expect(picked.toSet(), {'a', 'b', 'c'});
    });

    test('一轮抽空后自动重置，能继续播', () {
      final cands = [
        const ShuffleCandidate(id: 'a'),
        const ShuffleCandidate(id: 'b'),
      ];
      final engine = ShuffleEngine(random: Random(23));
      var played = <String>{};
      final seq = <String>[];
      for (var i = 0; i < 10; i++) {
        final r = engine.nextInRound(cands, played: played);
        seq.add(r.nextId!);
        played = r.played;
      }
      expect(seq.length, 10);
      // 每连续 2 首构成一个不重复的轮次
      expect(seq.sublist(0, 2).toSet(), {'a', 'b'});
      expect(seq.sublist(2, 4).toSet(), {'a', 'b'});
    });

    test('不会连续两次返回同一首（多元素场景）', () {
      final cands = List.generate(6, (i) => ShuffleCandidate(id: 'id$i'));
      for (var seed = 0; seed < 200; seed++) {
        final engine = ShuffleEngine(random: Random(seed));
        var played = <String>{};
        String? prev;
        for (var i = 0; i < 12; i++) {
          final r = engine.nextInRound(cands, played: played, currentId: prev);
          expect(r.nextId, isNot(prev), reason: 'seed=$seed 第 $i 步连续重复');
          prev = r.nextId;
          played = r.played;
        }
      }
    });

    test('空候选集返回 null 且不崩', () {
      final r = ShuffleEngine(random: Random(1)).nextInRound(const [], played: {});
      expect(r.nextId, isNull);
    });

    test('played 中的陈旧 id 会被清理，避免集合无限膨胀', () {
      final cands = [const ShuffleCandidate(id: 'a'), const ShuffleCandidate(id: 'b')];
      final r = ShuffleEngine(random: Random(1)).nextInRound(
        cands,
        played: {'已删除的曲目', 'a'},
      );
      expect(r.played.contains('已删除的曲目'), isFalse);
    });

    test('单曲库场景：永远返回同一首而不是 null', () {
      final cands = [const ShuffleCandidate(id: 'only')];
      final engine = ShuffleEngine(random: Random(1));
      var played = <String>{};
      for (var i = 0; i < 5; i++) {
        final r = engine.nextInRound(cands, played: played);
        expect(r.nextId, 'only');
        played = r.played;
      }
    });
  });
}
