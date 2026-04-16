import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgentAvatarService {
  AgentAvatarService._();

  static const String storageKey = 'agentAvatarIndex';

  static const List<String> presetAvatars = <String>[
    'assets/avatar/default_avatar1.png',
    'assets/avatar/default_avatar2.png',
    'assets/avatar/default_avatar3.png',
    'assets/avatar/default_avatar4.png',
    'assets/avatar/default_avatar5.png',
    'assets/avatar/default_avatar6.png',
  ];

  static final ValueNotifier<int> avatarIndexNotifier = ValueNotifier<int>(0);
  static bool _isLoaded = false;

  static int normalizeIndex(int? index) {
    if (index == null || index < 0 || index >= presetAvatars.length) {
      return 0;
    }
    return index;
  }

  static String assetForIndex(int? index) {
    return presetAvatars[normalizeIndex(index)];
  }

  static Future<int> load() async {
    final prefs = await SharedPreferences.getInstance();
    final avatarIndex = normalizeIndex(prefs.getInt(storageKey));
    avatarIndexNotifier.value = avatarIndex;
    _isLoaded = true;
    return avatarIndex;
  }

  static Future<int> ensureLoaded() async {
    if (_isLoaded) {
      return avatarIndexNotifier.value;
    }
    return load();
  }

  static Future<int> setAvatarIndex(int index) async {
    final avatarIndex = normalizeIndex(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(storageKey, avatarIndex);
    _isLoaded = true;
    avatarIndexNotifier.value = avatarIndex;
    return avatarIndex;
  }
}
