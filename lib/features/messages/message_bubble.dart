/// A single message.
///
/// Customer left, agent right, system centred — the same arrangement as the
/// web thread. The important detail is the failure state: a reply the backend
/// rejected is visibly **not sent**, with the server's reason and a way to
/// retry, never a checkmark.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' show ResponseType, Options;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/providers.dart';
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

class _Attachments extends ConsumerWidget {
  const _Attachments({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < message.attachments.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom:
                  i == message.attachments.length - 1 && message.text.isEmpty
                  ? 0
                  : Space.sm,
            ),
            child: _Attachment(
              attachment: message.attachments[i],
              isOutbound: message.isOutbound,
            ),
          ),
      ],
    );
  }
}

class _Attachment extends ConsumerWidget {
  const _Attachment({required this.attachment, this.isOutbound = true});

  final MessageAttachment attachment;
  final bool isOutbound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [localFilePath] is only ever set on the agent's own just-picked/
    // just-recorded file, before the server has returned anything — never
    // on a server-sourced attachment, so this branch cannot apply to
    // inbound (customer) content.
    final localPath = attachment.localFilePath;
    if (attachment.isImage && localPath != null && localPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Image.file(
          File(localPath),
          width: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _FileChip(attachment: attachment),
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

    final safeUrl = SafeUrl.forImage(resolvedUrl);
    if (attachment.isImage && safeUrl.isNotEmpty) {
      return _AttachmentImage(attachment: attachment, url: safeUrl);
    }

    return _FileChip(attachment: attachment);
  }
}

/// A received/sent image, rendered inline with a loading placeholder and an
/// error fallback, and opening full-screen on tap.
class _AttachmentImage extends ConsumerWidget {
  const _AttachmentImage({required this.attachment, required this.url});

  final MessageAttachment attachment;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, String>>(
      // The content endpoint requires the session cookie; CachedNetworkImage
      // uses its own HTTP client, which the app's Dio cookie interceptor
      // never touches, so the cookie has to be attached by hand here.
      future: ref.read(apiClientProvider).mediaAuthHeaders(),
      builder: (context, snapshot) {
        final headers = snapshot.data;
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 220,
            height: 160,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _ImageViewerScreen(url: url, headers: headers ?? const {}),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: headers,
              width: 220,
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox(
                width: 220,
                height: 160,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (_, _, _) => _FileChip(attachment: attachment),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen, pinch-to-zoom view of an image attachment.
class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers,
            fit: BoxFit.contain,
            placeholder: (_, _) => const CircularProgressIndicator(),
            errorWidget: (_, _, _) => Icon(
              Icons.broken_image_outlined,
              color: Colors.white.withValues(alpha: 0.7),
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}

/// A voice-message bubble: mic glyph, duration, waveform, and a play/pause control
/// with playback progress. Audio bytes are fetched lazily, only when the
/// agent actually taps play — never pre-loaded or auto-played.
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

class _VoicePlayerState extends ConsumerState<_VoicePlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  _PlaybackLoad _load = _PlaybackLoad.idle;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    // Best-effort, unawaited: nothing on screen still needs this once the
    // widget is gone, and it must not hold the conversation screen's
    // teardown open on a slow platform call.
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_load == _PlaybackLoad.loading) return;

    if (_playing) {
      await _player?.pause();
      return;
    }

    if (_player != null && _load == _PlaybackLoad.ready) {
      await _player!.resume();
      return;
    }

    final localPath = widget.localPath;
    final url = widget.url;
    if ((localPath == null || localPath.isEmpty) && url.isEmpty) {
      if (mounted) setState(() => _load = _PlaybackLoad.error);
      return;
    }

    setState(() => _load = _PlaybackLoad.loading);

    try {
      Uint8List bytes;
      if (localPath != null &&
          localPath.isNotEmpty &&
          File(localPath).existsSync()) {
        bytes = await File(localPath).readAsBytes();
      } else {
        final api = ref.read(apiClientProvider);
        final response = await api.raw.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final status = response.statusCode ?? 0;
        final data = response.data;
        if (status < 200 || status >= 300 || data == null) {
          throw StateError('attachment content fetch failed: $status');
        }
        bytes = Uint8List.fromList(data);
      }

      if (!mounted) return;

      final player = AudioPlayer();
      _stateSub = player.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state == PlayerState.playing);
      });
      _positionSub = player.onPositionChanged.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
      });
      _durationSub = player.onDurationChanged.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      });

      await player.play(BytesSource(bytes));

      if (!mounted) {
        unawaited(player.dispose());
        return;
      }

      _player = player;
      setState(() => _load = _PlaybackLoad.ready);
    } catch (_) {
      if (mounted) setState(() => _load = _PlaybackLoad.error);
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _duration ?? _durationFromAttachment();
    final progress = total != null && total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 15,
                      color: textColor.withValues(alpha: 0.90),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.voiceNoteLabel,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
                  Row(
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
                                final targetMs =
                                    (total.inMilliseconds * fraction).round();
                                _player!.seek(Duration(milliseconds: targetMs));
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _format(
                          total != null
                              ? (_playing ? _position : total)
                              : _position,
                        ),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.90),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Duration? _durationFromAttachment() {
    final ms = widget.attachment.durationMs;
    return ms == null ? null : Duration(milliseconds: ms);
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
              attachment.isAudio && attachment.durationMs != null
                  ? _formatDuration(attachment.durationMs!)
                  : (attachment.fileName.isEmpty
                        ? attachment.type.toLowerCase()
                        : attachment.fileName),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int durationMs) {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
