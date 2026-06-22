import 'package:drift/drift.dart';

/// 表情包包
@DataClassName('StickerPackData')
class StickerPacks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get iconPath => text().nullable()();
  TextColumn get description => text().nullable()();
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
