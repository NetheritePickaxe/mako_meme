import 'dart:convert';
import 'package:flutter/foundation.dart';

class CharacterCardService {
  static Future<Map<String, dynamic>?> parseFromBytes(Uint8List bytes) async {
    try {
      return _parsePngMeta(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> parseFromPath(String path) async {
    return null;
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
