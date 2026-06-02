import 'package:flutter_test/flutter_test.dart';

import 'mocks.dart';
import '../fixtures/sse_responses.dart';

void main() {
  test('FakeApiService can be instantiated', () {
    final fake = FakeApiService();
    expect(fake, isNotNull);
  });

  test('SseFixtures produces valid JSON strings', () {
    final thinking = SseFixtures.thinkingEvent('test');
    expect(thinking, contains('"type":"thinking"'));

    final sequence = SseFixtures.singleShotSequence();
    expect(sequence.length, 3);

    final raw = SseFixtures.rawSseWithEventTypes();
    expect(raw, contains('event: thought'));
    expect(raw, contains('event: done'));
  });
}
