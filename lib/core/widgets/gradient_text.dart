/// Text painted with a gradient fill instead of a flat colour.
library;

import 'package:flutter/widgets.dart';

class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    required this.style,
    required this.gradient,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style.copyWith(color: const Color(0xFFFFFFFF))),
    );
  }
}
