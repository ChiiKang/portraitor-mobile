/// "Exactly what we sent".
///
/// Two tabs: the literal masked payload, and what each token stands for. The
/// second tab holds the real values, which never left the device, so secrets and
/// account numbers stay hidden until the user asks for them explicitly.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../client/redaction.dart';
import '../pipeline/types.dart';

class PrivacyDetailScreen extends StatefulWidget {
  const PrivacyDetailScreen({
    required this.maskedText,
    required this.entities,
    this.youName,
    super.key,
  });

  /// The exact payload that was sent. Rendered verbatim, not re-derived, so the
  /// screen cannot claim something different from what actually went out.
  final String maskedText;

  final List<MaskEntity> entities;

  /// Marks the portrait's target with a YOU badge.
  final String? youName;

  @override
  State<PrivacyDetailScreen> createState() => _PrivacyDetailScreenState();
}

class _PrivacyDetailScreenState extends State<PrivacyDetailScreen> {
  int _tab = 0;

  /// Tokens the user has chosen to reveal. Kept per-screen, so leaving and
  /// coming back re-hides them.
  final Set<String> _revealed = {};

  late final Redaction _redaction = buildRedactionFromPipeline(
    widget.maskedText,
    widget.entities,
    youName: widget.youName,
  );

  /// Categories whose values are dangerous enough to hide by default.
  static const Set<String> _sensitive = {'secret', 'account'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortraitorTokens.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            _segmented(),
            Expanded(
              child: _tab == 0 ? _transcript() : _legend(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final total = _redaction.totalOccurrences;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.chevron_left),
                color: PortraitorTokens.onboardingInk,
              ),
              const Text(
                'Privacy',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Exactly what we sent',
            style: TextStyle(
              fontFamily: PortraitorTokens.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: PortraitorTokens.onboardingInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$total ${total == 1 ? 'detail' : 'details'} masked on this device '
            '- nothing has left it.',
            style: const TextStyle(
              fontFamily: PortraitorTokens.fontBody,
              fontSize: 13.5,
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented() {
    Widget tab(String label, int index) {
      final selected = _tab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? PortraitorTokens.onboardingPrimary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: PortraitorTokens.fontBody,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selected
                    ? PortraitorTokens.onboardingInk
                    : PortraitorTokens.onboardingInkSoft,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: PortraitorTokens.brandSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [tab('Transcript', 0), tab('What each tag hides', 1)],
        ),
      ),
    );
  }

  /// The masked payload, with tokens picked out as chips.
  Widget _transcript() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9E4F5)),
          ),
          child: SelectableText.rich(
            TextSpan(
              children: [
                for (final segment in _redaction.segments)
                  if (segment.mask)
                    TextSpan(
                      text: segment.token,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _categoryColor(segment.type),
                        backgroundColor:
                            _categoryColor(segment.type).withValues(alpha: .12),
                      ),
                    )
                  else
                    TextSpan(
                      text: segment.text,
                      style: const TextStyle(
                        fontFamily: PortraitorTokens.fontBody,
                        fontSize: 12.5,
                        height: 1.5,
                        color: PortraitorTokens.onboardingInkSoft,
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Timestamps stay visible on purpose - dates are not private detail.',
          style: TextStyle(
            fontFamily: PortraitorTokens.fontBody,
            fontSize: 11.5,
            color: PortraitorTokens.onboardingMutedLight,
          ),
        ),
      ],
    );
  }

  Widget _legend() {
    if (_redaction.byCategory.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing needed masking in this conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: PortraitorTokens.fontBody,
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        for (final category in _redaction.byCategory) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _categoryColor(category.category),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  category.group.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: PortraitorTokens.fontBody,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.9,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ),
              ],
            ),
          ),
          for (final row in category.rows)
            _row(row, isSensitive: _sensitive.contains(category.category)),
        ],
      ],
    );
  }

  Widget _row(RedactionRow row, {required bool isSensitive}) {
    final hidden = isSensitive && !_revealed.contains(row.token);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9E4F5)),
      ),
      child: Row(
        children: [
          Text(
            row.token,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PortraitorTokens.onboardingPrimaryDeep,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward,
            size: 13,
            color: PortraitorTokens.onboardingMutedLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hidden
                ? GestureDetector(
                    onTap: () => setState(() => _revealed.add(row.token)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: PortraitorTokens.brandSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off_outlined, size: 13),
                          SizedBox(width: 5),
                          Text(
                            'Tap to reveal',
                            style: TextStyle(
                              fontFamily: PortraitorTokens.fontBody,
                              fontSize: 11.5,
                              color: PortraitorTokens.onboardingInkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SelectableText(
                    row.value,
                    style: const TextStyle(
                      fontFamily: PortraitorTokens.fontBody,
                      fontSize: 12.5,
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
          ),
          if (row.count > 1) ...[
            const SizedBox(width: 8),
            Text(
              'x${row.count}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
          ],
          if (row.you) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: PortraitorTokens.brandSoft,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'YOU',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontBody,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: PortraitorTokens.onboardingPrimaryDeep,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _categoryColor(String? category) => switch (category) {
    'person' => PortraitorTokens.onboardingPrimaryDeep,
    'email' => const Color(0xFF2563EB),
    'phone' => const Color(0xFF14683A),
    'address' => const Color(0xFF92620C),
    'url' => const Color(0xFFBE185D),
    'secret' => const Color(0xFFB91C1C),
    'account' => const Color(0xFF0F766E),
    _ => PortraitorTokens.onboardingMuted,
  };
}
