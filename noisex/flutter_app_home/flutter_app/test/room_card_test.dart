import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/chat_room.dart';
import 'package:noisex/widgets/room_card.dart';

/// RoomCard 计时器回归测试。
///
/// 2026-11-06 安卓 debug 真机红屏事故：剩余 <6h 的房间会在入场淡入之外再建呼吸脉冲
/// 控制器，组件却混入单计时器 SingleTickerProviderStateMixin → 断言
/// 「multiple tickers were created」，整张卡片崩成红屏。这里锁死两条进入双控制器的路径：
/// 首次渲染即临期（initState）、渲染后才跨入临期（didUpdateWidget）。
void main() {
  ChatRoom roomExpiringIn(Duration remaining, DateTime now) => ChatRoom(
        id: 'room-critical',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: now.add(remaining),
      );

  Widget host(ChatRoom room, DateTime now) => MaterialApp(
        home: Scaffold(
          body: RoomCard(room: room, now: now, onEnter: () {}),
        ),
      );

  testWidgets('首次渲染即处于 <6h 红色警戒档：双控制器不抛计时器断言', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(host(roomExpiringIn(const Duration(hours: 3), now), now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('RX-0001'), findsOneWidget);
  });

  testWidgets('渲染后才跨入 <6h 档（didUpdateWidget 补建脉冲）：不抛计时器断言', (tester) async {
    final now = DateTime.now();
    final room = roomExpiringIn(const Duration(hours: 7), now);
    await tester.pumpWidget(host(room, now));
    // 同一房间，时钟推进 2 小时 → 剩 5 小时，进入红色警戒档
    await tester.pumpWidget(host(room, now.add(const Duration(hours: 2))));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('RX-0001'), findsOneWidget);
  });
}
