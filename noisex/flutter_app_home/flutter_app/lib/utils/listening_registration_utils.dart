bool shouldUpdateListeningRegistration({
  required String registeredGeohash,
  required String nextGeohash,
  bool force = false,
}) {
  if (nextGeohash.isEmpty) return false;
  return force || registeredGeohash != nextGeohash;
}

class ListeningOperationGate {
  int _currentId = 0;

  int get currentId => _currentId;

  int next() {
    _currentId++;
    return _currentId;
  }

  bool isCurrent(int operationId) => operationId == _currentId;
}
