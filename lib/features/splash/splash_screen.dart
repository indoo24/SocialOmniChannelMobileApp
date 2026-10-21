/// Launch splash: a one-shot logo animation on plain white, followed by a
/// bouncing loader that keeps going until the app is ready.
///
/// Navigation is not this widget's job. `main.dart` keeps it on screen while
/// the session restores, passes that state in as [SplashScreen.initDone], and
/// swaps the root app for the real one when [SplashScreen.onFinished] fires —
/// which happens only once the intro has played, init is done, and the
/// splash has faded out.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'splash_motion.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.initDone,
    required this.onFinished,
    this.playIntro = true,
    super.key,
  });

  /// Whether the app's startup work has finished. The splash holds (loader
  /// bouncing) until this is true.
  final bool initDone;

  /// Called once, after the exit fade, when it is time to leave.
  final VoidCallback onFinished;

  /// False shows the settled final frame straight away — for a splash that
  /// comes back after the intro already played once (e.g. a retried restore).
  final bool playIntro;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: SplashMotion.introDuration,
  );
  late final AnimationController _loader = AnimationController(
    vsync: this,
    duration: SplashMotion.loaderCycle,
  );

  bool _started = false;
  bool _reduceMotion = false;
  bool _exiting = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion || !widget.playIntro) {
      _intro.value = 1;
      if (!_reduceMotion) _loader.repeat();
      _maybeExit();
      return;
    }

    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeExit();
    });
    // Decode every piece first so nothing pops in half-loaded mid-animation.
    // A failed decode only loses that one sprite; the intro still runs.
    Future.wait([
      for (final sprite in _Sprite.all)
        precacheImage(
          AssetImage(sprite.asset),
          context,
          onError: (error, stackTrace) {},
        ),
    ]).then((_) {
      if (!mounted) return;
      _intro.forward();
      _loader.repeat();
    });
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initDone && !oldWidget.initDone) _maybeExit();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loader.dispose();
    super.dispose();
  }

  void _maybeExit() {
    if (_exiting || !widget.initDone || !_intro.isCompleted) return;
    _exiting = true;
    if (_reduceMotion) {
      // May be reached mid-build (didChangeDependencies/didUpdateWidget), and
      // onFinished rebuilds the parent — so hand off after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      setState(() {}); // starts the exit fade; _finish runs at its end
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnimatedOpacity(
      opacity: _exiting && !_reduceMotion ? 0 : 1,
      duration: SplashMotion.exitFade,
      onEnd: () {
        if (_exiting) _finish();
      },
      child: ColoredBox(
        color: SplashPalette.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stage = SplashStage(constraints.biggest);
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, _) => Stack(
                    fit: StackFit.expand,
                    children: _stageChildren(stage, _intro.value),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 92 + bottomInset,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _loader]),
                    builder: (context, _) => _LoaderDots(
                      opacity: SplashMotion.progress(_intro.value, 5040, 5390),
                      cycle: _loader.value,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Every stage element at intro progress [v], back to front.
  List<Widget> _stageChildren(SplashStage stage, double v) {
    double lerp(double a, double b, double t) => a + (b - a) * t;
    double p(double startMs, double endMs) =>
        SplashMotion.progress(v, startMs, endMs);
    double spring(double startMs, double endMs) =>
        SplashMotion.spring.transform(p(startMs, endMs));
    double out(double startMs, double endMs) =>
        SplashMotion.out.transform(p(startMs, endMs));

    // Pop in: fade + scale [from] -> 1 on the spring.
    Widget pop(_Sprite sprite, double startMs, double endMs, double from) {
      final t = spring(startMs, endMs);
      return _placed(stage, sprite, opacity: t, scale: lerp(from, 1, t));
    }

    final ringT = out(2380, 3220);
    final chatBackT = spring(2310, 2800);
    final scenarioT = out(3780, 4410);
    final omniT = out(4200, 4760);
    final taglineT = out(4620, 5110);

    final iconInT = spring(0, 630);
    final iconOutT = SplashMotion.iconExit.transform(p(1540, 2030));

    _PulseRing pulse(double startMs, double endMs, double from, Color color) {
      final linear = p(startMs, endMs);
      final t = SplashMotion.pulse.transform(linear);
      return _PulseRing(
        scale: lerp(0.7, 2.3, t),
        opacity: linear == 0 ? 0 : lerp(from, 0, t),
        color: color,
      );
    }

    return [
      _placed(
        stage,
        _Sprite.ring,
        opacity: ringT,
        scale: lerp(0.86, 1, ringT),
        rotation: lerp(-80, 0, ringT) * math.pi / 180,
        pivot: const Offset(295, 291),
      ),
      _placed(
        stage,
        _Sprite.bubble,
        opacity: spring(1610, 2240),
        scale: lerp(0.6, 1, spring(1610, 2240)),
        pivot: const Offset(204, 200),
      ),
      _placed(
        stage,
        _Sprite.chatBack,
        opacity: chatBackT,
        scale: lerp(0.6, 1, chatBackT),
        dx: lerp(-34, 0, chatBackT) * stage.k,
      ),
      pop(_Sprite.chatFront, 2100, 2590, 0.4),
      for (final (i, icon) in _Sprite.channels.indexed)
        pop(icon, 2800 + 140.0 * i, 3220 + 140.0 * i, 0.3),
      _placed(
        stage,
        _Sprite.wordScenario,
        opacity: scenarioT,
        dy: lerp(46, 0, scenarioT) * stage.k,
      ),
      _placed(
        stage,
        _Sprite.wordOmni,
        opacity: omniT,
        scaleX: lerp(0.8, 1, omniT),
      ),
      _placed(
        stage,
        _Sprite.wordTagline,
        opacity: taglineT,
        dy: lerp(14, 0, taglineT) * stage.k,
      ),
      CustomPaint(
        painter: _PulseRingsPainter(
          center: stage.map(_Sprite.iconCenter),
          baseRadius: _Sprite.iconSize.width / 2 * stage.k,
          rings: [
            pulse(560, 1470, 0.55, SplashPalette.violet),
            pulse(840, 1750, 0.40, SplashPalette.blue),
          ],
        ),
      ),
      _placed(
        stage,
        _Sprite.appIcon,
        opacity: iconInT.clamp(0.0, 1.0) * (1 - iconOutT),
        scale: lerp(0.3, 1, iconInT) * lerp(1, 1.9, iconOutT),
      ),
    ];
  }

  /// [sprite] at its stage rect, faded and transformed about [pivot]
  /// (sprite-local stage units; defaults to the sprite's centre). [dx]/[dy]
  /// are in logical pixels.
  Widget _placed(
    SplashStage stage,
    _Sprite sprite, {
    required double opacity,
    double scale = 1,
    double scaleX = 1,
    double rotation = 0,
    double dx = 0,
    double dy = 0,
    Offset? pivot,
  }) {
    final rect = stage.rect(
      sprite.left,
      sprite.top,
      sprite.width,
      sprite.height,
    );
    final origin = pivot == null
        ? rect.size.center(Offset.zero)
        : pivot * stage.k;
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          origin: origin,
          transform: Matrix4.translationValues(dx, dy, 0)
            ..multiply(Matrix4.rotationZ(rotation))
            ..multiply(Matrix4.diagonal3Values(scale * scaleX, scale, 1)),
          child: Image.asset(
            sprite.asset,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

/// One image piece and where it sits on the 1254x1254 stage.
class _Sprite {
  const _Sprite(this.name, this.left, this.top, this.width, this.height);

  final String name;
  final double left;
  final double top;
  final double width;
  final double height;

  String get asset => 'assets/splash/$name.png';

  static const ring = _Sprite('ring', 331, 174, 589, 581);
  static const bubble = _Sprite('bubble', 422, 265, 408, 439);
  static const chatBack = _Sprite('chat-back', 615, 433, 121, 131);
  static const chatFront = _Sprite('chat-front', 514, 398, 162, 140);

  /// In reveal order.
  static const channels = [
    _Sprite('ch-mail', 568, 121, 117, 117),
    _Sprite('ch-sms', 810, 259, 113, 113),
    _Sprite('ch-instagram', 808, 542, 113, 114),
    _Sprite('ch-globe', 567, 691, 116, 115),
    _Sprite('ch-phone', 324, 542, 114, 114),
    _Sprite('ch-whatsapp', 327, 257, 115, 115),
  ];

  static const wordScenario = _Sprite('word-scenario', 268, 825, 719, 141);
  static const wordOmni = _Sprite('word-omni', 269, 987, 715, 60);
  static const wordTagline = _Sprite('word-tagline', 270, 1073, 713, 46);

  /// The app icon is specified by centre and size rather than corner.
  static const iconCenter = Offset(626, 465);
  static const iconSize = Size(357, 339);
  static final appIcon = _Sprite(
    'app-icon',
    iconCenter.dx - iconSize.width / 2,
    iconCenter.dy - iconSize.height / 2,
    iconSize.width,
    iconSize.height,
  );

  static final all = [
    ring,
    bubble,
    chatBack,
    chatFront,
    ...channels,
    wordScenario,
    wordOmni,
    wordTagline,
    appIcon,
  ];
}

class _PulseRing {
  const _PulseRing({
    required this.scale,
    required this.opacity,
    required this.color,
  });

  final double scale;
  final double opacity;
  final Color color;
}

/// Outline circles expanding out of the app icon. Drawn rather than scaled
/// so the stroke stays 2 logical px at every size.
class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({
    required this.center,
    required this.baseRadius,
    required this.rings,
  });

  final Offset center;
  final double baseRadius;
  final List<_PulseRing> rings;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ring in rings) {
      if (ring.opacity <= 0) continue;
      canvas.drawCircle(
        center,
        baseRadius * ring.scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring.color.withValues(alpha: ring.opacity.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter oldDelegate) => true;
}

/// Three dots bouncing in a staggered loop. [cycle] is the loader
/// controller's 0..1 position within one [SplashMotion.loaderCycle].
class _LoaderDots extends StatelessWidget {
  const _LoaderDots({required this.opacity, required this.cycle});

  final double opacity;
  final double cycle;

  static const _colors = [
    SplashPalette.violet,
    SplashPalette.indigo,
    SplashPalette.blue,
  ];

  @override
  Widget build(BuildContext context) {
    final cycleMs = SplashMotion.loaderCycle.inMilliseconds.toDouble();
    return Opacity(
      opacity: opacity,
      child: Row(
        // Colours run left to right regardless of the app's locale.
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _colors.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            _dot(
              _colors[i],
              (cycle * cycleMs - i * SplashMotion.loaderStaggerMs) % cycleMs,
            ),
          ],
        ],
      ),
    );
  }

  /// Up by 300 ms, back down by 600 ms, at rest for the remainder.
  Widget _dot(Color color, double ms) {
    final double lift;
    if (ms < 300) {
      lift = Curves.easeInOut.transform(ms / 300);
    } else if (ms < 600) {
      lift = Curves.easeInOut.transform(1 - (ms - 300) / 300);
    } else {
      lift = 0;
    }
    return Transform.translate(
      offset: Offset(0, -7 * lift),
      child: Opacity(
        opacity: 0.35 + 0.65 * lift,
        child: SizedBox.square(
          dimension: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
