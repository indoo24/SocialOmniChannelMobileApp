/// The saved-reply picker: a searchable bottom sheet opened from the composer.
///
/// Returns the chosen reply and nothing else. It never sends: the composer puts
/// the text into the reply box for the agent to edit, and the ordinary Send
/// button sends it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
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
                return ListView.separated(
                  controller: widget.scrollController,
                  itemCount: replies.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final reply = replies[index];
                    return ListTile(
                      key: Key('savedReply-${reply.id}'),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              reply.title,
                              overflow: TextOverflow.ellipsis,
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
                      ),
                      trailing: Text(
                        _scopeLabel(context, reply),
                        style: theme.textTheme.labelSmall,
                      ),
                      onTap: () => Navigator.of(context).pop(reply),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
