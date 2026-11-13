import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/constants.dart';

void main() {
  group('Lifecycle constants', () {
    test('keeps room lifetime and unlock window product values', () {
      expect(Constants.roomLifetimeHours, equals(72));
      expect(Constants.unlockWindowHours, equals(24));
    });

    test('uses deep connection product thresholds', () {
      expect(Constants.deepConnectionTotalThreshold, equals(20));
      expect(Constants.deepConnectionPerUserThreshold, equals(5));
      expect(Constants.deepConnectionMinMessageLength, equals(5));
    });
  });
}
