import 'package:drift/drift.dart';

/// 命名空间（分类文件夹）
@DataClassName('NamespaceData')
class Namespaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()(); // 十六进制颜色码
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 表情包包
@DataClassName('StickerPackData')
class StickerPacks extends Table {
  TextColumn get id => text()();
  TextColumn get namespaceId => text().references(Namespaces, #id, onDelete: KeyAction.setNull).nullable()();
  TextColumn get name => text()();
  TextColumn get iconPath => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get tags => text().nullable()();           // 逗号分隔的包标签
  TextColumn get metadata => text().nullable()();       // JSON 格式的扩展属性
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 表情包里的单个表情
@DataClassName('StickerData')
class Stickers extends Table {
  TextColumn get id => text()();
  TextColumn get packId => text().references(StickerPacks, #id, onDelete: KeyAction.cascade)();
  TextColumn get filename => text()();      // 原始文件名
  TextColumn get storedPath => text()();    // 复制到应用目录后的路径
  TextColumn get mimeType => text()();      // image/png, image/gif, image/webp
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get tags => text().nullable()(); // 逗号分隔标签
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
