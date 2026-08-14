import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/pending_job_resume_card.dart';

PendingJob _job() {
  final now = DateTime.utc(2026, 6, 8, 12);
  return PendingJob(
    id: 'conv_resumable',
    deviceId: 'device_test',
    clientConversationRef: 'conv_resumable',
    inputText: 'hello chat',
    targetName: 'Alice',
    dateRange: 'Jan 2026',
    paymentSessionId: 'apl_0123456789abcdef0123456789abcdef',
    publicUuid: 'uuid-buyer-1',
    status: 'processing',
    chunksCompleted: 1,
    chunksTotal: 3,
    chunkResults: const [
      {'index': 0, 'content': 'first chunk'},
    ],
    chunkingMode: 'map-reduce',
    tokenLimit: 250000,
    chunkOverlapTokens: 250,
    createdAt: now,
    updatedAt: now,
  );
}

/// Records what the card asked the notifier to do, and lets a test hold
/// `cancelJob` open so the busy state can be observed.
class _RecordingNotifier extends PendingJobRecoveryNotifier {
  _RecordingNotifier() : super(api: _NoOpApi());

  int cancelCount = 0;
  int removeAnywayCount = 0;
  final List<String> dropped = [];
  Completer<void>? blockCancel;

  /// What cancelJob answers, so a test can put the card in front of a refusal
  /// rather than assume how one reads.
  CancelOutcome outcome = const CancelOutcome.discarded(
    funding: PendingJobFunding.storePurchase,
    purchaseKept: true,
  );

  @override
  Future<CancelOutcome> cancelJob(PendingJob job) async {
    cancelCount++;
    if (blockCancel != null) await blockCancel!.future;
    return outcome;
  }

  @override
  Future<void> removeJobAnyway(PendingJob job) async {
    removeAnywayCount++;
    dropped.add(job.id);
  }

  @override
  void dropClassification(String jobId) => dropped.add(jobId);

  @override
  Future<void> refresh() async {}
}

class _NoOpApi extends Fake implements ApiService {}

/// Routes recorded by the harness router, so a resume can be asserted on
/// behaviour rather than on the shape of the source.
class _Recorder {
  final List<String> paths = [];
  final List<Object?> extras = [];
}

Widget _harness({
  required RecoveryStatus status,
  _RecordingNotifier? notifier,
  _Recorder? recorder,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder:
            (_, __) => Scaffold(
              body: PendingJobResumeCard(
                classification: RecoveryClassification(
                  job: _job(),
                  status: status,
                ),
              ),
            ),
      ),
      GoRoute(
        path: '/processing',
        builder: (_, state) {
          recorder?.paths.add('/processing');
          recorder?.extras.add(state.extra);
          return const Scaffold(body: Text('processing'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      pendingJobRecoveryProvider.overrideWith(
        (ref) => notifier ?? _RecordingNotifier(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('what each state offers', () {
    testWidgets('a deferred store purchase waits without destructive actions', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.storePending));

      expect(find.text('Waiting for purchase approval'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a resumable portrait offers Continue and Cancel', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.resumable));

      expect(find.text('Unfinished portrait'), findsOneWidget);
      expect(
        find.text('Continue the portrait for Alice, or cancel it.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(
        find.text('Later'),
        findsNothing,
        reason:
            'Later meant "ask me again", forever. Cancel is the way out the '
            'banner never had',
      );
      expect(
        find.byKey(const Key('pending_job_resume_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pending_job_cancel_button')),
        findsOneWidget,
      );
    });

    testWidgets('a portrait the server is finalizing offers nothing to tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.serverFinalizing),
      );

      expect(find.text('Finishing your portrait'), findsOneWidget);
      expect(
        find.byKey(const Key('pending_job_resume_button')),
        findsNothing,
        reason:
            'the server is delivering; a local resume would duplicate the '
            'validate, email and capture pipeline',
      );
      expect(
        find.byType(FilledButton),
        findsNothing,
        reason:
            'there is nothing for the user to decide, so offering a '
            'button would only teach them to tap something inert',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('an unresumable portrait offers Cancel only', (tester) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.cancelOnly));

      expect(find.byKey(const Key('pending_job_resume_button')), findsNothing);
      expect(
        find.byKey(const Key('pending_job_cancel_button')),
        findsOneWidget,
        reason:
            'a 404 from job-status means the server lost the run, not the '
            'money, so this goes through the path that frees the purchase',
      );
    });
  });

  group('actions', () {
    testWidgets('resuming routes to processing with the job it left off', (
      tester,
    ) async {
      final recorder = _Recorder();
      final notifier = _RecordingNotifier();
      await tester.pumpWidget(
        _harness(
          status: RecoveryStatus.resumable,
          notifier: notifier,
          recorder: recorder,
        ),
      );

      await tester.tap(find.byKey(const Key('pending_job_resume_button')));
      await tester.pumpAndSettle();

      expect(recorder.paths, ['/processing']);
      final extra = recorder.extras.single! as Map<String, dynamic>;
      expect(extra['normalizedText'], 'hello chat');
      expect(extra['targetName'], 'Alice');
      expect(extra['conversationId'], 'conv_resumable');
      expect(
        extra['paymentReference'],
        'apl_0123456789abcdef0123456789abcdef',
        reason:
            'the route carries an opaque Portraitor reference, never a '
            "provider's own transaction id",
      );
      expect(
        extra['resume'],
        true,
        reason:
            'processing must resume rather than start, or the user pays '
            'for work already done',
      );
      expect(
        notifier.dropped,
        ['conv_resumable'],
        reason:
            'the card must clear itself so a resumed job is not offered '
            'again behind the processing screen',
      );
    });

    testWidgets('Cancel asks before it destroys anything', (tester) async {
      final notifier = _RecordingNotifier();
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.resumable, notifier: notifier),
      );

      await tester.tap(find.byKey(const Key('pending_job_cancel_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pending_job_cancel_dialog')),
        findsOneWidget,
      );
      expect(
        notifier.cancelCount,
        0,
        reason: 'nothing may go until the user says so',
      );

      await tester.tap(find.byKey(const Key('pending_job_cancel_dismiss')));
      await tester.pumpAndSettle();

      expect(notifier.cancelCount, 0);
      expect(find.byKey(const Key('pending_job_cancel_dialog')), findsNothing);
    });

    testWidgets('a store-funded cancel promises the purchase, truthfully', (
      tester,
    ) async {
      final notifier = _RecordingNotifier();
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.resumable, notifier: notifier),
      );

      await tester.tap(find.byKey(const Key('pending_job_cancel_button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You keep what you paid for'),
        findsOneWidget,
        reason:
            'the store charged at confirmation; telling the buyer the money '
            'is gone would be a lie',
      );

      await tester.tap(find.byKey(const Key('pending_job_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(notifier.cancelCount, 1);
      expect(
        find.textContaining('saved for your next portrait'),
        findsOneWidget,
      );
    });

    testWidgets('a double confirm cancels once', (tester) async {
      final notifier = _RecordingNotifier()..blockCancel = Completer<void>();
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.resumable, notifier: notifier),
      );

      final cancel = find.byKey(const Key('pending_job_cancel_button'));
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_job_cancel_confirm')));
      await tester.pump();
      await tester.tap(cancel, warnIfMissed: false);
      await tester.pump();

      expect(
        notifier.cancelCount,
        1,
        reason:
            'a second cancel would POST against a job already being torn '
            'down',
      );

      notifier.blockCancel!.complete();
      await tester.pumpAndSettle();
    });
  });

  /// A cancel that cannot free the purchase used to end at a snackbar, which
  /// left the card on the home screen with no action that could ever clear it.
  /// Protecting the money is right; making the card immortal was not.
  group('a cancel the app cannot complete', () {
    Future<_RecordingNotifier> tapCancel(
      WidgetTester tester,
      CancelOutcome outcome,
    ) async {
      final notifier = _RecordingNotifier()..outcome = outcome;
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.resumable, notifier: notifier),
      );
      await tester.tap(find.byKey(const Key('pending_job_cancel_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_job_cancel_confirm')));
      await tester.pumpAndSettle();
      return notifier;
    }

    testWidgets('offers a way out when retrying can never work', (tester) async {
      final notifier = await tapCancel(
        tester,
        const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          isPermanent: true,
          error: 'This purchase was made before the app could move it.',
        ),
      );

      expect(
        find.byKey(const Key('pending_job_remove_anyway_dialog')),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not refund or delete your purchase'),
        findsOneWidget,
        reason:
            'the charge stands, and a customer who reads this as a refund '
            'will not go to support for the money',
      );
      expect(
        notifier.removeAnywayCount,
        0,
        reason: 'the second refusal is still the user\'s to make',
      );

      await tester.tap(
        find.byKey(const Key('pending_job_remove_anyway_confirm')),
      );
      await tester.pumpAndSettle();

      expect(notifier.removeAnywayCount, 1);
      expect(notifier.dropped, ['conv_resumable']);
      expect(find.textContaining('Removed from this phone'), findsOneWidget);
    });

    testWidgets('keeping it removes nothing and still explains why', (
      tester,
    ) async {
      final notifier = await tapCancel(
        tester,
        const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          isPermanent: true,
          error: 'We could not move this purchase.',
        ),
      );

      await tester.tap(
        find.byKey(const Key('pending_job_remove_anyway_dismiss')),
      );
      await tester.pumpAndSettle();

      expect(notifier.removeAnywayCount, 0);
      expect(notifier.dropped, isEmpty);
      expect(
        find.textContaining('could not move this purchase'),
        findsOneWidget,
      );
    });

    testWidgets('a transient failure is never offered as removable', (
      tester,
    ) async {
      final notifier = await tapCancel(
        tester,
        const CancelOutcome.failed(
          funding: PendingJobFunding.storePurchase,
          error: 'This purchase is busy finishing a portrait.',
        ),
      );

      expect(
        find.byKey(const Key('pending_job_remove_anyway_dialog')),
        findsNothing,
        reason:
            'waiting frees the purchase properly, so inviting a throwaway '
            'here would cost the customer a portrait for no reason',
      );
      expect(notifier.removeAnywayCount, 0);
      expect(find.textContaining('busy finishing'), findsOneWidget);
    });
  });

  group('it is a card, not an overlay', () {
    testWidgets('renders inline with no route pushed above it', (tester) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.resumable));

      // The predecessor was a modal bottom sheet pushed onto the shell
      // navigator, which MainTabShell's floating dock then painted over. A
      // card that pushes no route cannot be occluded by a sibling overlay.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PendingJobResumeCard), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).body,
        isA<PendingJobResumeCard>(),
        reason: 'the card belongs to the page, not to a route stacked on it',
      );
    });
  });
}
