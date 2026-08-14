/// The fail-closed gate. These tests exist because the failure they guard is
/// silent: a resume or state bug that returns raw text would generate a perfectly
/// good portrait while leaking the entire conversation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/privacy/masking_worker.dart';
import 'package:portraitor_mobile/features/privacy/privacy_filter_service.dart';
import 'package:portraitor_mobile/features/privacy/pipeline/types.dart';

class _FakeMasker implements Masker {
  _FakeMasker(this.result);

  final MaskResult result;
  int calls = 0;

  @override
  Future<MaskResult> mask(
    String text, {
    void Function(MaskingProgress)? onProgress,
  }) async {
    calls++;
    onProgress?.call(const MaskingProgress(1, 1));
    return result;
  }

  @override
  Future<void> dispose() async {}
}

/// Builds a service with a session already established, without touching
/// storage. Mirrors what maskForGeneration leaves behind.
PrivacyFilterService _serviceWith(PrivacyMaskSession session) {
  final service = PrivacyFilterService(
    worker: _FakeMasker(
      MaskResult(
        maskedText: session.maskedText,
        entities: session.entities,
        csv: '',
        leaks: session.leaks,
      ),
    ),
  );
  service.adoptSessionForTest(session);
  return service;
}

const _entities = [
  MaskEntity(
    token: '[PERSON1]',
    type: 'person',
    value: 'Natalia',
    count: 2,
    you: false,
  ),
  MaskEntity(
    token: '[PERSON2]',
    type: 'person',
    value: 'Michael',
    count: 1,
    you: false,
  ),
  MaskEntity(
    token: '[EMAIL1]',
    type: 'email',
    value: 'a@b.com',
    count: 1,
    you: false,
  ),
];

const _session = PrivacyMaskSession(
  rawText: 'Natalia: hi Michael, mail a@b.com',
  maskedText: '[PERSON1]: hi [PERSON2], mail [EMAIL1]',
  entities: _entities,
  leaks: [],
);

void main() {
  group('outgoingText fails closed', () {
    test('throws when masking never ran', () {
      final service = PrivacyFilterService(
        worker: _FakeMasker(
          const MaskResult(
            maskedText: '',
            entities: [],
            csv: '',
            leaks: [],
          ),
        ),
      );

      expect(
        () => service.outgoingText('some raw chat'),
        throwsA(isA<PrivacyNotReadyException>()),
      );
    });

    test('throws when the mask was computed from different text', () {
      final service = _serviceWith(_session);

      // The exact resume bug this guards: a mask from conversation A paired
      // with conversation B. Returning either string would be wrong; the only
      // safe answer is to refuse.
      expect(
        () => service.outgoingText('a completely different conversation'),
        throwsA(isA<PrivacyNotReadyException>()),
      );
    });

    test('returns the masked text when it matches exactly', () {
      final service = _serviceWith(_session);

      expect(service.outgoingText(_session.rawText), _session.maskedText);
    });

    test('never returns the raw text on any path', () {
      final service = _serviceWith(_session);

      for (final input in [
        _session.rawText,
        '${_session.rawText} ',
        'other',
        '',
      ]) {
        String? out;
        try {
          out = service.outgoingText(input);
        } on PrivacyNotReadyException {
          continue;
        }
        expect(
          out,
          isNot(contains('Natalia')),
          reason: 'raw name escaped for input ${input.length} chars',
        );
      }
    });

    test('clearing the session re-closes the gate', () {
      final service = _serviceWith(_session);
      expect(service.outgoingText(_session.rawText), isNotEmpty);

      service.clear();

      expect(
        () => service.outgoingText(_session.rawText),
        throwsA(isA<PrivacyNotReadyException>()),
      );
    });
  });

  group('maskedTargetName', () {
    test('returns the token so the prompt matches the transcript', () {
      final service = _serviceWith(_session);
      expect(service.maskedTargetName('Natalia'), '[PERSON1]');
    });

    test('is case and whitespace insensitive', () {
      final service = _serviceWith(_session);
      expect(service.maskedTargetName('  NATALIA  '), '[PERSON1]');
    });

    test('falls back to the real name when it was never detected', () {
      // Correct, not a compromise: an undetected name is still in the masked
      // chat verbatim, so the model needs the real name to find it.
      final service = _serviceWith(_session);
      expect(service.maskedTargetName('Someone Else'), 'Someone Else');
    });

    test('never matches a non-person entity', () {
      final service = _serviceWith(
        const PrivacyMaskSession(
          rawText: 'x',
          maskedText: 'x',
          entities: [
            MaskEntity(
              token: '[EMAIL1]',
              type: 'email',
              value: 'Dana',
              count: 1,
              you: false,
            ),
          ],
          leaks: [],
        ),
      );

      expect(service.maskedTargetName('Dana'), 'Dana');
    });

    test('passes an empty name straight through', () {
      final service = _serviceWith(_session);
      expect(service.maskedTargetName(''), '');
    });
  });

  group('unmask', () {
    test('restores real values in model output', () {
      final service = _serviceWith(_session);

      expect(
        service.unmask('[PERSON1] shows up as grounded, unlike [PERSON2].'),
        'Natalia shows up as grounded, unlike Michael.',
      );
    });

    test('is a no-op without a session, matching a resumed conversation', () {
      final service = PrivacyFilterService(
        worker: _FakeMasker(
          const MaskResult(
            maskedText: '',
            entities: [],
            csv: '',
            leaks: [],
          ),
        ),
      );

      expect(service.unmask('[PERSON1] already stored un-masked'),
          '[PERSON1] already stored un-masked');
    });

    test('unmaskWith resolves from a map read back off disk', () {
      expect(
        PrivacyFilterService.unmaskWith('[PERSON1] and [EMAIL1]', _entities),
        'Natalia and a@b.com',
      );
    });
  });

  test('maskedCount counts occurrences, not distinct entities', () {
    // The green card says "43 details masked", which is occurrences. Counting
    // entities would understate it every time a name repeats.
    expect(_session.maskedCount, 4);
  });
}
