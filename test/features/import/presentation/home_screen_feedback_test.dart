import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/theme.dart';
import 'package:portraitor_mobile/features/import/presentation/home_screen.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final spaceGrotesk = FontLoader('Space Grotesk')
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Variable.ttf'));
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await Future.wait([spaceGrotesk.load(), inter.load()]);
  });

  testWidgets('demo portrait feedback clears the floating tab dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainTabShell(child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: portraitorTheme, routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('James · Emma'));
    await tester.pump();

    expect(find.textContaining('Demo session'), findsOneWidget);
    final feedbackRect = tester.getRect(find.textContaining('Demo session'));
    final dockRect = tester.getRect(find.byType(BackdropFilter));
    expect(feedbackRect.bottom, lessThanOrEqualTo(dockRect.top - 8));
  });
}
