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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
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
    this.fileSize,
  });

  final String draftId;
  final String localPath;
  final MessageAttachment attachment;
  final int? fileSize;
}

/// The attachment button (left of the text field): opens a sheet offering
/// document selection, gallery selection, or camera capture, uploads the result,
/// and reports the staged draft(s) back to the composer.
class ComposerAttachmentButton extends ConsumerStatefulWidget {
  const ComposerAttachmentButton({
    required this.conversationId,
    required this.enabled,
    required this.onStaged,
    required this.onError,
    this.currentStagedCount = 0,
    this.onUploadingChanged,
    super.key,
  });

  final int conversationId;
  final bool enabled;
  final ValueChanged<List<StagedAttachment>> onStaged;
  final ValueChanged<String> onError;
  final int currentStagedCount;
  final ValueChanged<bool>? onUploadingChanged;

  @override
  ConsumerState<ComposerAttachmentButton> createState() =>
      _ComposerAttachmentButtonState();
}

class _ComposerAttachmentButtonState
    extends ConsumerState<ComposerAttachmentButton> {
  bool _busy = false;

  static const int _maxAttachments = 10;
  static const List<String> _allowedDocExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'zip',
    'csv',
  ];

  Future<void> _uploadBatch(
    List<({String path, String name, int? size})> items,
  ) async {
    if (items.isEmpty) return;
    setState(() => _busy = true);
    widget.onUploadingChanged?.call(true);

    final stagedList = <StagedAttachment>[];
    final failedNames = <String>[];
    String? lastError;

    try {
      await Future.wait(
        items.map((item) async {
          try {
            final data = await ref
                .read(conversationRepositoryProvider)
                .stageAttachment(
                  widget.conversationId,
                  filePath: item.path,
                  fileName: item.name,
                  mimeType:
                      lookupMimeType(item.path) ?? lookupMimeType(item.name),
                );

            final staged = StagedAttachment(
              draftId: data.id,
              localPath: item.path,
              fileSize: item.size ?? data.sizeBytes,
              attachment: MessageAttachment(
                type: data.type,
                fileName: data.fileName,
                mimeType: data.mimeType,
                localFilePath: item.path,
                sizeBytes: item.size ?? data.sizeBytes,
              ),
            );
            stagedList.add(staged);
          } on ApiException catch (error) {
            failedNames.add(item.name);
            lastError = error.message;
          } catch (_) {
            failedNames.add(item.name);
          }
        }),
      );

      if (stagedList.isNotEmpty) {
        widget.onStaged(stagedList);
      }

      if (failedNames.isNotEmpty && mounted) {
        final err = lastError;
        if (stagedList.isEmpty && err != null) {
          widget.onError(err);
        } else if (stagedList.isEmpty) {
          widget.onError(context.l10n.attachmentUploadFailedError);
        } else {
          widget.onError(context.l10n.attachmentPartialUploadError);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onUploadingChanged?.call(false);
    }
  }

  Future<void> _pickGallery() async {
    if (_busy) return;
    Navigator.of(context).pop();

    final remaining = _maxAttachments - widget.currentStagedCount;
    if (remaining <= 0) {
      widget.onError(context.l10n.attachmentLimitReached);
      return;
    }

    List<XFile> pickedList = [];
    try {
      pickedList = await ImagePicker().pickMultiImage(imageQuality: 85);
    } on PlatformException catch (error) {
      if (!mounted) return;
      widget.onError(
        error.code == 'photo_access_denied'
            ? context.l10n.attachmentPermissionDeniedError
            : context.l10n.attachmentUploadFailedError,
      );
      return;
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
      return;
    }

    if (pickedList.isEmpty) return;

    if (pickedList.length > remaining) {
      if (mounted) widget.onError(context.l10n.attachmentLimitReached);
      pickedList = pickedList.take(remaining).toList();
    }

    await _uploadBatch(
      pickedList
          .map((x) => (path: x.path, name: x.name, size: null as int?))
          .toList(),
    );
  }

  Future<void> _pickCamera() async {
    if (_busy) return;
    Navigator.of(context).pop();

    final remaining = _maxAttachments - widget.currentStagedCount;
    if (remaining <= 0) {
      widget.onError(context.l10n.attachmentLimitReached);
      return;
    }

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      widget.onError(
        error.code == 'camera_access_denied'
            ? context.l10n.attachmentPermissionDeniedError
            : context.l10n.attachmentUploadFailedError,
      );
      return;
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
      return;
    }

    if (picked == null) return;
    await _uploadBatch([
      (path: picked.path, name: picked.name, size: null as int?),
    ]);
  }

  Future<void> _pickDocuments() async {
    if (_busy) return;
    Navigator.of(context).pop();

    final remaining = _maxAttachments - widget.currentStagedCount;
    if (remaining <= 0) {
      widget.onError(context.l10n.attachmentLimitReached);
      return;
    }

    List<PlatformFile> pickedFiles = [];
    try {
      pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedDocExtensions,
      );
    } on PlatformException catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
      return;
    } catch (_) {
      if (!mounted) return;
      widget.onError(context.l10n.attachmentUploadFailedError);
      return;
    }

    if (pickedFiles.isEmpty) return;

    var files = pickedFiles.where((f) => f.path != null).toList();
    if (files.isEmpty) return;

    if (files.length > remaining) {
      if (mounted) widget.onError(context.l10n.attachmentLimitReached);
      files = files.take(remaining).toList();
    }

    await _uploadBatch(
      files
          .map((f) => (path: f.path!, name: f.name, size: f.lengthSync()))
          .toList(),
    );
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AttachmentOption(
                    icon: Icons.insert_drive_file_rounded,
                    color: const Color(0xFF5F60B9),
                    label: sheetContext.l10n.attachDocumentAction,
                    onTap: _pickDocuments,
                  ),
                  _AttachmentOption(
                    icon: Icons.photo_camera_rounded,
                    color: const Color(0xFFEC407A),
                    label: sheetContext.l10n.attachFromCameraAction,
                    onTap: _pickCamera,
                  ),
                  _AttachmentOption(
                    icon: Icons.photo_library_rounded,
                    color: const Color(0xFF8B5CF6),
                    label: sheetContext.l10n.attachFromGalleryAction,
                    onTap: _pickGallery,
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: IconButton(
        tooltip: context.l10n.attachmentTooltip,
        padding: EdgeInsets.zero,
        onPressed: (!widget.enabled || _busy) ? null : _openSheet,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.attach_file_rounded, size: 20),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: Space.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An individual staged preview item shown above the text field.
class ComposerAttachmentPreviewItem extends ConsumerStatefulWidget {
  const ComposerAttachmentPreviewItem({
    required this.conversationId,
    required this.staged,
    required this.onRemoved,
    super.key,
  });

  final int conversationId;
  final StagedAttachment staged;
  final VoidCallback onRemoved;

  @override
  ConsumerState<ComposerAttachmentPreviewItem> createState() =>
      _ComposerAttachmentPreviewItemState();
}

class _ComposerAttachmentPreviewItemState
    extends ConsumerState<ComposerAttachmentPreviewItem> {
  bool _removing = false;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .discardAttachment(widget.conversationId, widget.staged.draftId);
    } on ApiException catch (_) {
      // Safe to call on something already gone
    } finally {
      if (mounted) widget.onRemoved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isImage = widget.staged.attachment.isImage;

    final Widget previewCard = isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Image.file(
              File(widget.staged.localPath),
              width: 84,
              height: 84,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: 148,
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _docIconColor(
                          widget.staged.attachment.fileExtension,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Icon(
                        _docIcon(widget.staged.attachment.fileExtension),
                        size: 20,
                        color: _docIconColor(
                          widget.staged.attachment.fileExtension,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        widget.staged.attachment.fileExtension.isEmpty
                            ? 'FILE'
                            : widget.staged.attachment.fileExtension,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _docIconColor(
                            widget.staged.attachment.fileExtension,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.staged.attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (widget.staged.attachment.formattedSize.isNotEmpty)
                      Text(
                        widget.staged.attachment.formattedSize,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        previewCard,
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
    );
  }

  static Color _docIconColor(String ext) => switch (ext.toUpperCase()) {
    'PDF' => const Color(0xFFEF4444),
    'DOC' || 'DOCX' => const Color(0xFF2563EB),
    'XLS' || 'XLSX' || 'CSV' => const Color(0xFF059669),
    'PPT' || 'PPTX' => const Color(0xFFEA580C),
    'ZIP' || 'RAR' => const Color(0xFFD97706),
    _ => const Color(0xFF64748B),
  };

  static IconData _docIcon(String ext) => switch (ext.toUpperCase()) {
    'PDF' => Icons.picture_as_pdf_rounded,
    'DOC' || 'DOCX' => Icons.description_rounded,
    'XLS' || 'XLSX' || 'CSV' => Icons.table_chart_rounded,
    'PPT' || 'PPTX' => Icons.slideshow_rounded,
    'ZIP' || 'RAR' => Icons.folder_zip_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

/// Horizontal scrolling preview bar of staged attachments.
class ComposerAttachmentsPreviewBar extends StatelessWidget {
  const ComposerAttachmentsPreviewBar({
    required this.conversationId,
    required this.attachments,
    required this.onRemoved,
    super.key,
  });

  final int conversationId;
  final List<StagedAttachment> attachments;
  final ValueChanged<int> onRemoved;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < attachments.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.sm),
              ComposerAttachmentPreviewItem(
                key: ValueKey(attachments[i].draftId),
                conversationId: conversationId,
                staged: attachments[i],
                onRemoved: () => onRemoved(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Backward-compatible single-item preview wrapper.
class ComposerAttachmentPreview extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: ComposerAttachmentPreviewItem(
        conversationId: conversationId,
        staged: staged,
        onRemoved: onRemoved,
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
    this.onRecordingChanged,
    super.key,
  });

  final int conversationId;
  final bool enabled;
  final ValueChanged<StagedAttachment> onStaged;
  final ValueChanged<String> onError;
  final ValueChanged<bool>? onRecordingChanged;

  @override
  ConsumerState<ComposerVoiceRecorder> createState() =>
      ComposerVoiceRecorderState();
}

class ComposerVoiceRecorderState extends ConsumerState<ComposerVoiceRecorder> {
  static const maxRecordingDuration = Duration(minutes: 5);

  AudioRecorder? _recorder;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = false;

  bool get isRecording => _recording;

  @override
  void dispose() {
    _ticker?.cancel();
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(_releaseRecorder(recorder));
    }
    super.dispose();
  }

  static Future<void> _releaseRecorder(AudioRecorder recorder) async {
    try {
      await recorder.cancel();
    } catch (_) {}
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

      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: path,
      );

      _recorder = recorder;
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _elapsed + const Duration(seconds: 1);
        if (next >= maxRecordingDuration) {
          setState(() => _elapsed = maxRecordingDuration);
          _stopAndSend();
        } else {
          setState(() => _elapsed = next);
        }
      });

      setState(() => _recording = true);
      widget.onRecordingChanged?.call(true);
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
    widget.onRecordingChanged?.call(false);
    if (recorder != null) {
      try {
        await recorder.cancel();
      } catch (_) {}
      await recorder.dispose();
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
    widget.onRecordingChanged?.call(false);

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
      final isDark = theme.brightness == Brightness.dark;
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A1517) : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? const Color(0xFF991B1B).withValues(alpha: 0.5)
                : const Color(0xFFFCA5A5),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      context.l10n.recordingText,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${_formatElapsed(_elapsed)} / 5:00',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF64748B),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.cancelRecordingTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.delete_outline,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                size: 20,
              ),
              onPressed: _cancel,
            ),
            const SizedBox(width: 6),
            Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _busy ? null : _stopAndSend,
                child: Tooltip(
                  message: context.l10n.stopRecordingTooltip,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.stop_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      child: IconButton(
        tooltip: context.l10n.recordVoiceTooltip,
        padding: EdgeInsets.zero,
        onPressed: (!widget.enabled || _busy) ? null : _start,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.mic_none_rounded, size: 22),
      ),
    );
  }
}
