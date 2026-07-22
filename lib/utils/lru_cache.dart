import 'dart:collection';
import 'dart:typed_data';

class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  LruCache(this.maxSize);

  V? get(K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  bool containsKey(K key) => _map.containsKey(key);

  void clear() => _map.clear();
}

final LruCache<String, Uint8List?> thumbCache = LruCache(50);
