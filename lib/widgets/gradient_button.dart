import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = PortraitorTokens.buttonHeightLg,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;

    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: disabled ? null : PortraitorTokens.brandGradient,
        color: disabled ? PortraitorTokens.inkDim : null,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        boxShadow: disabled
            ? null
            : const [
                BoxShadow(
                  color: PortraitorTokens.brandGlow,
                  offset: Offset(0, 14),
                  blurRadius: 36,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                },
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : DefaultTextStyle(
                    style: PortraitorTokens.button,
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}
