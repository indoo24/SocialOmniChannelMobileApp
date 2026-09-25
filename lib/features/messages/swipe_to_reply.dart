import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A custom horizontal drag recognizer that yields immediately to vertical
/// scrolling if vertical movement exceeds horizontal movement, ensuring that
/// conversation scrolling is never impeded.
class _SwipeToReplyGestureRecognizer extends HorizontalDragGestureRecognizer {
  _SwipeToReplyGestureRecognizer({
    required this.isRtl,
    super.debugOwner,
  });

  bool isRtl;
  Offset _startPosition = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _startPosition = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final delta = event.position - _startPosition;
      final dx = delta.dx;
      final dy = delta.dy;

      // 1. If vertical displacement is greater than horizontal displacement,
      // reject this recognizer so the Scrollable's VerticalDragGestureRecognizer
      // immediately wins without any delay or competition.
      if (dy.abs() > dx.abs() && dy.abs() > 4.0) {
        resolve(GestureDisposition.rejected);
        return;
      }

      // 2. In LTR, dragging to the left is an invalid swipe direction.
      // If the user drags leftward by more than 8px, reject so we don't block
      // diagonal scrolls or other handlers.
      if (!isRtl && dx < -8.0) {
        resolve(GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }
}

/// A WhatsApp-style swipe-to-reply wrapper widget.
///
/// When the user drags [child] horizontally past [threshold], haptic feedback
/// is triggered, a reply indicator is revealed, and upon release [onReply]
/// is invoked while [child] smoothly returns to its original position.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    required this.child,
    this.onReply,
    this.isMine = false,
    this.threshold = 64.0,
    super.key,
  });

  final Widget child;
  final VoidCallback? onReply;
  final bool isMine;
  final double threshold;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Animation<double>? _anim;

  double _dragOffset = 0.0;
  bool _hasCrossedThreshold = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      setState(() {
        _dragOffset = _anim?.value ?? 0.0;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (_animController.isAnimating) {
      _animController.stop();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!mounted || widget.onReply == null) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final delta = details.primaryDelta ?? 0.0;

    double newOffset = _dragOffset + delta;

    if (!isRtl) {
      // In LTR, only rightward drag (positive offset) is allowed.
      if (newOffset < 0.0) newOffset = 0.0;
    } else {
      // In RTL, the natural WhatsApp reply swipe is right-to-left (negative offset),
      // but we also permit positive offset if the user swipes rightward.
      // Once one direction starts, prevent drifting across zero in the same gesture.
      if (_dragOffset < 0 && newOffset > 0) newOffset = 0.0;
      if (_dragOffset > 0 && newOffset < 0) newOffset = 0.0;
    }

    final absOffset = newOffset.abs();
    if (!_hasCrossedThreshold && absOffset >= widget.threshold) {
      _hasCrossedThreshold = true;
      HapticFeedback.lightImpact();
    } else if (_hasCrossedThreshold && absOffset < widget.threshold * 0.75) {
      _hasCrossedThreshold = false;
    }

    setState(() {
      _dragOffset = newOffset;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!mounted) return;
    final triggered =
        _hasCrossedThreshold || _dragOffset.abs() >= widget.threshold;
    if (triggered && widget.onReply != null) {
      widget.onReply!();
    }
    _animateBack();
  }

  void _handleDragCancel() {
    if (!mounted) return;
    _animateBack();
  }

  void _animateBack() {
    _hasCrossedThreshold = false;
    _anim = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward(from: 0.0);
  }

  /// Calculates visual translation with rubber-band resistance beyond [threshold].
  double get _effectiveTranslation {
    final abs = _dragOffset.abs();
    final sign = _dragOffset >= 0 ? 1.0 : -1.0;
    if (abs <= widget.threshold) {
      return _dragOffset;
    }
    // Beyond threshold: add friction (0.2x) capped at threshold + 24px (~88px max)
    final excess = abs - widget.threshold;
    final resisted = widget.threshold + (excess * 0.2).clamp(0.0, 24.0);
    return sign * resisted;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) {
      return widget.child;
    }

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final translation = _effectiveTranslation;
    final absTranslation = translation.abs();
    final isPositive = translation >= 0;

    final progress = (absTranslation / widget.threshold).clamp(0.0, 1.0);
    final scale = (0.4 + 0.6 * progress).clamp(0.0, 1.0);
    final opacity = progress;

    // Centered in the gap revealed by the moving bubble
    final indicatorOffset = ((absTranslation - 36.0) / 2).clamp(0.0, 26.0);

    return RawGestureDetector(
      gestures: {
        _SwipeToReplyGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            _SwipeToReplyGestureRecognizer>(
          () => _SwipeToReplyGestureRecognizer(
            isRtl: isRtl,
            debugOwner: this,
          ),
          (_SwipeToReplyGestureRecognizer instance) {
            instance
              ..isRtl = isRtl
              ..onStart = _handleDragStart
              ..onUpdate = _handleDragUpdate
              ..onEnd = _handleDragEnd
              ..onCancel = _handleDragCancel;
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: isPositive ? Alignment.centerLeft : Alignment.centerRight,
        children: [
          if (absTranslation > 4.0)
            Positioned(
              left: isPositive ? indicatorOffset : null,
              right: isPositive ? null : indicatorOffset,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: _ReplyIndicatorBadge(
                    isCrossed: _hasCrossedThreshold,
                    pointsRight: !isPositive,
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(translation, 0.0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReplyIndicatorBadge extends StatelessWidget {
  const _ReplyIndicatorBadge({
    required this.isCrossed,
    this.pointsRight = false,
  });

  final bool isCrossed;
  final bool pointsRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isCrossed
        ? theme.colorScheme.primary
        : (isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHigh);

    final iconColor = isCrossed ? Colors.white : theme.colorScheme.primary;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Transform.flip(
          flipX: pointsRight,
          child: Icon(
            Icons.reply_rounded,
            size: 18,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
