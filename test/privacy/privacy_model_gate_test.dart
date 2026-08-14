/// The readiness gate that stops a user paying before their chat can be masked.
///
/// The failure this guards is the one that actually shipped: readiness was
/// checked at generation time, so a first-run user paid and only then met a
/// 175 MB download.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/model/model_repository.dart';
import 'package:portraitor_mobile/features/privacy/presentation/privacy_model_gate.dart';

/// Drives the gate's status without a repository or a network.
late StreamController<ModelStatus> statuses;

Widget _host({required Widget child}) => ProviderScope(
  overrides: [
    privacyModelStatusProvider.overrideWith((ref) => statuses.stream),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Reads the readiness provider through a real container.
bool _readyFor(ModelStatus? status) {
  final container = ProviderContainer(
    overrides: [
      privacyModelReadyProvider.overrideWith(
        (ref) => (status ?? const ModelAbsent(ModelAbsentReason.neverInstalled))
            is ModelReady,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(privacyModelReadyProvider);
}

void main() {
  setUp(() => statuses = StreamController<ModelStatus>.broadcast());
  tearDown(() => statuses.close());

  group('readiness', () {
    test('only a verified model counts as ready', () {
      expect(
        _readyFor(const ModelReady(path: '/m.onnx', version: 'v3', sizeBytes: 1)),
        isTrue,
      );
      for (final notReady in <ModelStatus>[
        const ModelAbsent(ModelAbsentReason.neverInstalled),
        const ModelAbsent(ModelAbsentReason.versionChanged),
        const ModelDownloading(receivedBytes: 10, totalBytes: 100),
        const ModelVerifying(),
        const ModelFailed(stage: ModelFailureStage.download, message: 'boom'),
      ]) {
        expect(
          _readyFor(notReady),
          isFalse,
          reason: '$notReady must not unlock payment',
        );
      }
    });
  });

  group('PrivacyModelGate', () {
    testWidgets('shows download progress as a percentage', (tester) async {
      await tester.pumpWidget(_host(child: const PrivacyModelGate()));
      statuses.add(const ModelDownloading(receivedBytes: 40, totalBytes: 100));
      await tester.pump();

      expect(find.textContaining('Preparing the privacy filter'), findsOneWidget);
      expect(find.textContaining('40%'), findsOneWidget);
    });

    testWidgets('says it is verifying before it says it is ready', (
      tester,
    ) async {
      await tester.pumpWidget(_host(child: const PrivacyModelGate()));
      statuses.add(const ModelVerifying());
      await tester.pump();

      expect(find.textContaining('Checking the privacy filter'), findsOneWidget);
    });

    testWidgets('a failure explains itself and offers a retry', (tester) async {
      await tester.pumpWidget(_host(child: const PrivacyModelGate()));
      statuses.add(
        const ModelFailed(
          stage: ModelFailureStage.download,
          message: 'connection lost',
        ),
      );
      await tester.pump();

      expect(find.textContaining('could not be prepared'), findsOneWidget);
      expect(find.textContaining('connection lost'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('disappears entirely once ready', (tester) async {
      await tester.pumpWidget(_host(child: const PrivacyModelGate()));
      statuses.add(const ModelDownloading(receivedBytes: 1, totalBytes: 2));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      statuses.add(
        const ModelReady(path: '/m.onnx', version: 'v3', sizeBytes: 1),
      );
      await tester.pump();

      // Nothing left to say. The green card after masking is where the user
      // learns this happened.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('privacy filter'), findsNothing);
    });
  });
}
