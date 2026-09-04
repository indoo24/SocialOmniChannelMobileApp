/// Composer image-attachment and voice-recording controls.
///
/// Both features share one backend contract, already used elsewhere in the
/// app's message-sending path:
///
///     POST /conversations/{id}/attachments/   (multipart: file, is_voice?, duration_ms?)
///       -> AttachmentDraft { id, type, mime_type, file_name, size_bytes, is_voice, duration_ms }
///     DELETE /conversations/{id}/attachments/{draft_id}/
///     POST /conversations/{id}/reply/         (attachment_ids: [draft.id], text?)
///
/// This file only ever picks/records a *local* file and stages it — sending
/// happens through `ConversationController.send()`, the same path a
/// text-only reply already takes, so retry/failure/optimistic-bubble
/// handling is not duplicated here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';

/// A file picked/recorded locally and already uploaded as a draft, kept in
/// the composer until the agent sends or removes it.
class StagedAttachment {
  const StagedAttachment({
    required this.draftId,
    required this.localPath,
    required this.attachment,
  });

  final String draftId;
  final String localPath;
  final MessageAttachment attachment;
}

/// The attachment button (left of the text field): opens a sheet offering
/// gallery selection or camera capture, uploads the result, and reports the
/// staged draft back to the composer.
///
/// Neither permission is requested until the agent actually taps one of the
/// two sheet options — `image_picker` requests the platform permission
/// itself at that point, not before.
class ComposerAttachmentButton extends ConsumerStatefulWidget {
  const ComposerAttachmentButton({
    required this.conversationId,
    required this.enabled,
    required this.onStaged,
    required this.onError,
    super.key,
  });

  final int conversationId;
  final bool enabled;
  final ValueChanged<StagedAttachment> onStaged;
  final ValueChanged<String> onError;

  @override
  ConsumerState<ComposerAttachmentButton> createState() =>
      _ComposerAttachmentButtonState();
}

class _ComposerAttachmentButtonState
    extends ConsumerState<ComposerAttachmentButton> {
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    Navigator.of(context).pop();
    setState(() => _busy = true);

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;

      final data = await ref
          .read(conversationRepositoryProvider)
          .stageAttachment(
            widget.conversationId,
            filePath: picked.path,
            fileName: picked.name,
          );

      widget.onStaged(
        StagedAttachment(
          draftId: data.id,
          localPath: picked.path,
          attachment: MessageAttachment(
            type: data.type,
            fileName: data.fileName,
            mimeType: data.mimeType,
            localFilePath: picked.path,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      widget.onError(error.message);
    } on PlatformException catch (error) {
      // image_picker's own signal for "permission denied" / "no camera" /
      // similar platform-level refusals — never a bug in this app's own
      // code, so it is shown as the friendly permission copy rather than
      // the raw platform error string.
      if (!mounted) return;
      widget.onError(
        error.code == 'camera_access_denied' ||
                error.code == 'photo_access_denied'
            ? context.l10n.attachmentPermissionDeniedError
            : context.l10n.attachmentUploadFailedError,
      );
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(sheetContext.l10n.attachFromGalleryAction),
              onTap: () => _pick(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(sheetContext.l10n.attachFromCameraAction),
              onTap: () => _pick(ImageSource.camera),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.attachmentTooltip,
      onPressed: (!widget.enabled || _busy) ? null : _openSheet,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.attach_file_rounded),
    );
  }
}

/// The staged-image preview shown above the text field before sending —
/// nothing is sent to the customer until the agent taps Send; tapping the
/// remove badge discards the server-side draft too.
class ComposerAttachmentPreview extends ConsumerStatefulWidget {
  const ComposerAttachmentPreview({
    required this.conversationId,
    required this.staged,
    required this.onRemoved,
    super.key,
  });

  final int conversationId;
  final StagedAttachment staged;
  final VoidCallback onRemoved;

  @override
  ConsumerState<ComposerAttachmentPreview> createState() =>
      _ComposerAttachmentPreviewState();
}

class _ComposerAttachmentPreviewState
    extends ConsumerState<ComposerAttachmentPreview> {
  bool _removing = false;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .discardAttachment(widget.conversationId, widget.staged.draftId);
    } on ApiException catch (_) {
      // "Safe to call on something already gone" per the endpoint's own
      // contract — a failed discard still removes it from the composer;
      // there is nothing local left over for the agent to be misled by.
    } finally {
      if (mounted) widget.onRemoved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Image.file(
              File(widget.staged.localPath),
              width: 84,
              height: 84,
              fit: BoxFit.cover,
            ),
          ),
          PositionedDirectional(
            top: -8,
            end: -8,
            child: Material(
              color: theme.colorScheme.error,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _remove,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: _removing
                      ? const Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.close,
                          size: 16,
                          color: theme.colorScheme.onError,
                          semanticLabel: context.l10n.removeAttachmentTooltip,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The finished recording, ready for `send()` to reference — the same
/// [StagedAttachment] shape an image produces, so the composer's send path
/// does not need to know which kind of attachment it is holding.
///
/// The voice-record button (right of Send, replacing it visually while
/// recording): tap to start, shows an inline recording bar with duration and
/// cancel/stop while active. Microphone permission is requested only on the
/// first tap, via `record`'s own `hasPermission()`/platform prompt — never
/// pre-emptively.
class ComposerVoiceRecorder extends ConsumerStatefulWidget {
  const ComposerVoiceRecorder({
    required this.conversationId,
    required this.enabled,
    required this.onStaged,
    required this.onError,
    super.key,
  });

  final int conversationId;
  final bool enabled;
  final ValueChanged<StagedAttachment> onStaged;
  final ValueChanged<String> onError;

  @override
  ConsumerState<ComposerVoiceRecorder> createState() =>
      ComposerVoiceRecorderState();
}

class ComposerVoiceRecorderState extends ConsumerState<ComposerVoiceRecorder> {
  AudioRecorder? _recorder;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = false;

  bool get isRecording => _recording;

  @override
  void dispose() {
    _ticker?.cancel();
    // Best-effort: dropping the recorder mid-recording (navigating away)
    // must not leave the microphone held or a half-written file behind.
    // cancel() then dispose(), not concurrently — the package serializes
    // its own calls through an internal semaphore, so firing both at once
    // just queues the second behind the first anyway.
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(_releaseRecorder(recorder));
    }
    super.dispose();
  }

  static Future<void> _releaseRecorder(AudioRecorder recorder) async {
    // cancel() is what actually matters for safety — it stops the
    // recording and releases the microphone. dispose() afterward only
    // releases the package's own internal Dart-side resources (stream
    // controllers, timers), so it runs best-effort and unawaited: nothing
    // is left on screen to show an error for on a conversation the agent
    // has already navigated away from, and it must not hold this future
    // open (and by extension, this closure's captured recorder) if the
    // platform call is slow.
    try {
      await recorder.cancel();
    } catch (_) {
      // Nothing to recover from here.
    }
    unawaited(recorder.dispose().catchError((_) {}));
  }

  Future<void> _start() async {
    if (_recording || _busy) return;
    setState(() => _busy = true);

    try {
      final recorder = AudioRecorder();
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        await recorder.dispose();
        if (!mounted) return;
        widget.onError(context.l10n.microphonePermissionDeniedError);
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice-${DateTime.now().microsecondsSinceEpoch}.ogg';

      // Opus in an Ogg container — what the backend's WhatsApp voice-note
      // flow expects (`audio/ogg`), and what WhatsApp's own voice notes
      // already use under the hood. `record`'s Android implementation
      // requires Android 10+ (API 29) for this; a well-supported floor for
      // this app's real device base, so a rejection here is treated as a
      // genuine recording failure — the same generic "couldn't start
      // recording" message any other `start()` failure already shows —
      // rather than a silently different output format on old devices.
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: path,
      );

      _recorder = recorder;
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });

      setState(() => _recording = true);
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.recordingFailedError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (!_recording) return;
    _ticker?.cancel();
    _ticker = null;
    final recorder = _recorder;
    _recorder = null;
    setState(() {
      _recording = false;
      _elapsed = Duration.zero;
    });
    if (recorder != null) {
      try {
        await recorder.cancel();
      } catch (_) {
        // Nothing to recover — the file, if any, is discarded either way.
      } finally {
        await recorder.dispose();
      }
    }
  }

  Future<void> _stopAndSend() async {
    if (!_recording || _busy) return;
    final recorder = _recorder;
    if (recorder == null) return;

    _ticker?.cancel();
    _ticker = null;
    final durationMs = _elapsed.inMilliseconds;

    setState(() {
      _recording = false;
      _busy = true;
    });

    String? path;
    try {
      path = await recorder.stop();
    } catch (_) {
      path = null;
    } finally {
      await recorder.dispose();
      _recorder = null;
    }

    if (path == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _elapsed = Duration.zero;
        });
        widget.onError(context.l10n.recordingFailedError);
      }
      return;
    }

    try {
      final data = await ref
          .read(conversationRepositoryProvider)
          .stageAttachment(
            widget.conversationId,
            filePath: path,
            fileName: 'voice-message.ogg',
            isVoice: true,
            durationMs: durationMs,
            mimeType: 'audio/ogg',
          );

      widget.onStaged(
        StagedAttachment(
          draftId: data.id,
          localPath: path,
          attachment: MessageAttachment(
            type: data.type,
            fileName: data.fileName,
            mimeType: data.mimeType,
            localFilePath: path,
            durationMs: data.durationMs ?? durationMs,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      widget.onError(error.message);
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
    } finally {
      if (mounted) setState(() => _elapsed = Duration.zero);
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_recording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        // No mainAxisSize.min here: this Row is meant to fill whatever
        // width its Flexible ancestor in the composer gives it, so the
        // label in the middle is the part that shrinks on a narrow
        // screen — the icon buttons on either side keep their full size.
        child: Row(
          children: [
            IconButton(
              tooltip: context.l10n.cancelRecordingTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
                size: 18,
              ),
              onPressed: _cancel,
            ),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsetsDirectional.only(end: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                context.l10n.recordingLabel(_formatElapsed(_elapsed)),
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton.filled(
              tooltip: context.l10n.stopRecordingTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 16),
              onPressed: _busy ? null : _stopAndSend,
            ),
          ],
        ),
      );
    }

    return IconButton(
      tooltip: context.l10n.recordVoiceTooltip,
      onPressed: (!widget.enabled || _busy) ? null : _start,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.mic_none_rounded),
    );
  }
}
