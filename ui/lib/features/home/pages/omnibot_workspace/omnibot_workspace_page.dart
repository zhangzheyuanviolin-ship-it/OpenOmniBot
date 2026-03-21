import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/omnibot_workspace/widgets/omnibot_workspace_browser.dart';
import 'package:ui/widgets/common_app_bar.dart';

class OmnibotWorkspacePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: 'Workspace', primary: true),
      body: OmnibotWorkspaceBrowser(
        workspacePath: workspacePath,
        workspaceShellPath: workspaceShellPath,
      ),
    );
  }
}
