/// The green confirmation card.
///
/// The only thing a user sees during normal use. It appears on the processing
/// screen once masking finishes and again on the finished portrait, and both
/// open the same detail screen.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Palette for the masked-details card. Green reads as "safe, done" and is what
/// the approved screens use.
abstract final class PrivacyCardColors {
  static const Color background = Color(0xFFE7F6EC);
  static const Color border = Color(0xFFB4DFC2);
  static const Color mark = Color(0xFF1E8E4A);
}

/// Reports how many details were masked, and opens the detail screen.
class PrivacyMaskedCard extends StatelessWidget {
  const PrivacyMaskedCard({
    required this.maskedCount,
    this.onTap,
    this.subtitle,
    super.key,
  });

  /// Occurrences masked, not distinct entities. A name appearing twenty times
  /// is twenty details the user would otherwise have sent.
  final int maskedCount;

  /// Null makes the card a passive status line with no chevron.
  final VoidCallback? onTap;

  /// Defaults differ by screen: during processing nothing has been sent yet,
  /// afterwards it has.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;

    return Semantics(
      button: tappable,
      label: '$maskedCount details masked on this device',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: PrivacyCardColors.background,
              border: Border.all(color: PrivacyCardColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: PrivacyCardColors.mark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$maskedCount ${maskedCount == 1 ? 'detail' : 'details'} masked',
                        style: const TextStyle(
                          fontFamily: PortraitorTokens.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: PortraitorTokens.onboardingInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            'Nothing has left this device - only the masked '
                                'text is sent',
                        style: const TextStyle(
                          fontFamily: PortraitorTokens.fontBody,
                          fontSize: 12,
                          height: 1.35,
                          color: PortraitorTokens.onboardingInkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tappable) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: PortraitorTokens.onboardingMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
