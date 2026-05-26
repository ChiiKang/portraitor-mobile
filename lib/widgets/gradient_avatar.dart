import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GradientAvatar extends StatelessWidget {
  final String name;
  final double size;

  const GradientAvatar({
    super.key,
    required this.name,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: PortraitorTokens.brandGradient,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontFamily: PortraitorTokens.fontFamily,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
