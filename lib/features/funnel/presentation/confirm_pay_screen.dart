import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/application/payment_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/presentation/apple_iap_sheet.dart';
import 'package:portraitor_mobile/features/payment/presentation/save_pass_screen.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// Step 4/4 — Confirm & pay.
/// Every one-off bundle → Apple IAP sheet → `/processing`. Apple IAP is the only
/// purchase path; the Stripe web checkout at `/payment` is kept in the codebase
/// but no longer reachable from the funnel. Pass Subscribe stays gated — see
/// [kDemoIapPurchase].
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
      ctaEnabled: !showPass && draft.selectedTier.canPurchase,
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
    final tier = draft.selectedTier;

    if (!tier.canPurchase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Pass needs a real StoreKit build.')),
      );
      return;
    }

    if (kDemoIapPurchase) {
      await showAppleIapSheet(
        context: context,
        productTitle: tier.iapProductTitle,
        productKind: tier.iapProductKind,
        priceLabel: tier.iapPriceLabel,
        priceCaption: tier.iapPriceCaption,
        isSubscription: !tier.isOneOff,
        onConfirm: () => _completeIapPurchase(context),
      );
      return;
    }

    await _completeStoreKitPurchase(context, tier);
  }

  /// Real StoreKit. Apple renders its own sheet, so there is none of ours to
  /// show; the funnel goes straight to save-your-code and then processing.
  Future<void> _completeStoreKitPurchase(
    BuildContext context,
    FunnelTier tier,
  ) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    final outcome = await ref.read(iapProvider.notifier).buy(tier);
    if (!context.mounted) return;

    switch (outcome) {
      case PurchaseVerified(:final passCode, :final paymentReference):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SavePassScreen(
              passCode: passCode,
              onContinue: () => Navigator.of(context).pop(),
            ),
          ),
        );
        if (!context.mounted) return;
        context.pushReplacement(
          '/processing',
          extra: {...payload, 'paymentReference': paymentReference ?? ''},
        );
      case PurchaseCancelled():
        break;
      case PurchasePending():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Waiting for approval. We will continue once it is approved.',
            ),
          ),
        );
      case PurchaseFailed(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Shared funnel payload for whichever post-purchase route is in use.
  /// Returns null (after surfacing a snackbar) when the draft is incomplete.
  Map<String, dynamic>? _funnelPayload(BuildContext context) {
    final draft = ref.read(funnelDraftProvider);
    final normalized = draft.normalized;
    if (normalized == null || draft.selectedNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing conversation or name.')),
      );
      return null;
    }

    String? dateRangeStr;
    if (draft.rangeStart != null && draft.rangeEnd != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      dateRangeStr =
          '${fmt.format(draft.rangeStart!)}..${fmt.format(draft.rangeEnd!)}';
    }

    return {
      'normalizedText': normalized.text,
      'targetName': draft.selectedNames.first,
      'tokenEstimate': draft.tokenEstimate,
      'conversationId': null,
      'dateRange': dateRangeStr,
    };
  }

  /// Apple IAP is the only purchase path. Face ID authorises the purchase, so
  /// the funnel goes straight to `/processing` — matching the prototype's
  /// `iap-confirm → go("processing", {replace: true})`. There is no second
  /// review-and-pay step to confirm the same charge twice.
  ///
  /// StoreKit is not wired yet, so the receipt is provisioned locally the same
  /// way the demo path does; swap `initiateDemo` for StoreKit verification when
  /// the products go live.
  Future<void> _completeIapPurchase(BuildContext context) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    final paymentNotifier = ref.read(paymentProvider.notifier);
    final authorized = await paymentNotifier.initiateDemo();
    if (!context.mounted) return;

    if (!authorized) {
      final error = ref.read(paymentProvider).error ?? 'Purchase failed';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final paymentState = ref.read(paymentProvider);
    context.pushReplacement(
      '/processing',
      extra: {
        ...payload,
        'conversationId': paymentState.clientConversationRef ?? '',
        'paymentReference': paymentState.paymentIntentId ?? '',
      },
    );
  }

  /// Retained for the Stripe web checkout path (`/payment` → `PaymentScreen`).
  /// Unused while the funnel is Apple-IAP-only; do not delete.
  // ignore: unused_element
  void _bridgeToLegacyPayment(BuildContext context) {
    final payload = _funnelPayload(context);
    if (payload == null) return;
    context.push('/payment', extra: payload);
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
