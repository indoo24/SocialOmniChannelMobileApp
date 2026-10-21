/// Add/Edit a saved reply — `POST /saved-replies/` and
/// `PATCH /saved-replies/{id}/`.
///
/// Every entry point that opens this sheet is itself gated on the caller
/// being allowed to create (personal always; organization needs
/// `Perm.savedReplyManage`) or, on edit, on [SavedReply.canEdit] — see
/// `saved_replies_settings_screen.dart` — so reaching this file already
/// implies that check passed; the backend still enforces it independently.
///
/// `scope` is immutable once a reply exists: on edit it is shown read-only
/// (as plain text, not a field), and is never sent in the update payload,
/// matching the API's own "scope cannot change" contract.
///
/// A reply may carry one file (`saved_reply_attachment_field.dart`). Saving
/// stores the text first, then uploads the file to that reply
/// (`POST /saved-reply-assets/`, which replaces any file it had) or removes
/// it (`DELETE /saved-reply-assets/{id}/`). Only when both succeed does the
/// sheet close and say so. If the text was saved but the file was not, the
/// sheet stays open on that reply, says exactly that, and the next Save
/// retries the file without creating a second reply.
library;

import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/attachment_helper.dart';
import '../../core/widgets/states.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';
import 'saved_reply_attachment_field.dart';

String savedReplyScopeLabel(BuildContext context, String scope) =>
    switch (scope) {
      'personal' => context.l10n.savedReplyScopePersonal,
      'team' => context.l10n.savedReplyScopeTeam,
      _ => context.l10n.savedReplyScopeOrganization,
    };

/// Opens the Add saved reply sheet. [canCreateOrganizationWide] gates whether
/// "Everyone" appears in the scope dropdown — a personal reply needs only
/// `conversation.reply`, which every entry point already required to reach
/// this screen at all.
Future<void> showAddSavedReplySheet(
  BuildContext context, {
  required bool canCreateOrganizationWide,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _SavedReplyFormSheet(
        canCreateOrganizationWide: canCreateOrganizationWide,
        scrollController: controller,
      ),
    ),
  );
}

/// Opens the Edit saved reply sheet, prefilled from [reply]. The scope is
/// read-only.
Future<void> showEditSavedReplySheet(
  BuildContext context, {
  required SavedReply reply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _SavedReplyFormSheet(
        existing: reply,
        canCreateOrganizationWide: false,
        scrollController: controller,
      ),
    ),
  );
}

class _SavedReplyFormSheet extends ConsumerStatefulWidget {
  const _SavedReplyFormSheet({
    this.existing,
    required this.canCreateOrganizationWide,
    required this.scrollController,
  });

  final SavedReply? existing;
  final bool canCreateOrganizationWide;
  final ScrollController scrollController;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_SavedReplyFormSheet> createState() =>
      _SavedReplyFormSheetState();
}

class _SavedReplyFormSheetState extends ConsumerState<_SavedReplyFormSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _shortcut = TextEditingController(text: widget.existing?.shortcut);
  late final _body = TextEditingController(text: widget.existing?.body);
  late String _scope = widget.existing?.scope ?? 'personal';

  bool _submitting = false;
  String? _error;

  /// A file chosen here, uploaded on Save.
  PendingSavedReplyFile? _pending;

  /// The reply's file on the server the person removed, deleted on Save.
  int? _removeAssetId;

  /// The reply as the server last returned it from this sheet — set once its
  /// text has been saved, so a retry updates it rather than creating another.
  SavedReply? _saved;

  bool _recording = false;

  /// The upload's share sent, while uploading; null otherwise.
  final _progress = ValueNotifier<double?>(null);
  CancelToken? _uploadToken;

  bool get _isEdit => widget.isEdit || _saved != null;
  SavedReply? get _reply => _saved ?? widget.existing;

  /// The server's file, unless the person removed it.
  SavedReplyAsset? get _keptAsset {
    final asset = _reply?.asset;
    return asset == null || asset.id == _removeAssetId ? null : asset;
  }

  void _onPicked(PendingSavedReplyFile file) {
    final previous = _pending;
    setState(() {
      _pending = file;
      _error = null;
    });
    if (previous != null && previous.path != file.path) {
      unawaited(discardPendingFile(previous));
    }
  }

  void _onRemoveFile() {
    final pending = _pending;
    setState(() {
      if (pending != null) {
        _pending = null;
      } else {
        _removeAssetId = _reply?.asset?.id;
      }
    });
    unawaited(discardPendingFile(pending));
  }

  void _showError(String message) => setState(() => _error = message);

  /// Why the file did not save, for the sentence that says so.
  String _fileReason(ApiException error) {
    final l10n = context.l10n;
    if (error.statusCode == 413) return l10n.attachmentTooLargeError;
    if (error is NetworkException || error.statusCode >= 500) {
      return l10n.savedReplyFileUploadFailedReason;
    }
    return error.message.isNotEmpty
        ? error.message
        : l10n.savedReplyFileUploadFailedReason;
  }

  /// The category chosen in the form, or [_noCategory]; null until the
  /// person picks one, which keeps the reply's current category untouched.
  int? _chosenCategory;

  /// The "No category" choice. No category has this id.
  static const _noCategory = -1;

  /// What the field shows before a choice: the reply's category — by id, or
  /// for a reply whose category is only a name, the category of that name.
  int _initialCategory(List<SavedReplyCategory> categories) {
    final existing = widget.existing;
    if (existing == null) return _noCategory;
    final id = existing.categoryId;
    if (id != null) {
      return categories.any((c) => c.id == id) ? id : _noCategory;
    }
    final name = existing.category.trim().toLowerCase();
    if (name.isEmpty) return _noCategory;
    for (final c in categories) {
      if (c.name.trim().toLowerCase() == name) return c.id;
    }
    return _noCategory;
  }

  @override
  void dispose() {
    _uploadToken?.cancel();
    unawaited(discardPendingFile(_pending));
    _progress.dispose();
    _title.dispose();
    _shortcut.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _recording) return;

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.savedReplyTitleRequiredError);
      return;
    }
    final body = _body.text.trim();
    // A reply with a file may be the file alone.
    if (body.isEmpty && _pending == null && _keptAsset == null) {
      setState(() => _error = context.l10n.savedReplyBodyRequiredError);
      return;
    }

    final repository = ref.read(savedRepliesRepositoryProvider);
    final shortcut = _shortcut.text.trim();
    final chosen = _chosenCategory;
    final categoryId = chosen == null || chosen == _noCategory ? null : chosen;

    final l10n = context.l10n;
    setState(() {
      _submitting = true;
      _error = null;
    });
    var textSaved = false;
    try {
      final id = _reply?.id;
      var saved = id != null
          ? await repository.update(
              id,
              title: title,
              body: body,
              shortcut: shortcut,
              // Only a category the person changed is sent.
              changeCategory: chosen != null,
              categoryId: categoryId,
            )
          : await repository.create(
              title: title,
              body: body,
              scope: _scope,
              shortcut: shortcut,
              categoryId: categoryId,
            );
      textSaved = true;
      if (mounted) setState(() => _saved = saved);

      final pending = _pending;
      final removeId = _removeAssetId;
      if (pending != null) {
        final token = CancelToken();
        // Rebuilt so Cancel now stops the upload.
        if (mounted) setState(() => _uploadToken = token);
        _progress.value = 0;
        saved = await repository.uploadAsset(
          saved.id,
          filePath: pending.path,
          fileName: pending.name,
          // From the bytes, not the name alone; the server re-checks.
          mimeType: pending.isRecording
              ? 'audio/ogg'
              : AttachmentHelper.detectMimeType(
                  fileName: pending.name,
                  filePath: pending.path,
                  headerBytes: await AttachmentHelper.readHeaderBytes(
                    pending.path,
                  ),
                ),
          isVoice: pending.isRecording,
          durationMs: pending.durationMs,
          cancelToken: token,
          onSendProgress: (sent, total) {
            if (total > 0) _progress.value = (sent / total).clamp(0.0, 1.0);
          },
        );
        _pending = null;
        // Uploaded: the recording's temporary file has done its job.
        unawaited(discardPendingFile(pending));
      } else if (removeId != null &&
          saved.assets.any((a) => a.id == removeId)) {
        saved = await repository.removeAsset(removeId);
      }
      _removeAssetId = null;
      _saved = saved;

      if (!mounted) return;
      _refreshLists();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? l10n.savedReplyUpdatedSnackbar
                : l10n.savedReplyAddedSnackbar,
          ),
        ),
      );
    } on RequestCancelledException {
      // The upload was cancelled; the text, already saved, stays.
      if (!mounted) return;
      _refreshLists();
      setState(() => _error = l10n.savedReplyUploadCancelled);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (textSaved) {
        _refreshLists();
        setState(
          () => _error = l10n.savedReplyFileNotSaved(_fileReason(error)),
        );
      } else {
        setState(() => _error = error.message);
      }
    } on FileSystemException {
      // The chosen file can no longer be read.
      if (!mounted) return;
      if (textSaved) _refreshLists();
      setState(
        () => _error = textSaved
            ? l10n.savedReplyFileNotSaved(l10n.savedReplyFilePickFailed)
            : l10n.savedReplyFilePickFailed,
      );
    } finally {
      _uploadToken = null;
      _progress.value = null;
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _refreshLists() {
    ref.invalidate(manageableSavedRepliesProvider);
    // Each category's count of replies.
    ref.invalidate(savedReplyCategoriesProvider);
  }

  /// The categories from `GET /saved-reply-categories/`, plus "No category".
  /// Until they load (or if they cannot) the field is disabled, and the
  /// reply's category stays as it is.
  Widget _categoryField(BuildContext context) {
    final categories = ref.watch(savedReplyCategoriesProvider).value;
    final l10n = context.l10n;
    // A form field reads its initial value once: built again when the
    // categories arrive, so it shows the reply's own.
    return KeyedSubtree(
      key: ValueKey(categories != null),
      child: _categoryDropdown(l10n, categories),
    );
  }

  Widget _categoryDropdown(
    AppLocalizations l10n,
    List<SavedReplyCategory>? categories,
  ) {
    return DropdownButtonFormField<int>(
      key: const Key('saved-reply-form-category'),
      initialValue: categories == null
          ? _noCategory
          : (_chosenCategory ?? _initialCategory(categories)),
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.savedReplyCategoryFieldLabel),
      items: [
        DropdownMenuItem(
          value: _noCategory,
          child: Text(l10n.savedReplyNoCategoryOption),
        ),
        for (final c in categories ?? const <SavedReplyCategory>[])
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: categories == null || _submitting
          ? null
          : (value) {
              if (value != null) setState(() => _chosenCategory = value);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeOptions = <String>[
      'personal',
      if (_isEdit && _scope == 'team') 'team',
      if (widget.canCreateOrganizationWide || _isEdit) 'organization',
    ];
    final uploading = _uploadToken != null;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          _isEdit
              ? context.l10n.editSavedReplyTitle
              : context.l10n.addSavedReplyTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        TextField(
          key: const Key('saved-reply-form-title'),
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.savedReplyTitleFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('saved-reply-form-shortcut'),
                controller: _shortcut,
                decoration: InputDecoration(
                  labelText: context.l10n.savedReplyShortcutFieldLabel,
                  hintText: context.l10n.savedReplyShortcutFieldHint,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(child: _categoryField(context)),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          context.l10n.savedReplyShortcutHelperText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.md),
        if (_isEdit)
          _ReadOnlyScopeRow(scope: _scope)
        else
          DropdownButtonFormField<String>(
            key: const Key('saved-reply-form-scope'),
            initialValue: _scope,
            decoration: InputDecoration(
              labelText: context.l10n.savedReplyScopeFieldLabel,
            ),
            items: [
              for (final scope in scopeOptions)
                DropdownMenuItem(
                  value: scope,
                  child: Text(savedReplyScopeLabel(context, scope)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _scope = value);
            },
          ),
        const SizedBox(height: Space.md),
        TextField(
          key: const Key('saved-reply-form-body'),
          controller: _body,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.savedReplyBodyFieldLabel,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          context.l10n.savedReplyBodyHelperText(
            '{{customer_name}}',
            '{{agent_name}}',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.lg),
        SavedReplyAttachmentField(
          existing: _keptAsset,
          pending: _pending,
          enabled: !_submitting,
          progress: _progress,
          onPicked: _onPicked,
          onRemove: _onRemoveFile,
          onError: _showError,
          onRecordingChanged: (recording) =>
              setState(() => _recording = recording),
        ),
        const SizedBox(height: Space.lg),
        // Beside Save, where the person is when it appears: the form is
        // longer than a screen, and an error at its top would go unseen.
        if (_error != null) ...[
          InlineError(
            key: const Key('saved-reply-form-error'),
            message: _error!,
          ),
          const SizedBox(height: Space.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('saved-reply-form-cancel'),
              // While the file uploads, Cancel stops the upload; otherwise
              // it closes the sheet.
              onPressed: uploading
                  ? () => _uploadToken?.cancel()
                  : _submitting
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: Space.md),
            FilledButton(
              key: const Key('saved-reply-form-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _submitting || _recording ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(context.l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadOnlyScopeRow extends StatelessWidget {
  const _ReadOnlyScopeRow({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.savedReplyScopeFieldLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          savedReplyScopeLabel(context, scope),
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
