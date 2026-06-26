class MemeFolder {
  final String id;
  final String name;
  final DateTime createdAt;
  final int colorValue;
  final String? coverMemeId;

  MemeFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.colorValue = 0xFF6366F1,
    this.coverMemeId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'colorValue': colorValue,
    'coverMemeId': coverMemeId,
  };

  factory MemeFolder.fromMap(Map<String, dynamic> map) => MemeFolder(
    id: map['id'] as String,
    name: map['name'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    colorValue: map['colorValue'] as int? ?? 0xFF6366F1,
    coverMemeId: map['coverMemeId'] as String?,
  );

  MemeFolder copyWith({String? id, String? name, DateTime? createdAt, int? colorValue, String? coverMemeId}) =>
    MemeFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      colorValue: colorValue ?? this.colorValue,
      coverMemeId: coverMemeId ?? this.coverMemeId,
    );
}
