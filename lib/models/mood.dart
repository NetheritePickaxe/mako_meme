import 'package:flutter/material.dart';

class MemeMood {
  final String id;
  final String name;
  final IconData icon;
  final int colorValue;

  const MemeMood({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };

  factory MemeMood.fromMap(Map<String, dynamic> map) => MemeMood(
    id: map['id'] as String,
    name: map['name'] as String,
    icon: Icons.abc,
    colorValue: map['colorValue'] as int? ?? 0xFF6366F1,
  );
}

/// 预设使用场景/状态分类
const List<MemeMood> presetMoods = [
  MemeMood(id: 'roast', name: '怼人', icon: Icons.flash_on, colorValue: 0xFFFF6B6B),
  MemeMood(id: 'funny', name: '搞笑', icon: Icons.emoji_emotions, colorValue: 0xFFFFD93D),
  MemeMood(id: 'greet', name: '打招呼', icon: Icons.waving_hand, colorValue: 0xFF6BCB77),
  MemeMood(id: 'goodnight', name: '晚安', icon: Icons.nightlight_round, colorValue: 0xFF6C63FF),
  MemeMood(id: 'morning', name: '早安', icon: Icons.wb_sunny, colorValue: 0xFFFF9F43),
  MemeMood(id: 'speechless', name: '无语', icon: Icons.sentiment_neutral, colorValue: 0xFF8395A7),
  MemeMood(id: 'mocking', name: '阴阳怪气', icon: Icons.sentiment_very_dissatisfied, colorValue: 0xFFA29BFE),
  MemeMood(id: 'cute', name: '卖萌', icon: Icons.favorite, colorValue: 0xFFFD79A8),
  MemeMood(id: 'busy', name: '摸鱼', icon: Icons.coffee, colorValue: 0xFF00D2D3),
  MemeMood(id: 'egao', name: '恶搞', icon: Icons.auto_fix_high, colorValue: 0xFFFF7F50),
  MemeMood(id: 'cold', name: '冷笑话', icon: Icons.ac_unit, colorValue: 0xFF74B9FF),
  MemeMood(id: 'agree', name: '附议', icon: Icons.thumb_up, colorValue: 0xFF00B894),
  MemeMood(id: 'disagree', name: '反对', icon: Icons.thumb_down, colorValue: 0xFFE17055),
  MemeMood(id: 'shutup', name: '闭嘴', icon: Icons.volume_off, colorValue: 0xFF636E72),
  MemeMood(id: 'cry', name: '泪目', icon: Icons.water_drop, colorValue: 0xFF0984E3),
];

MemeMood? findMoodById(String? id) {
  if (id == null) return null;
  return presetMoods.where((m) => m.id == id).firstOrNull;
}
