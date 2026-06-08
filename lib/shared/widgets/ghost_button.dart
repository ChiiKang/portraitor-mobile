import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

class GhostButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;

  const GhostButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = PortraitorTokens.buttonHeightLg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        border: Border.all(color: PortraitorTokens.borderSoft),
        boxShadow: PortraitorTokens.shadowGhost,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
          child: Center(
            child: DefaultTextStyle(
              style: PortraitorTokens.bodyLg.copyWith(
                fontWeight: FontWeight.w500,
                color: PortraitorTokens.ink,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
