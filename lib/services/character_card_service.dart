import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// SillyTavern 角色卡解析服务。
///
/// 角色卡数据存储在 PNG 的 tEXt / iTXt chunk 中：
/// - keyword: `chara`（V2/V1）或 `ccv3`（V3）
/// - value: **base64 编码**的 JSON 字符串（SillyTavern 官方规范）
///
/// V2 格式：`{spec: "chara_card_v2", spec_version: "2.0", data: {name, description, ...}}`
/// V1 格式：`{name, description, personality, scenario, first_mes, mes_example}`
///
/// 参考：https://github.com/malfoyslastname/character-card-spec-v2
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
        return _decodeCardJson(metaData);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parsePngMeta(Uint8List bytes) {
    try {
      final metaData = _extractTextChunk(bytes);
      if (metaData != null) {
        return _decodeCardJson(metaData);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 扫描 PNG 字节流，找到 chara / ccv3 关键字所在的 tEXt / iTXt chunk，返回原始文本（可能为 base64）。
  static String? _extractTextChunk(Uint8List bytes) {
    try {
      var offset = 8;
      while (offset + 12 <= bytes.length) {
        final length = _readInt32(bytes, offset);
        offset += 4;

        final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        offset += 4;

        if (type == 'iTXt' || type == 'tEXt') {
          if (length > 0 && offset + length <= bytes.length) {
            final chunkData = bytes.sublist(offset, offset + length);
            final result = _parseTextChunk(type, chunkData);
            if (result != null) return result;
          }
          offset += length + 4;
        } else {
          offset += length + 4;
        }
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

  /// 从文件流式扫描 PNG，找到 chara / ccv3 关键字所在的 tEXt / iTXt chunk。
  /// 不会一次性读取整个文件，超大图片也安全。
  static Future<String?> _extractChunkFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    final raf = await file.open();
    try {
      final header = await raf.read(8);
      if (header.length < 8 || !_listEq(header, signature)) return null;

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
            await raf.setPosition(await raf.position() + 4);
            final result = _parseTextChunk(type, data);
            if (result != null) return result;
          } else {
            await raf.setPosition(await raf.position() + length + 4);
          }
        } else {
          await raf.setPosition(await raf.position() + length + 4);
        }
      }
    } catch (_) {} finally {
      await raf.close();
    }
    return null;
  }

  /// 解析单个 tEXt / iTXt chunk 的原始文本。仅返回 keyword 为 chara / ccv3 的内容。
  static String? _parseTextChunk(String type, Uint8List data) {
    try {
      final keywordEnd = data.indexOf(0);
      if (keywordEnd == -1) return null;
      final keyword = String.fromCharCodes(data.sublist(0, keywordEnd));
      final lower = keyword.toLowerCase();
      // SillyTavern: chara = V1/V2, ccv3 = V3
      if (lower != 'chara' && lower != 'ccv3') return null;
      if (type == 'iTXt') {
        // iTXt: keyword\0 compressionFlag(1) compressionMethod(1) languageTag\0 translatedKeyword\0 text
        var dataOffset = keywordEnd + 1 + 1 + 1;
        final langEnd = data.indexOf(0, dataOffset);
        if (langEnd == -1) return null;
        dataOffset = langEnd + 1;
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

  /// 把 chunk 中提取出的文本解码为角色卡 JSON。
  /// SillyTavern 规范：文本是 base64 编码的 JSON；少数实现可能直接存 JSON，做兼容处理。
  static Map<String, dynamic>? _decodeCardJson(String raw) {
    String jsonStr;
    // 1. 优先尝试 base64 解码（SillyTavern 官方规范）
    try {
      final decoded = utf8.decode(base64.decode(raw.trim()));
      // 验证解码结果是合法 JSON
      jsonDecode(decoded);
      jsonStr = decoded;
    } catch (_) {
      // base64 解码失败，尝试当作直接 JSON
      try {
        jsonDecode(raw);
        jsonStr = raw;
      } catch (_) {
        return null;
      }
    }
    final parsed = jsonDecode(jsonStr);
    if (parsed is! Map<String, dynamic>) return null;
    return _normalizeCard(parsed);
  }

  /// 规范化角色卡：V2 嵌套 data 结构展开为扁平字段，V1 直接返回。
  static Map<String, dynamic> _normalizeCard(Map<String, dynamic> raw) {
    // V2/V3: {spec, spec_version, data: {...}}
    if (raw.containsKey('data') && raw['data'] is Map) {
      final data = Map<String, dynamic>.from(raw['data'] as Map);
      // 保留 spec 信息
      if (raw['spec'] != null) data['spec'] = raw['spec'];
      if (raw['spec_version'] != null) data['spec_version'] = raw['spec_version'];
      return data;
    }
    // V1: 顶层就是字段
    return raw;
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
