class Meme {
  static const String typeEmoji = 'emoji';
  static const String typeGif = 'gif';
  static const String typeImage = 'image';
  static const String typeText = 'text';
  static const String typePortrait = 'portrait';
  static const String typeCg = 'cg';
  static const String typeCharacterCard = 'character_card';
  static const String typeVector = 'vector';   // SVG 矢量图
  static const String typePsd = 'psd';          // PSD 多图层

  static const List<String> allTypes = [
    typeEmoji, typeGif, typeImage, typeText, typePortrait, typeCg,
    typeCharacterCard, typeVector, typePsd,
  ];

  bool get isImageType => type == typeImage || type == typeGif ||
      type == typePortrait || type == typeCg || type == typeCharacterCard ||
      type == typeVector || type == typePsd;

  /// 是否为动画类型（GIF / APNG）
  bool get isAnimated => type == typeGif || mimeType == 'image/apng';

  /// 是否为矢量图（SVG）
  bool get isVector => type == typeVector;

  /// 是否为 PSD
  bool get isPsd => type == typePsd;

  final String id;
  final String name;
  final String filePath;
  final String? folderId;
  final List<String> tags;
  final DateTime createdAt;
  bool isFavorite;
  final String mimeType;
  final int fileSize;
  final String type;
  final String? textContent;
  final String? remotePath;
  final Map<String, dynamic>? characterData;
  final int width;
  final int height;
  /// PSD 合成预览图路径（导入时生成的 PNG 副本）
  final String? thumbPath;
  /// PSD 图层信息（名称/可见性/边界），用于查看器图层面板
  final List<Map<String, dynamic>>? psdLayers;

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
    this.type = typeImage,
    this.textContent,
    this.remotePath,
    this.characterData,
    this.width = 0,
    this.height = 0,
    this.thumbPath,
    this.psdLayers,
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
    'type': type,
    'textContent': textContent,
    'remotePath': remotePath,
    'characterData': characterData,
    'width': width,
    'height': height,
    'thumbPath': thumbPath,
    'psdLayers': psdLayers,
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
    type: map['type'] as String? ?? 'image',
    textContent: map['textContent'] as String?,
    remotePath: map['remotePath'] as String?,
    characterData: map['characterData'] as Map<String, dynamic>?,
    width: map['width'] as int? ?? 0,
    height: map['height'] as int? ?? 0,
    thumbPath: map['thumbPath'] as String?,
    psdLayers: map['psdLayers'] != null
        ? List<Map<String, dynamic>>.from(
            (map['psdLayers'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : null,
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
    String? type,
    String? textContent,
    String? remotePath,
    Map<String, dynamic>? characterData,
    int? width,
    int? height,
    String? thumbPath,
    List<Map<String, dynamic>>? psdLayers,
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
    type: type ?? this.type,
    textContent: textContent ?? this.textContent,
    remotePath: remotePath ?? this.remotePath,
    characterData: characterData ?? this.characterData,
    width: width ?? this.width,
    height: height ?? this.height,
    thumbPath: thumbPath ?? this.thumbPath,
    psdLayers: psdLayers ?? this.psdLayers,
  );
}
