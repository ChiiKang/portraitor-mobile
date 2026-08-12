import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
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

  /// Where the finished portrait is sent, and for a Pass also where the
  /// one-time code is backed up.
  ///
  /// Collected BEFORE Apple's sheet opens, deliberately. Asking afterwards
  /// means a buyer can pay and close the app, leaving us with their money and
  /// no way to deliver - and a one-off buyer has no account to recover through.
  final _emailController = TextEditingController();
  bool _emailTouched = false;

  String get _email => _emailController.text.trim();

  bool get _emailValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Idempotent: the plan screen usually loads these already, but this screen
    // is reachable directly and must never render a price the store did not
    // give us.
    if (!kDemoIapPurchase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(iapProvider.notifier).loadPrices();
      });
    }
  }

  /// Demo renders its own copy; real builds render what StoreKit reports.
  String _priceFor(FunnelTier tier) {
    if (kDemoIapPurchase) return tier.priceLabel;
    return ref.watch(iapProvider).priceFor(tier) ?? tier.priceLabel;
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final iapState = ref.watch(iapProvider);
    final name = draft.selectedNames.isNotEmpty
        ? draft.selectedNames.first
        : 'Someone';
    final messages = draft.normalized?.messageCount ?? 0;
    final showPass = _passOpen;
    final purchaseBusy =
        iapState.status == IapStatus.purchasing ||
        iapState.status == IapStatus.verifying;

    return FunnelChrome(
      step: 4,
      title: 'Confirm & pay',
      lead: 'Review what you’re about to generate.',
      ctaLabel: showPass
          ? (FunnelTier.pass.canPurchase
                ? 'Subscribe ${_priceFor(FunnelTier.pass)}'
                : 'Subscribe — coming soon')
          : 'Pay ${_priceFor(draft.selectedTier)}',
      // The email gates the purchase. The server re-validates it, but letting
      // StoreKit open without one would take money we cannot deliver against.
      ctaEnabled:
          !showPass &&
          !purchaseBusy &&
          draft.selectedTier.canPurchase &&
          _emailValid,
      ctaLoading: purchaseBusy,
      onCta: () => _onCta(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DeliveryEmailField(
            controller: _emailController,
            showError: _emailTouched && !_emailValid,
            isSubscription: showPass,
            onChanged: (_) => setState(() => _emailTouched = true),
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: showPass
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
                              _priceFor(draft.selectedTier),
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
            priceCaption: FunnelTier.pass.canPurchase
                ? '${_priceFor(FunnelTier.pass)}/month'
                : '\$50/month · Coming soon',
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
        const SnackBar(content: Text('The Pass needs a store-enabled build.')),
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
        onConfirm: () => _completeDemoPurchase(context),
      );
      return;
    }

    await _completeStorePurchase(context, tier);
  }

  /// Real StoreKit. Apple renders its own sheet, so there is none of ours to
  /// show; the funnel goes straight to save-your-code and then processing.
  Future<void> _completeStorePurchase(
    BuildContext context,
    FunnelTier tier,
  ) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    // Generated BEFORE the purchase, not by the processing screen afterwards.
    // The server stores this on the payments row and the generation queue
    // refuses a payment whose stored ref does not match the run being queued,
    // so the id has to exist before the money moves. The same value is then
    // handed to /processing so both sides agree.
    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_'
        '${const Uuid().v4().substring(0, 8)}';

    final outcome = await ref
        .read(iapProvider.notifier)
        .buy(
          tier,
          clientConversationRef: conversationId,
          deliveryEmail: _email,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case PurchaseVerified(:final passCode, :final paymentReference):
        // A one-off bundle buys portraits of THIS conversation. It mints no
        // Pass and there is no code to save, so it goes straight to
        // generation. Only the subscription produces a Pass credential.
        if (IapProductCatalog.isSubscription(tier)) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SavePassScreen(
                passCode: passCode,
                onContinue: () => Navigator.of(context).pop(),
              ),
            ),
          );
          if (!context.mounted) return;
        }
        context.pushReplacement(
          '/processing',
          extra: {
            ...payload,
            'conversationId': conversationId,
            'paymentReference': paymentReference ?? '',
          },
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

  /// Demo path. Simulates an authorised purchase locally so the funnel can be
  /// walked without StoreKit or the payments backend.
  ///
  /// Deliberately self-contained: it borrows nothing from the Stripe provider,
  /// so removing that code cannot break the demo.
  Future<void> _completeDemoPurchase(BuildContext context) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;
    if (!context.mounted) return;

    const uuid = Uuid();
    context.pushReplacement(
      '/processing',
      extra: {
        ...payload,
        'conversationId': uuid.v4(),
        'paymentReference': 'demo_${uuid.v4()}',
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
    required this.priceCaption,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onShowOneOff;

  /// Resolved by the parent so this card stays free of provider lookups.
  final String priceCaption;

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
                          priceCaption,
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
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
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

/// Where the portrait is sent.
///
/// One field, asked once, used for two things: the finished portrait, and for a
/// Pass the one-time code backup. That backup is what closes the case the
/// design spec records as unrecoverable - a lost verify response otherwise
/// strands the Pass forever, because codes are stored as a peppered HMAC and
/// cannot be re-derived.
class _DeliveryEmailField extends StatelessWidget {
  const _DeliveryEmailField({
    required this.controller,
    required this.showError,
    required this.isSubscription,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool showError;
  final bool isSubscription;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Where should we send it?',
          style: TextStyle(
            fontFamily: PortraitorTokens.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PortraitorTokens.onboardingInk,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'you@example.com',
            errorText: showError ? 'Enter a valid email address' : null,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isSubscription
              ? 'Your portraits and your Pass code are emailed here. Keep it - '
                    'the code is the only way to use this Pass elsewhere.'
              : 'Your portrait is emailed here. The app keeps a copy on this '
                    'device only, so the email is what survives.',
          style: const TextStyle(
            fontFamily: PortraitorTokens.fontFamily,
            fontSize: 12,
            height: 1.35,
            color: Color(0xFF6B6580),
          ),
        ),
      ],
    );
  }
}
