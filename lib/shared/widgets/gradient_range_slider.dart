import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

class GradientRangeSlider extends StatelessWidget {
  final double startValue;
  final double endValue;
  final double min;
  final double max;
  final ValueChanged<RangeValues> onChanged;
  final String? startLabel;
  final String? endLabel;

  const GradientRangeSlider({
    super.key,
    required this.startValue,
    required this.endValue,
    required this.min,
    required this.max,
    required this.onChanged,
    this.startLabel,
    this.endLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        rangeThumbShape: const RoundRangeSliderThumbShape(
          enabledThumbRadius: 10,
        ),
        activeTrackColor: PortraitorTokens.brandPurple,
        inactiveTrackColor: PortraitorTokens.surfaceSunken,
        thumbColor: Colors.white,
        overlayColor: PortraitorTokens.brandPurple.withValues(alpha: 0.12),
        trackHeight: 6,
        rangeValueIndicatorShape: const PaddleRangeSliderValueIndicatorShape(),
        valueIndicatorColor: PortraitorTokens.brandPurple,
        valueIndicatorTextStyle: PortraitorTokens.bodySm.copyWith(
          color: Colors.white,
        ),
      ),
      child: RangeSlider(
        values: RangeValues(startValue, endValue),
        min: min,
        max: max,
        onChanged: onChanged,
        labels: RangeLabels(
          startLabel ?? startValue.round().toString(),
          endLabel ?? endValue.round().toString(),
        ),
      ),
    );
  }
}
