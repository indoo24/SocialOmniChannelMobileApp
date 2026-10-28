/// The saved-reply form's file: one image, video, audio file, document or
/// recorded voice message per reply — the backend keeps one
/// (`POST /saved-reply-assets/` replaces it).
///
/// This only picks or records a *local* file and shows it; the form uploads
/// it after saving the reply's text (see `saved_reply_form_sheet.dart`).
/// The pickers and the recorder are the ones the conversation composer uses
/// (`image_picker`, `file_picker`, `record`), and so are their permission
/// prompts: asked for on the tap that needs them, never before.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/models/message.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../messages/composer_attachment.dart' show RemoteAttachmentImage;
import '../messages/message_bubble.dart' show VoiceNotePlayer;
import '../messages/voice_note_recording.dart';
import 'saved_reply.dart';

/// What kind of file was chosen — which picker it came from.
enum SavedReplyFileKind { image, video, audio, file, voice }

/// A file chosen in the form and not uploaded yet.
@immutable
class PendingSavedReplyFile {
  const PendingSavedReplyFile({
    required this.path,
    required this.name,
    required this.kind,
    this.size,
    this.durationMs,
  });

  final String path;
  final String name;
  final SavedReplyFileKind kind;
  final int? size;

  /// A recording's length.
  final int? durationMs;

  /// Recorded here: a temporary file this app made, deleted once it is no
  /// longer needed. Picked files belong to their picker and are left alone.
  bool get isRecording => kind == SavedReplyFileKind.voice;

  MessageAttachment toAttachment() => MessageAttachment(
    type: switch (kind) {
      SavedReplyFileKind.image => 'IMAGE',
      SavedReplyFileKind.video => 'VIDEO',
      SavedReplyFileKind.audio || SavedReplyFileKind.voice => 'AUDIO',
      SavedReplyFileKind.file => 'FILE',
    },
    fileName: name,
    mimeType: isRecording ? 'audio/ogg' : '',
    localFilePath: path,
    sizeBytes: size,
    durationMs: durationMs,
  );
}

/// Deletes a recording's temporary file; a picked file is never touched.
Future<void> discardPendingFile(PendingSavedReplyFile? file) async {
  if (file == null || !file.isRecording) return;
  try {
    final f = File(file.path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // A temporary file the OS will clear anyway.
  }
}

class SavedReplyAttachmentField extends StatefulWidget {
  const SavedReplyAttachmentField({
    required this.existing,
    required this.pending,
    required this.onPicked,
    required this.onRemove,
    required this.onError,
    this.enabled = true,
    this.progress,
    this.onRecordingChanged,
    super.key,
  });

  /// The reply's file on the server, when it has one being kept.
  final SavedReplyAsset? existing;

  /// A file chosen here, replacing [existing] when saved.
  final PendingSavedReplyFile? pending;

  final ValueChanged<PendingSavedReplyFile> onPicked;

  /// Removes the shown file — [pending] if there is one, else [existing].
  final VoidCallback onRemove;
  final ValueChanged<String> onError;
  final bool enabled;

  /// Share of the upload sent, while uploading.
  final ValueListenable<double?>? progress;
  final ValueChanged<bool>? onRecordingChanged;

  /// The longest recording, as in the composer.
  static const maxRecording = Duration(minutes: 5);

  @override
  State<SavedReplyAttachmentField> createState() =>
      _SavedReplyAttachmentFieldState();
}

class _SavedReplyAttachmentFieldState extends State<SavedReplyAttachmentField>
    with WidgetsBindingObserver {
  AudioRecorder? _recorder;
  String? _recordingPath;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    final recorder = _recorder;
    final path = _recordingPath;
    if (recorder != null) unawaited(_abandon(recorder, path));
    super.dispose();
  }

  /// Leaving the app mid-recording keeps what was recorded rather than
  /// recording on in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_recording && state == AppLifecycleState.paused) unawaited(_stop());
  }

  static Future<void> _abandon(AudioRecorder recorder, String? path) async {
    try {
      await recorder.cancel();
    } catch (_) {}
    unawaited(recorder.dispose().catchError((Object _) {}));
    if (path != null) {
      await discardPendingFile(
        PendingSavedReplyFile(
          path: path,
          name: '',
          kind: SavedReplyFileKind.voice,
        ),
      );
    }
  }

  void _setRecording(bool value) {
    setState(() => _recording = value);
    widget.onRecordingChanged?.call(value);
  }

  // -- pickers ----------------------------------------------------------------

  Future<void> _pickFromGallery({required bool video}) async {
    final l10n = context.l10n;
    XFile? picked;
    try {
      picked = video
          ? await ImagePicker().pickVideo(source: ImageSource.gallery)
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
    } on PlatformException catch (error) {
      if (!mounted) return;
      widget.onError(
        error.code == 'photo_access_denied'
            ? l10n.attachmentPermissionDeniedError
            : l10n.savedReplyFilePickFailed,
      );
      return;
    } catch (_) {
      if (mounted) widget.onError(l10n.savedReplyFilePickFailed);
      return;
    }
    if (picked == null || !mounted) return;
    _deliver(
      picked.path,
      picked.name,
      video ? SavedReplyFileKind.video : SavedReplyFileKind.image,
    );
  }

  Future<void> _pickDocument({required bool audio}) async {
    final l10n = context.l10n;
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: audio ? FileType.audio : FileType.any,
      );
    } catch (_) {
      if (mounted) widget.onError(l10n.savedReplyFilePickFailed);
      return;
    }
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final path = file.path;
    if (path == null) {
      widget.onError(l10n.savedReplyFilePickFailed);
      return;
    }
    _deliver(
      path,
      file.name,
      audio ? SavedReplyFileKind.audio : SavedReplyFileKind.file,
      size: file.lengthSync(),
    );
  }

  /// Hands a picked file to the form — once it is known to be readable.
  void _deliver(
    String path,
    String name,
    SavedReplyFileKind kind, {
    int? size,
  }) {
    int? length = size;
    try {
      final file = File(path);
      if (!file.existsSync()) throw const FileSystemException();
      length ??= file.lengthSync();
    } catch (_) {
      widget.onError(context.l10n.savedReplyFilePickFailed);
      return;
    }
    widget.onPicked(
      PendingSavedReplyFile(path: path, name: name, kind: kind, size: length),
    );
  }

  // -- recording --------------------------------------------------------------

  Future<void> _start() async {
    if (_recording || _busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    AudioRecorder? recorder;
    try {
      recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        if (mounted) widget.onError(l10n.microphonePermissionDeniedError);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/saved-reply-voice-${DateTime.now().microsecondsSinceEpoch}.ogg';
      await startVoiceNote(
        recorder,
        path: path,
        onNotMono: () {
          if (!mounted || !_recording || !identical(_recorder, recorder)) {
            return;
          }
          unawaited(_discardRecording());
          widget.onError(l10n.recordingFailedError);
        },
      );
      if (!mounted) {
        unawaited(_abandon(recorder, path));
        return;
      }
      _recorder = recorder;
      _recordingPath = path;
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _elapsed + const Duration(seconds: 1);
        setState(() => _elapsed = next);
        if (next >= SavedReplyAttachmentField.maxRecording) unawaited(_stop());
      });
      _setRecording(true);
    } catch (_) {
      if (recorder != null) unawaited(_abandon(recorder, null));
      if (mounted) widget.onError(l10n.recordingFailedError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stops and hands the recording to the form, which shows it with a
  /// player to listen back before saving.
  Future<void> _stop() async {
    final recorder = _recorder;
    if (!_recording || recorder == null) return;
    _ticker?.cancel();
    _ticker = null;
    final durationMs = _elapsed.inMilliseconds;
    final fallbackPath = _recordingPath;
    _recorder = null;
    _recordingPath = null;
    _setRecording(false);
    String? path;
    try {
      path = await recorder.stop();
    } catch (_) {
      path = null;
    }
    unawaited(recorder.dispose().catchError((Object _) {}));
    if (!mounted) return;
    var file = path == null ? null : File(path);
    if (file != null && file.existsSync()) {
      try {
        prepareRecordedVoiceNote(file.path);
      } catch (_) {
        // Not mono, or not Opus WhatsApp can play: never offered for saving.
        try {
          file.deleteSync();
        } catch (_) {}
        file = null;
      }
    }
    if (file == null || !file.existsSync()) {
      if (fallbackPath != null) {
        unawaited(
          discardPendingFile(
            PendingSavedReplyFile(
              path: fallbackPath,
              name: '',
              kind: SavedReplyFileKind.voice,
            ),
          ),
        );
      }
      widget.onError(context.l10n.recordingFailedError);
      return;
    }
    widget.onPicked(
      PendingSavedReplyFile(
        path: file.path,
        name: 'voice-message.ogg',
        kind: SavedReplyFileKind.voice,
        size: file.lengthSync(),
        durationMs: durationMs,
      ),
    );
  }

  /// Throws the recording in progress away.
  Future<void> _discardRecording() async {
    final recorder = _recorder;
    final path = _recordingPath;
    _ticker?.cancel();
    _ticker = null;
    _recorder = null;
    _recordingPath = null;
    _setRecording(false);
    setState(() => _elapsed = Duration.zero);
    if (recorder != null) await _abandon(recorder, path);
  }

  // -- view -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final pending = widget.pending;
    final existing = widget.existing;
    final shown = pending?.toAttachment() ?? existing?.toAttachment();
    final enabled = widget.enabled && !_busy;

    return Column(
      key: const Key('saved-reply-attachment-field'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.savedReplyAttachmentLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        if (shown != null) ...[
          _AttachmentPreview(
            attachment: shown,
            isVoice: pending?.isRecording ?? existing?.isVoice ?? false,
            enabled: widget.enabled && !_recording,
            progress: widget.progress,
            onRemove: widget.onRemove,
          ),
          const SizedBox(height: Space.sm),
        ],
        if (_recording)
          _RecordingBar(
            elapsed: _elapsed,
            onDiscard: _discardRecording,
            onStop: _stop,
          )
        else
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              _PickButton(
                key: const Key('saved-reply-attach-image'),
                icon: Icons.image_outlined,
                label: l10n.savedReplyAttachImage,
                onPressed: enabled
                    ? () => _pickFromGallery(video: false)
                    : null,
              ),
              _PickButton(
                key: const Key('saved-reply-attach-video'),
                icon: Icons.videocam_outlined,
                label: l10n.savedReplyAttachVideo,
                onPressed: enabled ? () => _pickFromGallery(video: true) : null,
              ),
              _PickButton(
                key: const Key('saved-reply-attach-audio'),
                icon: Icons.audio_file_outlined,
                label: l10n.savedReplyAttachAudio,
                onPressed: enabled ? () => _pickDocument(audio: true) : null,
              ),
              _PickButton(
                key: const Key('saved-reply-attach-file'),
                icon: Icons.attach_file_rounded,
                label: l10n.savedReplyAttachFile,
                onPressed: enabled ? () => _pickDocument(audio: false) : null,
              ),
              _PickButton(
                key: const Key('saved-reply-attach-record'),
                icon: Icons.mic_none_rounded,
                label: l10n.savedReplyRecordVoice,
                busy: _busy,
                onPressed: enabled ? _start : null,
              ),
            ],
          ),
        const SizedBox(height: Space.xs),
        Text(
          shown == null
              ? l10n.savedReplyAttachmentHint
              : l10n.savedReplyAttachmentReplaceHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// A reply's file in a list: its kind's icon and its name — "Voice message"
/// for a recording.
class SavedReplyFileBadge extends StatelessWidget {
  const SavedReplyFileBadge({required this.asset, super.key});

  final SavedReplyAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final attachment = asset.toAttachment();
    final icon = asset.isVoice
        ? Icons.mic_rounded
        : attachment.isImage
        ? Icons.image_outlined
        : attachment.isVideo
        ? Icons.movie_outlined
        : attachment.isAudio
        ? Icons.audiotrack_rounded
        : Icons.insert_drive_file_outlined;
    final label = asset.isVoice || asset.originalFilename.isEmpty
        ? (asset.isVoice
              ? context.l10n.savedReplyVoiceMessageLabel
              : context.l10n.savedReplyAttachFile)
        : asset.originalFilename;
    return Row(
      key: Key('saved-reply-file-badge-${asset.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.primary),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// The chosen file: what it is, with a remove (×). An image shows itself,
/// audio and voice messages can be played, a video or document shows its
/// name, type and size.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.isVoice,
    required this.enabled,
    required this.onRemove,
    this.progress,
  });

  final MessageAttachment attachment;
  final bool isVoice;
  final bool enabled;
  final VoidCallback onRemove;
  final ValueListenable<double?>? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final local = attachment.localFilePath;
    final isImage = attachment.isImage;
    final isAudio = attachment.isAudio;

    final kindLabel = isVoice
        ? l10n.savedReplyVoiceMessageLabel
        : isImage
        ? l10n.savedReplyAttachImage
        : attachment.isVideo
        ? l10n.savedReplyAttachVideo
        : isAudio
        ? l10n.savedReplyAttachAudio
        : (attachment.fileExtension.isEmpty
              ? l10n.savedReplyAttachFile
              : attachment.fileExtension.toUpperCase());
    final size = attachment.formattedSize;
    // "1.2 MB" stays one left-to-right unit in Arabic, not "MB 1.2".
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final details = [
      kindLabel,
      if (size.isNotEmpty) rtl ? '\u2066$size\u2069' : size,
    ].join(' · ');

    Widget thumb() {
      final box = BorderRadius.circular(Radii.md);
      if (isImage) {
        return ClipRRect(
          borderRadius: box,
          child: SizedBox(
            width: 56,
            height: 56,
            child: local != null && local.isNotEmpty
                ? Image.file(
                    File(local),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _IconTile(icon: Icons.image_outlined),
                  )
                : RemoteAttachmentImage(url: attachment.resolvedUrl),
          ),
        );
      }
      return _IconTile(
        icon: isVoice
            ? Icons.mic_rounded
            : attachment.isVideo
            ? Icons.movie_outlined
            : isAudio
            ? Icons.audiotrack_rounded
            : Icons.insert_drive_file_outlined,
      );
    }

    return Container(
      key: const Key('saved-reply-attachment-preview'),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              thumb(),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName.isEmpty
                          ? kindLabel
                          : attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // A file name is the file's own, whatever the language.
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      details,
                      key: const Key('saved-reply-attachment-details'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('saved-reply-attachment-remove'),
                tooltip: l10n.removeAttachmentTooltip,
                onPressed: enabled ? onRemove : null,
                icon: Icon(Icons.close_rounded, color: theme.colorScheme.error),
              ),
            ],
          ),
          if (isAudio) ...[
            const SizedBox(height: Space.xs),
            VoiceNotePlayer(
              key: ValueKey(local ?? attachment.url),
              attachment: attachment,
              url: attachment.resolvedUrl,
              localPath: local,
              isOutbound: false,
            ),
          ],
          if (progress case final progress?)
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (context, value, _) => value == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: LinearProgressIndicator(
                          key: const Key('saved-reply-attachment-progress'),
                          value: value <= 0 ? null : value,
                          minHeight: 4,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Icon(icon, color: colors.primary),
    );
  }
}

/// Recording: a red dot, the time against the limit, discard and stop.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.onDiscard,
    required this.onStop,
  });

  final Duration elapsed;
  final VoidCallback onDiscard;
  final VoidCallback onStop;

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      liveRegion: true,
      label: l10n.recordingText,
      child: Container(
        key: const Key('saved-reply-recording-bar'),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 4),
        decoration: BoxDecoration(
          color: colors.dangerSurface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.danger,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                '${l10n.recordingText}  '
                '${_clock(elapsed)} / '
                '${_clock(SavedReplyAttachmentField.maxRecording)}',
                key: const Key('saved-reply-recording-time'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              key: const Key('saved-reply-recording-discard'),
              tooltip: l10n.cancelRecordingTooltip,
              onPressed: onDiscard,
              icon: Icon(Icons.delete_outline, color: colors.mutedForeground),
            ),
            IconButton.filled(
              key: const Key('saved-reply-recording-stop'),
              tooltip: l10n.stopRecordingTooltip,
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
