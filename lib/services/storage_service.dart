import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/meme.dart';
import '../models/folder.dart';

// Web 端使用 dart:html 的 localStorage
// ignore: undefined_hidden_name
import 'dart:html' show window;

/// JSON 文件存储 — 跨平台，Web 上使用 localStorage
class StorageService {
  final Uuid _uuid = const Uuid();
  List<Meme> _memes = [];
  List<MemeFolder> _folders = [];
  String? _basePath;

  /// Web 上存储图片字节（key = filePath, value = bytes）
  final Map<String, Uint8List> _webBytes = {};

  String get basePath => _basePath ?? '.';

  Future<void> init() async {
    if (kIsWeb) {
      _loadFromWeb();
    } else {
      final dir = await getApplicationDocumentsDirectory();
      _basePath = p.join(dir.path, 'mako_meme');
      final storageDir = Directory(_basePath!);
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }
      _loadFromFile();
    }
  }

  // ======================== Web 存储 ========================

  void _loadFromWeb() {
    try {
      // ignore: undefined_prefixed_name
      final raw = _getWebStorage('mako_memes');
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _memes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        _folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
        // 恢复图片字节缓存（base64）
        final bytes = data['stickerBytes'] as Map<String, dynamic>? ?? {};
        for (final entry in bytes.entries) {
          _webBytes[entry.key] = base64Decode(entry.value as String);
        }
      }
    } catch (_) {}
  }

  void _saveToWeb() {
    try {
      // 序列化图片字节（限制单张 1MB 避免 localStorage 溢出）
      final bytesMap = <String, String>{};
      for (final entry in _webBytes.entries) {
        if (entry.value.length <= 1024 * 1024) {
          bytesMap[entry.key] = base64Encode(entry.value);
        }
      }
      final data = jsonEncode({
        'memes': _memes.map((m) => m.toMap()).toList(),
        'folders': _folders.map((f) => f.toMap()).toList(),
        'stickerBytes': bytesMap,
      });
      _setWebStorage('mako_memes', data);
    } catch (_) {}
  }

  static String? _getWebStorage(String key) {
    try {
      return window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static void _setWebStorage(String key, String value) {
    try {
      window.localStorage[key] = value;
    } catch (_) {}
  }

  // ======================== 文件存储 (Native) ========================

  void _loadFromFile() {
    final memesFile = File(p.join(_basePath!, 'memes.json'));
    if (memesFile.existsSync()) {
      try {
        final data = jsonDecode(memesFile.readAsStringSync()) as Map<String, dynamic>;
        _memes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        _folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      } catch (_) {}
    }
  }

  void _saveToFile() {
    try {
      final memesFile = File(p.join(_basePath!, 'memes.json'));
      memesFile.writeAsStringSync(jsonEncode({
        'memes': _memes.map((m) => m.toMap()).toList(),
        'folders': _folders.map((f) => f.toMap()).toList(),
      }));
    } catch (_) {}
  }

  void _save() {
    if (kIsWeb) {
      _saveToWeb();
    } else {
      _saveToFile();
    }
  }

  // ======================== Meme CRUD ========================

  List<Meme> getAllMemes() => List.unmodifiable(_memes);
  List<MemeFolder> getAllFolders() => List.unmodifiable(_folders);

  String getFullMemePath(String relPath) {
    if (kIsWeb) return relPath;
    final base = _basePath;
    if (base == null) return relPath;
    return p.join(base, relPath);
  }

  Future<Meme> importFile(PlatformFile file, {String? folderId}) async {
    final id = _uuid.v4();
    final ext = _guessExt(file.name);
    final fileName = '$id$ext';
    final now = DateTime.now();

    Uint8List? bytes;
    String filePath;

    if (kIsWeb) {
      // Web: 从内存读取
      bytes = file.bytes;
      filePath = 'memes/$fileName';
      if (bytes != null) {
        _webBytes[filePath] = bytes;
      }
    } else {
      // Native: 复制文件到存储目录
      filePath = 'memes/$fileName';
      final dest = File(p.join(_basePath!, filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
      } else if (file.bytes != null) {
        await dest.writeAsBytes(file.bytes!);
      }
    }

    final meme = Meme(
      id: id,
      name: p.basenameWithoutExtension(file.name),
      filePath: filePath,
      folderId: folderId,
      tags: [],
      createdAt: now,
      mimeType: _guessMime(ext),
      fileSize: bytes?.length ?? file.size,
      type: 'image',
    );
    _memes.insert(0, meme);
    _save();
    return meme;
  }

  /// 获取图片字节（跨平台）
  Future<Uint8List?> readMemeBytes(String filePath) async {
    if (kIsWeb) {
      return _webBytes[filePath];
    }
    try {
      final file = File(p.join(_basePath!, filePath));
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<List<Meme>> importFiles(List<PlatformFile> files, {String? folderId}) async {
    final results = <Meme>[];
    for (final file in files) {
      results.add(await importFile(file, folderId: folderId));
    }
    return results;
  }

  Future<Meme> importText(String text, {String? name, String? folderId, List<String> tags = const [], String? mood}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final meme = Meme(
      id: id,
      name: name ?? text.substring(0, text.length.clamp(0, 30)),
      filePath: '',
      folderId: folderId,
      tags: tags,
      createdAt: now,
      mimeType: '',
      fileSize: text.length,
      mood: mood,
      type: 'text',
      textContent: text,
    );
    _memes.insert(0, meme);
    _save();
    return meme;
  }

  Future<void> deleteMeme(String id) async {
    final meme = _memes.where((m) => m.id == id).firstOrNull;
    if (meme != null && !kIsWeb && meme.filePath.isNotEmpty) {
      final file = File(p.join(_basePath!, meme.filePath));
      if (await file.exists()) await file.delete();
    }
    _memes.removeWhere((m) => m.id == id);
    _save();
  }

  Future<void> deleteMemes(List<String> ids) async {
    for (final id in ids) {
      await deleteMeme(id);
    }
  }

  Future<void> renameMeme(String id, String newName) async {
    final idx = _memes.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _memes[idx] = _memes[idx].copyWith(name: newName);
      _save();
    }
  }

  Future<void> toggleFavorite(String id) async {
    final meme = _memes.where((m) => m.id == id).firstOrNull;
    if (meme != null) {
      meme.isFavorite = !meme.isFavorite;
      _save();
    }
  }

  Future<void> setMood(String memeId, String? moodId) async {
    final meme = _memes.where((m) => m.id == memeId).firstOrNull;
    if (meme != null) {
      meme.mood = moodId;
      _save();
    }
  }

  Future<void> setMoodBatch(List<String> ids, String? moodId) async {
    for (final id in ids) {
      await setMood(id, moodId);
    }
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    final idx = _memes.indexWhere((m) => m.id == memeId);
    if (idx != -1) {
      _memes[idx] = _memes[idx].copyWith(folderId: folderId);
      _save();
    }
  }

  Future<void> moveToFolderBatch(List<String> ids, String? folderId) async {
    for (final id in ids) {
      await moveToFolder(id, folderId);
    }
  }

  // ======================== Folder CRUD ========================

  Future<MemeFolder> createFolder(String name) async {
    final folder = MemeFolder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    _folders.add(folder);
    _save();
    return folder;
  }

  Future<void> updateFolder(MemeFolder folder) async {
    final i = _folders.indexWhere((f) => f.id == folder.id);
    if (i != -1) {
      _folders[i] = folder;
      _save();
    }
  }

  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    // 将文件夹内的表情移出
    for (var i = 0; i < _memes.length; i++) {
      if (_memes[i].folderId == id) {
        _memes[i] = _memes[i].copyWith(folderId: null);
      }
    }
    _save();
  }

  // ======================== Utility ========================

  String _guessMime(String ext) {
    switch (ext) {
      case '.png': return 'image/png';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.bmp': return 'image/bmp';
      default: return 'image/png';
    }
  }

  String _guessExt(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '.png';
    return fileName.substring(dot).toLowerCase();
  }
}
