import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/processing_screen.dart';

/// A failed run must not look like a working one.
///
/// The screen previously kept its pulse animation, elapsed timer and the
/// "delivered to your email within 5-15 minutes" notice running after the
/// provider had already entered the error state, and PopScope(canPop: false)
/// meant there was no way off it. The user was told a portrait was coming, and
/// then trapped waiting for it.
void main() {
  Future<void> pumpProcessing(
    WidgetTester tester, {
    required ProcessingState state,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        processingProvider.overrideWith((ref) => _StubProcessing(state)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/processing',
            routes: [
              GoRoute(
                path: '/processing',
                builder:
                    (context, state) => const ProcessingScreen(
                      normalizedText: '[01/01/2026, 10:00:00] Emma: hello',
                      targetName: 'Emma',
                      conversationId: 'conv_1',
                      paymentReference: 'credit-uuid-1',
                    ),
              ),
              GoRoute(
                path: '/',
                builder:
                    (context, state) =>
                        const Scaffold(body: Center(child: Text('HOME'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const failure = ProcessingState(
    status: ProcessingStatus.error,
    error: 'ApiException: Payment not found (status: 400, code: null)',
    statusMessage: 'Waiting in queue...',
  );

  testWidgets('a failed run does not promise an email', (tester) async {
    await pumpProcessing(tester, state: failure);

    // The exact false promise that was shipping: the notice rendered
    // unconditionally, so a run that had already failed still told the user
    // their portrait was on its way.
    // By widget type, not copy: the notice renders markdown as spans, so a
    // text match would silently find nothing and pass for the wrong reason.
    expect(
      find.byType(ProcessingEmailNotice),
      findsNothing,
      reason: 'no portrait is coming, so the screen must not say one is',
    );
  });

  testWidgets('a failed run explains itself in plain language', (tester) async {
    await pumpProcessing(tester, state: failure);

    expect(find.text('We could not finish this portrait'), findsOneWidget);
    expect(
      find.textContaining('could not confirm your payment'),
      findsOneWidget,
      reason: 'the first thing read should be the cause, not a stack trace',
    );
    expect(
      find.textContaining('Payment not found'),
      findsNothing,
      reason: 'transport and server details belong in diagnostics, not UI',
    );
    expect(find.textContaining('ApiException'), findsNothing);
  });

  testWidgets('a failed run stops showing progress', (tester) async {
    await pumpProcessing(tester, state: failure);

    expect(
      find.text('Waiting in queue...'),
      findsNothing,
      reason: 'nothing is queued any more',
    );
  });

  testWidgets('a failed run offers a way out', (tester) async {
    await pumpProcessing(tester, state: failure);

    final back = find.text('Back to start');
    expect(back, findsOneWidget, reason: 'PopScope locks the screen otherwise');

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a running job still shows progress and the email notice', (
    tester,
  ) async {
    await pumpProcessing(
      tester,
      state: const ProcessingState(
        status: ProcessingStatus.processing,
        statusMessage: 'Waiting in queue...',
      ),
    );

    // The failure branch must not have swallowed the working one.
    expect(find.text('Waiting in queue...'), findsOneWidget);
    expect(find.byType(ProcessingEmailNotice), findsOneWidget);
    expect(find.text('Back to start'), findsNothing);
  });
}

/// Holds a fixed state without running the real notifier, which would start
/// timers and reach for the network.
class _StubProcessing extends StateNotifier<ProcessingState>
    implements ProcessingNotifier {
  _StubProcessing(super.state);

  // The screen kicks off work in initState. These do nothing so the widget
  // renders the state it was given rather than starting timers and network
  // calls; noSuchMethod alone returns null, which is not a Future.
  @override
  Future<void> startProcessing({
    required String normalizedText,
    required String targetName,
    required String conversationId,
    required String paymentSessionId,
    required String deliveryEmail,
    String? dateRange,
    List<String> people = const [],
    String tier = 'you',
  }) async {}

  @override
  Future<void> resumeProcessing(PendingJob job) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
