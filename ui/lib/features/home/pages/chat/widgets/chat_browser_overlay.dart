import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/services/agent_browser_session_service.dart';

class ChatBrowserOverlay extends StatelessWidget {
  const ChatBrowserOverlay({
    super.key,
    required this.workspaceId,
    required this.title,
    required this.currentUrl,
    required this.onClose,
    required this.onDragDelta,
    required this.onResizeLeftDelta,
    required this.onResizeRightDelta,
  });

  final String workspaceId;
  final String title;
  final String currentUrl;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDragDelta;
  final ValueChanged<Offset> onResizeLeftDelta;
  final ValueChanged<Offset> onResizeRightDelta;

  @override
  Widget build(BuildContext context) {
    final defaultTitle = context.l10n.browserOverlayTitle;
    final resolvedTitle = title.trim().isEmpty ? defaultTitle : title.trim();
    final resolvedUrl = currentUrl.trim();
    final dragText = resolvedUrl.isNotEmpty
        ? '${resolvedTitle == defaultTitle ? '' : '$resolvedTitle · '}$resolvedUrl'
        : resolvedTitle;
    final creationParams = <String, dynamic>{
      'workspaceId': workspaceId,
      'currentUrl': currentUrl,
      'title': title,
    };
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
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF6F9FF),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE3EBF8)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dragText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF42526B),
                            ),
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
                          tooltip: context.l10n.browserOverlayClose,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFFF4F7FB),
                    child: switch (Platform.operatingSystem) {
                      'android' => AndroidView(
                        viewType: AgentBrowserSessionService.platformViewType,
                        creationParams: creationParams,
                        creationParamsCodec: const StandardMessageCodec(),
                      ),
                      'ios' => UiKitView(
                        viewType: AgentBrowserSessionService.platformViewType,
                        creationParams: creationParams,
                        creationParamsCodec: const StandardMessageCodec(),
                      ),
                      _ => Center(
                        child: Text(
                          context.l10n.browserOverlayUnsupported,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF617390),
                          ),
                        ),
                      ),
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              bottom: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onResizeLeftDelta(details.delta),
                child: const SizedBox(width: 32, height: 28),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onResizeRightDelta(details.delta),
                child: const SizedBox(width: 32, height: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
