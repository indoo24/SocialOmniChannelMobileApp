/// Saved replies admin — the Settings tab that manages saved-reply
/// *definitions* (`GET/POST/PATCH/DELETE /saved-replies/`), not the
/// composer's read-only picker.
///
/// `saved_reply_picker.dart` is the other saved-replies screen in this app;
/// it lets an agent *use* an existing reply from the conversation composer
/// and is deliberately left untouched here — the two are different concerns
/// against the same resource, same as `custom_fields_section.dart` versus
/// the customer-fields admin tab.
///
/// Every employee with `conversation.reply` may see this tab and manage
/// their own personal replies (the same permission the composer picker
/// already requires); creating or editing an organization-wide reply
/// additionally needs `Perm.savedReplyManage`, mirrored from the backend's
/// own `saved_replies_create` rule. Per-row edit/delete is gated on the
/// server's own `SavedReply.canEdit`, never re-derived client-side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/employee.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'delete_saved_reply_dialog.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';
import 'saved_reply_form_sheet.dart';

class SavedRepliesSettingsTab extends ConsumerWidget {
  const SavedRepliesSettingsTab({super.key, this.scrollable = true});

  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canProvider(Perm.conversationReply));
    if (!canView) {
      return scrollable
          ? Center(
              child: EmptyState(
                title: context.l10n.savedRepliesPermissionDenied,
                icon: Icons.lock_outline,
              ),
            )
          : const SizedBox.shrink();
    }

    final canManage = ref.watch(canProvider(Perm.savedReplyManage));
    final repliesAsync = ref.watch(manageableSavedRepliesProvider);

    Widget buildList(List<SavedReply> replies) => _SavedRepliesList(
      replies: replies,
      canCreateOrganizationWide: canManage,
      scrollable: scrollable,
    );

    if (!scrollable) {
      return repliesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: Space.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(manageableSavedRepliesProvider),
        ),
        data: buildList,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(manageableSavedRepliesProvider);
        await ref.read(manageableSavedRepliesProvider.future);
      },
      child: repliesAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(manageableSavedRepliesProvider),
        ),
        data: buildList,
      ),
    );
  }
}

class _SavedRepliesList extends StatelessWidget {
  const _SavedRepliesList({
    required this.replies,
    required this.canCreateOrganizationWide,
    this.scrollable = true,
  });

  final List<SavedReply> replies;
  final bool canCreateOrganizationWide;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      Text(
        context.l10n.tabSavedReplies,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Space.sm),
      Text(
        context.l10n.savedRepliesTabDescription,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: Space.lg),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          key: const Key('add-saved-reply'),
          onPressed: () => showAddSavedReplySheet(
            context,
            canCreateOrganizationWide: canCreateOrganizationWide,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.l10n.newSavedReplyAction),
        ),
      ),
      const SizedBox(height: Space.lg),
      if (replies.isEmpty)
        SizedBox(
          height: scrollable ? MediaQuery.sizeOf(context).height * 0.5 : 180,
          child: EmptyState(
            icon: Icons.quickreply_outlined,
            title: context.l10n.noSavedRepliesTitle,
            message: context.l10n.noSavedRepliesMessage,
          ),
        )
      else
        for (final reply in replies) ...[
          _SavedReplyCard(reply: reply),
          const SizedBox(height: Space.md),
        ],
    ];

    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.lg),
      children: items,
    );
  }
}

class _SavedReplyCard extends ConsumerWidget {
  const _SavedReplyCard({required this.reply});

  final SavedReply reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      key: Key('saved-reply-${reply.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: reply.isActive ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                reply.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (!reply.isActive) ...[
                              const SizedBox(width: Space.xs),
                              StatusBadge(
                                label: context.l10n.savedReplyDisabledBadge,
                                dense: true,
                              ),
                            ],
                          ],
                        ),
                        if (reply.shortcut.isNotEmpty) ...[
                          const SizedBox(height: Space.xs),
                          Text(
                            context.l10n.savedReplyShortcutLabel(
                              reply.shortcut,
                            ),
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (reply.category.isNotEmpty) ...[
                          const SizedBox(height: Space.xs),
                          Text(
                            context.l10n.savedReplyCategoryLabel(
                              reply.category,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: savedReplyScopeLabel(context, reply.scope),
                    tone: BadgeTone.info,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                reply.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (reply.canEdit) ...[
                const SizedBox(height: Space.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: Key('saved-reply-${reply.id}-edit'),
                      tooltip: context.l10n.editAction,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          showEditSavedReplySheet(context, reply: reply),
                    ),
                    IconButton(
                      key: Key('saved-reply-${reply.id}-delete'),
                      tooltip: context.l10n.deleteSavedReplyAction,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      onPressed: reply.isActive
                          ? () => confirmDeleteSavedReply(
                              context,
                              ref,
                              reply: reply,
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
