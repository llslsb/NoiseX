import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/ws_service.dart';

/// WS 握手连续失败自愈的判定状态机。
/// 场景背景：换服务器/封禁/token 轮换后旧 token 握手永远被拒，
/// REST 有 401 自动重注册兜底，WS 没有自愈会无限重连失败（2026-11-03 实锤）。
void main() {
  group('HandshakeFailureTracker', () {
    test('连续 3 次失败在第 3 次触发重注册建议', () {
      final t = HandshakeFailureTracker();
      final t0 = DateTime(2026, 11, 3, 22, 0, 0);
      expect(t.noteFailure(t0), isFalse); // 1
      expect(t.noteFailure(t0.add(const Duration(seconds: 3))), isFalse); // 2
      expect(t.noteFailure(t0.add(const Duration(seconds: 7))), isTrue); // 3
    });

    test('握手成功清零计数：2 败 + 成功 + 2 败不触发', () {
      final t = HandshakeFailureTracker();
      final t0 = DateTime(2026, 11, 3, 22, 0, 0);
      t.noteFailure(t0);
      t.noteFailure(t0.add(const Duration(seconds: 3)));
      t.noteSuccess(); // 连上了
      expect(t.noteFailure(t0.add(const Duration(seconds: 10))), isFalse);
      expect(t.noteFailure(t0.add(const Duration(seconds: 13))), isFalse);
      expect(t.streak, equals(2));
    });

    test('重注册后冷却期内再次 3 连败不重复触发', () {
      final t = HandshakeFailureTracker();
      final t0 = DateTime(2026, 11, 3, 22, 0, 0);
      t.noteFailure(t0);
      t.noteFailure(t0.add(const Duration(seconds: 3)));
      expect(t.noteFailure(t0.add(const Duration(seconds: 7))), isTrue);
      t.noteReRegister(t0.add(const Duration(seconds: 8)));
      // 冷却期内（<2min）又连败 3 次：不触发
      expect(t.noteFailure(t0.add(const Duration(seconds: 20))), isFalse);
      expect(t.noteFailure(t0.add(const Duration(seconds: 23))), isFalse);
      expect(t.noteFailure(t0.add(const Duration(seconds: 27))), isFalse);
    });

    test('冷却期过后再次 3 连败可再次触发', () {
      final t = HandshakeFailureTracker();
      final t0 = DateTime(2026, 11, 3, 22, 0, 0);
      t.noteFailure(t0);
      t.noteFailure(t0.add(const Duration(seconds: 3)));
      expect(t.noteFailure(t0.add(const Duration(seconds: 7))), isTrue);
      t.noteReRegister(t0.add(const Duration(seconds: 8)));
      // 取 +2m2s：第三次失败落在 +2m9s，距冷却戳 121s > 120s 冷却
      final afterCooldown = t0.add(const Duration(minutes: 2, seconds: 2));
      expect(t.noteFailure(afterCooldown), isFalse); // streak=1
      expect(
          t.noteFailure(afterCooldown.add(const Duration(seconds: 3))),
          isFalse); // streak=2
      expect(
          t.noteFailure(afterCooldown.add(const Duration(seconds: 7))),
          isTrue); // streak=3 且冷却已过
    });

    test('阈值可配置：threshold=1 时首败即触发', () {
      final t = HandshakeFailureTracker(threshold: 1);
      expect(t.noteFailure(DateTime(2026, 11, 3)), isTrue);
    });
  });
}
