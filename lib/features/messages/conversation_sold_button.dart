/// "تم البيع" — the compact icon button in the conversation header.
///
/// It looks exactly as the header's Resolved button did: a light mint square
/// with a green ✓, which turns dark green with a white ✓✓ (with the same
/// scale and glow) once done. What it does is confirm a purchase:
/// `POST /conversations/{id}/confirm-purchase/` with
/// `{confirmed: true, note: ""}`, the employee's word that the purchase
/// actually happened. That ruling is the only way `AGENT_CONFIRMED` comes
/// about, and only the server records it: nothing here sets it, and nothing
/// is shown as confirmed before the server has answered. It is not a status
/// change — resolving is in the conversation's actions sheet — and it creates
/// no order.
///
/// A tap acts at once, as the purchase card's Confirm purchase button does —
/// no question first:
///  - without `conversation.confirm_purchase`: says so; nothing is sent;
///  - on a purchase already known to be confirmed: says by whom; nothing is
///    sent;
///  - otherwise: sends, with a spinner in place of the ✓ and further taps
///    ignored until the server answers; then ✓✓, "Purchase confirmed", and
///    Customer Information shows the confirmed banner from that answer.
///
/// An AI-detected claim is not required: the employee's word is enough to
/// record a sale (a manual confirmation). Whether a conversation without a
/// claim can be confirmed is the server's call — until it accepts those, it
/// answers 400 and that refusal is shown as it says it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/employee.dart';
import '../../core/models/intelligence.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversation_controller.dart';
import 'intelligence_providers.dart';

/// Confirms the purchase on conversation [conversationId] — the header
/// button's tap, shared with the actions sheet's entry (where it lives while
/// conversation markers hold the header's place):
///  - without `conversation.confirm_purchase`: says so; nothing is sent;
///  - on a purchase already known to be confirmed: says by whom; nothing is
///    sent;
///  - otherwise: `POST /conversations/{id}/confirm-purchase/`, then
///    "Purchase confirmed", or the server's refusal.
///
/// Resolves to the server's answer, or null when nothing was confirmed.
Future<ConversationIntelligence?> confirmSale(
  BuildContext context,
  WidgetRef ref,
  int conversationId,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  void say(String message, {bool isError = false}) => messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? errorColor : null,
    ),
  );

  if (!ref.read(canProvider(Perm.conversationConfirmPurchase))) {
    say(l10n.confirmPurchaseForbiddenMessage, isError: true);
    return null;
  }
  // What is already known — not waited for: the tap acts now. Only to
  // avoid a second confirmation of a purchase already confirmed; not a
  // condition for selling (no AI claim is needed).
  final known = ref.read(conversationIntelligenceProvider(conversationId)).value;
  if (known != null && known.isAgentConfirmed) {
    say(
      known.confirmedByName.trim().isEmpty
          ? l10n.purchaseConfirmedMessage
          : l10n.purchaseConfirmedBy(known.confirmedByName.trim()),
    );
    return null;
  }

  try {
    final result = await ref
        .read(conversationControllerProvider(conversationId).notifier)
        .confirmPurchase();
    say(l10n.purchaseConfirmedMessage);
    return result;
  } on SessionExpiredException {
    // The app is already on its way back to sign-in.
  } on RequestCancelledException {
    // Abandoned on purpose: nothing to say.
  } on ApiException catch (error) {
    say(switch (error) {
      _ when error.isForbidden => l10n.confirmPurchaseForbiddenMessage,
      _ when error.isNotFound => l10n.conversationNoLongerAvailable,
      // 400 (while the server still requires a claim: no claim to rule
      // on) and everything else: the server's own explanation.
      _ when error.message.trim().isNotEmpty => error.message,
      _ => l10n.genericErrorFallbackMessage,
    }, isError: true);
  }
  return null;
}

class ConversationSoldButton extends ConsumerStatefulWidget {
  const ConversationSoldButton({required this.conversation, super.key});

  final Conversation conversation;

  @override
  ConsumerState<ConversationSoldButton> createState() =>
      _ConversationSoldButtonState();
}

class _ConversationSoldButtonState extends ConsumerState<ConversationSoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  /// The confirmation is on its way. The button is disabled and shows a
  /// spinner until the server answers, so one tap is one request.
  bool _busy = false;

  int get _id => widget.conversation.id;

  static bool _confirmedIn(ConversationIntelligence? intel) =>
      intel?.isAgentConfirmed ?? false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: _confirmedIn(ref.read(conversationIntelligenceProvider(_id)).value)
          ? 1.0
          : 0.0,
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await confirmSale(context, ref, _id);
      if (mounted && _confirmedIn(result)) _controller.forward(from: 0.0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The intelligence — this button's own answer included, applied by the
    // controller — decides ✓ or ✓✓ whenever it changes while nothing is in
    // flight here.
    ref.listen(conversationIntelligenceProvider(_id), (_, next) {
      if (next is! AsyncData<ConversationIntelligence?>) return;
      if (!_busy && !_controller.isAnimating) {
        _controller.value = _confirmedIn(next.value) ? 1.0 : 0.0;
      }
    });
    final confirmed = _confirmedIn(
      ref.watch(conversationIntelligenceProvider(_id)).value,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Palette — unchanged from the header button this replaces.
    // Mint / light green before; dark green once confirmed.
    final pendingBg = isDark
        ? const Color(0xFF065F46).withValues(alpha: 0.40)
        : const Color(0xFFD1FAE5);
    final pendingIconColor = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF15803D);

    final confirmedBg = isDark
        ? const Color(0xFF059669)
        : const Color(0xFF16A34A);
    const confirmedIconColor = Colors.white;

    final glowColor = isDark
        ? const Color(0x5534D399)
        : const Color(0x4410B981);

    final tooltip = confirmed
        ? context.l10n.purchaseConfirmedMessage
        : context.l10n.markSoldTooltip;

    return Tooltip(
      message: tooltip,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final currentBg = Color.lerp(pendingBg, confirmedBg, t)!;
              final currentIconColor = Color.lerp(
                pendingIconColor,
                confirmedIconColor,
                t,
              )!;
              final isFullyConfirmed = t >= 0.5;

              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Outer expanding glow/ripple ring during the animation
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
                        key: const Key('conversation_sold_button'),
                        // Disabled while the confirmation is in flight.
                        onTap: _busy ? null : _handleTap,
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: Center(
                            child: _busy
                                // The purchase card's in-flight spinner, in
                                // the button's own ink.
                                ? SizedBox(
                                    key: const Key('conversation_sold_busy'),
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: currentIconColor,
                                    ),
                                  )
                                : Icon(
                                    isFullyConfirmed
                                        ? Icons.done_all_rounded
                                        : Icons.check_rounded,
                                    size: isFullyConfirmed ? 19 : 18,
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
