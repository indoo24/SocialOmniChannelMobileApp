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
import '../../core/utils/formatting.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    this.onRetry,
    this.onDiscard,
    super.key,
  });

  final Message message;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

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
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(Radii.lg),
                        topRight: const Radius.circular(Radii.lg),
                        bottomLeft: Radius.circular(
                          isMine ? Radii.lg : Radii.sm,
                        ),
                        bottomRight: Radius.circular(
                          isMine ? Radii.sm : Radii.lg,
                        ),
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
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  _MetaRow(message: message),
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
      formatTime(message.sentAt),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(labels.join(' · '), style: theme.textTheme.labelSmall),
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
        : 'Not delivered.';

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
                  child: const Text('Discard', style: TextStyle(fontSize: 12)),
                ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
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
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: attachment.isImage && attachment.url.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: CachedNetworkImage(
                      imageUrl: attachment.url,
                      width: 220,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          _FileChip(attachment: attachment),
                    ),
                  )
                : _FileChip(attachment: attachment),
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
