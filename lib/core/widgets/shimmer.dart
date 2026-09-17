/// Reusable shimmer animation engine and skeleton placeholders.
///
/// Designed to provide lightweight, 60fps/120fps synchronized shimmer loading
/// without external dependencies. Skeletons adapt automatically to dark/light
/// themes, RTL/LTR layouts, and Cairo font typography proportions.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Provides a single synchronized shimmer ticker down the widget tree.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;
  final bool enabled;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AppShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;

    final defaultBase = isDark
        ? const Color(0xFF1E293B) // Dark muted slate
        : const Color(0xFFE2E8F0); // Light subtle slate

    final defaultHighlight = isDark
        ? const Color(0xFF334155) // Subtle highlight in dark mode
        : const Color(0xFFF8FAFC); // Clean highlight in light mode

    final base = widget.baseColor ?? defaultBase;
    final highlight = widget.highlightColor ?? defaultHighlight;

    if (!widget.enabled || !tickerEnabled) {
      return AppShimmerScope(
        animationValue: 0.5,
        baseColor: base,
        highlightColor: highlight,
        isRtl: isRtl,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return AppShimmerScope(
          animationValue: _controller.value,
          baseColor: base,
          highlightColor: highlight,
          isRtl: isRtl,
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

/// InheritedWidget that carries shimmer animation state and colors.
class AppShimmerScope extends InheritedWidget {
  const AppShimmerScope({
    required this.animationValue,
    required this.baseColor,
    required this.highlightColor,
    required this.isRtl,
    required super.child,
    super.key,
  });

  final double animationValue;
  final Color baseColor;
  final Color highlightColor;
  final bool isRtl;

  static AppShimmerScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShimmerScope>();
  }

  /// Derives a sweep gradient corresponding to the current animation frame.
  LinearGradient get gradient {
    // Translate from -1.0 to 2.0 to give a smooth edge-to-edge sweep
    final shift = -1.0 + (animationValue * 3.0);
    final startX = isRtl ? (1.0 - shift) : shift;
    final endX = isRtl ? (-0.5 - shift) : (shift + 1.5);

    return LinearGradient(
      begin: Alignment(startX, -0.2),
      end: Alignment(endX, 0.2),
      colors: [baseColor, highlightColor, baseColor],
      stops: const [0.1, 0.5, 0.9],
    );
  }

  @override
  bool updateShouldNotify(AppShimmerScope oldWidget) {
    return animationValue != oldWidget.animationValue ||
        baseColor != oldWidget.baseColor ||
        highlightColor != oldWidget.highlightColor ||
        isRtl != oldWidget.isRtl;
  }
}

/// A basic rectangular or rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.width,
    this.height,
    this.borderRadius = Radii.md,
    this.shape = BoxShape.rectangle,
    this.margin,
    this.padding,
    this.child,
    super.key,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = AppShimmerScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fallbackBase = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    final decoration = BoxDecoration(
      shape: shape,
      borderRadius: shape == BoxShape.circle
          ? null
          : BorderRadius.circular(borderRadius),
      color: scope == null ? fallbackBase : null,
      gradient: scope?.gradient,
    );

    Widget box = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    return box;
  }
}

/// A circular placeholder, ideal for avatars, icon badges, or status indicators.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({required this.size, this.margin, super.key});

  final double size;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: size,
      height: size,
      shape: BoxShape.circle,
      margin: margin,
    );
  }
}

/// A text placeholder with proportion matching Cairo typography.
class SkeletonText extends StatelessWidget {
  const SkeletonText({
    this.width = 100,
    this.height = 12,
    this.borderRadius = Radii.sm,
    this.margin,
    super.key,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
      margin: margin,
    );
  }
}

/// A container matching the app's standard [Card] decoration with skeleton styling.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: child,
    );
  }
}

/// A top-level helper widget that bundles [AppShimmer] for whole-screen skeletons.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(enabled: enabled, child: child);
  }
}
