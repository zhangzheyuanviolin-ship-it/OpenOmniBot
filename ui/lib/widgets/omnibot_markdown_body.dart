import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/omnibot_resource_widgets.dart';

class OmnibotMarkdownBody extends StatelessWidget {
  static const String _trailingInlineToken = '[[omnibot-trailing-inline]]';

  final String data;
  final TextStyle baseStyle;
  final bool selectable;
  final bool inlineResourcePlainStyle;
  final Widget? trailingInline;

  const OmnibotMarkdownBody({
    super.key,
    required this.data,
    required this.baseStyle,
    this.selectable = false,
    this.inlineResourcePlainStyle = false,
    this.trailingInline,
  });

  @override
  Widget build(BuildContext context) {
    final codeTapHandler = OmnibotCodeTapHandler();
    return MarkdownBody(
      data: _linkifyBareOmnibotUris(_withTrailingInlineToken(data)),
      selectable: selectable,
      onTapLink: (text, href, title) {
        if (href == null) return;
        OmnibotResourceService.handleLinkTap(href);
      },
      blockSyntaxes: <md.BlockSyntax>[OmnibotMathBlockSyntax()],
      inlineSyntaxes: <md.InlineSyntax>[
        OmnibotInlineMathSyntax(),
        OmnibotInlineLinkSyntax(),
        if (trailingInline != null) OmnibotTrailingInlineSyntax(),
      ],
      builders: <String, MarkdownElementBuilder>{
        'code': OmnibotInlineCodeBuilder(onCopy: codeTapHandler.copy),
        'pre': OmnibotCodeBlockBuilder(onCopy: codeTapHandler.copy),
        'math-inline': OmnibotInlineMathBuilder(baseStyle: baseStyle),
        'math-block': OmnibotBlockMathBuilder(baseStyle: baseStyle),
        'omnibot-link': OmnibotInlineLinkBuilder(
          inlineResourcePlainStyle: inlineResourcePlainStyle,
        ),
        if (trailingInline != null)
          'omnibot-trailing-inline': OmnibotTrailingInlineBuilder(
            child: trailingInline!,
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

  String _withTrailingInlineToken(String source) {
    if (trailingInline == null) {
      return source;
    }
    final trimmed = source.trimRight();
    if (trimmed.isEmpty) {
      return _trailingInlineToken;
    }
    return '$trimmed $_trailingInlineToken';
  }
}

MarkdownStyleSheet buildOmnibotMarkdownStyleSheet(
  BuildContext context,
  TextStyle baseStyle,
) {
  final baseColor = baseStyle.color;
  TextStyle headingStyle(double fontSize) => baseStyle.copyWith(
    fontSize: fontSize,
    fontWeight: FontWeight.bold,
    color: baseColor,
  );

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: baseStyle.copyWith(height: 1.5),
    h1: headingStyle(24),
    h2: headingStyle(20),
    h3: headingStyle(18),
    h4: headingStyle(16),
    h5: headingStyle(15),
    h6: headingStyle(baseStyle.fontSize ?? 14),
    code: baseStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: (baseStyle.fontSize ?? 14) * 0.92,
      backgroundColor: Colors.transparent,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    codeblockDecoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
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
    tableHead: baseStyle.copyWith(
      color: baseColor,
      fontWeight: FontWeight.w600,
    ),
    tableBody: baseStyle.copyWith(color: baseColor),
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

class OmnibotMathBlockSyntax extends md.BlockSyntax {
  static const String expressionAttribute = 'data-expression';

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  bool canParse(md.BlockParser parser) {
    return pattern.hasMatch(parser.current.content);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLineTrimmed = parser.current.content.trim();
    if (firstLineTrimmed.startsWith(r'$$') &&
        firstLineTrimmed.endsWith(r'$$') &&
        firstLineTrimmed.length > 4) {
      final inlineExpression = firstLineTrimmed
          .substring(2, firstLineTrimmed.length - 2)
          .trim();
      parser.advance();
      return _buildMathElement(inlineExpression);
    }

    final expressionBuffer = StringBuffer();
    final firstRemainder = firstLineTrimmed.substring(2).trimRight();
    if (firstRemainder.isNotEmpty) {
      expressionBuffer.write(firstRemainder);
    }
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      final lineTrimmedRight = line.trimRight();
      final normalized = lineTrimmedRight.trim();

      if (normalized == r'$$') {
        parser.advance();
        break;
      }

      if (normalized.endsWith(r'$$')) {
        final closeIndex = lineTrimmedRight.lastIndexOf(r'$$');
        final contentBeforeClose = lineTrimmedRight.substring(0, closeIndex);
        if (expressionBuffer.isNotEmpty) {
          expressionBuffer.writeln();
        }
        expressionBuffer.write(contentBeforeClose.trimRight());
        parser.advance();
        break;
      }

      if (expressionBuffer.isNotEmpty) {
        expressionBuffer.writeln();
      }
      expressionBuffer.write(lineTrimmedRight);
      parser.advance();
    }

    return _buildMathElement(expressionBuffer.toString().trim());
  }

  md.Element _buildMathElement(String expression) {
    final element = md.Element.empty('math-block');
    element.attributes[expressionAttribute] = expression;
    return element;
  }
}

class OmnibotInlineMathSyntax extends md.InlineSyntax {
  OmnibotInlineMathSyntax() : super(_pattern);

  static const String _pattern = r'(?<!\\)(?<!\$)\$([^\$\n]+?)\$(?!\$)';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = match[1] ?? '';
    parser.addNode(md.Element.text('math-inline', expression));
    return true;
  }
}

typedef OmnibotCodeCopyCallback = Future<void> Function(String code);

class OmnibotCodeTapHandler {
  const OmnibotCodeTapHandler();

  Future<void> copy(String code) async {
    if (code.trim().isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      showToast(
        LegacyTextLocalizer.isEnglish ? 'Code copied' : '代码已复制',
        type: ToastType.success,
      );
    } catch (_) {
      showToast(
        LegacyTextLocalizer.isEnglish
            ? 'Copy failed, please try again'
            : '复制失败，请重试',
        type: ToastType.error,
      );
    }
  }
}

class OmnibotInlineCodeBuilder extends MarkdownElementBuilder {
  OmnibotInlineCodeBuilder({required this.onCopy});

  final OmnibotCodeCopyCallback onCopy;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(8);
    final codeStyle = (preferredStyle ?? parentStyle ?? const TextStyle())
        .copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.transparent,
          color: theme.colorScheme.onSurfaceVariant,
          fontSize:
              ((preferredStyle?.fontSize ?? parentStyle?.fontSize ?? 14) * 0.92)
                  .toDouble(),
          height: 1.2,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => onCopy(code),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.72,
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
            child: Text(code, style: codeStyle),
          ),
        ),
      ),
    );
  }
}

class OmnibotCodeBlockBuilder extends MarkdownElementBuilder {
  OmnibotCodeBlockBuilder({required this.onCopy});

  final OmnibotCodeCopyCallback onCopy;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = _normalizedCodeText(element.textContent);
    final canCopy = code.trim().isNotEmpty;
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final codeStyle = (preferredStyle ?? parentStyle ?? const TextStyle())
        .copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.transparent,
          color: theme.colorScheme.onSurfaceVariant,
          fontSize:
              ((preferredStyle?.fontSize ?? parentStyle?.fontSize ?? 14) * 0.92)
                  .toDouble(),
          height: 1.45,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: canCopy ? () => onCopy(code) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(code, style: codeStyle, softWrap: false),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizedCodeText(String value) {
    if (value.endsWith('\n') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}

class OmnibotInlineMathBuilder extends MarkdownElementBuilder {
  OmnibotInlineMathBuilder({required this.baseStyle});

  final TextStyle baseStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = element.textContent.trim();
    if (expression.isEmpty) {
      return const SizedBox.shrink();
    }
    final style = (preferredStyle ?? parentStyle ?? baseStyle).copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.4,
    );
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = _resolveMathMaxWidth(
                context,
                constraints,
                fallbackScreenRatio: 0.72,
              );
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Math.tex(
                    expression,
                    mathStyle: MathStyle.text,
                    textStyle: style,
                    onErrorFallback: (error) =>
                        Text('\$$expression\$', style: style),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class OmnibotBlockMathBuilder extends MarkdownElementBuilder {
  OmnibotBlockMathBuilder({required this.baseStyle});

  final TextStyle baseStyle;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression =
        (element.attributes[OmnibotMathBlockSyntax.expressionAttribute] ??
                element.textContent)
            .trim();
    if (expression.isEmpty) {
      return const SizedBox.shrink();
    }
    final style = (preferredStyle ?? parentStyle ?? baseStyle).copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          expression,
          mathStyle: MathStyle.display,
          textStyle: style,
          onErrorFallback: (error) => Text('\$\$$expression\$\$', style: style),
        ),
      ),
    );
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

class OmnibotTrailingInlineSyntax extends md.InlineSyntax {
  OmnibotTrailingInlineSyntax() : super(_pattern);

  static const String _pattern = r'\[\[omnibot-trailing-inline\]\]';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('omnibot-trailing-inline'));
    return true;
  }
}

class OmnibotTrailingInlineBuilder extends MarkdownElementBuilder {
  OmnibotTrailingInlineBuilder({required this.child});

  final Widget child;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(padding: const EdgeInsets.only(left: 4), child: child),
      ),
    );
  }
}

double _resolveMathMaxWidth(
  BuildContext context,
  BoxConstraints constraints, {
  double fallbackScreenRatio = 1.0,
}) {
  if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
    return constraints.maxWidth;
  }
  final screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 360;
  return screenWidth * fallbackScreenRatio;
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
          : (LegacyTextLocalizer.isEnglish ? 'Resource' : '资源');
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
