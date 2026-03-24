import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/agent_browser_session_service.dart';

class ChatBrowserOverlay extends StatelessWidget {
  const ChatBrowserOverlay({
    super.key,
    required this.workspaceId,
    required this.title,
    required this.currentUrl,
    required this.onClose,
    required this.onDragDelta,
    required this.onResizeDelta,
  });

  final String workspaceId;
  final String title;
  final String currentUrl;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDragDelta;
  final ValueChanged<Offset> onResizeDelta;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title.trim().isEmpty ? 'Agent Browser' : title.trim();
    final resolvedUrl = currentUrl.trim();
    return Material(
      elevation: 18,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8E4F4)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F1930D9),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => onDragDelta(details.delta),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF6F9FF),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE3EBF8)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F1FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.language_rounded,
                            size: 18,
                            color: Color(0xFF1930D9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resolvedTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              if (resolvedUrl.isNotEmpty)
                                Text(
                                  resolvedUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF617390),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF617390),
                          ),
                          splashRadius: 18,
                          tooltip: '关闭浏览器窗口',
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFFF4F7FB),
                    child: Platform.isAndroid
                        ? AndroidView(
                            viewType:
                                AgentBrowserSessionService.platformViewType,
                            creationParams: <String, dynamic>{
                              'workspaceId': workspaceId,
                            },
                            creationParamsCodec: const StandardMessageCodec(),
                          )
                        : const Center(
                            child: Text(
                              '当前平台暂不支持浏览器工具视图',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF617390),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onResizeDelta(details.delta),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.bottomRight,
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    size: 16,
                    color: Color(0xFF90A2BC),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
