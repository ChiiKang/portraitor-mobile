import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/payment/services/manage_subscriptions_channel.dart';

/// Pass status for an Apple-funded subscription.
///
/// Only the controls differ from a Stripe-funded Pass, never the information.
/// Cancel, change-card and refill all belong to Apple, which exposes no API
/// for any of them, so they are absent rather than present-and-broken.
class ManageSubscriptionTile extends StatelessWidget {
  const ManageSubscriptionTile({
    super.key,
    required this.status,
    required this.renewalDate,
    required this.usesRemaining,
    required this.cancelPending,
    required this.provider,
  });

  final String status;
  final String renewalDate;
  final int usesRemaining;

  /// Auto-renew is off, so the pool stays usable until the paid period ends.
  final bool cancelPending;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final quota = usesRemaining == 1 ? 'portrait' : 'portraits';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Portraitor Pass',
                  style: PortraitorTokens.titleMd.copyWith(
                    color: PortraitorTokens.onboardingInk,
                  ),
                ),
              ),
              Text(
                status,
                style: PortraitorTokens.labelSm.copyWith(
                  color: PortraitorTokens.onboardingMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cancelPending ? 'Ends $renewalDate' : 'Renews $renewalDate',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.onboardingInkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$usesRemaining $quota left this month',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.onboardingInkSoft,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Billing managed by ${provider == 'google' ? 'Google Play' : 'Apple'}',
            style: PortraitorTokens.labelSm.copyWith(
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: PortraitorTokens.buttonHeightMd,
            child: OutlinedButton(
              key: const Key('manage_subscription'),
              onPressed:
                  () => const ManageSubscriptionsChannel().show(provider),
              child: const Text('Manage subscription'),
            ),
          ),
        ],
      ),
    );
  }
}
