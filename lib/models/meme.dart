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
  static const String typePdf = 'pdf';          // PDF 文档
  static const String typeNovel = 'novel';       // 小说（长文本）
  static const String typeManga = 'manga';       // 漫画（多页图片）

  static const List<String> allTypes = [
    typeEmoji, typeGif, typeImage, typeText, typePortrait, typeCg,
    typeCharacterCard, typeVector, typePsd, typePdf, typeNovel, typeManga,
  ];

  /// 所有支持的图片/文档格式扩展名（不含点，小写）
  static const List<String> supportedExtensions = [
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
    'svg', 'apng', 'psd', 'ico', 'tif', 'tiff', 'pdf',
  ];

  bool get isImageType => type == typeImage || type == typeGif ||
      type == typePortrait || type == typeCg || type == typeCharacterCard ||
      type == typeVector || type == typePsd || type == typePdf || type == typeNovel ||
      type == typeManga;

  /// 是否为动画类型（GIF / APNG）
  bool get isAnimated => type == typeGif || mimeType == 'image/apng';

  /// 是否为矢量图（SVG）
  bool get isVector => type == typeVector;

  /// 是否为 PSD
  bool get isPsd => type == typePsd;

  /// 是否有情绪标签
  bool get hasMoods => moods.isNotEmpty;

  /// 是否为立绘/CG 精灵图（支持图层合成）
  bool get isSprite => (type == typePortrait || type == typeCg) &&
      spriteLayers != null && spriteLayers!.isNotEmpty;

  /// 是否为 PDF
  bool get isPdf => type == typePdf;

  /// 是否为漫画（多页图片）
  bool get isManga => type == typeManga;

  /// 是否为小说（长文本）
  bool get isNovel => type == typeNovel;

  /// 是否为文本类（文本或小说）
  bool get isTextLike => type == typeText || type == typeNovel;

  /// 实际显示用路径：有缩略图（PSD/ICO/TIF 转换的 PNG）时用 thumbPath，否则用 filePath
  String get displayPath => thumbPath ?? filePath;

  /// 文件后缀名（小写，不含点），如 "png"、"jpg"
  String get extension {
    final dot = filePath.lastIndexOf('.');
    if (dot == -1 || dot == filePath.length - 1) return '';
    return filePath.substring(dot + 1).toLowerCase();
  }

  /// 类型对应的 i18n 键名
  String get typeLabelKey {
    switch (type) {
      case typeEmoji: return 'type_emoji';
      case typeGif: return 'type_gif';
      case typeText: return 'type_text';
      case typeImage: return 'type_image';
      case typePortrait: return 'type_portrait';
      case typeCg: return 'type_cg';
      case typeCharacterCard: return 'type_character_card';
      case typeVector: return 'type_vector';
      case typePsd: return 'type_psd';
      case typePdf: return 'type_pdf';
      case typeNovel: return 'type_novel';
      case typeManga: return 'type_manga';
      default: return 'type_image';
    }
  }

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
  /// 立绘/CG 精灵图层（krkr pjson / VN 多图合并）
  /// 每层结构：{name, path, category(base/expression/outfit/accessory), visible, zOrder}
  final List<Map<String, dynamic>>? spriteLayers;
  /// 情绪标签（带权重），每项 {name, weight(1-5)}
  /// weight 表示情绪强度：1=轻微，5=强烈（如"大笑"weight=5，"微笑"weight=2）
  final List<Map<String, dynamic>> moods;
  /// 漫画多页路径列表（每页为相对存储路径，filePath 为首页/封面）
  final List<String> pages;

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
    this.spriteLayers,
    this.moods = const [],
    this.pages = const [],
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
    'spriteLayers': spriteLayers,
    'moods': moods,
    'pages': pages,
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
    spriteLayers: map['spriteLayers'] != null
        ? List<Map<String, dynamic>>.from(
            (map['spriteLayers'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : null,
    moods: map['moods'] != null
        ? List<Map<String, dynamic>>.from(
            (map['moods'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : const [],
    pages: map['pages'] != null
        ? List<String>.from(map['pages'] as List)
        : const [],
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
    List<Map<String, dynamic>>? spriteLayers,
    List<Map<String, dynamic>>? moods,
    List<String>? pages,
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
    spriteLayers: spriteLayers ?? this.spriteLayers,
    moods: moods ?? this.moods,
    pages: pages ?? this.pages,
  );
}
