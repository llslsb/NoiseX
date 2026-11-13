import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/utils/listening_registration_utils.dart';

void main() {
  group('shouldUpdateListeningRegistration', () {
    // 重连即补登收听（app.dart _reRegisterListeningAfterReconnect）唯一依赖这条：
    // 掉线后本地仍记着同一格，只有 force 能穿过同格去重——改坏它重连补登会静默失效
    test('returns true when force refreshing same geohash', () {
      expect(
        shouldUpdateListeningRegistration(
          registeredGeohash: 'wx4g0s',
          nextGeohash: 'wx4g0s',
          force: true,
        ),
        isTrue,
      );
    });

    test('returns true when geohash changes', () {
      expect(
        shouldUpdateListeningRegistration(
          registeredGeohash: 'wx4g0s',
          nextGeohash: 'wx4g0t',
        ),
        isTrue,
      );
    });

    test('returns false when geohash is unchanged', () {
      expect(
        shouldUpdateListeningRegistration(
          registeredGeohash: 'wx4g0s',
          nextGeohash: 'wx4g0s',
        ),
        isFalse,
      );
    });

    test('returns true when registering from empty state', () {
      expect(
        shouldUpdateListeningRegistration(
          registeredGeohash: '',
          nextGeohash: 'wx4g0s',
        ),
        isTrue,
      );
    });

    test('returns false when next geohash is empty', () {
      expect(
        shouldUpdateListeningRegistration(
          registeredGeohash: 'wx4g0s',
          nextGeohash: '',
        ),
        isFalse,
      );
    });
  });

  group('ListeningOperationGate', () {
    test('starts with zero current id', () {
      expect(ListeningOperationGate().currentId, equals(0));
    });

    test('next increments current id', () {
      final gate = ListeningOperationGate();

      expect(gate.next(), equals(1));
      expect(gate.next(), equals(2));
      expect(gate.currentId, equals(2));
    });

    test('isCurrent returns true for latest operation', () {
      final gate = ListeningOperationGate();
      final operationId = gate.next();

      expect(gate.isCurrent(operationId), isTrue);
    });

    test('isCurrent returns false for stale operation', () {
      final gate = ListeningOperationGate();
      final operationId = gate.next();
      gate.next();

      expect(gate.isCurrent(operationId), isFalse);
    });
  });
}
