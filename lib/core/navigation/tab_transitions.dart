import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Horizontal, direction-aware transitions for the Home / Portraits / Profile
/// tabs.
///
/// The dock reads left to right, so a tab to the right of the current one
/// should arrive from the right and a tab to the left should arrive from the
/// left. The page being left slides out the opposite way, so the two pages
/// travel together like a carousel instead of both coming from the right.
class TabTransitions {
  TabTransitions._();

  static const duration = Duration(milliseconds: 260);
  static const _curve = Curves.easeOutCubic;

  /// Index of the tab currently shown. Seeded to Home, the shell entry point.
  static int _currentIndex = 0;

  /// -1 (new tab is to the left), 1 (to the right) or 0 (no lateral movement).
  ///
  /// Read while the transition runs rather than captured per page, so the
  /// arriving and departing pages always agree on which way the stack moved.
  static int _direction = 0;

  @visibleForTesting
  static void resetForTest() {
    _currentIndex = 0;
    _direction = 0;
  }

  /// Builds a shell tab page whose transition points away from [index].
  static Page<void> page({
    required GoRouterState state,
    required int index,
    required Widget child,
  }) {
    _direction = index.compareTo(_currentIndex);
    _currentIndex = index;

    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      child: child,
      transitionsBuilder: buildTransition,
    );
  }

  @visibleForTesting
  static Widget buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_direction == 0) {
      return FadeTransition(opacity: animation, child: child);
    }

    return _TabSlide(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Slides [child] in from the edge the new tab lies towards, and pushes it out
/// the opposite edge once another tab covers it.
class _TabSlide extends StatelessWidget {
  const _TabSlide({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final edge = TabTransitions._direction.toDouble();
        final entering = TabTransitions._curve.transform(
          animation.value.clamp(0.0, 1.0),
        );
        final leaving = TabTransitions._curve.transform(
          secondaryAnimation.value.clamp(0.0, 1.0),
        );

        return FractionalTranslation(
          translation: Offset((1 - entering) * edge - leaving * edge, 0),
          child: child,
        );
      },
    );
  }
}
