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
    paymentSessionId: 'pi_conv_resumable',
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
/// `cancel` open so the busy state can be observed.
class _RecordingNotifier extends PendingJobRecoveryNotifier {
  _RecordingNotifier() : super(api: _NoOpApi());

  int cancelCount = 0;
  final List<String> dropped = [];
  Completer<void>? blockCancel;

  @override
  Future<void> cancel(PendingJob job) async {
    cancelCount++;
    if (blockCancel != null) await blockCancel!.future;
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
    testWidgets('a resumable portrait offers Resume and Later', (tester) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.resumable));

      expect(find.text('Unfinished portrait'), findsOneWidget);
      expect(
        find.text('Continue the portrait for Alice, or keep it for later.'),
        findsOneWidget,
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

    testWidgets('an unresumable portrait offers Clear only', (tester) async {
      await tester.pumpWidget(_harness(status: RecoveryStatus.cancelOnly));

      expect(find.byKey(const Key('pending_job_resume_button')), findsNothing);
      expect(find.byKey(const Key('pending_job_cancel_button')), findsNothing);
      expect(find.byKey(const Key('pending_job_clear_button')), findsOneWidget);
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
        'pi_conv_resumable',
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

    testWidgets('a double tap on Cancel cancels once', (tester) async {
      final notifier = _RecordingNotifier()..blockCancel = Completer<void>();
      await tester.pumpWidget(
        _harness(status: RecoveryStatus.resumable, notifier: notifier),
      );

      final cancel = find.byKey(const Key('pending_job_cancel_button'));
      await tester.tap(cancel);
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
