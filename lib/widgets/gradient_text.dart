import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const GradientText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) =>
          PortraitorTokens.brandGradient.createShader(bounds),
      child: Text(
        text,
        style: (style ?? PortraitorTokens.titleLg).copyWith(color: Colors.white),
      ),
    );
  }
}
