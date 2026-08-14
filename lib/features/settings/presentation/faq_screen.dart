import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  static const _faqs = [
    _FAQ(
      question: 'How long does a portrait take?',
      answer:
          'Most portraits complete in about 60–90 seconds, depending on chat length.',
    ),
    _FAQ(
      question: 'What chat formats are supported?',
      answer:
          'WhatsApp (.txt and .zip exports) and Telegram text exports. More formats coming soon.',
    ),
    _FAQ(
      question: 'Is my data safe?',
      answer:
          'Your chat is processed once by our AI, then immediately deleted from our servers. We never store raw chat data.',
    ),
    _FAQ(
      question: 'Can I delete my data?',
      answer:
          'Yes. Go to Settings → Data & Privacy to request full data deletion. Local portraits are deleted immediately.',
    ),
    _FAQ(
      question: 'How accurate are the portraits?',
      answer:
          'Portraits are AI-generated personality analyses. They provide insights based on communication patterns but should be taken as one perspective, not absolute truth.',
    ),
    _FAQ(
      question: 'How is pricing determined?',
      answer:
          'Prices vary by bundle and storefront. The app shows the current localized App Store or Google Play price before purchase.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount: _faqs.length,
                  itemBuilder: (context, index) => _FAQItem(faq: _faqs[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          const Text('FAQ', style: PortraitorTokens.titleMd),
        ],
      ),
    );
  }
}

class _FAQ {
  final String question;
  final String answer;
  const _FAQ({required this.question, required this.answer});
}

class _FAQItem extends StatefulWidget {
  final _FAQ faq;
  const _FAQItem({required this.faq});

  @override
  State<_FAQItem> createState() => _FAQItemState();
}

class _FAQItemState extends State<_FAQItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: PortraitorTokens.surface,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          border: Border.all(color: PortraitorTokens.borderSoft),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(PortraitorTokens.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.faq.question,
                        style: PortraitorTokens.titleSm,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: PortraitorTokens.durBase,
                      child: const Icon(
                        Icons.expand_more,
                        color: PortraitorTokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(widget.faq.answer, style: PortraitorTokens.bodyMd),
              ),
              crossFadeState:
                  _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: PortraitorTokens.durBase,
            ),
          ],
        ),
      ),
    );
  }
}
