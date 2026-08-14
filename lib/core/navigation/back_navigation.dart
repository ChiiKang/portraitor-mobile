import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Returns to the previous route, or Home when this route has no history.
void popOrGoHome(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}
