import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/pending_job_resume_sheet.dart';

PendingJob _resumableJob() {
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

/// Render the sheet widget directly inside a Scaffold, bypassing
/// showModalBottomSheet. The recovery provider is overridden with a fake
/// notifier whose async methods are no-ops, so taps cannot trigger real
/// sqflite or HTTP work that would deadlock the widget tester's FakeAsync
/// clock.
Widget _harness({required RecoveryClassification classification}) {
  return ProviderScope(
    overrides: [
      pendingJobRecoveryProvider.overrideWith(
        (ref) => _NoOpRecoveryNotifier(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: PendingJobResumeSheet(classification: classification),
      ),
    ),
  );
}

class _NoOpRecoveryNotifier extends PendingJobRecoveryNotifier {
  _NoOpRecoveryNotifier() : super(api: _NoOpApi());
}

class _NoOpApi extends Fake implements ApiService {}

void main() {
  group('Source contract — modal flags and disable guards', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/processing/presentation/pending_job_resume_sheet.dart',
      ).readAsStringSync();
    });

    test('showPendingJobResumeSheet uses isDismissible:false and enableDrag:false',
        () {
      // Mobile must match web's non-dismissible resume banner. Swipe-down or
      // scrim-tap closing the sheet would leave the pending row visible on
      // next launch and look like a bug.
      expect(source, contains('isDismissible: false'));
      expect(source, contains('enableDrag: false'));
    });

    test('cancel handler sets _busy before any await (double-tap guard)', () {
      // _onCancel must perform setState(() => _busy = true) BEFORE awaiting
      // the cancel call, so the disabled state is applied synchronously and
      // a double tap on the Cancel button cannot fire two cancel POSTs.
      final cancelStart = source.indexOf('Future<void> _onCancel()');
      expect(cancelStart, greaterThan(0));
      final cancelBody = source.substring(cancelStart, cancelStart + 600);
      final setStateIdx = cancelBody.indexOf('setState(() => _busy = true)');
      final awaitIdx = cancelBody.indexOf('await ');
      expect(setStateIdx, greaterThan(0));
      expect(awaitIdx, greaterThan(0));
      expect(setStateIdx, lessThan(awaitIdx),
          reason: 'setState must run before any await — guarantees the '
              'disabled state lands synchronously.');
      // The handler must also early-return on re-entry.
      expect(cancelBody, contains('if (_busy) return'));
    });

    test('resume handler sets _busy before any await (double-tap guard)', () {
      final resumeStart = source.indexOf('Future<void> _onResume()');
      expect(resumeStart, greaterThan(0));
      final resumeBody = source.substring(resumeStart, resumeStart + 800);
      expect(resumeBody, contains('if (_busy) return'));
      expect(resumeBody, contains('setState(() => _busy = true)'));
    });

    test('clear handler sets _busy before any await (double-tap guard)', () {
      final clearStart = source.indexOf('Future<void> _onClear()');
      expect(clearStart, greaterThan(0));
      final clearBody = source.substring(clearStart, clearStart + 600);
      expect(clearBody, contains('if (_busy) return'));
      expect(clearBody, contains('setState(() => _busy = true)'));
    });

    test('Navigator.pop is guarded by canPop() (safe in test harness and on root route)',
        () {
      // Pop must check canPop() so the same widget works whether shown as
      // a modal bottom sheet (canPop=true) or in a test harness Scaffold
      // (canPop=false) without throwing.
      expect(
        source,
        isNot(contains('Navigator.of(context).pop();')),
        reason: 'Every Navigator.pop must be guarded by canPop()',
      );
      expect(source, contains('if (nav.canPop()) nav.pop()'));
    });

    test('resume callback maps PendingJob fields to processing route args',
        () {
      expect(source, contains("'/processing'"));
      expect(source, contains("'normalizedText': _job.inputText"));
      expect(source, contains("'targetName': _job.targetName"));
      expect(source, contains("'conversationId': _job.id"));
      expect(source, contains("'paymentIntentId': _job.paymentSessionId"));
      expect(source, contains("'dateRange': _job.dateRange"));
      expect(source, contains("'resume': true"),
          reason: 'processing screen must know it is a resume so it can call '
              'resumeProcessing instead of startProcessing in Phase 4.');
    });
  });

  group('PendingJobResumeSheet widget rendering', () {
    testWidgets('resumable classification renders Resume and Cancel buttons',
        (tester) async {
      final classification = RecoveryClassification(
        job: _resumableJob(),
        status: RecoveryStatus.resumable,
      );
      await tester.pumpWidget(_harness(classification: classification));

      expect(find.text('Unfinished portrait'), findsOneWidget);
      expect(
        find.byKey(const Key('pending_job_resume_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pending_job_cancel_button')),
        findsOneWidget,
      );
    });

    testWidgets('serverFinalizing classification shows wait state with no Resume',
        (tester) async {
      final classification = RecoveryClassification(
        job: _resumableJob(),
        status: RecoveryStatus.serverFinalizing,
      );
      await tester.pumpWidget(_harness(classification: classification));

      expect(find.text('Portrait is being finalized'), findsOneWidget);
      expect(
        find.byKey(const Key('pending_job_resume_button')),
        findsNothing,
        reason: 'Server is delivering — local Resume would duplicate the '
            'validation/email/capture pipeline.',
      );
      expect(
        find.byKey(const Key('pending_job_dismiss_button')),
        findsOneWidget,
      );
    });

    testWidgets('cancelOnly classification shows Clear button only',
        (tester) async {
      final classification = RecoveryClassification(
        job: _resumableJob(),
        status: RecoveryStatus.cancelOnly,
      );
      await tester.pumpWidget(_harness(classification: classification));

      expect(find.byKey(const Key('pending_job_resume_button')), findsNothing);
      expect(find.byKey(const Key('pending_job_cancel_button')), findsNothing);
      expect(
        find.byKey(const Key('pending_job_clear_button')),
        findsOneWidget,
      );
    });
  });
}
