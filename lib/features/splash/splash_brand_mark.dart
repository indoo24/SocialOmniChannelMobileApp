/// The logo mark (speech-bubble + six channel icons) with two animated
/// accents layered around it: a progressive circular "connection" sweep and
/// a brief activation glow behind each channel icon.
///
/// The icon artwork itself is untouched — these accents paint behind it from
/// a [CustomPainter] keyed to the same controller that drives the rest of
/// the splash, so the whole mark stays one Ticker instead of six.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'splash_motion.dart';

/// Icon centres as fractions of the mark image's own box, measured from the
/// artwork (`assets/images/brand_logo_mark.png`, 750x737): mail, WhatsApp,
/// chat, phone, Instagram, globe, evenly spaced on the printed ring.
const _iconAnchors = <Alignment>[
  Alignment(0.0, -0.75),
  Alignment(-0.64, -0.38),
  Alignment(0.64, -0.38),
  Alignment(-0.64, 0.38),
  Alignment(0.64, 0.38),
  Alignment(0.0, 0.79),
];

class SplashBrandMark extends StatelessWidget {
  const SplashBrandMark({required this.controller, super.key});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 750 / 737,
      child: CustomPaint(
        painter: _ConnectionPainter(controller),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.asset(
            'assets/images/brand_logo_mark.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  _ConnectionPainter(this.controller) : super(repaint: controller);

  final AnimationController controller;

  static double _stage(double start, double span, double t) {
    if (t <= start) return 0;
    if (t >= start + span) return 1;
    return (t - start) / span;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = controller.value;
    final center = size.center(Offset.zero);
    final radius = size.width * 0.375;

    // Sweeps once to a full circle, holds briefly, then fades away entirely —
    // so the resting frame is just the printed artwork, with nothing extra
    // left behind, and this never reads as a loading spinner.
    final sweepT = Curves.easeOutCubic.transform(
      _stage(SplashMotion.ringStart, SplashMotion.ringSpan, t),
    );
    final ringEnd = SplashMotion.ringStart + SplashMotion.ringSpan;
    final fadeT = _stage(ringEnd, SplashMotion.ringFadeSpan, t);
    final opacity = sweepT * (1 - Curves.easeIn.transform(fadeT));

    if (opacity > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: const [SplashPalette.violet, SplashPalette.blue],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

      canvas.saveLayer(
        rect.inflate(8),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      canvas.drawArc(rect, -math.pi / 2, sweepT * 2 * math.pi, false, paint);
      canvas.restore();
    }

    for (var i = 0; i < _iconAnchors.length; i++) {
      final start =
          SplashMotion.iconPulseStart + i * SplashMotion.iconPulseStagger;
      final local = _stage(start, SplashMotion.iconPulseSpan, t);
      if (local <= 0 || local >= 1) continue;

      final eased = Curves.easeOut.transform(local);
      final fade = math.sin(local * math.pi);
      final align = _iconAnchors[i];
      final pos = Offset(
        center.dx + align.x * size.width / 2,
        center.dy + align.y * size.height / 2,
      );
      final glowRadius = size.width * 0.1 * (0.7 + 0.3 * eased);
      final glowColor = Color.lerp(
        SplashPalette.violet,
        SplashPalette.blue,
        i / (_iconAnchors.length - 1),
      )!;

      canvas.drawCircle(
        pos,
        glowRadius,
        Paint()
          ..color = glowColor.withValues(alpha: 0.35 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) => false;
}
