/// The saved-reply picker: a searchable bottom sheet opened from the composer,
/// with the replies grouped by the category each was saved under.
///
/// Returns the chosen reply and nothing else. It never sends: the composer puts
/// the text into the reply box for the agent to edit, and the ordinary Send
/// button sends it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';

/// Opens the picker. Resolves to the chosen reply, or `null` if dismissed.
Future<SavedReply?> showSavedReplyPicker(BuildContext context) {
  return showModalBottomSheet<SavedReply>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          SavedReplyPickerSheet(scrollController: controller),
    ),
  );
}

class SavedReplyPickerSheet extends ConsumerStatefulWidget {
  const SavedReplyPickerSheet({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<SavedReplyPickerSheet> createState() =>
      _SavedReplyPickerSheetState();
}

class _SavedReplyPickerSheetState extends ConsumerState<SavedReplyPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _term = '';

  /// The category being browsed; null for all of them.
  String? _category;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // A short pause so each keystroke is not its own request.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  String _scopeLabel(BuildContext context, SavedReply reply) {
    switch (reply.scope) {
      case 'personal':
        return context.l10n.savedReplyScopePersonal;
      case 'team':
        return reply.teamName ?? context.l10n.savedReplyScopeTeam;
      default:
        return context.l10n.savedReplyScopeOrganization;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(savedRepliesProvider(_term));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
            child: Text(
              context.l10n.savedRepliesTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: TextField(
              key: const Key('savedReplySearch'),
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.l10n.savedRepliesSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Expanded(
            child: async.when(
              loading: () =>
                  LoadingState(label: context.l10n.savedRepliesLoading),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(savedRepliesProvider(_term)),
              ),
              data: (replies) {
                if (replies.isEmpty) {
                  return EmptyState(
                    title: context.l10n.savedRepliesTitle,
                    message: _term.isEmpty
                        ? context.l10n.savedRepliesEmpty
                        : context.l10n.savedRepliesNoMatch,
                    icon: Icons.quickreply_outlined,
                  );
                }

                final groups = groupSavedRepliesByCategory(replies);
                // A category chosen before a new search may not be in the new
                // results; then everything that matched is shown.
                final selected = groups.any((g) => g.category == _category)
                    ? _category
                    : null;
                final visible = selected == null
                    ? groups
                    : groups.where((g) => g.category == selected).toList();
                // Section headings only help when there is more than one
                // section to tell apart.
                final showHeadings = visible.length > 1;

                final rows = <Widget>[
                  for (final group in visible) ...[
                    if (showHeadings)
                      _CategoryHeading(
                        label: _categoryLabel(context, group.category),
                        count: group.replies.length,
                      ),
                    for (final reply in group.replies)
                      _ReplyTile(
                        reply: reply,
                        scopeLabel: _scopeLabel(context, reply),
                      ),
                  ],
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Only worth a row when the replies actually have
                    // categories to choose between.
                    if (groups.length > 1)
                      _CategoryChips(
                        categories: [for (final g in groups) g.category],
                        selected: selected,
                        labelOf: (c) => _categoryLabel(context, c),
                        onSelected: (c) => setState(() => _category = c),
                      ),
                    Expanded(
                      child: ListView(
                        key: const Key('savedReplyList'),
                        controller: widget.scrollController,
                        children: rows,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A category as written by whoever created the replies; replies without
  /// one are listed under a localized "Uncategorized".
  String _categoryLabel(BuildContext context, String category) =>
      category.isEmpty ? context.l10n.savedRepliesUncategorized : category;
}

/// Replies sharing one category, in the order the server returned them.
class SavedReplyGroup {
  const SavedReplyGroup(this.category, this.replies);

  /// As stored on the replies, trimmed; empty for "no category".
  final String category;
  final List<SavedReply> replies;
}

/// [replies] grouped by their `category`: named categories alphabetically
/// (ignoring case), uncategorized ones last. Within a group the server's
/// order — most specific scope first — is kept. Categories that differ only
/// in case or surrounding spaces are one category, shown as first written.
List<SavedReplyGroup> groupSavedRepliesByCategory(List<SavedReply> replies) {
  final byKey = <String, List<SavedReply>>{};
  final names = <String, String>{};
  for (final reply in replies) {
    final name = reply.category.trim();
    final key = name.toLowerCase();
    names.putIfAbsent(key, () => name);
    (byKey[key] ??= []).add(reply);
  }
  final keys = byKey.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.compareTo(b);
    });
  return [for (final k in keys) SavedReplyGroup(names[k]!, byKey[k]!)];
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<String> categories;

  /// Null for "all categories".
  final String? selected;
  final String Function(String) labelOf;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String? category, String label) => Padding(
      padding: const EdgeInsetsDirectional.only(end: Space.sm),
      child: ChoiceChip(
        key: Key('savedReplyCategory-${category ?? '*'}'),
        label: Text(label, textDirection: textDirectionOf(label)),
        selected: selected == category,
        onSelected: (_) => onSelected(category),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
      child: Row(
        children: [
          chip(null, context.l10n.savedRepliesAllCategories),
          for (final c in categories) chip(c, labelOf(c)),
        ],
      ),
    );
  }
}

class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs + 2,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: textDirectionOf(label),
                textAlign: ambientStartAlign(context),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text('$count', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply, required this.scopeLabel});

  final SavedReply reply;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startAlign = ambientStartAlign(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: Key('savedReply-${reply.id}'),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  reply.title,
                  overflow: TextOverflow.ellipsis,
                  textDirection: textDirectionOf(reply.title),
                  textAlign: startAlign,
                ),
              ),
              if (reply.shortcut.isNotEmpty) ...[
                const SizedBox(width: Space.sm),
                Text(
                  '/${reply.shortcut}',
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            reply.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirectionOf(reply.body),
            textAlign: startAlign,
          ),
          trailing: Text(scopeLabel, style: theme.textTheme.labelSmall),
          onTap: () => Navigator.of(context).pop(reply),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
