import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

class MarkdownText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final bool stripOrphanMarkers;
  final bool breakAfterLeadingBold;
  final InlineSpan? trailingSpan;

  const MarkdownText(
    this.data, {
    super.key,
    this.style,
    this.stripOrphanMarkers = false,
    this.breakAfterLeadingBold = false,
    this.trailingSpan,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? PortraitorTokens.bodyMd;
    final spans = _parse(data, baseStyle);
    final trailing = trailingSpan;
    if (trailing != null) spans.add(trailing);
    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }

  List<InlineSpan> _parse(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    var index = 0;

    while (index < text.length) {
      if (text.startsWith('**', index)) {
        final end = text.indexOf('**', index + 2);
        if (end != -1) {
          spans.add(
            TextSpan(
              text: text.substring(index + 2, end),
              style: baseStyle.copyWith(fontWeight: FontWeight.w700),
            ),
          );
          index = end + 2;
          if (breakAfterLeadingBold && spans.length == 1) {
            if (index < text.length && text[index] == ' ') index++;
            spans.add(const TextSpan(text: '\n'));
          }
          continue;
        }
        if (stripOrphanMarkers) {
          index += 2;
          continue;
        }
      }

      if (text[index] == '*') {
        final end = text.indexOf('*', index + 1);
        if (end != -1) {
          spans.add(
            TextSpan(
              text: text.substring(index + 1, end),
              style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          index = end + 1;
          continue;
        }
        if (stripOrphanMarkers) {
          index++;
          continue;
        }
      }

      final nextMarker = text.indexOf('*', index + 1);
      final end = nextMarker == -1 ? text.length : nextMarker;
      spans.add(TextSpan(text: text.substring(index, end)));
      index = end;
    }

    return spans;
  }
}
