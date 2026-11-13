import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/chat_room.dart';
import 'package:noisex/models/constants.dart';

void main() {
  tearDown(resetServerTimeOffset);

  group('ChatRoom save connection state', () {
    test('allows saving only before current user confirms', () {
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(room.canSaveConnection, isTrue);
      expect(room.saveConnectionLabel, equals('保存连接'));
    });

    test('disables saving while waiting for peer confirmation', () {
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        mySaveConfirmed: true,
      );

      expect(room.canSaveConnection, isFalse);
      expect(room.saveConnectionLabel, equals('等待对方确认'));
    });

    test('disables saving after both users confirm', () {
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        mySaveConfirmed: true,
        bothSaveConfirmed: true,
      );

      expect(room.canSaveConnection, isFalse);
      expect(room.saveConnectionLabel, equals('连接已保存'));
    });

    test('uses server save state as current room authority', () {
      final room = ChatRoom(
        id: 'room-2',
        sonarContent: 'new connection',
        signalCode: 'RX-0002',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        savedConnection: true,
        mySaveConfirmed: true,
        bothSaveConfirmed: true,
      );

      final synced = room.applyServerSaveState(
        savedConnection: false,
        mySaveConfirmed: false,
        bothSaveConfirmed: false,
      );

      expect(synced.savedConnection, isFalse);
      expect(synced.mySaveConfirmed, isFalse);
      expect(synced.bothSaveConfirmed, isFalse);
      expect(synced.saveConnectionLabel, equals('保存连接'));
    });
  });

  group('ChatRoom time windows', () {
    test('uses expiresAt minus room lifetime as createdAt fallback', () {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(7200000);
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: expiresAt,
      );

      expect(
        room.createdAt,
        equals(expiresAt
            .subtract(const Duration(hours: Constants.roomLifetimeHours))),
      );
    });

    test('remainingHours uses server time offset', () {
      final localNow = DateTime.now();
      updateServerTimeOffset(
          localNow.add(const Duration(hours: 2)).millisecondsSinceEpoch);
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: localNow.add(const Duration(hours: 24)),
        createdAt: localNow,
      );

      expect(room.remainingHours, inInclusiveRange(21, 22));
    });

    test('unlock window is open within first 24 hours', () {
      final now = DateTime.now();
      updateServerTimeOffset(now.millisecondsSinceEpoch);
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: now.add(const Duration(hours: 72)),
        createdAt: now.subtract(const Duration(hours: 10)),
      );

      expect(room.isUnlockWindowOpen, isTrue);
      expect(room.remainingUnlockHours, inInclusiveRange(13, 14));
    });

    test('unlock window closes after 24 hours', () {
      final now = DateTime.now();
      updateServerTimeOffset(now.millisecondsSinceEpoch);
      final room = ChatRoom(
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-0001',
        expiresAt: now.add(const Duration(hours: 47)),
        createdAt: now.subtract(const Duration(hours: 25)),
      );

      expect(room.isUnlockWindowOpen, isFalse);
      expect(room.remainingUnlockHours, equals(0));
    });
  });
}
