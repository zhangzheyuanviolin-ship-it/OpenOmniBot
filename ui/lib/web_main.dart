import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/webchat/web_chat_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const WebChatApp());
}
