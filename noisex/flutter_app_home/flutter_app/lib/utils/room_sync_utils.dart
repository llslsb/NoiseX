List<String> computeStaleRoomIds(
  Iterable<String> oldRoomIds,
  Iterable<String> activeRoomIds,
) {
  final activeIds = activeRoomIds.toSet();
  return oldRoomIds.where((id) => !activeIds.contains(id)).toList();
}

bool isSaveConnectionCompleteStatus(String status) {
  return status == 'saved' || status == 'confirmed';
}

bool shouldShowSaveConfirmedPrompt({
  required bool roomExists,
  required bool wasBothSaveConfirmed,
}) {
  return roomExists && !wasBothSaveConfirmed;
}
