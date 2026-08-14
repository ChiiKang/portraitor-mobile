import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'markdown_text.dart';

/// Renders a portrait exactly as the model wrote it, with one consistent set of
/// styles.
///
/// The screen used to split the text on `##` headings into collapsible section
/// cards. That made the layout depend on how the model happened to format its
/// answer: the same portrait rendered as a tidy accordion when headings came
/// back, and as a single undifferentiated blob when they did not - and a
/// numbered outline like "1. Overview" produced the blob every time. Model
/// output varies run to run, so any layout derived from its shape varies too.
///
/// This renders every document the same way instead. Headings become headings,
/// lists become lists, and anything unrecognised stays a paragraph rather than
/// being dropped or mangled. Nothing is invented, reordered, or hidden behind a
/// disclosure - what the model sent is what appears.
///
/// [MarkdownText] handles the inline layer (bold, italic) and is deliberately
/// not given whole documents on its own: it treats a line-leading `*` as an
/// italic marker, so an unsplit bullet list renders as mangled italics.
class PortraitDocument extends StatelessWidget {
  const PortraitDocument(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(markdown);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].spacingBefore),
          blocks[i].build(),
        ],
      ],
    );
  }

  /// Line-based on purpose. A model that closes a `**` on the wrong line or
  /// forgets a blank line between paragraphs should still produce a readable
  /// document, and a block parser cannot be thrown off by an unbalanced marker
  /// the way a document-wide scan can.
  static List<_Block> _parseBlocks(String markdown) {
    final blocks = <_Block>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isNotEmpty) blocks.add(_Paragraph(text));
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      // A rule is a separator, not content. Rendering it as text would show a
      // row of dashes in the middle of the portrait.
      if (RegExp(r'^([-*_])\1{2,}$').hasMatch(trimmed)) {
        flushParagraph();
        blocks.add(const _Rule());
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(
          _Heading(
            level: heading.group(1)!.length,
            text: heading.group(2)!.trim(),
          ),
        );
        continue;
      }

      final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_ListItem(marker: '•', text: bullet.group(1)!.trim()));
        continue;
      }

      final numbered = RegExp(r'^(\d{1,3})[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        blocks.add(
          _ListItem(
            marker: '${numbered.group(1)}.',
            text: numbered.group(2)!.trim(),
          ),
        );
        continue;
      }

      // A model often writes a section title as a bold line rather than a
      // heading. Treating it as one keeps those documents looking like the
      // documents that did use `##`, which is the whole point here.
      final boldTitle = RegExp(r'^\*\*(.+?)\*\*:?$').firstMatch(trimmed);
      if (boldTitle != null) {
        flushParagraph();
        blocks.add(_Heading(level: 3, text: boldTitle.group(1)!.trim()));
        continue;
      }

      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(trimmed);
    }

    flushParagraph();

    return blocks;
  }
}

abstract class _Block {
  const _Block();

  double get spacingBefore;

  Widget build();
}

class _Heading extends _Block {
  const _Heading({required this.level, required this.text});

  final int level;
  final String text;

  // A heading needs more air above it than below, or it reads as belonging to
  // the paragraph it follows rather than the one it introduces.
  @override
  double get spacingBefore => level <= 2 ? 24 : 20;

  @override
  Widget build() {
    final style = switch (level) {
      1 => PortraitorTokens.titleMd,
      2 => PortraitorTokens.titleSm,
      _ => PortraitorTokens.titleSm.copyWith(fontSize: 15),
    };

    return Text(text, style: style);
  }
}

class _Paragraph extends _Block {
  const _Paragraph(this.text);

  final String text;

  @override
  double get spacingBefore => 12;

  @override
  Widget build() => MarkdownText(
    text,
    style: PortraitorTokens.bodyMd,
    stripOrphanMarkers: true,
  );
}

class _ListItem extends _Block {
  const _ListItem({required this.marker, required this.text});

  final String marker;
  final String text;

  @override
  double get spacingBefore => 8;

  @override
  Widget build() => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(
            marker,
            style: PortraitorTokens.bodyMd.copyWith(
              color: PortraitorTokens.inkMuted,
            ),
          ),
        ),
        Expanded(
          child: MarkdownText(
            text,
            style: PortraitorTokens.bodyMd,
            stripOrphanMarkers: true,
          ),
        ),
      ],
    ),
  );
}

class _Rule extends _Block {
  const _Rule();

  @override
  double get spacingBefore => 20;

  @override
  Widget build() =>
      Divider(height: 1, thickness: 1, color: PortraitorTokens.borderSoft);
}
