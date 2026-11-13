import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/ws_service.dart';

/// WS 死链检测判定（D-M11-1）。
/// 场景背景：TCP 半开（对端静默掉网/中间设备掐链）时 sink.add 只进本地
/// 缓冲不报错、onError/onDone 永不触发，断网红条要等下次业务发送才出现
/// （2026-11-05 M11 双端实测）。连续 90s 无服务端任何帧即判死链强断重连。
void main() {
  group('isDeadLinkSilence', () {
    final t0 = DateTime(2026, 11, 5, 10, 0, 0);

    test('基线为 null（从未收到服务端帧）不判死链', () {
      expect(
        WsService.isDeadLinkSilence(lastServerFrameAt: null, now: t0),
        isFalse,
      );
    });

    test('静默 89s（容忍 2 个 ping 周期丢 pong）不判死链', () {
      expect(
        WsService.isDeadLinkSilence(
          lastServerFrameAt: t0,
          now: t0.add(const Duration(seconds: 89)),
        ),
        isFalse,
      );
    });

    test('静默满 90s 判死链', () {
      expect(
        WsService.isDeadLinkSilence(
          lastServerFrameAt: t0,
          now: t0.add(const Duration(seconds: 90)),
        ),
        isTrue,
      );
    });

    test('收到 pong 刷新基线后重新计时', () {
      // 60s 静默 → pong 到达刷新基线 → 再 60s 不判死（合计 120s 但分两段）
      final pongAt = t0.add(const Duration(seconds: 60));
      expect(
        WsService.isDeadLinkSilence(
          lastServerFrameAt: pongAt,
          now: pongAt.add(const Duration(seconds: 60)),
        ),
        isFalse,
      );
    });
  });
}
