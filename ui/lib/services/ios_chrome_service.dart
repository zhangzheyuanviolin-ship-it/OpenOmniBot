import 'dart:io';

import 'package:flutter/services.dart';

class IosChromeService {
  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/ios_chrome',
  );

  static Future<void> setBottomTabBarHidden(bool hidden) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setBottomTabBarHidden', {
        'hidden': hidden,
      });
    } on PlatformException {
      // Ignore missing iOS shell chrome support on non-hosted runtimes.
    }
  }
}
