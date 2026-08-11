import 'package:flutter/material.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';

/// Native-style App Store purchase sheet (UI shell), mirroring the prototype's
/// `#iap-sheet`. Face ID confirm → [onConfirm]; there is no second review step.
///
/// StoreKit is not wired yet, so this simulates the purchase. Replace the
/// confirm button's action with a real StoreKit transaction when products ship.
Future<void> showAppleIapSheet({
  required BuildContext context,
  required String productTitle,
  required String productKind,
  required String priceLabel,
  required String priceCaption,
  required bool isSubscription,
  required VoidCallback onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (context) => _AppleIapSheet(
          productTitle: productTitle,
          productKind: productKind,
          priceLabel: priceLabel,
          priceCaption: priceCaption,
          isSubscription: isSubscription,
          onConfirm: onConfirm,
        ),
  );
}

class _AppleIapSheet extends StatefulWidget {
  const _AppleIapSheet({
    required this.productTitle,
    required this.productKind,
    required this.priceLabel,
    required this.priceCaption,
    required this.isSubscription,
    required this.onConfirm,
  });

  final String productTitle;
  final String productKind;
  final String priceLabel;
  final String priceCaption;
  final bool isSubscription;
  final VoidCallback onConfirm;

  @override
  State<_AppleIapSheet> createState() => _AppleIapSheetState();
}

class _AppleIapSheetState extends State<_AppleIapSheet> {
  bool _paymentExpanded = false;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom > 0 ? 8 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFC7C7CC),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.apple, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    'App Store',
                    style: PortraitorTokens.titleSm.copyWith(
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: PortraitorTokens.bodyMd.copyWith(
                        color: const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const _IapAppIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productTitle,
                          style: PortraitorTokens.titleMd.copyWith(
                            color: PortraitorTokens.onboardingInk,
                          ),
                        ),
                        Text(
                          widget.productKind,
                          style: PortraitorTokens.bodySm.copyWith(
                            color: PortraitorTokens.onboardingMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.priceLabel,
                      style: PortraitorTokens.displaySm.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.priceCaption,
                      textAlign: TextAlign.center,
                      style: PortraitorTokens.bodySm.copyWith(
                        color: PortraitorTokens.onboardingMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const _IapRow(
                      label: 'Account',
                      value: 'you@icloud.com',
                    ),
                    const Divider(height: 1),
                    InkWell(
                      onTap:
                          () => setState(
                            () => _paymentExpanded = !_paymentExpanded,
                          ),
                      child: _IapRow(
                        label: 'Payment',
                        value: 'Visa  •••• 4242',
                        trailing: Icon(
                          _paymentExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: PortraitorTokens.onboardingMuted,
                        ),
                      ),
                    ),
                    if (_paymentExpanded) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: Column(
                          children: [
                            _FakeField(label: 'Card number', hint: '•••• •••• •••• 4242'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _FakeField(
                                    label: 'Expiry',
                                    hint: 'MM/YY',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _FakeField(
                                    label: 'Card code',
                                    hint: 'CVV',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: PortraitorTokens.buttonHeightLg,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onConfirm();
                  },
                  child: Text(
                    widget.isSubscription
                        ? 'Subscribe with Face ID'
                        : 'Pay with Face ID',
                    style: PortraitorTokens.titleSm.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isSubscription
                    ? 'Subscription renews monthly. Cancel at least 24 hours '
                        'before renewal in Settings → Apple ID → Subscriptions.'
                    : 'One-time App Store purchase. Portrait generation starts '
                        'after payment is confirmed.',
                style: PortraitorTokens.bodySm.copyWith(
                  fontSize: 12,
                  height: 1.4,
                  color: PortraitorTokens.onboardingMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App Store product tile — prototype `.iap-app-icon` + `.iap-app-orb`.
/// A white rounded square holding the brand **circle** mark, not the
/// rounded-square app icon (see `brand-spec.md`, observed rule 6).
class _IapAppIcon extends StatelessWidget {
  const _IapAppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1)),
          BoxShadow(
            color: Color(0x1A211A37),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 34,
          height: 34,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFC4B5FD), Color(0xFF7C5CFF), Color(0xFFF9A8D4)],
              stops: [0.0, 0.48, 1.0],
            ),
          ),
          // Approximates the prototype's `inset 0 1px 0 rgba(255,255,255,.45)`.
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x73FFFFFF), Color(0x00FFFFFF)],
                stops: [0.0, 0.14],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IapRow extends StatelessWidget {
  const _IapRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: PortraitorTokens.bodyMd.copyWith(
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: PortraitorTokens.bodyMd.copyWith(
                color: PortraitorTokens.onboardingInk,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

class _FakeField extends StatelessWidget {
  const _FakeField({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PortraitorTokens.labelSm.copyWith(
            color: PortraitorTokens.onboardingMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            hint,
            style: PortraitorTokens.bodyMd.copyWith(
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
        ),
      ],
    );
  }
}
