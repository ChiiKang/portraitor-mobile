/// Readiness gate for the on-device privacy model.
///
/// Downloading 175 MB is unavoidable, but making a user pay first and only then
/// discover it is not. This starts the download while they are still in the
/// funnel and blocks the pay button until the model is verified, so the cost is
/// paid during a screen they were reading anyway.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../model/model_repository.dart';
import '../privacy_providers.dart';

/// Live model status, seeded with whatever the repository already knows.
///
/// Watching this does NOT start a download. [PrivacyModelGate] does that, so a
/// screen can display readiness without causing it.
final privacyModelStatusProvider = StreamProvider.autoDispose<ModelStatus>((
  ref,
) {
  final repo = ref.watch(privacyModelRepositoryProvider);
  return repo.statuses.asBroadcastStream();
});

/// True once the model is verified and masking can run.
///
/// A provider rather than a helper so widget tests can declare readiness
/// instead of reaching for a 175 MB download they will never have.
final privacyModelReadyProvider = Provider<bool>((ref) {
  final repo = ref.watch(privacyModelRepositoryProvider);
  final live = ref.watch(privacyModelStatusProvider).value;
  return (live ?? repo.status) is ModelReady;
});

/// Starts the download if needed, and reports progress.
///
/// Safe to call from more than one screen and on every build: the repository
/// joins concurrent callers into a single attempt and returns without touching
/// the network once a verified copy exists.
class PrivacyModelGate extends ConsumerStatefulWidget {
  const PrivacyModelGate({super.key});

  @override
  ConsumerState<PrivacyModelGate> createState() => _PrivacyModelGateState();
}

class _PrivacyModelGateState extends ConsumerState<PrivacyModelGate> {
  @override
  void initState() {
    super.initState();
    // Kick off during the funnel so the wait overlaps a screen the user is
    // reading, instead of landing after payment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(privacyModelRepositoryProvider).ensureReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(privacyModelRepositoryProvider);
    final status = ref.watch(privacyModelStatusProvider).value ?? repo.status;

    // Nothing to say once it is ready. The green card after masking is where
    // the user learns this happened.
    if (status is ModelReady) return const SizedBox.shrink();

    final (label, detail, showBar, fraction) = switch (status) {
      ModelDownloading(:final fraction) => (
        'Preparing the privacy filter',
        fraction == null
            ? 'Downloading, so your chat can be masked on this device'
            : 'Downloading ${(fraction * 100).round()}%, so your chat can be '
                  'masked on this device',
        true,
        fraction,
      ),
      ModelVerifying() => (
        'Checking the privacy filter',
        'Almost ready',
        true,
        null,
      ),
      ModelFailed(:final message) => (
        'The privacy filter could not be prepared',
        message,
        false,
        null,
      ),
      _ => (
        'Preparing the privacy filter',
        'Your chat is masked on this device before anything is sent',
        true,
        null,
      ),
    };

    final failed = status is ModelFailed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: failed ? const Color(0xFFFDECEF) : Colors.white,
        border: Border.all(
          color: failed ? const Color(0xFFF5C2CC) : const Color(0xFFE9E4F5),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.error_outline : Icons.shield_outlined,
                size: 18,
                color: failed
                    ? const Color(0xFF9B1C3A)
                    : PortraitorTokens.onboardingPrimaryDeep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: failed
                        ? const Color(0xFF9B1C3A)
                        : PortraitorTokens.onboardingInk,
                  ),
                ),
              ),
              if (failed)
                TextButton(
                  onPressed: () => repo.ensureReady(),
                  child: const Text('Retry'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(
              fontFamily: PortraitorTokens.fontBody,
              fontSize: 12,
              height: 1.35,
              color: PortraitorTokens.onboardingInkSoft,
            ),
          ),
          if (showBar) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                backgroundColor: const Color(0xFFE6E0F5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  PortraitorTokens.onboardingPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
