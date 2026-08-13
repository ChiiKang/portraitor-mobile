import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/features/library/presentation/library_screen.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/shared/widgets/session_card.dart';

Portrait _portrait({
  required String id,
  required String name,
  required DateTime at,
}) {
  return Portrait(
    id: id,
    title: name,
    targetName: name,
    mode: 'single',
    status: 'completed',
    createdAt: at.toIso8601String(),
    outputSummary: 'A finished portrait of $name.',
  );
}

PendingJob _pendingJob({
  required String id,
  required String name,
  required DateTime at,
}) {
  return PendingJob(
    id: id,
    deviceId: 'device_test',
    clientConversationRef: id,
    inputText: 'hello chat',
    targetName: name,
    paymentSessionId: 'apl_0123456789abcdef0123456789abcdef',
    publicUuid: 'uuid-buyer-1',
    status: 'processing',
    chunksCompleted: 1,
    chunksTotal: 3,
    chunkResults: const [],
    createdAt: at,
    updatedAt: at,
  );
}

class _NoOpApi extends Fake implements ApiService {}

class _StubPortraits extends PortraitsNotifier {
  _StubPortraits(List<Portrait> portraits) {
    state = PortraitsState(portraits: portraits);
  }

  @override
  Future<void> loadPortraits() async {}
}

class _StubRecovery extends PendingJobRecoveryNotifier {
  _StubRecovery(List<RecoveryClassification> classifications)
    : super(api: _NoOpApi()) {
    state = PendingJobRecoveryState(classifications: classifications);
  }

  @override
  Future<void> refresh() async {}
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  List<Portrait> portraits = const [],
  List<RecoveryClassification> pending = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portraitsProvider.overrideWith((ref) => _StubPortraits(portraits)),
        pendingJobRecoveryProvider.overrideWith(
          (ref) => _StubRecovery(pending),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/library',
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, __) => const LibraryScreen(),
            ),
            GoRoute(
              path: '/result/:id',
              builder: (_, __) => const Scaffold(body: Text('result')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final newest = DateTime.utc(2026, 8, 13, 12);
  final middle = DateTime.utc(2026, 8, 12, 12);
  final oldest = DateTime.utc(2026, 8, 11, 12);

  testWidgets('an unfinished portrait sits in the same chronological list', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      portraits: [
        _portrait(id: 'conv_new', name: 'Nina', at: newest),
        _portrait(id: 'conv_old', name: 'Otto', at: oldest),
      ],
      pending: [
        RecoveryClassification(
          job: _pendingJob(id: 'conv_mid', name: 'Mika', at: middle),
          status: RecoveryStatus.resumable,
        ),
      ],
    );

    final cards =
        tester.widgetList<SessionCard>(find.byType(SessionCard)).toList();
    expect(
      cards.map((card) => card.session.id).toList(),
      ['conv_new', 'conv_mid', 'conv_old'],
      reason:
          'an unfinished portrait belongs where it happened, not pinned to '
          'the top or hidden at the bottom',
    );
    expect(cards[1].session.isUnfinished, isTrue);
    expect(
      find.text('Unfinished'),
      findsOneWidget,
      reason: 'it must not read as a delivered portrait',
    );
  });

  testWidgets('an unfinished portrait offers Cancel and Continue', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      pending: [
        RecoveryClassification(
          job: _pendingJob(id: 'conv_mid', name: 'Mika', at: middle),
          status: RecoveryStatus.resumable,
        ),
      ],
    );

    expect(
      find.byKey(const Key('session_card_cancel_button')),
      findsOneWidget,
      reason: 'Cancel has to be reachable from here, not only from Home',
    );
    expect(
      find.byKey(const Key('session_card_continue_button')),
      findsOneWidget,
    );
  });

  testWidgets('a portrait that cannot be continued still offers Cancel', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      pending: [
        RecoveryClassification(
          job: _pendingJob(id: 'conv_dead', name: 'Mika', at: middle),
          status: RecoveryStatus.cancelOnly,
        ),
      ],
    );

    expect(find.byKey(const Key('session_card_cancel_button')), findsOneWidget);
    expect(find.byKey(const Key('session_card_continue_button')), findsNothing);
  });

  testWidgets('a deferred store purchase offers neither', (tester) async {
    await _pumpLibrary(
      tester,
      pending: [
        RecoveryClassification(
          job: _pendingJob(id: 'conv_wait', name: 'Mika', at: middle),
          status: RecoveryStatus.storePending,
        ),
      ],
    );

    expect(
      find.byKey(const Key('session_card_cancel_button')),
      findsNothing,
      reason:
          'the store may still approve this purchase, and the staged payload '
          'is the only thing that could receive it',
    );
  });

  testWidgets('demo samples stay away when an unfinished portrait exists', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      pending: [
        RecoveryClassification(
          job: _pendingJob(id: 'conv_mid', name: 'Mika', at: middle),
          status: RecoveryStatus.resumable,
        ),
      ],
    );

    expect(find.byType(SessionCard), findsOneWidget);
    expect(
      find.text('James · Emma'),
      findsNothing,
      reason: 'real unfinished work must not be padded out with fiction',
    );
    expect(find.text('Mika'), findsOneWidget);
  });

  testWidgets('demo samples still fill a genuinely empty library', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    expect(find.text('James · Emma'), findsOneWidget);
    expect(find.byKey(const Key('session_card_cancel_button')), findsNothing);
  });
}
