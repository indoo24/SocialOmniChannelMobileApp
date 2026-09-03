/// A single message.
///
/// Customer left, agent right, system centred — the same arrangement as the
/// web thread. The important detail is the failure state: a reply the backend
/// rejected is visibly **not sent**, with the server's reason and a way to
/// retry, never a checkmark.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/message.dart';
import '../../core/realtime/realtime_logger.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/safe_url.dart';
import '../../core/utils/formatting.dart';
import '../../l10n/l10n_extensions.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    this.onRetry,
    this.onDiscard,
    this.onDelete,
    super.key,
  });

  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  /// Long-press to delete. Null hides the affordance entirely — the caller
  /// only supplies this for a real, server-confirmed message when the
  /// signed-in employee holds `conversation.delete_message` (ADMIN/SUPERVISOR).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
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

    final background = failed
        ? theme.colorScheme.error.withValues(alpha: 0.10)
        : isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surface;

    final foreground = failed
        ? theme.colorScheme.onSurface
        : isMine
        ? Colors.white
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 3),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onLongPress: onDelete,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMine ? 16 : 4),
                          bottomRight: Radius.circular(isMine ? 4 : 16),
                        ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.attachments.isNotEmpty)
                            _Attachments(message: message),
                          if (message.text.isNotEmpty)
                            Text(
                              message.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: foreground,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _MetaRow(message: message),
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
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = <String>[
      if (message.isOutbound && message.senderName.isNotEmpty)
        message.senderName,
      formatTime(context, message.sentAt),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labels.join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: theme.textTheme.labelSmall?.color?.withValues(alpha: 0.75),
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

    final (icon, color) = switch (message.deliveryStatus) {
      'READ' => (Icons.done_all, ScenarioColors.info),
      'DELIVERED' => (Icons.done_all, theme.textTheme.labelSmall?.color),
      _ => (Icons.done, theme.textTheme.labelSmall?.color),
    };

    return Icon(icon, size: 12, color: color);
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
    final reason = message.deliveryError.isNotEmpty
        ? message.deliveryError
        : context.l10n.notDeliveredFallback;

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

class _Attachments extends StatelessWidget {
  const _Attachments({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attachment in message.attachments)
          Builder(
            builder: (context) {
              // Attachment URLs reach the app from inbound channel messages,
              // so their content is ultimately customer-controlled. Anything
              // that is not an https URL degrades to the file chip, which
              // names the attachment without fetching it.
              final safeUrl = SafeUrl.forImage(attachment.url);
              return Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: attachment.isImage && safeUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: CachedNetworkImage(
                          imageUrl: safeUrl,
                          width: 220,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              _FileChip(attachment: attachment),
                        ),
                      )
                    : _FileChip(attachment: attachment),
              );
            },
          ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
          Icon(_iconFor(attachment.type), size: 16),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              attachment.fileName.isEmpty
                  ? attachment.type.toLowerCase()
                  : attachment.fileName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
    'IMAGE' => Icons.image_outlined,
    'VIDEO' => Icons.videocam_outlined,
    'AUDIO' => Icons.mic_none,
    'LOCATION' => Icons.location_on_outlined,
    _ => Icons.attach_file,
  };
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
