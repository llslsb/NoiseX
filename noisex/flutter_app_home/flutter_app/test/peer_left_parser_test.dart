import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/utils/peer_left_parser.dart';

void main() {
  group('PeerLeftEvent.fromPayload', () {
    test('parses well-formed payload with signalCode and leftAt', () {
      final ev = PeerLeftEvent.fromPayload({
        'type': 'peer_left',
        'roomId': 'room-1',
        'signalCode': 'RX-1234',
        'leftAt': 1700000000000,
      });

      expect(ev.roomId, 'room-1');
      expect(ev.signalCode, 'RX-1234');
      expect(ev.leftAt, 1700000000000);
      expect(ev.isValid, isTrue);
      expect(ev.notificationBody, 'RX-1234 已离开对话');
      // 关键回归：通知 body 永远不会包含 undefined / null
      expect(ev.notificationBody.contains('undefined'), isFalse);
      expect(ev.notificationBody.contains('null'), isFalse);
    });

    test('falls back to "对方" when signalCode is missing', () {
      final ev = PeerLeftEvent.fromPayload({
        'type': 'peer_left',
        'roomId': 'room-1',
      });

      expect(ev.signalCode, '对方');
      expect(ev.notificationBody, '对方 已离开对话');
      expect(ev.notificationBody.contains('undefined'), isFalse);
      expect(ev.notificationBody.contains('null'), isFalse);
    });

    test('falls back to "对方" when signalCode is empty string', () {
      final ev = PeerLeftEvent.fromPayload({
        'roomId': 'room-1',
        'signalCode': '',
      });

      expect(ev.signalCode, '对方');
      expect(ev.notificationBody, '对方 已离开对话');
    });

    test('isValid is false when roomId is missing', () {
      final ev = PeerLeftEvent.fromPayload({
        'signalCode': 'RX-1',
      });

      expect(ev.roomId, '');
      expect(ev.isValid, isFalse);
    });

    test('isValid is false when roomId is empty', () {
      final ev = PeerLeftEvent.fromPayload({
        'roomId': '',
        'signalCode': 'RX-1',
      });

      expect(ev.isValid, isFalse);
    });

    test('leftAt defaults to 0 when missing or wrong type', () {
      final missing = PeerLeftEvent.fromPayload({'roomId': 'r'});
      final wrong = PeerLeftEvent.fromPayload({
        'roomId': 'r',
        'leftAt': 'not-a-number',
      });

      expect(missing.leftAt, 0);
      expect(wrong.leftAt, 0);
    });

    test('leftAt accepts double from JSON', () {
      final ev = PeerLeftEvent.fromPayload({
        'roomId': 'r',
        'leftAt': 1700000000000.0,
      });

      expect(ev.leftAt, 1700000000000);
    });
  });

  group('roomExpiredNotificationBody', () {
    test('does not include room id short code', () {
      final body = roomExpiredNotificationBody('room-abcdef');

      expect(body, '对话已风干，散入夜空');
      expect(body.contains('room'), isFalse);
      expect(body.contains('undefined'), isFalse);
    });
  });
}
