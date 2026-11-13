import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/utils/room_sync_utils.dart';

void main() {
  group('computeStaleRoomIds', () {
    test('returns empty when both lists are empty', () {
      expect(computeStaleRoomIds([], []), isEmpty);
    });

    test('returns empty when all old rooms are still active', () {
      expect(computeStaleRoomIds(['room-1', 'room-2'], ['room-2', 'room-1']),
          isEmpty);
    });

    test('returns rooms that disappeared from active list', () {
      expect(
        computeStaleRoomIds(['room-1', 'room-2', 'room-3'], ['room-2']),
        equals(['room-1', 'room-3']),
      );
    });

    test('returns all old rooms when active list is empty', () {
      expect(computeStaleRoomIds(['room-1', 'room-2'], []),
          equals(['room-1', 'room-2']));
    });
  });

  group('save connection prompt helpers', () {
    test('treats saved and confirmed API statuses as completed', () {
      expect(isSaveConnectionCompleteStatus('saved'), isTrue);
      expect(isSaveConnectionCompleteStatus('confirmed'), isTrue);
      expect(isSaveConnectionCompleteStatus('waiting'), isFalse);
    });

    test('shows save confirmed prompt only on first transition', () {
      expect(
        shouldShowSaveConfirmedPrompt(
          roomExists: true,
          wasBothSaveConfirmed: false,
        ),
        isTrue,
      );
      expect(
        shouldShowSaveConfirmedPrompt(
          roomExists: true,
          wasBothSaveConfirmed: true,
        ),
        isFalse,
      );
      expect(
        shouldShowSaveConfirmedPrompt(
          roomExists: false,
          wasBothSaveConfirmed: false,
        ),
        isFalse,
      );
    });
  });
}
