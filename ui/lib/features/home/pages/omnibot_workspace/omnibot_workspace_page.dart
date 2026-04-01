import 'package:flutter/material.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/omnibot_workspace/widgets/omnibot_workspace_browser.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/widgets/app_background_widgets.dart';
import 'package:ui/widgets/common_app_bar.dart';

class OmnibotWorkspacePage extends StatefulWidget {
  final String workspacePath;
  final String? workspaceId;
  final String? workspaceShellPath;

  const OmnibotWorkspacePage({
    super.key,
    required this.workspacePath,
    this.workspaceId,
    this.workspaceShellPath,
  });

  @override
  State<OmnibotWorkspacePage> createState() => _OmnibotWorkspacePageState();
}

class _OmnibotWorkspacePageState extends State<OmnibotWorkspacePage> {
  final GlobalKey<OmnibotWorkspaceBrowserState> _browserKey =
      GlobalKey<OmnibotWorkspaceBrowserState>();
  bool _browserCanGoUp = false;

  void _handleBackPressed() {
    final browserState = _browserKey.currentState;
    if (browserState != null && browserState.canGoUp) {
      browserState.openParentDirectory();
    } else {
      GoRouterManager.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppBackgroundConfig>(
      valueListenable: AppBackgroundService.notifier,
      builder: (context, backgroundConfig, _) {
        final backgroundActive = backgroundConfig.isActive;
        return PopScope(
          canPop: !_browserCanGoUp,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _handleBackPressed();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AppBackgroundLayer(
                    config: backgroundConfig,
                    fallbackColor: const Color(0xFFF9FCFF),
                    layerKey: const ValueKey('workspace-page-background'),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      CommonAppBar(
                        title: 'Workspace',
                        primary: false,
                        backgroundColor: backgroundSurfaceColor(
                          translucent: backgroundActive,
                          opacity: 0.68,
                        ),
                        onBackPressed: _handleBackPressed,
                      ),
                      Expanded(
                        child: OmnibotWorkspaceBrowser(
                          key: _browserKey,
                          workspacePath: widget.workspacePath,
                          workspaceShellPath: widget.workspaceShellPath,
                          enableSystemBackHandler: false,
                          translucentSurfaces: backgroundActive,
                          onCanGoUpChanged: (canGoUp) {
                            if (_browserCanGoUp == canGoUp || !mounted) {
                              return;
                            }
                            setState(() {
                              _browserCanGoUp = canGoUp;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
