/// The Categories panel at the top of the Saved replies settings: add,
/// rename, delete and order the saved-reply categories.
///
/// Every change goes through `/saved-reply-categories/` and the screen shows
/// what the server answered (see [SavedReplyCategoriesController]). The order
/// is the categories' saved `position`: it orders the sections below and the
/// composer's picker, everywhere the replies are listed.
///
/// Shown to holders of `saved_reply.manage`, the capability the backend
/// documents for creating categories; it re-checks every change.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';

/// The server's limit on a category name.
const _maxNameLength = 60;

class SavedReplyCategoriesPanel extends ConsumerStatefulWidget {
  const SavedReplyCategoriesPanel({super.key});

  @override
  ConsumerState<SavedReplyCategoriesPanel> createState() =>
      _SavedReplyCategoriesPanelState();
}

class _SavedReplyCategoriesPanelState
    extends ConsumerState<SavedReplyCategoriesPanel> {
  final _name = TextEditingController();
  bool _adding = false;
  String? _addError;

  /// A new order is being saved: the order controls wait for it.
  bool _reordering = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SavedReplyCategoriesController get _controller =>
      ref.read(savedReplyCategoriesProvider.notifier);

  Future<void> _add() async {
    if (_adding) return;
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _addError = l10n.savedReplyCategoryNameRequired);
      return;
    }
    final existing = ref.read(savedReplyCategoriesProvider).value ?? const [];
    // The same name, exactly: a duplicate under any rule. Anything subtler
    // is the server's to judge.
    if (existing.any((c) => c.name.trim() == name)) {
      setState(() => _addError = l10n.savedReplyCategoryDuplicate);
      return;
    }
    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      await _controller.create(name);
      if (!mounted) return;
      _name.clear();
      _snack(l10n.savedReplyCategoryAdded);
    } on ApiException catch (error) {
      if (mounted) setState(() => _addError = _message(error));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Moves the category at [from] to [to] and saves the whole order.
  Future<void> _move(
    List<SavedReplyCategory> categories,
    int from,
    int to,
  ) async {
    if (_reordering || from == to) return;
    final ids = [for (final c in categories) c.id];
    ids.insert(to, ids.removeAt(from));
    setState(() => _reordering = true);
    try {
      await _controller.reorder(ids);
    } on ApiException catch (error) {
      if (mounted) {
        _snack(
          '${context.l10n.savedReplyCategoryOrderFailed} ${_message(error)}',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _rename(SavedReplyCategory category) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RenameCategoryDialog(category: category),
    );
    if (saved == true && mounted) {
      _snack(context.l10n.savedReplyCategoryRenamed);
    }
  }

  Future<void> _delete(SavedReplyCategory category) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.savedReplyCategoryDeleteTitle(category.name)),
        content: Text(
          category.replyCount > 0
              ? l10n.savedReplyCategoryDeleteWithReplies(category.replyCount)
              : l10n.savedReplyCategoryDeleteEmpty,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('saved-reply-category-delete-confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.savedReplyCategoryDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _controller.delete(category.id);
      if (mounted) _snack(l10n.savedReplyCategoryDeleted);
    } on ApiException catch (error) {
      if (mounted) _snack(_message(error), error: true);
    }
  }

  /// The server's own reason where it gave one (a duplicate name, a missing
  /// permission), the generic one otherwise.
  String _message(ApiException error) {
    final l10n = context.l10n;
    if (error is NetworkException || error.statusCode >= 500) {
      return l10n.savedReplyCategoryRequestFailed;
    }
    if (error.statusCode == 403) return l10n.savedReplyCategoryNoPermission;
    final field = error.fieldError('name');
    if (field != null && field.isNotEmpty) return field;
    return error.message.isNotEmpty
        ? error.message
        : l10n.savedReplyCategoryRequestFailed;
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final async = ref.watch(savedReplyCategoriesProvider);

    return Container(
      key: const Key('saved-reply-categories-panel'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.md,
              Space.md,
              Space.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    l10n.savedReplyCategoriesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_reordering)
                  const SizedBox(
                    key: Key('saved-reply-categories-saving'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Text(
              l10n.savedReplyCategoriesHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.lg),
              child: LoadingState(),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.savedReplyCategoriesLoadFailed,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(savedReplyCategoriesProvider),
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ),
            data: (categories) => categories.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.md,
                    ),
                    child: Text(
                      l10n.savedReplyCategoriesEmpty,
                      key: const Key('saved-reply-categories-empty'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  )
                : _list(categories),
          ),
          Divider(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('saved-reply-category-name'),
                    controller: _name,
                    enabled: !_adding,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxNameLength),
                    ],
                    onSubmitted: (_) => _add(),
                    onChanged: (_) {
                      if (_addError != null) setState(() => _addError = null);
                    },
                    decoration: InputDecoration(
                      hintText: l10n.savedReplyCategoryNameHint,
                      isDense: true,
                      errorText: _addError,
                      errorMaxLines: 3,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                FilledButton.icon(
                  key: const Key('saved-reply-category-add'),
                  // The theme's buttons fill the width; this one sits beside
                  // the field.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  ),
                  onPressed: _adding ? null : _add,
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 18),
                  label: Text(l10n.savedReplyCategoryAddAction),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<SavedReplyCategory> categories) {
    final last = categories.length - 1;
    return ReorderableListView.builder(
      key: const Key('saved-reply-categories-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: categories.length,
      onReorderItem: (from, to) => _move(categories, from, to),
      proxyDecorator: (child, _, _) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(Radii.md),
        child: child,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryRow(
          key: ValueKey('saved-reply-category-${category.id}'),
          category: category,
          index: index,
          enabled: !_reordering,
          onUp: index == 0 ? null : () => _move(categories, index, index - 1),
          onDown: index == last
              ? null
              : () => _move(categories, index, index + 1),
          onRename: () => _rename(category),
          onDelete: () => _delete(category),
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.index,
    required this.enabled,
    required this.onUp,
    required this.onDown,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final SavedReplyCategory category;
  final int index;
  final bool enabled;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final id = category.id;
    const compact = VisualDensity(horizontal: -3, vertical: -3);

    final handle = Padding(
      padding: const EdgeInsetsDirectional.only(start: Space.xs),
      child: Icon(
        Icons.drag_indicator_rounded,
        color: enabled
            ? colors.mutedForeground
            : colors.mutedForeground.withValues(alpha: 0.4),
      ),
    );

    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (enabled)
              ReorderableDragStartListener(
                key: Key('saved-reply-category-$id-handle'),
                index: index,
                child: Semantics(
                  label: l10n.savedReplyCategoryDragHint,
                  child: handle,
                ),
              )
            else
              handle,
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A name is backend data — never translated.
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    l10n.savedReplyCategoryReplyCount(category.replyCount),
                    key: Key('saved-reply-category-$id-count'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('saved-reply-category-$id-up'),
              tooltip: l10n.savedReplyCategoryMoveUp,
              visualDensity: compact,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: enabled ? onUp : null,
            ),
            IconButton(
              key: Key('saved-reply-category-$id-down'),
              tooltip: l10n.savedReplyCategoryMoveDown,
              visualDensity: compact,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: enabled ? onDown : null,
            ),
            IconButton(
              key: Key('saved-reply-category-$id-rename'),
              tooltip: l10n.savedReplyCategoryRenameAction,
              visualDensity: compact,
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: onRename,
            ),
            IconButton(
              key: Key('saved-reply-category-$id-delete'),
              tooltip: l10n.savedReplyCategoryDeleteAction,
              visualDensity: compact,
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameCategoryDialog extends ConsumerStatefulWidget {
  const _RenameCategoryDialog({required this.category});

  final SavedReplyCategory category;

  @override
  ConsumerState<_RenameCategoryDialog> createState() =>
      _RenameCategoryDialogState();
}

class _RenameCategoryDialogState extends ConsumerState<_RenameCategoryDialog> {
  late final _name = TextEditingController(text: widget.category.name);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.savedReplyCategoryNameRequired);
      return;
    }
    if (name == widget.category.name.trim()) {
      Navigator.of(context).pop(false);
      return;
    }
    final others = ref.read(savedReplyCategoriesProvider).value ?? const [];
    if (others.any(
      (c) => c.id != widget.category.id && c.name.trim() == name,
    )) {
      setState(() => _error = l10n.savedReplyCategoryDuplicate);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(savedReplyCategoriesProvider.notifier)
          .rename(widget.category.id, name);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      final field = error.fieldError('name');
      setState(
        () => _error = error is NetworkException || error.statusCode >= 500
            ? l10n.savedReplyCategoryRequestFailed
            : error.statusCode == 403
            ? l10n.savedReplyCategoryNoPermission
            : (field?.isNotEmpty ?? false)
            ? field
            : error.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.savedReplyCategoryRenameTitle),
      content: TextField(
        key: const Key('saved-reply-category-rename-field'),
        controller: _name,
        autofocus: true,
        enabled: !_saving,
        inputFormatters: [LengthLimitingTextInputFormatter(_maxNameLength)],
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: l10n.savedReplyCategoryNameLabel,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saved-reply-category-rename-save'),
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.commonSave),
        ),
      ],
    );
  }
}
