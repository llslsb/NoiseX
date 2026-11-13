class Sonar {
  final String id;
  final String content;
  final String distance;
  final DateTime timestamp;
  final String geohash;

  const Sonar({
    required this.id,
    required this.content,
    required this.distance,
    required this.timestamp,
    this.geohash = '',
  });

  Sonar copyWith({
    String? id,
    String? content,
    String? distance,
    DateTime? timestamp,
    String? geohash,
  }) {
    return Sonar(
      id: id ?? this.id,
      content: content ?? this.content,
      distance: distance ?? this.distance,
      timestamp: timestamp ?? this.timestamp,
      geohash: geohash ?? this.geohash,
    );
  }
}
