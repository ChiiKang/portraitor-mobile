import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/setup/presentation/setup_screen.dart';

void main() {
  testWidgets('setup does not load or display the legacy backend price', (
    tester,
  ) async {
    var configFetches = 0;

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigFetcherProvider.overrideWithValue(() async {
            configFetches += 1;
            return const {
              'data': {
                'payment': {
                  'priceCents': 123456,
                  'amountDisplay': r'$1,234.56',
                },
              },
            };
          }),
        ],
        child: const MaterialApp(
          home: SetupScreen(
            normalizedText: 'Dan: Hello\nAlex: Hi',
            format: 'whatsapp',
            detectedNames: ['Dan', 'Alex'],
            messageCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(configFetches, 0);
    expect(find.text('TOKEN ESTIMATE'), findsOneWidget);
    expect(find.text('PRICE'), findsNothing);
    expect(find.text(r'$1,234.56'), findsNothing);
    expect(find.text(r'$5.00'), findsNothing);
  });
}
