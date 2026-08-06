import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/presentation/apple_iap_sheet.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// Step 4/4 — Confirm & pay.
/// You → Apple IAP sheet UI → legacy `/payment` bridge until StoreKit verifies.
/// Pass Subscribe stays gated.
class ConfirmPayScreen extends ConsumerStatefulWidget {
  const ConfirmPayScreen({super.key});

  @override
  ConsumerState<ConfirmPayScreen> createState() => _ConfirmPayScreenState();
}

class _ConfirmPayScreenState extends ConsumerState<ConfirmPayScreen> {
  bool _passOpen = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final name =
        draft.selectedNames.isNotEmpty
            ? draft.selectedNames.first
            : 'Someone';
    final messages = draft.normalized?.messageCount ?? 0;
    final showPass = _passOpen;

    return FunnelChrome(
      step: 4,
      title: 'Confirm & pay',
      lead: 'Review what you’re about to generate.',
      ctaLabel:
          showPass
              ? 'Subscribe — coming soon'
              : 'Pay ${draft.selectedTier.priceLabel}',
      ctaEnabled: !showPass && draft.selectedTier.isEnabledInV1,
      onCta: () => _onCta(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child:
                showPass
                    ? const SizedBox.shrink()
                    : Column(
                      children: [
                        _SummaryCard(
                          children: [
                            _SummaryRow(
                              label: 'Bundle',
                              value: draft.selectedTier.label,
                            ),
                            _SummaryRow(label: 'Portrait for', value: name),
                            _SummaryRow(label: 'Messages', value: '$messages'),
                            if (draft.rangeStart != null &&
                                draft.rangeEnd != null)
                              _SummaryRow(
                                label: 'Range',
                                value:
                                    '${_fmt(draft.rangeStart!)} – ${_fmt(draft.rangeEnd!)}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: PortraitorTokens.borderSoft,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL',
                                style: PortraitorTokens.labelMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.06,
                                  color: PortraitorTokens.onboardingMuted,
                                ),
                              ),
                              Text(
                                draft.selectedTier.priceLabel,
                                style: PortraitorTokens.displaySm.copyWith(
                                  fontSize: 28,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
          ),
          _PassInsteadCard(
            open: showPass,
            onToggle: () => setState(() => _passOpen = !_passOpen),
            onShowOneOff: () => setState(() => _passOpen = false),
          ),
        ],
      ),
    );
  }

  Future<void> _onCta(BuildContext context) async {
    final draft = ref.read(funnelDraftProvider);
    if (_passOpen || !draft.selectedTier.isEnabledInV1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pass needs StoreKit + quota API. Coming soon.'),
        ),
      );
      return;
    }

    await showAppleIapSheet(
      context: context,
      productTitle: 'You · one portrait',
      priceLabel: draft.selectedTier.priceLabel,
      isSubscription: false,
      onConfirm: () => _bridgeToLegacyPayment(context),
    );
  }

  void _bridgeToLegacyPayment(BuildContext context) {
    final draft = ref.read(funnelDraftProvider);
    final normalized = draft.normalized;
    if (normalized == null || draft.selectedNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing conversation or name.')),
      );
      return;
    }

    String? dateRangeStr;
    if (draft.rangeStart != null && draft.rangeEnd != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      dateRangeStr =
          '${fmt.format(draft.rangeStart!)}..${fmt.format(draft.rangeEnd!)}';
    }

    context.push(
      '/payment',
      extra: {
        'normalizedText': normalized.text,
        'targetName': draft.selectedNames.first,
        'tokenEstimate': draft.tokenEstimate,
        'conversationId': null,
        'dateRange': dateRangeStr,
      },
    );
  }

  String _fmt(DateTime d) => DateFormat('MMM yyyy').format(d);
}

class _PassInsteadCard extends StatelessWidget {
  const _PassInsteadCard({
    required this.open,
    required this.onToggle,
    required this.onShowOneOff,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onShowOneOff;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1E4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: open ? const Color(0xFFC1A354) : const Color(0x33C1A354),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get the Pass instead',
                          style: PortraitorTokens.titleSm.copyWith(
                            color: const Color(0xFF5C4A28),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$50/month · Coming soon',
                          style: PortraitorTokens.bodySm.copyWith(
                            color: const Color(0xFF8A7348),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.expand_more,
                      color: Color(0xFFC1A354),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: Color(0x33C1A354)),
                  const SizedBox(height: 12),
                  Text(
                    'Monthly · \$50/mo · 10 portraits',
                    style: PortraitorTokens.titleSm.copyWith(
                      color: const Color(0xFF5C4A28),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Any mix of You, Partner, and Family once Pass is live.',
                    style: PortraitorTokens.bodySm.copyWith(
                      color: const Color(0xFF8A7348),
                      height: 1.4,
                    ),
                  ),
                  TextButton(
                    onPressed: onShowOneOff,
                    child: Text(
                      'Show one-time total',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: const Color(0xFF8A7348),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(children: children),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PortraitorTokens.bodyMd.copyWith(
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: PortraitorTokens.titleSm.copyWith(
                color: PortraitorTokens.onboardingInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
