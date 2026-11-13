import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/constants.dart';
import 'package:noisex/services/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PushService notification policy', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PushService().setCurrentRoom(null);
      await PushService().setEnabled(true);
    });

    test('push is enabled by default', () {
      expect(PushService().isEnabled, isTrue);
    });

    test('setEnabled persists disabled state', () async {
      await PushService().setEnabled(false);

      expect(PushService().isEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(Constants.prefsKeyPushEnabled), isFalse);
    });

    test('setEnabled persists enabled state', () async {
      await PushService().setEnabled(false);
      await PushService().setEnabled(true);

      expect(PushService().isEnabled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(Constants.prefsKeyPushEnabled), isTrue);
    });

    test('does not show notifications for the current room', () {
      PushService().setCurrentRoom('room-1');

      expect(PushService().shouldShowNotificationForRoom('room-1'), isFalse);
      expect(PushService().shouldShowNotificationForRoom('room-2'), isTrue);
    });

    test('does not show notifications when push is disabled', () async {
      await PushService().setEnabled(false);
      PushService().setCurrentRoom(null);

      expect(PushService().shouldShowNotificationForRoom('room-1'), isFalse);
    });

    test('chat notification title and body are redacted', () {
      expect(
        PushService().notificationTitleForType('chat', '私密标题'),
        equals('新消息'),
      );
      expect(
        PushService().notificationBodyForType('chat', '真实聊天内容'),
        equals('收到新消息'),
      );
      expect(
        PushService().notificationTitleForType('matched', '匹配成功'),
        equals('匹配成功'),
      );
      expect(
        PushService().notificationBodyForType('matched', '匹配成功'),
        equals('匹配成功'),
      );
    });
  });
}
