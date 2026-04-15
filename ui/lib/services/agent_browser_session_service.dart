import 'package:flutter/services.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/services/host_platform_bridge.dart';

class AgentBrowserSessionService {
  AgentBrowserSessionService._();

  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/AgentBrowserSession',
  );

  static const String platformViewType =
      'cn.com.omnimind.bot/agent_browser_view';

  static Future<ChatBrowserSessionSnapshot?> getLiveSessionSnapshot() async {
    final bridgeSnapshot =
        await HostPlatformBridge.tryGetBrowserSessionSnapshot();
    if (bridgeSnapshot != null && bridgeSnapshot.available) {
      return ChatBrowserSessionSnapshot(
        available: bridgeSnapshot.available,
        workspaceId: bridgeSnapshot.workspaceId,
        activeTabId: bridgeSnapshot.activeTabId,
        currentUrl: bridgeSnapshot.currentUrl,
        title: bridgeSnapshot.title,
        userAgentProfile: bridgeSnapshot.userAgentProfile,
      );
    }
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
