class Meme {
  final String id;
  final String name;
  final String filePath;
  final String? folderId;
  final List<String> tags;
  final DateTime createdAt;
  bool isFavorite;
  final String mimeType;
  final int fileSize;
  String? mood;
  final String type; // "image" | "emoji" | "text"
  final String? textContent;
  final String? remotePath;

  Meme({
    required this.id,
    required this.name,
    this.filePath = '',
    this.folderId,
    this.tags = const [],
    required this.createdAt,
    this.isFavorite = false,
    this.mimeType = '',
    this.fileSize = 0,
    this.mood,
    this.type = 'image',
    this.textContent,
    this.remotePath,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'folderId': folderId,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'isFavorite': isFavorite,
    'mimeType': mimeType,
    'fileSize': fileSize,
    'mood': mood,
    'type': type,
    'textContent': textContent,
    'remotePath': remotePath,
  };

  factory Meme.fromMap(Map<String, dynamic> map) => Meme(
    id: map['id'] as String,
    name: map['name'] as String,
    filePath: map['filePath'] as String? ?? '',
    folderId: map['folderId'] as String?,
    tags: List<String>.from(map['tags'] ?? []),
    createdAt: DateTime.parse(map['createdAt'] as String),
    isFavorite: map['isFavorite'] as bool? ?? false,
    mimeType: map['mimeType'] as String? ?? '',
    fileSize: map['fileSize'] as int? ?? 0,
    mood: map['mood'] as String?,
    type: map['type'] as String? ?? 'image',
    textContent: map['textContent'] as String?,
    remotePath: map['remotePath'] as String?,
  );

  Meme copyWith({
    String? id,
    String? name,
    String? filePath,
    String? folderId,
    List<String>? tags,
    DateTime? createdAt,
    bool? isFavorite,
    String? mimeType,
    int? fileSize,
    String? mood,
    String? type,
    String? textContent,
    String? remotePath,
  }) => Meme(
    id: id ?? this.id,
    name: name ?? this.name,
    filePath: filePath ?? this.filePath,
    folderId: folderId ?? this.folderId,
    tags: tags ?? this.tags,
    createdAt: createdAt ?? this.createdAt,
    isFavorite: isFavorite ?? this.isFavorite,
    mimeType: mimeType ?? this.mimeType,
    fileSize: fileSize ?? this.fileSize,
    mood: mood ?? this.mood,
    type: type ?? this.type,
    textContent: textContent ?? this.textContent,
    remotePath: remotePath ?? this.remotePath,
  );
}
