/// Branded splash shown while [AuthController] restores a stored session.
///
/// Purely presentational: it runs its entrance animation once and then sits
/// still. Navigation is not this widget's job — `main.dart` already swaps it
/// out for the real app the moment `auth.isRestoring` flips to false, so
/// there is nothing here that could fire a redirect twice.
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/gradient_text.dart';
import 'splash_brand_mark.dart';
import 'splash_motion.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logo;
  late final Animation<double> _scenarioText;
  late final Animation<double> _omniChannelText;
  late final Animation<double> _tagline;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SplashMotion.totalDuration,
    )..forward();

    _logo = CurvedAnimation(parent: _controller, curve: SplashMotion.logo);
    _scenarioText = CurvedAnimation(
      parent: _controller,
      curve: SplashMotion.scenarioText,
    );
    _omniChannelText = CurvedAnimation(
      parent: _controller,
      curve: SplashMotion.omniChannelText,
    );
    _tagline = CurvedAnimation(
      parent: _controller,
      curve: SplashMotion.tagline,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    final mutedForeground = theme.textTheme.bodySmall!.color!;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final markSize = (constraints.biggest.shortestSide * 0.5).clamp(
              180.0,
              300.0,
            );

            return Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeSlideIn(
                      animation: _logo,
                      scaleBegin: 0.75,
                      slideOffset: 18,
                      child: SizedBox(
                        width: markSize,
                        child: SplashBrandMark(controller: _controller),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    FadeSlideIn(
                      animation: _scenarioText,
                      child: Text(
                        'Scenario',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: foreground,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FadeSlideIn(
                      animation: _omniChannelText,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _OmniChannelDash(),
                          const SizedBox(width: 10),
                          const GradientText(
                            'Omni Channel',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                            gradient: LinearGradient(
                              colors: [
                                SplashPalette.violet,
                                SplashPalette.blue,
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const _OmniChannelDash(),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    FadeSlideIn(
                      animation: _tagline,
                      child: Text(
                        'Omnichannel customer service & intelligence',
                        style: TextStyle(
                          fontSize: 13,
                          color: mutedForeground,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The short flanking rule beside "Omni Channel", matching the wordmark in
/// the reference artwork.
class _OmniChannelDash extends StatelessWidget {
  const _OmniChannelDash();

  @override
  Widget build(BuildContext context) {
    final mutedForeground = Theme.of(context).textTheme.bodySmall!.color!;
    return Container(
      width: 18,
      height: 2,
      color: mutedForeground.withValues(alpha: 0.5),
    );
  }
}
