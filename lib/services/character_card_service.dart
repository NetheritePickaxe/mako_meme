import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class CharacterCardService {
  static Future<Map<String, dynamic>?> parseFromBytes(Uint8List bytes) async {
    try {
      return _parsePngMeta(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 从文件路径流式读取 PNG chunk，避免一次性载入超大文件
  static Future<Map<String, dynamic>?> parseFromPath(String path) async {
    try {
      final metaData = await _extractChunkFromFile(path);
      if (metaData != null) {
        return jsonDecode(metaData) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parsePngMeta(Uint8List bytes) {
    try {
      final metaData = _extractITxtChunk(bytes);
      if (metaData != null) {
        return jsonDecode(metaData) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractITxtChunk(Uint8List bytes) {
    try {
      var offset = 8;
      while (offset + 12 <= bytes.length) {
        final length = _readInt32(bytes, offset);
        offset += 4;

        final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        offset += 4;

        if (type == 'iTXt') {
          final chunkData = bytes.sublist(offset, offset + length);
          final keywordEnd = chunkData.indexOf(0);
          if (keywordEnd == -1) {
            offset += length + 4;
            continue;
          }

          final keyword = String.fromCharCodes(chunkData.sublist(0, keywordEnd));
          if (keyword.toLowerCase() == 'chara') {
            var dataOffset = keywordEnd + 1 + 1 + 1 + 1;
            if (dataOffset < chunkData.length) {
              final textData = chunkData.sublist(dataOffset);
              return utf8.decode(textData);
            }
          }
        } else if (type == 'tEXt') {
          final chunkData = bytes.sublist(offset, offset + length);
          final keywordEnd = chunkData.indexOf(0);
          if (keywordEnd == -1) {
            offset += length + 4;
            continue;
          }

          final keyword = String.fromCharCodes(chunkData.sublist(0, keywordEnd));
          if (keyword.toLowerCase() == 'chara') {
            final textData = chunkData.sublist(keywordEnd + 1);
            return utf8.decode(textData);
          }
        }

        offset += length + 4;
      }
    } catch (_) {}
    return null;
  }

  static int _readInt32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
           (bytes[offset + 1] << 16) |
           (bytes[offset + 2] << 8) |
           bytes[offset + 3];
  }

  /// 从文件流式扫描 PNG，找到 chara 关键字所在的 iTXt/tEXt chunk。
  /// 不会一次性读取整个文件，超大图片也安全。
  static Future<String?> _extractChunkFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    final raf = await file.open();
    try {
      // 验证 PNG 签名
      final header = await raf.read(8);
      if (header.length < 8 || !_listEq(header, signature)) return null;

      // 单次 chunk 最多读取 16MB，避免单 chunk 异常导致 OOM
      const maxChunkSize = 16 * 1024 * 1024;

      while (true) {
        final lengthBytes = await raf.read(4);
        if (lengthBytes.length < 4) break;
        final length = (lengthBytes[0] << 24) |
                       (lengthBytes[1] << 16) |
                       (lengthBytes[2] << 8) |
                       lengthBytes[3];
        final typeBytes = await raf.read(4);
        if (typeBytes.length < 4) break;
        final type = String.fromCharCodes(typeBytes);

        if (type == 'IEND') break;

        if (type == 'iTXt' || type == 'tEXt') {
          if (length > 0 && length <= maxChunkSize) {
            final data = await raf.read(length);
            // 跳过 CRC
            await raf.skip(4);
            final result = _parseTextChunk(type, data);
            if (result != null) return result;
          } else {
            // 超大或空 chunk，跳过 data + CRC
            await raf.skip(length + 4);
          }
        } else {
          // 跳过 chunk 数据 + 4 字节 CRC
          await raf.skip(length + 4);
        }
      }
    } catch (_) {} finally {
      await raf.close();
    }
    return null;
  }

  static String? _parseTextChunk(String type, Uint8List data) {
    try {
      final keywordEnd = data.indexOf(0);
      if (keywordEnd == -1) return null;
      final keyword = String.fromCharCodes(data.sublist(0, keywordEnd));
      if (keyword.toLowerCase() != 'chara') return null;
      if (type == 'iTXt') {
        // iTXt: keyword\0 compressionFlag(1) compressionMethod(1) languageTag\0 translatedKeyword\0 text
        var dataOffset = keywordEnd + 1 + 1 + 1;
        // 跳过 languageTag\0
        final langEnd = data.indexOf(0, dataOffset);
        if (langEnd == -1) return null;
        dataOffset = langEnd + 1;
        // 跳过 translatedKeyword\0
        final transEnd = data.indexOf(0, dataOffset);
        if (transEnd == -1) return null;
        dataOffset = transEnd + 1;
        if (dataOffset >= data.length) return null;
        return utf8.decode(data.sublist(dataOffset));
      } else {
        // tEXt: keyword\0 text
        return utf8.decode(data.sublist(keywordEnd + 1));
      }
    } catch (_) {
      return null;
    }
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool isValidCharacterCard(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data.containsKey('name') && (data['name'] as String?)?.isNotEmpty == true;
  }

  static String getName(Map<String, dynamic> data) {
    return data['name'] as String? ?? data['character_name'] as String? ?? '未知角色';
  }

  static Map<String, dynamic> createEmptyCard() {
    return {
      'name': '',
      'description': '',
      'personality': '',
      'scenario': '',
      'first_mes': '',
      'mes_example': '',
      'tags': [],
      'version': '2',
    };
  }

  static Map<String, dynamic> sanitizeCard(Map<String, dynamic> data) {
    return {
      'name': data['name'] as String? ?? '',
      'description': data['description'] as String? ?? '',
      'personality': data['personality'] as String? ?? '',
      'scenario': data['scenario'] as String? ?? '',
      'first_mes': data['first_mes'] as String? ?? '',
      'mes_example': data['mes_example'] as String? ?? '',
      'tags': (data['tags'] as List?)?.cast<String>() ?? [],
      'version': data['version'] as String? ?? '2',
      'system_prompt': data['system_prompt'] as String?,
      'character_book': data['character_book'] as Map<String, dynamic>?,
      'alternate_greetings': data['alternate_greetings'] as List?,
    };
  }
}
