/// Compact, animated icon-only "Resolved" button in the conversation header.
///
/// Unresolved: light mint background with a green checkmark (✓).
/// Tapping: runs a smooth scale + ripple/glow animation and calls the resolve API.
/// Resolved: dark green background with a white double-check (✓✓).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_controller.dart';

class ConversationResolveButton extends ConsumerStatefulWidget {
  const ConversationResolveButton({
    required this.conversation,
    required this.canChange,
    super.key,
  });

  final Conversation conversation;
  final bool canChange;

  @override
  ConsumerState<ConversationResolveButton> createState() =>
      _ConversationResolveButtonState();
}

class _ConversationResolveButtonState
    extends ConsumerState<ConversationResolveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;
  bool _busy = false;

  bool get _isResolved =>
      widget.conversation.status.toUpperCase() == 'RESOLVED';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: _isResolved ? 1.0 : 0.0,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.90,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.90,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_controller);

    _glowAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    );
  }

  @override
  void didUpdateWidget(covariant ConversationResolveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) {
      if (_isResolved && _controller.value != 1.0) {
        _controller.value = 1.0;
      } else if (!_isResolved && _controller.value != 0.0) {
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_busy) return;

    if (_isResolved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.statusUpdatedMessage),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!widget.canChange) return;

    setState(() => _busy = true);
    _controller.forward(from: 0.0);

    try {
      await ref
          .read(conversationControllerProvider(widget.conversation.id).notifier)
          .updateStatus('RESOLVED');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.statusUpdatedMessage),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        _controller.reverse();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _controller.reverse();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.statusUpdateFailedMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Palette:
    // Mint / light green for unresolved
    final unresolvedBg = isDark
        ? const Color(0xFF065F46).withValues(alpha: 0.40)
        : const Color(0xFFD1FAE5);
    final unresolvedIconColor = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF15803D);

    // Dark green for resolved
    final resolvedBg = isDark
        ? const Color(0xFF059669)
        : const Color(0xFF16A34A);
    const resolvedIconColor = Colors.white;

    final glowColor = isDark
        ? const Color(0x5534D399)
        : const Color(0x4410B981);

    final tooltip = _isResolved
        ? context.l10n.conversationResolvedTooltip
        : context.l10n.resolveConversationTooltip;

    return Tooltip(
      message: tooltip,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final currentBg = Color.lerp(unresolvedBg, resolvedBg, t)!;
              final currentIconColor = Color.lerp(
                unresolvedIconColor,
                resolvedIconColor,
                t,
              )!;
              final isFullyResolved = t >= 0.5;

              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Outer expanding glow/ripple ring during tap animation
                  if (_controller.isAnimating)
                    Positioned.fill(
                      child: Transform.scale(
                        scale: 1.0 + (_glowAnimation.value * 0.35),
                        child: Container(
                          decoration: BoxDecoration(
                            color: glowColor.withValues(
                              alpha: (1.0 - _glowAnimation.value) * 0.45,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                  // Button body with scale bounce
                  Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Material(
                      color: currentBg,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const Key('conversation_resolve_button'),
                        onTap: (widget.canChange || _isResolved)
                            ? _handleTap
                            : null,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Center(
                            child: Icon(
                              isFullyResolved
                                  ? Icons.done_all_rounded
                                  : Icons.check_rounded,
                              size: isFullyResolved ? 19 : 18,
                              color: currentIconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
