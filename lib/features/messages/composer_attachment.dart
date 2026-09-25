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

import 'package:dio/dio.dart' show CancelToken;
import 'package:file_picker/file_picker.dart';
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
import '../../core/utils/attachment_helper.dart';
import '../conversations/conversation_repository.dart';
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

/// Files the composer uploads at the same time. A phone's uplink gains
/// nothing from more parallel streams, and a 10-file selection should not
/// become 10 competing transfers that each look stalled.
const int maxConcurrentAttachmentUploads = 3;

/// Files one message can carry — the reply endpoint's `attachment_ids`
/// `maxItems`. Counts every card in the composer, whatever its state.
const int maxComposerAttachments = 10;

/// A file picked for upload: where it is on disk, what the user called it,
/// and — for the card shown while it uploads — whether it came from the
/// photo pickers.
typedef PickedAttachmentFile = ({
  String path,
  String name,
  int? size,
  bool isImage,
});

enum ComposerUploadStatus { uploading, uploaded, failed }

/// One file in the composer, from the moment it is picked until it is sent
/// or removed. Its card renders straight from this: [progress] for the bar
/// (updated per whole percent of bytes actually sent), [status] for which
/// state the card is in, [staged] once the server has accepted the draft.
class ComposerUpload {
  ComposerUpload._(this.file);

  final PickedAttachmentFile file;

  /// Share of this file's request bytes sent (0–1), or null until the first
  /// byte has gone — queued behind other uploads, or still preparing.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  ComposerUploadStatus _status = ComposerUploadStatus.uploading;
  ComposerUploadStatus get status => _status;

  /// The server's draft, once uploaded — what Send references.
  StagedAttachment? staged;

  /// Why the upload failed, when it did.
  ApiException? error;

  CancelToken? _token;

  /// Failures worth offering again: the network, a timeout, the server
  /// having a bad moment. A rejected type or size fails identically on
  /// every attempt, so it gets no retry.
  bool get canRetry {
    final e = error;
    if (_status != ComposerUploadStatus.failed || e == null) return false;
    if (e is SessionExpiredException) return false;
    if (e is NetworkException) return true;
    return e.statusCode == 408 || e.statusCode == 429 || e.statusCode >= 500;
  }

  /// What the card shows: the server's view once uploaded, the picked file
  /// until then.
  MessageAttachment get preview =>
      staged?.attachment ??
      MessageAttachment(
        type: file.isImage ? 'IMAGE' : 'FILE',
        fileName: file.name,
        localFilePath: file.path,
        sizeBytes: file.size,
      );
}

/// The composer's attachments and their uploads — the single owner of
/// upload state. Cards appear the moment files are picked, upload at most
/// [maxConcurrent] at a time in pick order, and each can be cancelled,
/// retried or removed on its own.
///
/// Listeners hear about structural changes only (a card added, removed, or
/// changing state); byte-level progress goes to each card's own
/// [ComposerUpload.progress], so a large upload repaints one card rather than
/// the composer around it.
class ComposerUploadQueue extends ChangeNotifier {
  ComposerUploadQueue({
    required this.repository,
    required this.conversationId,
    this.maxConcurrent = maxConcurrentAttachmentUploads,
    this.onFailed,
  });

  final ConversationRepository repository;
  final int conversationId;
  final int maxConcurrent;

  /// Told about each failure, to explain it — the card itself only says
  /// that it failed.
  final void Function(ComposerUpload upload)? onFailed;

  final List<ComposerUpload> _items = [];
  final List<ComposerUpload> _waiting = [];
  int _running = 0;
  bool _disposed = false;

  List<ComposerUpload> get items => List.unmodifiable(_items);
  int get count => _items.length;

  /// True while any file is still on its way up — Send waits for these, so
  /// a message never goes out without a file the agent attached.
  bool get hasActiveUploads =>
      _items.any((u) => u.status == ComposerUploadStatus.uploading);

  List<ComposerUpload> get uploaded => _items
      .where((u) => u.status == ComposerUploadStatus.uploaded)
      .toList(growable: false);

  /// Adds a card per file immediately and starts uploading them.
  void add(List<PickedAttachmentFile> files) {
    if (files.isEmpty || _disposed) return;
    for (final file in files) {
      final upload = ComposerUpload._(file);
      _items.add(upload);
      _waiting.add(upload);
    }
    notifyListeners();
    _pump();
  }

  /// Removes the uploaded cards and returns their drafts, in card order,
  /// for Send. Uploading and failed cards stay where they are.
  List<StagedAttachment> takeUploaded() {
    final done = uploaded;
    if (done.isEmpty) return const [];
    _items.removeWhere(done.contains);
    notifyListeners();
    return [for (final u in done) u.staged!];
  }

  /// The card's × — cancels an upload in flight, discards an uploaded
  /// draft server-side, or simply drops a failed card. Only that file.
  void remove(ComposerUpload upload) {
    if (!_items.remove(upload)) return;
    _waiting.remove(upload);
    upload._token?.cancel();
    final draftId = upload.staged?.draftId;
    if (draftId != null) _discard(draftId);
    notifyListeners();
  }

  /// Uploads a failed file again, as a fresh draft. Only ever on the
  /// agent's tap: a lost response may already have created the first
  /// draft, which is never referenced and expires server-side — no
  /// message is ever sent twice.
  void retry(ComposerUpload upload) {
    if (!upload.canRetry || !_items.contains(upload)) return;
    upload
      ..error = null
      .._status = ComposerUploadStatus.uploading
      ..progress.value = null;
    _waiting.add(upload);
    notifyListeners();
    _pump();
  }

  void _pump() {
    while (!_disposed && _running < maxConcurrent && _waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      _running++;
      unawaited(
        _upload(next).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _upload(ComposerUpload upload) async {
    final token = CancelToken();
    upload._token = token;
    final file = upload.file;
    try {
      final data = await repository.stageAttachment(
        conversationId,
        filePath: file.path,
        fileName: file.name,
        mimeType: AttachmentHelper.detectMimeType(
          fileName: file.name,
          filePath: file.path,
          headerBytes: await AttachmentHelper.readHeaderBytes(file.path),
        ),
        cancelToken: token,
        onSendProgress: (sent, total) {
          if (total <= 0 || token.isCancelled) return;
          final fraction = (sent / total).clamp(0.0, 1.0);
          final previous = upload.progress.value;
          // Whole percents only: a large file reports thousands of chunks.
          if (previous == null ||
              (fraction * 100).floor() != (previous * 100).floor()) {
            upload.progress.value = fraction;
          }
        },
      );
      final staged = StagedAttachment(
        draftId: data.id,
        localPath: file.path,
        fileSize: file.size ?? data.sizeBytes,
        attachment: MessageAttachment(
          type: data.type,
          fileName: data.fileName,
          mimeType: data.mimeType,
          localFilePath: file.path,
          sizeBytes: file.size ?? data.sizeBytes,
        ),
      );
      if (_disposed || !_items.contains(upload)) {
        // Removed or abandoned while the last bytes were in flight: nobody
        // will send this draft, so release it now.
        _discard(staged.draftId);
        return;
      }
      upload
        ..staged = staged
        .._status = ComposerUploadStatus.uploaded
        ..progress.value = 1;
      notifyListeners();
    } on RequestCancelledException {
      // Removed on purpose (its card is already gone) — nothing to report.
    } catch (error) {
      if (_disposed || !_items.contains(upload)) return;
      upload
        ..error = error is ApiException
            ? error
            // A file that vanished or became unreadable after it was picked.
            : ApiException(statusCode: 0, message: '')
        .._status = ComposerUploadStatus.failed;
      notifyListeners();
      onFailed?.call(upload);
    } finally {
      if (identical(upload._token, token)) upload._token = null;
    }
  }

  void _discard(String draftId) {
    unawaited(
      repository
          .discardAttachment(conversationId, draftId)
          // Safe to call on something already gone; an unsent draft that
          // survives a failed DELETE still expires server-side.
          .catchError((Object _) {}),
    );
  }

  /// Leaving the conversation: stop every transfer still running. Drafts
  /// that were already uploaded but never sent expire server-side.
  @override
  void dispose() {
    _disposed = true;
    _waiting.clear();
    for (final u in _items) {
      u._token?.cancel();
    }
    super.dispose();
  }
}

/// The attachment button (left of the text field): opens a sheet offering
/// document selection, gallery selection, or camera capture, and hands the
/// picked files to the composer's [ComposerUploadQueue] via [onPicked]. It
/// never becomes a spinner — each file's progress lives on its own card —
/// so more files can be added while others are still uploading.
class ComposerAttachmentButton extends ConsumerStatefulWidget {
  const ComposerAttachmentButton({
    required this.conversationId,
    required this.enabled,
    required this.onPicked,
    required this.onError,
    this.currentStagedCount = 0,
    super.key,
  });

  final int conversationId;
  final bool enabled;
  final ValueChanged<List<PickedAttachmentFile>> onPicked;
  final ValueChanged<String> onError;

  /// Cards already in the composer, in any state — counted against
  /// [maxComposerAttachments].
  final int currentStagedCount;

  @override
  ConsumerState<ComposerAttachmentButton> createState() =>
      _ComposerAttachmentButtonState();
}

class _ComposerAttachmentButtonState
    extends ConsumerState<ComposerAttachmentButton> {
  /// Hands [files] to the composer — at most as many as still fit, saying
  /// so when some did not. [unreadable] counts picked files that never had
  /// a readable path, so they are reported instead of silently dropped.
  void _deliver(List<PickedAttachmentFile> files, {int unreadable = 0}) {
    if (!mounted) return;
    final remaining = maxComposerAttachments - widget.currentStagedCount;
    var accepted = files;
    if (accepted.length > remaining) {
      widget.onError(context.l10n.attachmentLimitReached);
      accepted = accepted.take(remaining).toList();
    } else if (unreadable > 0) {
      widget.onError(
        accepted.isEmpty
            ? context.l10n.attachmentUploadFailedError
            : context.l10n.attachmentPartialUploadError,
      );
    }
    if (accepted.isNotEmpty) widget.onPicked(accepted);
  }

  bool _hasRoom() {
    if (widget.currentStagedCount < maxComposerAttachments) return true;
    widget.onError(context.l10n.attachmentLimitReached);
    return false;
  }

  Future<void> _pickGallery() async {
    Navigator.of(context).pop();
    if (!_hasRoom()) return;

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
    _deliver([
      for (final x in pickedList)
        (path: x.path, name: x.name, size: null, isImage: true),
    ]);
  }

  Future<void> _pickCamera() async {
    Navigator.of(context).pop();
    if (!_hasRoom()) return;

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
    _deliver([
      (path: picked.path, name: picked.name, size: null, isImage: true),
    ]);
  }

  Future<void> _pickDocuments() async {
    Navigator.of(context).pop();
    if (!_hasRoom()) return;

    // Any file on the device, as WhatsApp's own picker allows. Whether the
    // conversation's platform can actually carry it is the backend's call:
    // the upload re-derives the type from the bytes and rejects what the
    // platform does not accept, and that reason is shown to the agent.
    List<PlatformFile> pickedFiles = [];
    try {
      pickedFiles = await FilePicker.pickFiles(type: FileType.any);
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

    final files = pickedFiles.where((f) => f.path != null).toList();
    // A provider that handed back no local copy (rare: file_picker copies
    // cloud and SAF documents into the cache) is reported, not ignored.
    _deliver([
      for (final f in files)
        (path: f.path!, name: f.name, size: f.lengthSync(), isImage: false),
    ], unreadable: pickedFiles.length - files.length);
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
        onPressed: widget.enabled ? _openSheet : null,
        icon: const Icon(Icons.attach_file_rounded, size: 20),
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

/// One attachment card above the text field, in whichever state its
/// [ComposerUpload] is in: uploading (real bytes-sent percentage and bar,
/// × cancels), uploaded (done mark, × removes the draft) or failed (error
/// state, retry when [ComposerUpload.canRetry], × removes).
class ComposerAttachmentPreviewItem extends StatelessWidget {
  const ComposerAttachmentPreviewItem({
    required this.upload,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  final ComposerUpload upload;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploading = upload.status == ComposerUploadStatus.uploading;
    final attachment = upload.preview;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (attachment.isImage)
          _ImageUploadCard(upload: upload, onRetry: onRetry)
        else
          _DocumentUploadCard(upload: upload, onRetry: onRetry),
        PositionedDirectional(
          top: -8,
          end: -8,
          child: Tooltip(
            message: uploading
                ? context.l10n.cancelUploadTooltip
                : context.l10n.removeAttachmentTooltip,
            child: Material(
              color: theme.colorScheme.error,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: theme.colorScheme.onError,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentUploadCard extends StatelessWidget {
  const _DocumentUploadCard({required this.upload, required this.onRetry});

  final ComposerUpload upload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final attachment = upload.preview;
    final ext = attachment.fileExtension;
    final failed = upload.status == ComposerUploadStatus.failed;

    return Container(
      width: 148,
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: failed
              ? theme.colorScheme.error.withValues(alpha: 0.6)
              : theme.colorScheme.outlineVariant,
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
                  color: _docIconColor(ext).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(_docIcon(ext), size: 20, color: _docIconColor(ext)),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  // Upper-case like the sent bubble's chip and this
                  // badge's own 'FILE' fallback.
                  ext.isEmpty ? 'FILE' : ext.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _docIconColor(ext),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            attachment.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          switch (upload.status) {
            ComposerUploadStatus.uploading => _UploadProgressLine(
              upload: upload,
            ),
            ComposerUploadStatus.uploaded => Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 12,
                  color: ScenarioColors.success,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    attachment.formattedSize.isNotEmpty
                        ? attachment.formattedSize
                        : context.l10n.attachmentUploadedLabel,
                    // "1.2 MB" stays one left-to-right unit in Arabic too,
                    // rather than reordering to "MB 1.2".
                    textDirection: attachment.formattedSize.isNotEmpty
                        ? TextDirection.ltr
                        : null,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            ComposerUploadStatus.failed => _UploadFailedLine(
              upload: upload,
              onRetry: onRetry,
            ),
          },
        ],
      ),
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

/// The bar and percentage under an uploading file — the only part of the
/// composer that repaints as bytes go out.
class _UploadProgressLine extends StatelessWidget {
  const _UploadProgressLine({required this.upload});

  final ComposerUpload upload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<double?>(
      valueListenable: upload.progress,
      builder: (context, value, _) => Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              // Indeterminate until the first byte is sent (still queued
              // behind other uploads, or preparing), so it never looks
              // frozen at 0%.
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            context.l10n.attachmentUploadPercent(_percent(value)),
            key: const Key('attachmentUploadPercent'),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Whole percent of [fraction] sent, rounded down — a card never claims
/// 100% before the last byte is out — with a hair of tolerance so an exact
/// 0.58 (57.999… in binary floating point) still reads 58%.
int _percent(double? fraction) =>
    ((fraction ?? 0) * 100 + 1e-6).floor().clamp(0, 100);

class _UploadFailedLine extends StatelessWidget {
  const _UploadFailedLine({required this.upload, required this.onRetry});

  final ComposerUpload upload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            context.l10n.attachmentUploadFailedLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (upload.canRetry)
          Tooltip(
            message: context.l10n.retryUploadTooltip,
            child: InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(Radii.pill),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImageUploadCard extends StatelessWidget {
  const _ImageUploadCard({required this.upload, required this.onRetry});

  final ComposerUpload upload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = upload.status;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(upload.file.path),
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (status == ComposerUploadStatus.uploading)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: ValueListenableBuilder<double?>(
                  valueListenable: upload.progress,
                  builder: (context, value, _) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.attachmentUploadPercent(_percent(value)),
                        key: const Key('attachmentUploadPercent'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (status == ComposerUploadStatus.failed)
              Material(
                color: Colors.black.withValues(alpha: 0.55),
                child: InkWell(
                  onTap: upload.canRetry ? onRetry : null,
                  child: Tooltip(
                    message: upload.canRetry
                        ? context.l10n.retryUploadTooltip
                        : context.l10n.attachmentUploadFailedLabel,
                    child: Icon(
                      upload.canRetry
                          ? Icons.refresh_rounded
                          : Icons.error_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scrolling bar of the composer's attachment cards, rebuilt
/// only when a card is added, removed or changes state.
class ComposerAttachmentsPreviewBar extends StatelessWidget {
  const ComposerAttachmentsPreviewBar({required this.uploads, super.key});

  final ComposerUploadQueue uploads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: uploads,
      builder: (context, _) {
        final items = uploads.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.sm),
                  ComposerAttachmentPreviewItem(
                    key: ObjectKey(items[i]),
                    upload: items[i],
                    onRemove: () => uploads.remove(items[i]),
                    onRetry: () => uploads.retry(items[i]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

      // Left the conversation while it uploaded: sending now would act on a
      // screen that no longer exists. The unsent draft expires server-side.
      if (!mounted) return;
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
