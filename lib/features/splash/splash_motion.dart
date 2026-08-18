/// Timing, curves and brand colours for the splash entrance sequence.
///
/// One controller (0.0-1.0 over [totalDuration]) drives every stage; each
/// stage reads its own slice of that controller through the [Interval]s
/// below, so the whole sequence stays a single Ticker instead of five.
library;

import 'package:flutter/animation.dart';

class SplashMotion {
  const SplashMotion._();

  static const totalDuration = Duration(milliseconds: 2500);

  static const logo = Interval(0.08, 0.35, curve: Curves.easeOutCubic);
  static const scenarioText = Interval(0.38, 0.54, curve: Curves.easeOutCubic);
  static const omniChannelText = Interval(
    0.54,
    0.69,
    curve: Curves.easeOutCubic,
  );
  static const tagline = Interval(0.69, 0.85, curve: Curves.easeOutCubic);

  /// Circular connection ring: sweeps a full turn, then fades away
  /// completely so the resting frame carries nothing but the artwork.
  static const ringStart = 0.19;
  static const ringSpan = 0.43;
  static const ringFadeSpan = 0.18;

  /// Stagger window for the six channel-icon activation glows.
  static const iconPulseStart = 0.19;
  static const iconPulseStagger = 0.045;
  static const iconPulseSpan = 0.14;
}

/// Brand purple → blue, sampled from the official logo artwork so the
/// gradient text and connection glow match the mark exactly.
class SplashPalette {
  const SplashPalette._();

  static const violet = Color.fromARGB(255, 60, 53, 248);
  static const blue = Color(0xFF3A46F0);
}
