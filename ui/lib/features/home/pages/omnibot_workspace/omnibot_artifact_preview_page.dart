import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/omnibot_markdown_body.dart';
import 'package:ui/widgets/omnibot_resource_widgets.dart';

class OmnibotArtifactPreviewPage extends StatefulWidget {
  final String path;
  final String? uri;
  final String title;
  final String previewKind;
  final String mimeType;
  final String? shellPath;
  final bool exists;

  const OmnibotArtifactPreviewPage({
    super.key,
    required this.path,
    required this.title,
    required this.previewKind,
    required this.mimeType,
    this.shellPath,
    this.uri,
    this.exists = true,
  });

  @override
  State<OmnibotArtifactPreviewPage> createState() =>
      _OmnibotArtifactPreviewPageState();
}

class _OmnibotArtifactPreviewPageState
    extends State<OmnibotArtifactPreviewPage> {
  static const String _externalLinkIconAsset =
      'assets/home/workspace_external_link_icon.svg';

  String? _textContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    if (!widget.exists) return;
    if (widget.previewKind != 'text' && widget.previewKind != 'code') return;
    try {
      final text = await File(widget.path).readAsString();
      if (!mounted) return;
      setState(() => _textContent = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读取失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: widget.title,
        primary: true,
        trailing: IconButton(
          onPressed: () {
            OmnibotResourceService.openWithSystem(
              sourcePath: widget.path,
              mimeType: widget.mimeType,
            );
          },
          icon: SvgPicture.asset(
            _externalLinkIconAsset,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Color(0xFF111827),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFF5F7FB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.path,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!widget.exists) {
      return const Center(child: Text('文件不存在'));
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    switch (widget.previewKind) {
      case 'image':
        return InteractiveViewer(
          child: Center(child: Image.file(File(widget.path))),
        );
      case 'audio':
      case 'video':
        final metadata = OmnibotResourceService.describePath(
          widget.path,
          uri: widget.uri,
          shellPath: widget.shellPath,
          title: widget.title,
          previewKind: widget.previewKind,
          mimeType: widget.mimeType,
        );
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: OmnibotInlineResourceEmbed(metadata: metadata),
          ),
        );
      case 'html':
        return Center(
          child: FilledButton.icon(
            onPressed: () {
              GoRouterManager.push(
                '/webview/webview_page',
                extra: <String, dynamic>{
                  'url': Uri.file(widget.path).toString(),
                  'title': widget.title,
                },
              );
            },
            icon: const Icon(Icons.language_outlined),
            label: const Text('在 WebView 中打开'),
          ),
        );
      case 'text':
      case 'code':
        if (_textContent == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (widget.mimeType == 'text/markdown') {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: OmnibotMarkdownBody(
              data: _textContent!,
              baseStyle: const TextStyle(fontSize: 14, height: 1.5),
              selectable: true,
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _textContent!,
            style: TextStyle(
              fontFamily: widget.previewKind == 'code' ? 'monospace' : null,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 56),
                const SizedBox(height: 12),
                Text(widget.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  widget.mimeType,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    OmnibotResourceService.openWithSystem(
                      sourcePath: widget.path,
                      mimeType: widget.mimeType,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('系统打开'),
                ),
              ],
            ),
          ),
        );
    }
  }
}
