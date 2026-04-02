import 'package:flutter/services.dart';

/// 应用状态服务 - 处理与Android应用状态相关的通信
class AppStateService {
  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/app_state',
  );

  /// 通知原生层初始化半屏Flutter引擎
  /// 应在主Flutter页面加载完成后调用
  static Future<bool> initHalfScreenEngine() async {
    final initStart = DateTime.now();
    print('📱 [FlutterStartup] Calling native to init half screen engine');

    try {
      final result = await _channel.invokeMethod('initHalfScreenEngine');
      print(
        '✅ [FlutterStartup] Half screen engine init requested, cost: ${DateTime.now().difference(initStart).inMilliseconds}ms',
      );
      return result == true;
    } catch (e) {
      print('⚠️  [FlutterStartup] Failed to init half screen engine: $e');
      return false;
    }
  }

  static Future<bool> exitApp() async {
    try {
      final result = await _channel.invokeMethod('exitApp');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> navigateBackToChat() async {
    try {
      final result = await _channel.invokeMethod('navigateBackToChat');
      return result == true;
    } catch (e) {
      return false;
    }
  }
}
