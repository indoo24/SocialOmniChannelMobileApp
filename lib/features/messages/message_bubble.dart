/// A single message.
///
/// Customer left, agent right, system centred — the same arrangement as the
/// web thread. The important detail is the failure state: a reply the backend
/// rejected is visibly **not sent**, with the server's reason and a way to
/// retry, never a checkmark.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' show ResponseType, Options;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/realtime/realtime_logger.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/external_link.dart';
import '../../core/utils/safe_url.dart';
import '../../core/utils/text_direction.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/linkified_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../core/utils/attachment_helper.dart';
import 'highlight_message_coordinator.dart';
import 'audio_duration.dart';
import 'media_group_grid.dart';
import 'swipe_to_reply.dart';
import 'voice_playback_coordinator.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    this.provider = '',
    this.onRetry,
    this.onDiscard,
    this.onDelete,
    this.onReply,
    this.onQuoteTap,
    this.isHighlighted,
    this.isContinuation = false,
    super.key,
  });

  final Message message;

  /// Directly follows a message from the same side within a few minutes:
  /// drawn closer to it, with the corner facing it less rounded, so a run of
  /// messages reads as one block.
  final bool isContinuation;

  /// The conversation's channel provider (`WHATSAPP`, `INSTAGRAM`, ...),
  /// used only to name the platform in [message.sentFromPlatform]'s label.
  final String provider;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  /// Long-press menu item. Null hides the affordance entirely — the caller
  /// only supplies this for a real, server-confirmed message when the
  /// signed-in employee holds `conversation.delete_message` (ADMIN/SUPERVISOR).
  final VoidCallback? onDelete;

  /// Long-press menu item. Null hides the affordance entirely — the caller
  /// only supplies this for a real, server-confirmed message when the
  /// signed-in employee holds `conversation.reply` (there being nothing to
  /// quote a message *into* without it).
  final VoidCallback? onReply;

  /// Tapping the quoted message preview inside this bubble jumps to and
  /// highlights the referenced message.
  final ValueChanged<int>? onQuoteTap;

  /// Optional highlight override, primarily for testing. When null, observes
  /// [highlightedMessageProvider] for matching message.id.
  final bool? isHighlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgIdStr = message.id.toString();
    final trace = RealtimeLogger.findTraceByMessageOrConvo(msgIdStr, null);
    if (trace != null) {
      RealtimeLogger.markStep(
        trace.traceId,
        'WIDGET_BUILT',
        messageId: msgIdStr,
      );
      RealtimeLogger.log(
        'UI',
        'MESSAGE_WIDGET_BUILT',
        traceId: trace.traceId,
        messageId: msgIdStr,
      );
      RealtimeLogger.finishTrace(trace.traceId);
    }

    if (message.isSystem) return _SystemLine(message: message);

    final theme = Theme.of(context);
    final isMine = message.isOutbound;
    final failed = message.hasFailed || message.isDeliveryFailure;

    final isDark = theme.brightness == Brightness.dark;
    final background = failed
        ? theme.colorScheme.error.withValues(alpha: 0.10)
        : isMine
        ? (isDark
              ? ScenarioColors.darkOutgoingBubble
              : theme.colorScheme.primary)
        : theme.colorScheme.surface;

    final foreground = failed
        ? theme.colorScheme.onSurface
        : isMine
        ? Colors.white
        : theme.colorScheme.onSurface;

    final copyText = copyableMessageText(message.text);

    // Only pictures: the bubble shrinks to a thin frame around them instead
    // of a wide coloured margin.
    final mediaOnly =
        message.attachments.isNotEmpty &&
        message.attachments.every((a) => a.isInlineImage) &&
        message.text.isEmpty &&
        message.replyTo == null &&
        message.contentNotice == null;
    const mediaFrame = 3.0;

    // Every corner round except the tail (bottom, on the sender's side) and,
    // inside a run, the corner facing the message above.
    const round = Radius.circular(Radii.xl);
    const tight = Radius.circular(6);
    final bubbleRadius = BorderRadiusDirectional.only(
      topStart: !isMine && isContinuation ? tight : round,
      topEnd: isMine && isContinuation ? tight : round,
      bottomStart: isMine ? round : tight,
      bottomEnd: isMine ? tight : round,
    );
    final maxBubbleWidth = math.min(
      MediaQuery.sizeOf(context).width * Sizes.bubbleWidthFactor,
      Sizes.bubbleMaxWidth,
    );

    final isTarget = ref.watch(
      highlightedMessageProvider.select((id) => id == message.id),
    );
    final bool activeHighlight = isHighlighted ?? (isTarget == true);
    final highlightColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary.withValues(alpha: 0.25)
        : theme.colorScheme.primary.withValues(alpha: 0.12);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(top: isContinuation ? 0 : Space.xs, bottom: 1),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xxs,
      ),
      decoration: BoxDecoration(
        color: activeHighlight ? highlightColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: SwipeToReply(
              onReply: onReply,
              isMine: isMine,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPressStart:
                          (onReply != null ||
                              copyText != null ||
                              onDelete != null)
                          ? (details) => showMessageActionsMenu(
                              context,
                              position: details.globalPosition,
                              onReply: onReply,
                              copyText: copyText,
                              onDelete: onDelete,
                            )
                          : null,
                      child: Container(
                        padding: mediaOnly
                            ? const EdgeInsets.all(mediaFrame)
                            : const EdgeInsets.symmetric(
                                horizontal: Space.md,
                                vertical: Space.sm + 1,
                              ),
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: bubbleRadius,
                          border: isMine && !failed
                              ? null
                              : Border.all(
                                  color: failed
                                      ? theme.colorScheme.error.withValues(
                                          alpha: 0.35,
                                        )
                                      : theme.colorScheme.outline,
                                ),
                          boxShadow: [
                            if (activeHighlight)
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            else
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.15
                                      : 0.03,
                                ),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                          ],
                        ),
                        child: _clipMedia(
                          mediaOnly,
                          Radii.xl - mediaFrame,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.replyTo != null) ...[
                                _QuoteBlock(
                                  quote: message.replyTo!,
                                  isMine: isMine,
                                  onTap: onQuoteTap != null
                                      ? () => onQuoteTap!(message.replyTo!.id)
                                      : null,
                                ),
                                const SizedBox(height: Space.xs),
                              ],
                              if (message.attachments.isNotEmpty)
                                _Attachments(message: message),
                              if (message.text.isNotEmpty)
                                // Text only — attachments above never are.
                                LinkifiedText(
                                  message.text,
                                  // Laid out in the message's own direction, so
                                  // an Arabic message in the English app (or
                                  // the reverse) wraps and aligns correctly.
                                  textDirection: textDirectionOf(message.text),
                                  // WhatsApp's own `*bold*`, as the customer
                                  // sees it; other channels show asterisks.
                                  whatsappBold:
                                      provider.toUpperCase() == 'WHATSAPP',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: foreground,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                  // The brand colour would vanish on the
                                  // agent's own indigo bubble: there a link is
                                  // the bubble's white, underlined.
                                  linkColor: isMine && !failed
                                      ? foreground
                                      : theme.colorScheme.primary,
                                ),
                              if (message.contentNotice != null)
                                ContentNoticeView(
                                  notice: message.contentNotice!,
                                  color: foreground,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _MetaRow(message: message, provider: provider),
                    ),
                    if (failed) ...[
                      const SizedBox(height: Space.xs),
                      _FailureActions(
                        message: message,
                        onRetry: onRetry,
                        onDiscard: onDiscard,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [child] clipped to [radius] when [clip] is set, so a picture-only
/// bubble's images follow its rounded corners instead of poking past them.
Widget _clipMedia(bool clip, double radius, Widget child) => clip
    ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
    : child;

/// The text the long-press Copy action puts on the clipboard, or null when
/// there is none worth copying (an image/document/voice-only message).
///
/// Only ever the body text the bubble itself displays — never the quoted
/// message, attachment names, ids or `[media: …]` markers, which
/// [Message.fromJson] has already stripped from [Message.text].
String? copyableMessageText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The long-press menu on a bubble (and on an internal note) — Reply, Copy
/// and/or Delete, whichever the caller made available. Positioned at the
/// touch point rather than anchored to the bubble, matching the platform's
/// own context-menu placement.
void showMessageActionsMenu(
  BuildContext context, {
  required Offset position,
  VoidCallback? onReply,
  String? copyText,
  VoidCallback? onDelete,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  // Captured now: the menu route is gone by the time Copy runs.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copiedLabel = context.l10n.messageCopiedSnackbar;
  showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (onReply != null)
        PopupMenuItem<VoidCallback>(
          value: onReply,
          child: ListTile(
            leading: const Icon(Icons.reply_outlined),
            title: Text(context.l10n.replyMessageAction),
          ),
        ),
      if (copyText != null)
        PopupMenuItem<VoidCallback>(
          value: () async {
            await Clipboard.setData(ClipboardData(text: copyText));
            messenger
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(copiedLabel)));
          },
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(context.l10n.copyMessageAction),
          ),
        ),
      if (onDelete != null)
        PopupMenuItem<VoidCallback>(
          value: onDelete,
          child: ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              context.l10n.deleteMessageAction,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
    ],
  ).then((selected) => selected?.call());
}

/// The quote block a reply shows above its own content — a snapshot of the
/// message it answers, rendered the same whether the original is still
/// loaded, deleted, or (rarely) outside this employee's visibility.
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.quote, required this.isMine, this.onTap});

  final QuotedMessage quote;
  final bool isMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.primary;
    final backgroundColor = isMine
        ? Colors.white.withValues(alpha: 0.12)
        : theme.colorScheme.primary.withValues(alpha: 0.08);
    final textColor = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    final summary = quote.isDeleted
        ? context.l10n.quotedMessageDeletedLabel
        : !quote.available
        ? context.l10n.quotedMessageUnavailableLabel
        : quote.text.isNotEmpty
        ? quote.text
        : switch (quote.messageType) {
            'IMAGE' => context.l10n.photoMessageLabel,
            'AUDIO' => context.l10n.voiceMessageLabel,
            _ => context.l10n.attachmentMessageLabel,
          };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: BorderDirectional(
              start: BorderSide(color: accentColor, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quote.senderName.isNotEmpty)
                Text(
                  quote.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.message, this.provider = ''});

  final Message message;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = <String>[
      if (message.isOutbound && message.sentFromPlatform)
        context.l10n.sentFromPlatformLabel(
          ConversationBadges.providerLabel(context, provider),
        )
      else if (message.isOutbound && message.senderName.isNotEmpty)
        message.senderName,
      formatTime(context, message.sentAt),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shrinks before the tick does: a long sender name at a large text
        // size must not push the row past the bubble's width.
        Flexible(
          child: Text(
            labels.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: theme.textTheme.labelSmall?.color?.withValues(alpha: 0.75),
            ),
          ),
        ),
        if (message.isOutbound) ...[
          const SizedBox(width: 4),
          _DeliveryIcon(message: message),
        ],
      ],
    );
  }
}

/// Delivery state, shown only for outbound messages.
///
/// Deliberately never optimistic: a message in flight shows a clock, not a
/// tick. The tick means the backend accepted it.
class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.isPending) {
      return Icon(
        Icons.schedule,
        size: 12,
        color: theme.textTheme.labelSmall?.color,
      );
    }
    if (message.hasFailed || message.isDeliveryFailure) {
      return Icon(
        Icons.error_outline,
        size: 12,
        color: theme.colorScheme.error,
      );
    }

    final (icon, color) = ConversationBadges.deliveryStatusIcon(
      context,
      message.deliveryStatus,
    );

    return Icon(icon, size: 12, color: color);
  }
}

/// The agent-facing reason a message failed: a known server code is
/// translated, anything else falls back to the server's English text, so a new
/// code is never shown as a blank.
String deliveryErrorText(AppLocalizations l10n, Message message) {
  final translated = switch (message.deliveryErrorCode) {
    'channel_unavailable' => l10n.deliveryErrorChannelUnavailable,
    'tiktok_token_invalid' => l10n.deliveryErrorTiktokTokenInvalid,
    'tiktok_permission_denied' => l10n.deliveryErrorTiktokPermissionDenied,
    'tiktok_invalid_request' => l10n.deliveryErrorTiktokInvalidRequest,
    'tiktok_messaging_limit' => l10n.deliveryErrorTiktokMessagingLimit,
    'tiktok_rate_limited' => l10n.deliveryErrorTiktokRateLimited,
    'tiktok_not_eligible' => l10n.deliveryErrorTiktokNotEligible,
    'tiktok_unavailable' => l10n.deliveryErrorTiktokUnavailable,
    'tiktok_media_rejected' => l10n.deliveryErrorTiktokMediaRejected,
    'tiktok_unknown_error' => l10n.deliveryErrorTiktokUnknownError,
    'tiktok_not_ready' => l10n.deliveryErrorTiktokNotReady,
    'tiktok_no_customer_message' => l10n.deliveryErrorTiktokNoCustomerMessage,
    _ => null,
  };
  if (translated != null) return translated;
  if (message.deliveryError.isNotEmpty) return message.deliveryError;
  return l10n.notDeliveredFallback;
}

/// What a message shows when its content is neither text nor a file — a
/// shared TikTok post, a question card, or a type the app cannot display.
/// Says plainly what arrived rather than leaving an empty bubble.
class ContentNoticeView extends StatelessWidget {
  const ContentNoticeView({
    super.key,
    required this.notice,
    required this.color,
  });

  final ContentNotice notice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: color.withValues(alpha: 0.85),
      fontStyle: FontStyle.italic,
      height: 1.35,
    );

    if (notice.kind == 'share_post') {
      final uri = Uri.tryParse(notice.url);
      final canOpen =
          uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tiktokSharedPost, style: style),
          if (canOpen)
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                foregroundColor: color,
              ),
              onPressed: () => openExternalLink(uri),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.tiktokOpenOnTikTok),
            ),
        ],
      );
    }

    final text = notice.kind == 'template'
        ? (notice.title.isNotEmpty
              ? l10n.tiktokQuestionCard(notice.title)
              : l10n.tiktokQuestionCardUntitled)
        : l10n.tiktokUnsupportedContent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child: Icon(Icons.info_outline, size: 16, color: style?.color),
        ),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

class _FailureActions extends StatelessWidget {
  const _FailureActions({required this.message, this.onRetry, this.onDiscard});

  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = deliveryErrorText(context.l10n, message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            reason,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        if (onRetry != null || onDiscard != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onDiscard != null)
                TextButton(
                  onPressed: onDiscard,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.l10n.discardAction,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.l10n.retryMessageAction,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Attachments extends ConsumerWidget {
  const _Attachments({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = <Widget>[];
    final attachments = message.attachments;

    var i = 0;
    while (i < attachments.length) {
      final current = attachments[i];
      if (current.isInlineImage) {
        final imageGroup = <MessageAttachment>[current];
        var j = i + 1;
        while (j < attachments.length && attachments[j].isInlineImage) {
          imageGroup.add(attachments[j]);
          j++;
        }

        if (imageGroup.length >= 2) {
          widgets.add(
            MediaGroupGrid(
              attachments: imageGroup,
              messageId: message.id,
              isOutbound: message.isOutbound,
              onTapImage: (index) async {
                final headers = await ref
                    .read(apiClientProvider)
                    .mediaAuthHeaders();
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ImageViewerScreen(
                      attachments: imageGroup,
                      initialIndex: index,
                      headers: headers,
                      messageId: message.id,
                    ),
                  ),
                );
              },
            ),
          );
        } else {
          widgets.add(
            _Attachment(
              attachment: current,
              isOutbound: message.isOutbound,
              messageId: message.id,
            ),
          );
        }
        i = j;
      } else {
        widgets.add(
          _Attachment(
            attachment: current,
            isOutbound: message.isOutbound,
            messageId: message.id,
          ),
        );
        i++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var idx = 0; idx < widgets.length; idx++)
          Padding(
            padding: EdgeInsets.only(
              bottom: idx == widgets.length - 1 && message.text.isEmpty
                  ? 0
                  : Space.sm,
            ),
            child: widgets[idx],
          ),
      ],
    );
  }
}

class _Attachment extends ConsumerWidget {
  const _Attachment({
    required this.attachment,
    this.isOutbound = true,
    this.messageId,
  });

  final MessageAttachment attachment;
  final bool isOutbound;
  final int? messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [localFilePath] is only ever set on the agent's own just-picked/
    // just-recorded file, before the server has returned anything — never
    // on a server-sourced attachment, so this branch cannot apply to
    // inbound (customer) content.
    final localPath = attachment.localFilePath;
    if (attachment.isInlineImage && localPath != null && localPath.isNotEmpty) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ImageViewerScreen(
              url: '',
              localPath: localPath,
              headers: const {},
              attachment: attachment,
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: Image.file(
            File(localPath),
            width: Sizes.inlineImageWidth,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _FileChip(attachment: attachment, messageId: messageId),
          ),
        ),
      );
    }

    final resolvedUrl = attachment.resolvedUrl;

    if (attachment.isAudio &&
        ((localPath != null && localPath.isNotEmpty) ||
            resolvedUrl.isNotEmpty)) {
      return _VoicePlayer(
        attachment: attachment,
        url: resolvedUrl,
        localPath: localPath,
        isOutbound: isOutbound,
      );
    }

    // Document attachments (such as images sent as WhatsApp documents) remain
    // visually represented as document attachments.
    if (!attachment.isDocument) {
      final safeUrl = SafeUrl.forImage(resolvedUrl);
      if (attachment.isImage && safeUrl.isNotEmpty) {
        return _AttachmentImage(
          attachment: attachment,
          url: safeUrl,
          messageId: messageId,
        );
      }
    }

    return _FileChip(attachment: attachment, messageId: messageId);
  }
}

/// A received/sent image, rendered inline with a loading placeholder and an
/// error fallback, and opening full-screen on tap.
class _AttachmentImage extends ConsumerWidget {
  const _AttachmentImage({
    required this.attachment,
    required this.url,
    this.messageId,
  });

  final MessageAttachment attachment;
  final String url;
  final int? messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, String>>(
      // The content endpoint requires the session cookie; CachedNetworkImage
      // uses its own HTTP client, which the app's Dio cookie interceptor
      // never touches, so the cookie has to be attached by hand here.
      future: ref.read(apiClientProvider).mediaAuthHeaders(),
      builder: (context, snapshot) {
        final headers = snapshot.data;
        if (!snapshot.hasData) return const _ImagePlaceholder();

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ImageViewerScreen(
                url: url,
                headers: headers ?? const {},
                attachment: attachment,
                messageId: messageId,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: headers,
              width: Sizes.inlineImageWidth,
              fit: BoxFit.cover,
              placeholder: (_, _) => const _ImagePlaceholder(),
              errorWidget: (_, _, _) =>
                  _FileChip(attachment: attachment, messageId: messageId),
            ),
          ),
        );
      },
    );
  }
}

/// Where an inline image will appear while it loads: a quiet tile the size of
/// a typical photo, so the thread jumps less when the picture arrives.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: Sizes.inlineImageWidth,
      height: 180,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      alignment: Alignment.center,
      child: Semantics(
        label: context.l10n.photoMessageLabel,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom view of an image attachment or multi-image gallery.
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({
    this.attachments = const [],
    this.initialIndex = 0,
    this.url = '',
    this.headers = const {},
    this.localPath,
    this.attachment,
    this.messageId,
  });

  final List<MessageAttachment> attachments;
  final int initialIndex;
  final String url;
  final Map<String, String> headers;
  final String? localPath;
  final MessageAttachment? attachment;
  final int? messageId;

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  late final List<MessageAttachment> _galleryItems;

  @override
  void initState() {
    super.initState();
    if (widget.attachments.isNotEmpty) {
      _galleryItems = widget.attachments;
      _currentIndex = widget.initialIndex.clamp(0, _galleryItems.length - 1);
    } else if (widget.attachment != null) {
      _galleryItems = [widget.attachment!];
      _currentIndex = 0;
    } else {
      _galleryItems = [
        MessageAttachment(
          type: 'IMAGE',
          url: widget.url,
          localFilePath: widget.localPath,
        ),
      ];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentAttachment = _currentIndex < _galleryItems.length
        ? _galleryItems[_currentIndex]
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _galleryItems.length > 1
            ? Text(
                '${_currentIndex + 1} / ${_galleryItems.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        actions: [
          if (currentAttachment != null)
            Consumer(
              builder: (context, ref, _) => IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: context.l10n.downloadAttachmentAction,
                onPressed: () => AttachmentHelper.saveAttachmentToDownloads(
                  context: context,
                  attachment: currentAttachment,
                  api: ref.read(apiClientProvider),
                  messageId: widget.messageId,
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _galleryItems.length,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemBuilder: (context, index) {
          final item = _galleryItems[index];
          final localPath =
              item.localFilePath ??
              (index == 0 && widget.localPath != null
                  ? widget.localPath
                  : null);
          final hasLocal =
              localPath != null &&
              localPath.isNotEmpty &&
              File(localPath).existsSync();
          final rawUrl = item.resolvedUrl.isNotEmpty
              ? item.resolvedUrl
              : widget.url;
          final safeUrl = SafeUrl.forImage(rawUrl);

          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: hasLocal
                  ? Image.file(File(localPath), fit: BoxFit.contain)
                  : CachedNetworkImage(
                      imageUrl: safeUrl,
                      httpHeaders: widget.headers,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.white38,
                          size: 48,
                        ),
                      ),
                      errorWidget: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 48,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// A voice-message bubble: mic glyph, duration, waveform, and a play/pause control
/// with playback progress, behaving like WhatsApp's:
///
/// * **Idle** — play button, the recording's full length (`0:42`), no speed
///   control.
/// * **Playing** — pause button, the elapsed position counting up from `0:00`,
///   and a small `1x / 1.5x / 2x` speed control.
/// * **Paused** — play button; the position and speed control stay, and play
///   resumes from the same point at the same speed.
/// * **Completed**, or stopped because another voice note started — back to
///   idle: full length shown, speed control hidden, the next play starts from
///   `0:00` at `1x`.
///
/// Audio is played by one [AudioPlayer], created on first play. Before that,
/// the full length comes from the backend's `duration_ms` or, when a note
/// carries none, from the recording's own container header (fetched once and
/// reused for playback — see `audio_duration.dart`).
class _VoicePlayer extends ConsumerStatefulWidget {
  const _VoicePlayer({
    required this.attachment,
    required this.url,
    this.localPath,
    this.isOutbound = true,
  });

  final MessageAttachment attachment;
  final String url;
  final String? localPath;
  final bool isOutbound;

  @override
  ConsumerState<_VoicePlayer> createState() => _VoicePlayerState();
}

enum _PlaybackLoad { idle, loading, ready, error }

class _VoicePlayerState extends ConsumerState<_VoicePlayer>
    with AutomaticKeepAliveClientMixin {
  late final String _playbackId =
      '${identityHashCode(this)}_${widget.attachment.attachmentId}';

  /// The speeds the speed control cycles through, as WhatsApp's does.
  static const _playbackRates = [1.0, 1.5, 2.0];

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  _PlaybackLoad _load = _PlaybackLoad.idle;
  bool _playing = false;

  /// True from the moment playback starts until it completes or another
  /// voice note takes over — including while paused. This is what switches
  /// the label from the full length to the elapsed position, and shows the
  /// speed control.
  bool _started = false;

  /// The player's position. A notifier rather than widget state: it ticks
  /// several times a second, and only the waveform and the time label need
  /// to repaint for it — not the rest of the bubble.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  /// Reported by the player once the audio is loaded — the authority.
  Duration? _duration;

  /// Read from the recording's header before playback, for notes the backend
  /// sent no `duration_ms` for.
  Duration? _fileDuration;

  double _rate = 1.0;

  /// The recording's bytes, fetched at most once: for the header read that
  /// finds the full length, and then for playback.
  Future<Uint8List>? _bytes;

  @override
  bool get wantKeepAlive => _playing || _load == _PlaybackLoad.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveFileDuration());
  }

  @override
  void didUpdateWidget(_VoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url ||
        widget.localPath != oldWidget.localPath) {
      _stopAndReset();
      _resolveFileDuration();
    }
  }

  bool get _hasSource =>
      (widget.localPath?.isNotEmpty ?? false) || widget.url.isNotEmpty;

  Duration? _durationFromAttachment() {
    final ms = widget.attachment.durationMs;
    return ms == null || ms <= 0 ? null : Duration(milliseconds: ms);
  }

  /// The full length: the player's once it has one, otherwise the backend's
  /// `duration_ms`, otherwise the one read from the file's header.
  Duration? get _totalDuration =>
      _duration ?? _durationFromAttachment() ?? _fileDuration;

  Future<Uint8List> _loadBytes() => _bytes ??= _fetchBytes();

  Future<Uint8List> _fetchBytes() async {
    final localPath = widget.localPath;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      return File(localPath).readAsBytes();
    }
    final api = ref.read(apiClientProvider);
    final response = await api.raw.get<List<int>>(
      widget.url,
      options: Options(responseType: ResponseType.bytes),
    );
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status < 200 || status >= 300 || data == null) {
      throw StateError('attachment content fetch failed: $status');
    }
    return Uint8List.fromList(data);
  }

  /// Finds the full length before playback when the backend did not send
  /// one, so an unplayed note shows `0:42` rather than `0:00`. Silent on
  /// failure: pressing play retries the fetch and reports any error then.
  Future<void> _resolveFileDuration() async {
    if (!mounted || !_hasSource || _totalDuration != null) return;
    try {
      final bytes = await _loadBytes();
      final duration = audioDurationFromBytes(bytes);
      if (duration != null && mounted) {
        setState(() => _fileDuration = duration);
      }
    } catch (_) {
      _bytes = null;
    }
  }

  void _safePause() {
    final p = _player;
    if (p != null &&
        p.state != PlayerState.disposed &&
        p.state != PlayerState.stopped) {
      try {
        p.pause();
      } catch (_) {}
    }
  }

  void _disposePlayerOnly() {
    unawaited(_stateSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_completeSub?.cancel());
    _stateSub = null;
    _positionSub = null;
    _durationSub = null;
    _completeSub = null;
    final p = _player;
    _player = null;
    unawaited(p?.dispose());
  }

  void _stopAndReset() {
    try {
      ref.read(activeVoicePlaybackProvider.notifier).clear(_playbackId);
    } catch (_) {}
    _disposePlayerOnly();
    _bytes = null;
    _load = _PlaybackLoad.idle;
    _playing = false;
    _started = false;
    _rate = 1.0;
    _position.value = Duration.zero;
    _duration = null;
    _fileDuration = null;
    if (mounted) setState(() {});
  }

  /// Back to idle, ready for a fresh play: full length shown, speed control
  /// hidden, position rewound and speed back to 1x — on the player itself,
  /// so the next session really does start at normal speed.
  void _endSession() {
    if (!mounted) return;
    final player = _player;
    if (_rate != 1.0 && player != null) {
      unawaited(player.setPlaybackRate(1.0).catchError((_) {}));
    }
    setState(() {
      _playing = false;
      _started = false;
      _rate = 1.0;
    });
    _position.value = Duration.zero;
    updateKeepAlive();
  }

  void _onCompleted() {
    if (!mounted) return;
    try {
      ref.read(activeVoicePlaybackProvider.notifier).clear(_playbackId);
    } catch (_) {}
    if (_playing || _started) _endSession();
  }

  /// Another voice note started playing: stop this one and reset it, rather
  /// than leave it paused half-way with its speed control showing.
  void _onPreempted() {
    _safePause();
    _endSession();
  }

  void _registerAsActive() {
    try {
      ref
          .read(activeVoicePlaybackProvider.notifier)
          .setActive(_playbackId, onPause: _onPreempted);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      ref.read(activeVoicePlaybackProvider.notifier).clear(_playbackId);
    } catch (_) {}
    _disposePlayerOnly();
    _position.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_load == _PlaybackLoad.loading) return;

    if (_playing) {
      // Paused, not ended: position and speed stay for the resume.
      _safePause();
      try {
        ref.read(activeVoicePlaybackProvider.notifier).clear(_playbackId);
      } catch (_) {}
      if (mounted) {
        setState(() => _playing = false);
        updateKeepAlive();
      }
      return;
    }

    // Player already loaded: resume a paused session, or start a new one
    // from the top after completion.
    if (_player != null && _load == _PlaybackLoad.ready) {
      _registerAsActive();
      try {
        if (!_started) {
          try {
            await _player!
                .seek(Duration.zero)
                .timeout(const Duration(milliseconds: 300));
          } catch (_) {}
          _position.value = Duration.zero;
        }
        await _player!.resume();
        if (mounted) {
          setState(() {
            _playing = true;
            _started = true;
          });
          updateKeepAlive();
        }
        return;
      } catch (_) {
        _disposePlayerOnly();
      }
    }

    if (_bytes == null && !_hasSource) {
      if (mounted) setState(() => _load = _PlaybackLoad.error);
      return;
    }

    setState(() => _load = _PlaybackLoad.loading);
    updateKeepAlive();

    try {
      final bytes = await _loadBytes();
      if (!mounted) return;
      _fileDuration ??= audioDurationFromBytes(bytes);

      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);

      _stateSub = player.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        if (state == PlayerState.completed) {
          _onCompleted();
        } else {
          setState(() => _playing = state == PlayerState.playing);
          updateKeepAlive();
        }
      });
      // The real position stream — never a timer. Ignored outside a session
      // so a late tick after completion cannot show a stale position.
      _positionSub = player.onPositionChanged.listen((position) {
        if (!mounted || !_started) return;
        _position.value = position;
      });
      _durationSub = player.onDurationChanged.listen((duration) {
        if (!mounted || duration <= Duration.zero) return;
        setState(() => _duration = duration);
      });
      _completeSub = player.onPlayerComplete.listen((_) {
        _onCompleted();
      });

      _registerAsActive();
      _started = true;
      _position.value = Duration.zero;

      await player.play(BytesSource(bytes));

      if (!mounted) {
        unawaited(player.dispose());
        return;
      }

      _player = player;
      setState(() {
        _load = _PlaybackLoad.ready;
        _playing = true;
      });
      updateKeepAlive();
    } catch (_) {
      _bytes = null;
      _started = false;
      if (mounted) {
        setState(() => _load = _PlaybackLoad.error);
        updateKeepAlive();
      }
    }
  }

  /// 1x → 1.5x → 2x → 1x, on the player itself. Changes speed only: the
  /// player neither restarts nor seeks, and a paused note stays paused.
  Future<void> _cycleRate() async {
    final next =
        _playbackRates[(_playbackRates.indexOf(_rate) + 1) %
            _playbackRates.length];
    setState(() => _rate = next);
    try {
      await _player?.setPlaybackRate(next);
    } catch (_) {}
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final total = _totalDuration;

    final isOutbound = widget.isOutbound;
    final textColor = isOutbound ? Colors.white : theme.colorScheme.onSurface;
    final activeWaveColor = isOutbound
        ? Colors.white
        : theme.colorScheme.primary;
    final inactiveWaveColor = isOutbound
        ? Colors.white.withValues(alpha: 0.40)
        : theme.colorScheme.outlineVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PlaybackButton(
            load: _load,
            playing: _playing,
            onTap: _toggle,
            isOutbound: isOutbound,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 15,
                      color: textColor.withValues(alpha: 0.90),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        context.l10n.voiceNoteLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_started) ...[
                      _SpeedChip(
                        rate: _rate,
                        onTap: _cycleRate,
                        isOutbound: isOutbound,
                      ),
                      const SizedBox(width: 4),
                    ],
                    InkWell(
                      onTap: () => AttachmentHelper.saveAttachmentToDownloads(
                        context: context,
                        attachment: widget.attachment,
                        api: ref.read(apiClientProvider),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Tooltip(
                        message: context.l10n.downloadAttachmentAction,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.download_rounded,
                            size: 16,
                            color: textColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_load == _PlaybackLoad.error)
                  Text(
                    context.l10n.voiceMessagePlaybackFailedError,
                    style: TextStyle(
                      color: isOutbound
                          ? Colors.white
                          : theme.colorScheme.error,
                      fontSize: 11,
                    ),
                  )
                else
                  ValueListenableBuilder<Duration>(
                    valueListenable: _position,
                    builder: (context, position, _) {
                      final elapsed = total != null && position > total
                          ? total
                          : position;
                      final progress =
                          _started && total != null && total.inMilliseconds > 0
                          ? (elapsed.inMilliseconds / total.inMilliseconds)
                                .clamp(0.0, 1.0)
                          : 0.0;
                      // Idle: the full length. In a session (playing or
                      // paused): the elapsed position.
                      final shown = _started
                          ? elapsed
                          : (total ?? Duration.zero);
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 20,
                              child: _AudioWaveform(
                                progress: progress,
                                activeColor: activeWaveColor,
                                inactiveColor: inactiveWaveColor,
                                onSeek: (fraction) {
                                  if (_load == _PlaybackLoad.ready &&
                                      _player != null &&
                                      total != null) {
                                    final target = Duration(
                                      milliseconds:
                                          (total.inMilliseconds * fraction)
                                              .round(),
                                    );
                                    if (!_started) {
                                      setState(() => _started = true);
                                    }
                                    _position.value = target;
                                    _player!.seek(target);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _format(shown),
                            key: const ValueKey('voiceNoteTime'),
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.90),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small `1x` / `1.5x` / `2x` control shown while a voice note is in a
/// playback session — sized to sit inside the label row without making the
/// bubble any taller.
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.rate,
    required this.onTap,
    this.isOutbound = true,
  });

  final double rate;
  final VoidCallback onTap;
  final bool isOutbound;

  static String label(double rate) =>
      rate == rate.roundToDouble() ? '${rate.toInt()}x' : '${rate}x';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isOutbound
        ? Colors.white.withValues(alpha: 0.22)
        : theme.colorScheme.primary.withValues(alpha: 0.12);
    final textColor = isOutbound ? Colors.white : theme.colorScheme.primary;

    return Tooltip(
      message: context.l10n.playbackSpeedTooltip,
      child: Material(
        key: const ValueKey('voiceNoteSpeed'),
        color: bgColor,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              label(rate),
              // "1.5x" reads the same in Arabic; keep it from reordering.
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: textColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackButton extends StatelessWidget {
  const _PlaybackButton({
    required this.load,
    required this.playing,
    required this.onTap,
    this.isOutbound = true,
  });

  final _PlaybackLoad load;
  final bool playing;
  final VoidCallback onTap;
  final bool isOutbound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isOutbound
        ? Colors.white.withValues(alpha: 0.22)
        : theme.colorScheme.primary.withValues(alpha: 0.12);
    final iconColor = isOutbound ? Colors.white : theme.colorScheme.primary;

    if (load == _PlaybackLoad.loading) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        padding: const EdgeInsets.all(10),
        child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
      );
    }

    final icon = load == _PlaybackLoad.error
        ? Icons.refresh
        : (playing ? Icons.pause : Icons.play_arrow);

    final tooltip = playing
        ? context.l10n.pauseVoiceMessageTooltip
        : context.l10n.playVoiceMessageTooltip;

    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 24, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _AudioWaveform extends StatelessWidget {
  const _AudioWaveform({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.onSeek,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onSeek == null
          ? null
          : (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.size.width > 0) {
                final fraction = (details.localPosition.dx / box.size.width)
                    .clamp(0.0, 1.0);
                onSeek!(fraction);
              }
            },
      child: CustomPaint(
        painter: _WaveformPainter(
          progress: progress,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  static const List<double> _barFractions = [
    0.30,
    0.45,
    0.70,
    0.35,
    0.55,
    0.85,
    0.65,
    0.80,
    0.50,
    0.35,
    0.60,
    0.90,
    0.75,
    0.45,
    0.65,
    0.85,
    0.95,
    0.70,
    0.40,
    0.55,
    0.75,
    0.50,
    0.30,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = _barFractions.length;
    if (barCount == 0 || size.width <= 0) return;

    final barWidth = 2.5;
    final totalBarsWidth = barCount * barWidth;
    final spacing =
        (size.width - totalBarsWidth) /
        (barCount - 1).clamp(1, double.infinity);
    final clampedSpacing = spacing.clamp(1.5, 4.0);

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + clampedSpacing);
      if (x + barWidth > size.width) break;

      final barFraction = _barFractions[i];
      final barHeight = (size.height * barFraction).clamp(4.0, size.height);
      final y = (size.height - barHeight) / 2;

      final barProgress = i / barCount;
      final paint = barProgress <= progress ? activePaint : inactivePaint;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}

class _FileChip extends ConsumerStatefulWidget {
  const _FileChip({required this.attachment, this.messageId});

  final MessageAttachment attachment;
  final int? messageId;

  @override
  ConsumerState<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends ConsumerState<_FileChip> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await AttachmentHelper.openAttachment(
        context: context,
        attachment: widget.attachment,
        api: ref.read(apiClientProvider),
        messageId: widget.messageId,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final theme = Theme.of(context);
    final fileName = attachment.isAudio && attachment.durationMs != null
        ? _formatDuration(attachment.durationMs!)
        : (attachment.fileName.isEmpty
              ? attachment.type.toLowerCase()
              : attachment.fileName);

    final ext = attachment.fileExtension.toUpperCase();
    final size = attachment.formattedSize;
    final details = [
      if (size.isNotEmpty) size,
      if (ext.isNotEmpty && !fileName.toUpperCase().endsWith('.$ext')) ext,
    ].join(' · ');

    final hasAction =
        (attachment.localFilePath != null &&
            attachment.localFilePath!.isNotEmpty) ||
        attachment.resolvedUrl.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (hasAction && !_isLoading) ? _handleTap : null,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(attachment), size: 18),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.textTheme.labelSmall?.color?.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(width: Space.xs),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ] else if (hasAction) ...[
                const SizedBox(width: Space.xs),
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  tooltip: context.l10n.downloadAttachmentAction,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: () => AttachmentHelper.saveAttachmentToDownloads(
                    context: context,
                    attachment: attachment,
                    api: ref.read(apiClientProvider),
                    messageId: widget.messageId,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(int durationMs) {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static IconData _iconFor(MessageAttachment attachment) {
    if (attachment.isAudio) return Icons.mic_none;
    if (attachment.hasImageFile || attachment.isImage) {
      return Icons.image_outlined;
    }
    if (attachment.isVideo) return Icons.videocam_outlined;

    final ext = attachment.fileExtension.toLowerCase();
    final mime = attachment.mimeType.toLowerCase();

    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext) ||
        mime.startsWith('video/')) {
      return Icons.videocam_outlined;
    }
    if (ext == 'pdf' || mime.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (['doc', 'docx'].contains(ext) ||
        mime.contains('word') ||
        mime.contains('document')) {
      return Icons.description_outlined;
    }
    if (['xls', 'xlsx', 'csv'].contains(ext) ||
        mime.contains('excel') ||
        mime.contains('spreadsheet')) {
      return Icons.table_chart_outlined;
    }
    if (['ppt', 'pptx'].contains(ext) ||
        mime.contains('presentation') ||
        mime.contains('powerpoint')) {
      return Icons.slideshow_outlined;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext) ||
        mime.contains('zip') ||
        mime.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    if (ext == 'txt' || mime.startsWith('text/')) {
      return Icons.text_snippet_outlined;
    }

    return switch (attachment.type.toUpperCase()) {
      'IMAGE' => Icons.image_outlined,
      'VIDEO' => Icons.videocam_outlined,
      'AUDIO' || 'VOICE' => Icons.mic_none,
      'LOCATION' => Icons.location_on_outlined,
      'FILE' => Icons.insert_drive_file_outlined,
      _ => Icons.attach_file,
    };
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.sm,
      ),
      child: Center(
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
