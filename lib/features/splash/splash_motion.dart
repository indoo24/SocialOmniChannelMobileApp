/// Stage geometry, timeline and colours for the splash logo animation.
///
/// Every sprite lives in a fixed 1254x1254 "stage" space; [SplashStage] maps
/// that space onto the screen. One controller runs 0.0-1.0 over
/// [SplashMotion.introDuration] and each element reads its own millisecond
/// window of it through [SplashMotion.progress], so the whole intro stays a
/// single Ticker.
library;

import 'package:flutter/animation.dart';

class SplashMotion {
  const SplashMotion._();

  /// Scales the whole intro timeline: 2.0 plays it twice as fast, 0.5 at half
  /// speed. The loader loop and the exit fade are not affected.
  static const double speed = 1.0;

  /// Length of the intro at [speed] 1.0. All the window bounds below are in
  /// these milliseconds.
  static const double introMs = 5400;

  static Duration get introDuration =>
      Duration(microseconds: (introMs * 1000 / speed).round());

  static const exitFade = Duration(milliseconds: 350);

  /// One full bounce cycle of a loader dot, and the delay between dots.
  static const loaderCycle = Duration(milliseconds: 1000);
  static const loaderStaggerMs = 150.0;

  /// Overshooting ease used for the "pop in" transforms.
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);

  /// Decelerating ease for slides and the ring's spin-in.
  static const out = Cubic(0.2, 0.8, 0.2, 1.0);

  /// The app icon's accelerating zoom-out.
  static const iconExit = Cubic(0.5, 0, 0.8, 0.4);

  static const pulse = Cubic(0.2, 0.7, 0.3, 1.0);

  /// Linear 0..1 progress through the [startMs]..[endMs] window of the intro,
  /// given the intro controller's [value]; clamped outside the window.
  static double progress(double value, double startMs, double endMs) {
    final ms = value * introMs;
    if (ms <= startMs) return 0;
    if (ms >= endMs) return 1;
    return (ms - startMs) / (endMs - startMs);
  }
}

/// Maps 1254x1254 stage coordinates to screen coordinates for one layout.
class SplashStage {
  SplashStage(Size screen)
    : k = 0.42 * _min(screen.width, screen.height * 390 / 844) / 390,
      _center = screen.center(Offset.zero);

  /// Logical pixels per stage unit.
  final double k;
  final Offset _center;

  static const _origin = Offset(626, 619);

  static double _min(double a, double b) => a < b ? a : b;

  /// Screen position of stage point [stage].
  Offset map(Offset stage) => _center + (stage - _origin) * k;

  /// Screen rect of a sprite placed at stage [left], [top] with stage size
  /// [width] x [height].
  Rect rect(double left, double top, double width, double height) =>
      map(Offset(left, top)) & Size(width * k, height * k);
}

class SplashPalette {
  const SplashPalette._();

  static const background = Color(0xFFFFFFFF);
  static const violet = Color(0xFF6D3EF6);
  static const indigo = Color(0xFF5340F2);
  static const blue = Color(0xFF393CEF);
}
