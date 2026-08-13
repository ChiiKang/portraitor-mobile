import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portraitor_mobile/core/config/runtime_config_provider.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/funnel/presentation/configure_screen.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';

void main() {
  testWidgets('family configuration uses the backend selection limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        runtimeEntitlementsProvider.overrideWithValue(
          const RuntimeEntitlements(
            youMaxPortraits: 1,
            partnerMaxPortraits: 3,
            familyMaxPortraits: 7,
            passPortraitsPerMonth: 12,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(funnelDraftProvider.notifier)
      ..setFromImport(
        normalized: const NormalizationResult(
          text: 'Alex: Hello\nBlake: Hi',
          format: ChatFormat.whatsapp,
          detectedNames: ['Alex', 'Blake'],
          messageCount: 2,
        ),
        dateRange: null,
        tokenEstimate: 10,
      )
      ..selectTier(FunnelTier.family)
      ..setSelectedNames(const ['Alex']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConfigureScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Choose up to 7 portraits from this chat.'),
      findsOneWidget,
    );
    expect(find.text('1 / 7'), findsOneWidget);
    expect(find.textContaining(' / 5'), findsNothing);
  });
}
