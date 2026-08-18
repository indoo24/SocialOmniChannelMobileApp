/// Fade + upward-slide (+ optional scale) entrance reveal.
///
/// Shared by the splash sequence's staged elements so each stage reads from
/// the same easing/motion language instead of hand-rolling its own
/// Opacity/Transform pair.
library;

import 'package:flutter/widgets.dart';

class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    required this.animation,
    required this.child,
    this.slideOffset = 14,
    this.scaleBegin = 1.0,
    super.key,
  });

  /// Drives the reveal; 0 = fully hidden, 1 = fully settled.
  final Animation<double> animation;
  final Widget child;

  /// Vertical distance (logical px) the child travels upward into place.
  final double slideOffset;

  /// Starting scale factor. 1.0 (the default) disables the scale effect.
  final double scaleBegin;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        Widget result = Opacity(opacity: t, child: child);
        if (scaleBegin != 1.0) {
          result = Transform.scale(
            scale: scaleBegin + (1.0 - scaleBegin) * t,
            child: result,
          );
        }
        return Transform.translate(
          offset: Offset(0, slideOffset * (1 - t)),
          child: result,
        );
      },
      child: child,
    );
  }
}
