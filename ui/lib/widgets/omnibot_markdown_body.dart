import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/widgets/omnibot_resource_widgets.dart';

class OmnibotMarkdownBody extends StatelessWidget {
  final String data;
  final TextStyle baseStyle;
  final bool selectable;
  final bool inlineResourcePlainStyle;

  const OmnibotMarkdownBody({
    super.key,
    required this.data,
    required this.baseStyle,
    this.selectable = false,
    this.inlineResourcePlainStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: _linkifyBareOmnibotUris(data),
      selectable: selectable,
      onTapLink: (text, href, title) {
        if (href == null) return;
        OmnibotResourceService.handleLinkTap(href);
      },
      inlineSyntaxes: <md.InlineSyntax>[OmnibotInlineLinkSyntax()],
      builders: <String, MarkdownElementBuilder>{
        'omnibot-link': OmnibotInlineLinkBuilder(
          inlineResourcePlainStyle: inlineResourcePlainStyle,
        ),
      },
      sizedImageBuilder: (config) {
        final uri = config.uri;
        if (uri.scheme == 'omnibot') {
          final metadata = OmnibotResourceService.resolveUri(uri.toString());
          if (metadata != null) {
            return OmnibotInlineResourceEmbed(
              metadata: metadata,
              plainStyle: inlineResourcePlainStyle,
            );
          }
        }
        if (uri.scheme == 'file') {
          return Image.file(File.fromUri(uri));
        }
        return Image.network(uri.toString());
      },
      styleSheet: buildOmnibotMarkdownStyleSheet(context, baseStyle),
    );
  }
}

MarkdownStyleSheet buildOmnibotMarkdownStyleSheet(
  BuildContext context,
  TextStyle baseStyle,
) {
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: baseStyle.copyWith(height: 1.5),
    h1: baseStyle.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
    h2: baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
    code: baseStyle.copyWith(
      fontFamily: 'monospace',
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    codeblockDecoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquoteDecoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: 0.1),
      border: Border(
        left: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 4,
        ),
      ),
    ),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.all(6),
  );
}

class OmnibotInlineLinkSyntax extends md.InlineSyntax {
  OmnibotInlineLinkSyntax() : super(_pattern);

  static const String _pattern = r'(?<!!)\[([^\]]*?)\]\((omnibot://[^)\s]+)\)';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final label = match[1] ?? '';
    final href = match[2] ?? '';
    final element = md.Element.text(
      'omnibot-link',
      label.isEmpty ? href : label,
    )..attributes['href'] = href;
    parser.addNode(element);
    return true;
  }
}

class OmnibotInlineLinkBuilder extends MarkdownElementBuilder {
  OmnibotInlineLinkBuilder({this.inlineResourcePlainStyle = false});

  final bool inlineResourcePlainStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final metadata = href == null
        ? null
        : OmnibotResourceService.resolveUri(href);
    if (metadata == null) {
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: href == null
                ? null
                : () => OmnibotResourceService.handleLinkTap(href),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                element.textContent,
                style: preferredStyle?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: OmnibotInlineResourceEmbed(
            metadata: metadata,
            plainStyle: inlineResourcePlainStyle,
          ),
        ),
      ),
    );
  }
}

String _linkifyBareOmnibotUris(String input) {
  final buffer = StringBuffer();
  final lines = input.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('omnibot://') &&
        !trimmed.contains(' ') &&
        !trimmed.contains('[') &&
        !trimmed.contains(']')) {
      final parsed = Uri.tryParse(trimmed);
      final label = parsed?.pathSegments.isNotEmpty == true
          ? parsed!.pathSegments.last
          : '资源';
      buffer.write('[$label]($trimmed)');
    } else {
      buffer.write(line);
    }
    if (i != lines.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}
