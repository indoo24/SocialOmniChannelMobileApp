/// Compact, animated icon-only "Resolved" button in the conversation header.
///
/// Unresolved: light mint background with a green checkmark (✓).
/// Tapping: runs a smooth scale + ripple/glow animation and calls the resolve API.
/// Resolved: dark green background with a white double-check (✓✓); tapping
/// it again reopens the conversation.
///
/// After a resolve the confirmation offers Undo for [undoWindow]: it puts the
/// conversation back to the status it had, through the same status endpoint,
/// and only once the server has accepted that is it shown as reopened.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
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
    this.undoWindow = defaultUndoWindow,
    super.key,
  });

  final Conversation conversation;
  final bool canChange;

  /// How long the Undo offered after resolving stays available.
  final Duration undoWindow;

  static const defaultUndoWindow = Duration(seconds: 5);

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

    if (!widget.canChange) return;

    // The button toggles: tapped while resolved, it reopens.
    if (_isResolved) return _reopen();

    // What Undo goes back to. Read before the request, which changes it.
    final previousStatus = widget.conversation.status;
    final conversationId = widget.conversation.id;

    setState(() => _busy = true);
    _controller.forward(from: 0.0);

    try {
      await ref
          .read(conversationControllerProvider(conversationId).notifier)
          .updateStatus('RESOLVED');
      if (mounted) {
        showResolveUndoSnackBar(
          context,
          conversationId: conversationId,
          previousStatus: previousStatus,
          undoWindow: widget.undoWindow,
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

  /// Puts a resolved conversation back to Open through the status endpoint.
  /// Shown as open only once the server accepted it; on a refusal the button
  /// returns to resolved and says why.
  Future<void> _reopen() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() => _busy = true);
    // A resolve's Undo would now fight this reopen; it is no longer needed.
    messenger.hideCurrentSnackBar();
    _controller.reverse(from: 1.0);

    try {
      await ref
          .read(conversationControllerProvider(widget.conversation.id).notifier)
          .updateStatus('OPEN');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.conversationReopenedSnackbar)),
      );
    } catch (e) {
      if (mounted) _controller.value = 1.0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException && e.message.isNotEmpty
                ? e.message
                : l10n.statusUpdateFailedMessage,
          ),
          backgroundColor: errorColor,
        ),
      );
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
                        // Resolves, or reopens when already resolved.
                        onTap: widget.canChange ? _handleTap : null,
                        child: SizedBox(
                          width: 38,
                          height: 38,
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

/// Shows "Conversation resolved" with Undo, after a resolve the server has
/// accepted. Undo puts the conversation back to [previousStatus] through the
/// status endpoint, via the conversation's controller so the thread and the
/// inbox both follow — and says "reopened" only once the server agreed.
///
/// Everything Undo needs is taken from [context] now: the agent may have left
/// the conversation by the time they tap it.
void showResolveUndoSnackBar(
  BuildContext context, {
  required int conversationId,
  required String previousStatus,
  Duration undoWindow = ConversationResolveButton.defaultUndoWindow,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final l10n = context.l10n;
  final errorColor = Theme.of(context).colorScheme.error;
  var undone = false;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('resolveUndoSnackBar'),
        content: Text(l10n.conversationResolvedSnackbar),
        duration: undoWindow,
        // A snack bar with an action otherwise stays until dismissed; the
        // Undo window is meant to close by itself.
        persist: false,
        action: SnackBarAction(
          key: const Key('resolveUndoAction'),
          label: l10n.undoAction,
          onPressed: () async {
            // One Undo per resolve, however the action is reached.
            if (undone) return;
            undone = true;
            if (kDebugMode) {
              debugPrint(
                '[RESOLVE_UNDO] conversation=$conversationId '
                'restoring=$previousStatus',
              );
            }
            try {
              await container
                  .read(conversationControllerProvider(conversationId).notifier)
                  .updateStatus(previousStatus);
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.conversationReopenedSnackbar)),
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  '[RESOLVE_UNDO] conversation=$conversationId failed '
                  '(${e.runtimeType})',
                );
              }
              // Nothing changed locally: the controller only applies a
              // status the server accepted, so it still reads Resolved.
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    e is ApiException && e.message.isNotEmpty
                        ? e.message
                        : l10n.resolveUndoFailedMessage,
                  ),
                  backgroundColor: errorColor,
                ),
              );
            }
          },
        ),
      ),
    );
}
