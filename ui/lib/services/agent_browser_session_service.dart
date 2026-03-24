import 'package:flutter/services.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';

class AgentBrowserSessionService {
  AgentBrowserSessionService._();

  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/AgentBrowserSession',
  );

  static const String platformViewType =
      'cn.com.omnimind.bot/agent_browser_view';

  static Future<ChatBrowserSessionSnapshot?> getLiveSessionSnapshot() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getLiveBrowserSessionSnapshot',
      );
      if (result == null || result['available'] != true) {
        return null;
      }
      return ChatBrowserSessionSnapshot.fromMap(result);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
