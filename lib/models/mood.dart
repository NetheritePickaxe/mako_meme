import 'package:flutter/material.dart';

/// 场景/情绪分类 — 支持预设和自定义
class MemeMood {
  final String id;
  final String name;
  final String iconName; // Material icon 名称，如 "flash_on"
  final String? iconFontFamily;
  final int colorValue;
  final bool isPreset;

  const MemeMood({
    required this.id,
    required this.name,
    required this.iconName,
    this.iconFontFamily,
    required this.colorValue,
    this.isPreset = false,
  });

  Color get color => Color(colorValue);

  /// 通过 iconName 从预定义映射中获取 IconData（const-safe）
  IconData get icon => iconFromName(iconName);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'iconFontFamily': iconFontFamily,
    'colorValue': colorValue,
    'isPreset': isPreset,
  };

  factory MemeMood.fromMap(Map<String, dynamic> map) => MemeMood(
    id: map['id'] as String,
    name: map['name'] as String,
    iconName: map['iconName'] as String? ?? 'abc',
    iconFontFamily: map['iconFontFamily'] as String?,
    colorValue: map['colorValue'] as int? ?? 0xFF6366F1,
    isPreset: map['isPreset'] as bool? ?? false,
  );

  MemeMood copyWith({
    String? id,
    String? name,
    String? iconName,
    String? iconFontFamily,
    int? colorValue,
    bool? isPreset,
  }) => MemeMood(
    id: id ?? this.id,
    name: name ?? this.name,
    iconName: iconName ?? this.iconName,
    iconFontFamily: iconFontFamily ?? this.iconFontFamily,
    colorValue: colorValue ?? this.colorValue,
    isPreset: isPreset ?? this.isPreset,
  );
}

/// 根据名称查找 IconData（所有 icon 参数都是 const 的，tree-shaking 友好）
IconData iconFromName(String name) {
  return _iconMap[name] ?? Icons.abc;
}

const Map<String, IconData> _iconMap = {
  'flash_on': Icons.flash_on,
  'emoji_emotions': Icons.emoji_emotions,
  'waving_hand': Icons.waving_hand,
  'nightlight_round': Icons.nightlight_round,
  'wb_sunny': Icons.wb_sunny,
  'sentiment_neutral': Icons.sentiment_neutral,
  'sentiment_very_dissatisfied': Icons.sentiment_very_dissatisfied,
  'favorite': Icons.favorite,
  'coffee': Icons.coffee,
  'auto_fix_high': Icons.auto_fix_high,
  'ac_unit': Icons.ac_unit,
  'thumb_up': Icons.thumb_up,
  'thumb_down': Icons.thumb_down,
  'volume_off': Icons.volume_off,
  'water_drop': Icons.water_drop,
  'abc': Icons.abc,
  'add': Icons.add,
  'add_circle': Icons.add_circle,
  'alarm': Icons.alarm,
  'anchor': Icons.anchor,
  'archive': Icons.archive,
  'arrow_back': Icons.arrow_back,
  'arrow_forward': Icons.arrow_forward,
  'audiotrack': Icons.audiotrack,
  'block': Icons.block,
  'bolt': Icons.bolt,
  'book': Icons.book,
  'brush': Icons.brush,
  'build': Icons.build,
  'cake': Icons.cake,
  'celebration': Icons.celebration,
  'chat': Icons.chat,
  'check': Icons.check,
  'check_circle': Icons.check_circle,
  'close': Icons.close,
  'cloud': Icons.cloud,
  'color_lens': Icons.color_lens,
  'construction': Icons.construction,
  'create': Icons.create,
  'dark_mode': Icons.dark_mode,
  'delete': Icons.delete,
  'design_services': Icons.design_services,
  'diamond': Icons.diamond,
  'done': Icons.done,
  'downloading': Icons.downloading,
  'edit': Icons.edit,
  'email': Icons.email,
  'emoji_events': Icons.emoji_events,
  'emoji_flags': Icons.emoji_flags,
  'emoji_nature': Icons.emoji_nature,
  'emoji_objects': Icons.emoji_objects,
  'emoji_people': Icons.emoji_people,
  'emoji_symbols': Icons.emoji_symbols,
  'emoji_transportation': Icons.emoji_transportation,
  'energy_savings_leaf': Icons.energy_savings_leaf,
  'face': Icons.face,
  'family_restroom': Icons.family_restroom,
  'fast_forward': Icons.fast_forward,
  'fast_rewind': Icons.fast_rewind,
  'file_copy': Icons.file_copy,
  'file_download': Icons.file_download,
  'file_upload': Icons.file_upload,
  'filter_vintage': Icons.filter_vintage,
  'fireplace': Icons.fireplace,
  'flag': Icons.flag,
  'flare': Icons.flare,
  'flight': Icons.flight,
  'folder': Icons.folder,
  'forest': Icons.forest,
  'gavel': Icons.gavel,
  'gesture': Icons.gesture,
  'gif': Icons.gif,
  'golf_course': Icons.golf_course,
  'grass': Icons.grass,
  'groups': Icons.groups,
  'headphones': Icons.headphones,
  'heart_broken': Icons.heart_broken,
  'history': Icons.history,
  'home': Icons.home,
  'icecream': Icons.icecream,
  'image': Icons.image,
  'info': Icons.info,
  'insert_emoticon': Icons.insert_emoticon,
  'invert_colors': Icons.invert_colors,
  'kitesurfing': Icons.kitesurfing,
  'light': Icons.light,
  'light_mode': Icons.light_mode,
  'link': Icons.link,
  'local_fire_department': Icons.local_fire_department,
  'local_pizza': Icons.local_pizza,
  'lock': Icons.lock,
  'luggage': Icons.luggage,
  'mail': Icons.mail,
  'map': Icons.map,
  'mood': Icons.mood,
  'mood_bad': Icons.mood_bad,
  'music_note': Icons.music_note,
  'nature': Icons.nature,
  'nightlife': Icons.nightlife,
  'notifications': Icons.notifications,
  'palette': Icons.palette,
  'park': Icons.park,
  'pets': Icons.pets,
  'pin': Icons.pin,
  'place': Icons.place,
  'polymer': Icons.polymer,
  'public': Icons.public,
  'question_answer': Icons.question_answer,
  'recommend': Icons.recommend,
  'rocket': Icons.rocket,
  'satellite': Icons.satellite,
  'school': Icons.school,
  'search': Icons.search,
  'self_improvement': Icons.self_improvement,
  'send': Icons.send,
  'sentiment_satisfied': Icons.sentiment_satisfied,
  'sentiment_dissatisfied': Icons.sentiment_dissatisfied,
  'settings': Icons.settings,
  'share': Icons.share,
  'shield': Icons.shield,
  'shopping_cart': Icons.shopping_cart,
  'sledding': Icons.sledding,
  'smartphone': Icons.smartphone,
  'smoke_free': Icons.smoke_free,
  'snowboarding': Icons.snowboarding,
  'snowmobile': Icons.snowmobile,
  'spa': Icons.spa,
  'sports_bar': Icons.sports_bar,
  'sports_esports': Icons.sports_esports,
  'star': Icons.star,
  'store': Icons.store,
  'support': Icons.support,
  'surfing': Icons.surfing,
  'tag': Icons.tag,
  'terrain': Icons.terrain,
  'theater_comedy': Icons.theater_comedy,
  'thumb_up_alt': Icons.thumb_up_alt,
  'thunderstorm': Icons.thunderstorm,
  'toys': Icons.toys,
  'travel_explore': Icons.travel_explore,
  'volcano': Icons.volcano,
  'wallet': Icons.wallet,
  'warning': Icons.warning,
  'wc': Icons.wc,
  'weekend': Icons.weekend,
  'whatshot': Icons.whatshot,
  'wifi': Icons.wifi,
  'workspaces': Icons.workspaces,
  'yard': Icons.yard,
  'zoom_in': Icons.zoom_in,
  'zoom_out': Icons.zoom_out,
};

/// 所有可用图标名称列表（供图标选择器使用）
List<String> get allIconNames => _iconMap.keys.toList()..sort();

/// 预设场景（内置，不可删除）
const List<MemeMood> presetMoods = [
  MemeMood(id: 'roast', name: '怼人', iconName: 'flash_on', colorValue: 0xFFFF6B6B, isPreset: true),
  MemeMood(id: 'funny', name: '搞笑', iconName: 'emoji_emotions', colorValue: 0xFFFFD93D, isPreset: true),
  MemeMood(id: 'greet', name: '打招呼', iconName: 'waving_hand', colorValue: 0xFF6BCB77, isPreset: true),
  MemeMood(id: 'goodnight', name: '晚安', iconName: 'nightlight_round', colorValue: 0xFF6C63FF, isPreset: true),
  MemeMood(id: 'morning', name: '早安', iconName: 'wb_sunny', colorValue: 0xFFFF9F43, isPreset: true),
  MemeMood(id: 'speechless', name: '无语', iconName: 'sentiment_neutral', colorValue: 0xFF8395A7, isPreset: true),
  MemeMood(id: 'mocking', name: '阴阳怪气', iconName: 'sentiment_very_dissatisfied', colorValue: 0xFFA29BFE, isPreset: true),
  MemeMood(id: 'cute', name: '卖萌', iconName: 'favorite', colorValue: 0xFFFD79A8, isPreset: true),
  MemeMood(id: 'busy', name: '摸鱼', iconName: 'coffee', colorValue: 0xFF00D2D3, isPreset: true),
  MemeMood(id: 'egao', name: '恶搞', iconName: 'auto_fix_high', colorValue: 0xFFFF7F50, isPreset: true),
  MemeMood(id: 'cold', name: '冷笑话', iconName: 'ac_unit', colorValue: 0xFF74B9FF, isPreset: true),
  MemeMood(id: 'agree', name: '附议', iconName: 'thumb_up', colorValue: 0xFF00B894, isPreset: true),
  MemeMood(id: 'disagree', name: '反对', iconName: 'thumb_down', colorValue: 0xFFE17055, isPreset: true),
  MemeMood(id: 'shutup', name: '闭嘴', iconName: 'volume_off', colorValue: 0xFF636E72, isPreset: true),
  MemeMood(id: 'cry', name: '泪目', iconName: 'water_drop', colorValue: 0xFF0984E3, isPreset: true),
];

MemeMood? findMoodById(String? id) {
  if (id == null) return null;
  return presetMoods.where((m) => m.id == id).firstOrNull;
}
