import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/core/storage/storage_service.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/payment/application/iap_provider.dart';
import 'package:portraitor_mobile/features/payment/application/pass_funding_provider.dart';
import 'package:portraitor_mobile/features/payment/application/portrait_credit_provider.dart';
import 'package:portraitor_mobile/features/payment/services/pass_grant_api.dart';
import 'package:portraitor_mobile/features/payment/domain/iap_product.dart';
import 'package:portraitor_mobile/features/payment/domain/purchase_outcome.dart';
import 'package:portraitor_mobile/features/payment/presentation/apple_iap_sheet.dart';
import 'package:portraitor_mobile/features/payment/presentation/save_pass_screen.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';

/// The tier name the server prices against.
///
/// Must match the arms of `UsageService::costForPortraitRequest`. A Pass holder
/// buys a portrait tier, never another Pass, so the pass tier never reaches the
/// server as a name.
String passTierNameFor(FunnelTier tier) =>
    tier == FunnelTier.pass ? 'you' : tier.name;

/// Uses a run costs, mirroring `UsageService::costForPortraitRequest`.
///
/// Duplicated deliberately so the funnel can refuse locally instead of letting
/// the user commit and then discovering an exhausted pool. The server stays
/// authoritative and still rejects an underfunded reserve with a 402; if its
/// pricing changes, this must change with it.
int passUseCostFor(FunnelTier tier, int personCount) {
  switch (tier) {
    case FunnelTier.partner:
      return 2;
    case FunnelTier.family:
      return personCount < 1 ? 1 : (personCount > 5 ? 5 : personCount);
    case FunnelTier.you:
    case FunnelTier.pass:
      return 1;
  }
}

/// Step 4/4 — Confirm & pay.
/// Real builds use the platform-selected native store for every product.
/// Verified consumables continue to `/processing`; a verified Pass first shows
/// its save-your-code screen. Only the backend-free demo gates Pass purchases -
/// see [kDemoIapPurchase].
class ConfirmPayScreen extends ConsumerStatefulWidget {
  const ConfirmPayScreen({super.key});

  @override
  ConsumerState<ConfirmPayScreen> createState() => _ConfirmPayScreenState();
}

enum PostPurchaseDestination { processing, profile }

PostPurchaseDestination postPurchaseDestinationFor(FunnelTier tier) =>
    IapProductCatalog.isSubscription(tier)
        ? PostPurchaseDestination.profile
        : PostPurchaseDestination.processing;

class _ConfirmPayScreenState extends ConsumerState<ConfirmPayScreen> {
  bool _passOpen = false;

  /// Where the finished portrait is sent, and for a Pass also where the
  /// one-time code is backed up.
  ///
  /// Collected before the store sheet opens, deliberately. Asking afterwards
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(iapProvider.notifier).loadPrices();
    });
  }

  /// Demo renders its own copy; real builds render what the store reports.
  String _priceFor(FunnelTier tier) {
    if (kDemoIapPurchase) return tier.priceLabel;
    final state = ref.watch(iapProvider);
    if (state.status == IapStatus.failed && state.priceFor(tier) == null) {
      return 'Unavailable';
    }
    return state.priceFor(tier) ?? 'Loading…';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final iapState = ref.watch(iapProvider);
    final entitlements = ref.watch(runtimeEntitlementsProvider);
    final passPortraits = FunnelTier.pass.portraitCount(entitlements);
    final passPortraitLabel =
        '$passPortraits ${passPortraits == 1 ? 'portrait' : 'portraits'}';
    final name =
        draft.selectedNames.isNotEmpty ? draft.selectedNames.first : 'Someone';
    final messages = draft.normalized?.messageCount ?? 0;
    final showPass = _passOpen;
    final purchaseBusy =
        iapState.status == IapStatus.purchasing ||
        iapState.status == IapStatus.verifying;
    final activeTier = showPass ? FunnelTier.pass : draft.selectedTier;
    final productReady = iapState.priceFor(activeTier) != null;

    // A held Pass funds the run server-side, so the store catalog is irrelevant
    // to it. Watched here rather than only read at tap, because `ctaEnabled`
    // gates on `productReady` - false on a build with no store catalog, which
    // is exactly the build this path exists to serve. Gated on canCover, not
    // isUsable: offering "Use my Pass" for a five-use Family run with one use
    // left is a promise the reserve call breaks after the user commits.
    final passFundingAsync = ref.watch(passFundingProvider);
    final passUseCost = passUseCostFor(
      draft.selectedTier,
      draft.selectedNames.length,
    );
    final passFunded =
        !showPass &&
        (passFundingAsync.valueOrNull?.canCover(passUseCost) ?? false);

    // Resolving is a network call, so the first frame has no answer. Without
    // this the button shows the disabled "Pay Unavailable" that this feature
    // exists to remove, then flips a moment later.
    final passChecking = !showPass && passFundingAsync.isLoading;

    // A purchase freed by cancelling an earlier portrait. Already paid for, so
    // it is offered ahead of both the Pass and the store: leaving it idle while
    // the customer pays again is the one outcome cancelling was meant to avoid.
    final freedCredit =
        showPass
            ? null
            : creditForTier(
              ref.watch(portraitCreditsProvider).valueOrNull ?? const [],
              draft.selectedTier.name,
            );
    final purchaseError =
        iapState.status == IapStatus.failed &&
                iapState.products.isNotEmpty &&
                !(iapState.error ?? '').startsWith('Store products')
            ? iapState.error
            : null;

    return FunnelChrome(
      step: 4,
      title: 'Confirm & pay',
      lead: 'Review what you’re about to generate.',
      ctaLabel:
          showPass
              ? (FunnelTier.pass.canPurchase
                  ? 'Subscribe ${_priceFor(FunnelTier.pass)}'
                  : 'Subscribe — coming soon')
              : freedCredit != null
                  ? 'Use your paid portrait'
                  : passFunded
                      ? 'Use my Pass'
                      : passChecking
                          ? 'Checking your Pass…'
                          : 'Pay ${_priceFor(draft.selectedTier)}',
      // The email gates the purchase. The server re-validates it, but letting
      // Opening the store without one would take money we cannot deliver against.
      ctaEnabled:
          !purchaseBusy &&
          (!passChecking || freedCredit != null) &&
          _emailValid &&
          // Neither a freed credit nor a Pass-funded run needs a purchasable
          // tier or a store price, so both bypass the store gates rather than
          // relaxing them.
          (freedCredit != null ||
              passFunded ||
              (activeTier.canPurchase && productReady)),
      ctaLoading: purchaseBusy,
      onCta: () => _onCta(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DeliveryEmailField(
            controller: _emailController,
            showError: _emailTouched && !_emailValid,
            isSubscription: showPass,
            isDemo: kDemoIapPurchase,
            onChanged: (_) => setState(() => _emailTouched = true),
          ),
          if (!kDemoIapPurchase &&
              iapState.status == IapStatus.failed &&
              iapState.products.isEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    iapState.error ?? 'Store products are unavailable.',
                    key: const ValueKey('iap-products-error'),
                    style: PortraitorTokens.bodySm.copyWith(
                      color: PortraitorTokens.onboardingInkSoft,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('iap-products-retry'),
                  onPressed: ref.read(iapProvider.notifier).loadPrices,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
          if (purchaseError != null) ...[
            const SizedBox(height: 12),
            _PurchaseErrorCard(message: purchaseError),
          ],
          const SizedBox(height: 14),
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
            priceCaption:
                kDemoIapPurchase
                    ? '\$50/month · Coming soon'
                    : '${_priceFor(FunnelTier.pass)}/month',
            detailsCaption:
                kDemoIapPurchase
                    ? 'Monthly · \$50/mo · $passPortraitLabel'
                    : 'Monthly · ${_priceFor(FunnelTier.pass)}/month · '
                        '$passPortraitLabel',
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
    final tier = _passOpen ? FunnelTier.pass : draft.selectedTier;

    // Spend a freed purchase before anything else. It is already paid for, so
    // letting a Pass use or a fresh charge go first would waste it.
    if (!_passOpen) {
      final credits = await ref.read(portraitCreditsProvider.future);
      final credit = creditForTier(credits, tier.name);
      if (credit != null) {
        if (!context.mounted) return;
        await _completeCreditRun(context, credit);
        return;
      }
    }

    // A held Pass funds the run server-side, so no store transaction happens.
    //
    // Re-resolved here rather than trusting what `build` watched: a use spent
    // on another device changes the answer. `_passOpen` is excluded because
    // with the Pass card open the CTA subscribes, and a holder tapping it must
    // not silently spend a use of the Pass they already have.
    if (!_passOpen) {
      final funding = await ref.read(passFundingResolverProvider).resolve();
      final personCount = ref.read(funnelDraftProvider).selectedNames.length;
      final useCost = passUseCostFor(tier, personCount);

      if (funding.canCover(useCost)) {
        if (!context.mounted) return;
        await _completePassRun(context, tier, funding, personCount);
        return;
      }

      // The button said "Use my Pass" when it was drawn, so something changed
      // underneath. Say so rather than falling through to a store purchase
      // that cannot succeed on a build with no catalog.
      if (funding.isUsable && !funding.canCover(useCost)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your Pass has ${funding.usesRemaining} '
              '${funding.usesRemaining == 1 ? 'portrait' : 'portraits'} left, '
              'and this needs $useCost.',
            ),
          ),
        );
        return;
      }
    }

    // The Pass check above awaits, so everything below it now crosses an async
    // gap that did not exist before this branch was added.
    if (!context.mounted) return;

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
        priceCaption: tier.iapPriceCaptionFor(
          ref.read(runtimeEntitlementsProvider),
        ),
        isSubscription: !tier.isOneOff,
        onConfirm: () => _completeDemoPurchase(context),
      );
      return;
    }

    await _completeStorePurchase(context, tier);
  }

  /// Run funded by a purchase the customer already made and then freed by
  /// cancelling the portrait it was bought for.
  ///
  /// No store round trip and no network call: the server already holds the
  /// payment, bound to the conversation ref this row carries, which is why the
  /// run has to reuse that ref rather than mint a fresh one.
  Future<void> _completeCreditRun(
    BuildContext context,
    PendingJob credit,
  ) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    try {
      await stageCreditRun(credit: credit, payload: payload);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This portrait could not start safely. Free some storage and try again.',
          ),
        ),
      );
      return;
    }

    // The row is no longer a credit, so anything still offering it has to stop.
    ref.invalidate(portraitCreditsProvider);

    if (!context.mounted) return;
    context.pushReplacement(
      '/processing',
      extra: {
        ...payload,
        'conversationId': credit.id,
        'paymentReference': credit.paymentSessionId,
      },
    );
  }

  /// Pass-funded run. The reserved use IS the payment, so the grant token takes
  /// the `paymentReference` slot a store purchase would fill and nothing
  /// downstream of `/processing` needs to know the difference.
  ///
  /// Everything after a successful reserve is compensated: if the local write
  /// fails, the use goes straight back rather than sitting reserved until the
  /// server's expiry sweep notices, which can take fifteen minutes.
  Future<void> _completePassRun(
    BuildContext context,
    FunnelTier tier,
    PassFunding funding,
    int personCount,
  ) async {
    final payload = _funnelPayload(context);
    if (payload == null) return;

    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_'
        '${const Uuid().v4().substring(0, 8)}';

    // Staged before reserving, so a storage failure costs no use at all.
    try {
      await _stagePendingGeneration(
        conversationId: conversationId,
        payload: payload,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This portrait could not start safely. Free some storage and try again.',
          ),
        ),
      );
      return;
    }

    final sessionToken = funding.sessionToken!;
    final String grantToken;
    try {
      grantToken = await ref
          .read(passGrantApiProvider)
          .reserve(
            sessionToken: sessionToken,
            tier: passTierNameFor(tier),
            // The PERSON count. The server prices the run itself.
            personCount: personCount,
          );
    } on PassGrantException catch (error) {
      await StorageService.instance.deletePendingJob(conversationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.isSessionExpired
                ? 'Your Pass session expired. Re-enter your Pass code in Profile.'
                : error.message,
          ),
        ),
      );
      return;
    }

    // From here a use is spent, so every failure path hands it back before
    // returning. Awaited, not fire-and-forget: the user is about to see an
    // error and the count they check next has to be right.
    try {
      await StorageService.instance.updatePendingJob(
        conversationId,
        paymentSessionId: grantToken,
        status: 'ready',
      );
    } catch (_) {
      await ref
          .read(passGrantApiProvider)
          .release(sessionToken: sessionToken, grantToken: grantToken);
      await StorageService.instance.deletePendingJob(conversationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This portrait could not start. Your Pass use was returned.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) {
      // Nothing left to hand off to. Give the use back rather than stranding it.
      await ref
          .read(passGrantApiProvider)
          .release(sessionToken: sessionToken, grantToken: grantToken);
      return;
    }
    context.pushReplacement(
      '/processing',
      extra: {
        ...payload,
        'conversationId': conversationId,
        'paymentReference': grantToken,
      },
    );
  }

  /// Real store purchase. The platform renders its own sheet, so the funnel
  /// goes straight to save-your-code when needed and then processing.
  Future<void> _completeStorePurchase(
    BuildContext context,
    FunnelTier tier,
  ) async {
    final destination = postPurchaseDestinationFor(tier);
    final payload =
        destination == PostPurchaseDestination.processing
            ? _funnelPayload(context)
            : null;
    if (destination == PostPurchaseDestination.processing && payload == null) {
      return;
    }

    // Generated BEFORE the purchase, not by the processing screen afterwards.
    // The server stores this on the payments row and the generation queue
    // refuses a payment whose stored ref does not match the run being queued,
    // so the id has to exist before the money moves. The same value is then
    // handed to /processing so both sides agree.
    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_'
        '${const Uuid().v4().substring(0, 8)}';

    if (destination == PostPurchaseDestination.processing) {
      try {
        await _stagePendingGeneration(
          conversationId: conversationId,
          payload: payload!,
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase could not start safely. Free some storage and try again.',
            ),
          ),
        );
        return;
      }
    }

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
              builder:
                  (_) => SavePassScreen(
                    passCode: passCode,
                    onContinue: () => Navigator.of(context).pop(),
                  ),
            ),
          );
          if (!context.mounted) return;
          context.go('/profile');
          return;
        }

        if (paymentReference == null || paymentReference.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Purchase verified, but generation is not ready yet. '
                'Use Continue on your unfinished portrait shortly.',
              ),
            ),
          );
          return;
        }
        await StorageService.instance.updatePendingJob(
          conversationId,
          paymentSessionId: paymentReference,
          status: 'ready',
        );
        if (!context.mounted) return;
        context.pushReplacement(
          '/processing',
          extra: {
            ...payload!,
            'conversationId': conversationId,
            'paymentReference': paymentReference,
          },
        );
      case PurchaseCancelled():
        await StorageService.instance.deletePendingJob(conversationId);
        break;
      case PurchasePending():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Waiting for approval. We will continue once it is approved.',
            ),
          ),
        );
      case PurchaseFailed():
        if (shouldDiscardPendingGeneration(outcome)) {
          await StorageService.instance.deletePendingJob(conversationId);
        }
    }
  }

  Future<void> _stagePendingGeneration({
    required String conversationId,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now().toUtc();
    await StorageService.instance.savePendingJobRecord(
      PendingJob(
        id: conversationId,
        deviceId: StorageService.instance.deviceId,
        clientConversationRef: conversationId,
        inputText: payload['normalizedText'] as String,
        targetName: payload['targetName'] as String,
        dateRange: payload['dateRange'] as String?,
        paymentSessionId: '',
        deliveryEmail: payload['deliveryEmail'] as String? ?? '',
        status: 'awaiting_purchase',
        chunksCompleted: 0,
        chunksTotal: 0,
        chunkResults: const [],
        createdAt: now,
        updatedAt: now,
        tier: payload['tier'] as String,
        people: (payload['people'] as List<String>),
      ),
    );
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
      // Rides through to the generation requests. A store purchase leaves an
      // Apple/Google payments row with no Stripe customer, so the backend has
      // no recipient to resolve and refuses every generation call that does
      // not carry the address the buyer typed here.
      'deliveryEmail': _email,
      'people': List<String>.unmodifiable(draft.selectedNames),
      'tier': draft.selectedTier.name,
      'tokenEstimate': draft.tokenEstimate,
      'conversationId': null,
      'dateRange': dateRangeStr,
    };
  }

  /// Demo path. Simulates an authorised purchase locally so the funnel can be
  /// walked without a platform store or the payments backend.
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
    required this.detailsCaption,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onShowOneOff;

  /// Resolved by the parent so this card stays free of provider lookups.
  final String priceCaption;
  final String detailsCaption;

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
                    detailsCaption,
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

class _PurchaseErrorCard extends StatelessWidget {
  const _PurchaseErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Purchase problem. $message',
      child: Container(
        key: const ValueKey('purchase-error'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFC9C5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: Color(0xFFA63B32),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchase did not continue',
                    style: PortraitorTokens.bodySm.copyWith(
                      color: const Color(0xFF7B2F29),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: PortraitorTokens.bodySm.copyWith(
                      color: const Color(0xFF6B3A36),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    required this.isDemo,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool showError;
  final bool isSubscription;
  final bool isDemo;
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
          isDemo
              ? 'Demo mode does not charge or send email. This address only '
                  'lets you preview the complete checkout flow.'
              : isSubscription
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
