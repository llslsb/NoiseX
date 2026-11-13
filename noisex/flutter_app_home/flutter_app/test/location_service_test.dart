import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/location_service.dart';

void main() {
  group('encodeGeohash', () {
    test('known coordinate should return valid base32 geohash', () {
      final geohash = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 6);
      const validChars = '0123456789bcdefghjkmnpqrstuvwxyz';
      for (final c in geohash.runes) {
        expect(validChars.contains(String.fromCharCode(c)), isTrue,
            reason: '字符 ${String.fromCharCode(c)} 不是合法的 base32 geohash 字符');
      }
    });

    test('should return 6 character string', () {
      final geohash = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 6);
      expect(geohash.length, equals(6));
    });

    test('different coordinates should produce different geohash', () {
      final g1 = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 6);
      final g2 = LocationService.encodeGeohashForTesting(31.2304, 121.4737, 6);
      expect(g1, isNot(equals(g2)));
    });

    test('Beijing approximate should start with wx4g', () {
      final geohash = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 6);
      expect(geohash, startsWith('wx4g'));
    });

    test('same coordinates with different precision should differ', () {
      final g4 = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 4);
      final g6 = LocationService.encodeGeohashForTesting(39.9042, 116.4074, 6);
      expect(g4.length, equals(4));
      expect(g6.length, equals(6));
      expect(g6, startsWith(g4));
    });
  });
}
