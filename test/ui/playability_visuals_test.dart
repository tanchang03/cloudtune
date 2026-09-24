import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// 锁死可播性文案的对外口径。
///
/// 这一组不是测 UI 渲染，而是测**给用户看的那几句话**：
/// 需求 #3 要求把「超限」「为什么播不了」这类内部术语改成说人话，
/// 并明确「哪些文件 / 什么原因 / 什么条件」三段。
///
/// 文案是产品契约：它一旦变，UI、文档、用户预期一起变，
/// 所以把它当 API 一样测，下次有人想随手改文案就会撞红。
void main() {
  group('badgeLabel —— 列表行内四个字以内的提醒', () {
    test('用用户能直接读懂的词，不出现「超限」', () {
      final labels =
          PlayabilityState.values.map((s) => s.badgeLabel).toList();
      // 用户产品决策：原术语「超限」必须换掉
      expect(labels, isNot(contains('超限')));
    });

    test('5 个状态各有不重复的短文案', () {
      final labels = PlayabilityState.values.map((s) => s.badgeLabel).toSet();
      expect(labels.length, PlayabilityState.values.length);
    });
  });

  group('explainWhat / explainWhy / explainHow —— 三段说明', () {
    test('每段都是非空、人话，且不互相抄（不是把同一句话贴三次）', () {
      for (final state in PlayabilityState.values) {
        expect(state.explainWhat, isNotEmpty,
            reason: '${state.name} 缺少「哪些文件会这样」');
        expect(state.explainWhy, isNotEmpty,
            reason: '${state.name} 缺少「什么原因」');
        // 「可播」也需要「怎样才能播」——告诉用户「直接点播即可」
        expect(state.explainHow, isNotEmpty,
            reason: '${state.name} 缺少「怎样才能播」');
        expect(state.explainWhat, isNot(state.explainWhy),
            reason: '${state.name} 的 what 与 why 是同一句话，糊弄');
      }
    });

    test('取不到链的文案指向「接口限制」，不把责任推给文件', () {
      final s = PlayabilityState.overLimit;
      expect(s.explainWhy, contains('网盘'));
      expect(s.explainWhy, contains('取链接口'));
      expect(s.explainHow, contains('路由'));

      // 回归：改造前 explainHow 写的是「换成体积更小的版本就能播」，
      // 那是把**接口的限制**说成了**文件的毛病** —— 用户会以为文件坏了，
      // 而实际上同一个文件在夸克官方 App 里能正常播放。
      // 2026-09-24 验证后确认了这一点，所以这段话不能再出现。
      for (final state in PlayabilityState.values) {
        expect(
          state.explainHow,
          isNot(contains('换成体积更小')),
          reason: '${state.name} 仍在引导用户「换个更小的文件」',
        );
        expect(
          state.explainHow,
          isNot(contains('换成不超过')),
          reason: '${state.name} 仍在把接口限制说成文件问题',
        );
        expect(
          state.explainWhy,
          isNot(contains('文件太大')),
          reason: '${state.name} 仍在用「文件太大」这种笼统且误导的说法',
        );
      }
    });
  });

  group('helpTitle —— 弹窗主标题', () {
    test('5 个状态都有各自标题，不复用同一句', () {
      final titles = PlayabilityState.values.map((s) => s.helpTitle).toSet();
      expect(titles.length, PlayabilityState.values.length);
    });
  });

  group('badgeLabel / helpTitle 在 playable 状态上的措辞', () {
    test('可播时徽标不显示（但 helpTitle 仍能复用「确认可播」语义）', () {
      expect(PlayabilityState.playable.badgeLabel, '可播');
      expect(PlayabilityState.playable.helpTitle, isNot(contains('不能')));
      expect(PlayabilityState.playable.helpTitle, isNot(contains('无法')));
    });
  });
}