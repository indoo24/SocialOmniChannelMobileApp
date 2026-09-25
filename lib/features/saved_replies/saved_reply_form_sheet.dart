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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';

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
  late final _category = TextEditingController(text: widget.existing?.category);
  late final _body = TextEditingController(text: widget.existing?.body);
  late String _scope = widget.existing?.scope ?? 'personal';

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _shortcut.dispose();
    _category.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.savedReplyTitleRequiredError);
      return;
    }
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _error = context.l10n.savedReplyBodyRequiredError);
      return;
    }

    final repository = ref.read(savedRepliesRepositoryProvider);
    final shortcut = _shortcut.text.trim();
    final category = _category.text.trim();

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.isEdit) {
        await repository.update(
          widget.existing!.id,
          title: title,
          body: body,
          shortcut: shortcut,
          category: category,
        );
      } else {
        await repository.create(
          title: title,
          body: body,
          scope: _scope,
          shortcut: shortcut,
          category: category,
        );
      }

      if (!mounted) return;
      ref.invalidate(manageableSavedRepliesProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? context.l10n.savedReplyUpdatedSnackbar
                : context.l10n.savedReplyAddedSnackbar,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeOptions = <String>[
      'personal',
      if (widget.isEdit && _scope == 'team') 'team',
      if (widget.canCreateOrganizationWide || widget.isEdit) 'organization',
    ];

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          widget.isEdit
              ? context.l10n.editSavedReplyTitle
              : context.l10n.addSavedReplyTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
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
            Expanded(
              child: TextField(
                key: const Key('saved-reply-form-category'),
                controller: _category,
                decoration: InputDecoration(
                  labelText: context.l10n.savedReplyCategoryFieldLabel,
                ),
              ),
            ),
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
        if (widget.isEdit)
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: Space.md),
            FilledButton(
              key: const Key('saved-reply-form-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _submitting ? null : _submit,
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
