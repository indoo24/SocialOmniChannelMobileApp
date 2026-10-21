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
///
/// With `saved_reply.manage` a Categories panel heads the screen (see
/// `saved_reply_categories_panel.dart`), and the replies are listed under
/// their categories in the categories' saved order, uncategorized ones last.
/// If the categories cannot be read, the replies are listed as before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/employee.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/settings_section_header.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../settings/settings_skeleton.dart';
import 'delete_saved_reply_dialog.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';
import 'saved_reply_attachment_field.dart' show SavedReplyFileBadge;
import 'saved_reply_categories_panel.dart';
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
    final categories = ref.watch(savedReplyCategoriesProvider).value;

    Widget buildList(List<SavedReply> replies) => _SavedRepliesList(
      replies: replies,
      sections: categories == null || categories.isEmpty
          ? null
          : sectionSavedReplies(categories, replies),
      canCreateOrganizationWide: canManage,
      showCategoriesPanel: canManage,
      scrollable: scrollable,
    );

    if (!scrollable) {
      return repliesAsync.when(
        loading: () => const SavedRepliesSkeleton(scrollable: false),
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
        ref.invalidate(savedReplyCategoriesProvider);
        await Future.wait<Object?>([
          ref.read(manageableSavedRepliesProvider.future),
          ref
              .read(savedReplyCategoriesProvider.future)
              .catchError((_) => <SavedReplyCategory>[]),
        ]);
      },
      child: repliesAsync.when(
        loading: () => const SavedRepliesSkeleton(),
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
    this.sections,
    this.showCategoriesPanel = false,
    this.scrollable = true,
  });

  final List<SavedReply> replies;

  /// [replies] under their categories, in order; null to list them as they
  /// came (no categories, or they could not be read).
  final List<SavedReplySection>? sections;
  final bool canCreateOrganizationWide;
  final bool showCategoriesPanel;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final items = [
      SettingsSectionHeader(
        title: context.l10n.tabSavedReplies,
        action: FilledButton.icon(
          key: const Key('add-saved-reply'),
          onPressed: () => showAddSavedReplySheet(
            context,
            canCreateOrganizationWide: canCreateOrganizationWide,
          ),
          style: sectionActionStyle(context),
          icon: const Icon(Icons.add, size: 18),
          label: sectionActionLabel(context.l10n.newSavedReplyAction),
        ),
      ),
      const SizedBox(height: Space.lg),
      if (showCategoriesPanel) ...[
        const SavedReplyCategoriesPanel(),
        const SizedBox(height: Space.lg),
      ],
      if (replies.isEmpty)
        SizedBox(
          height: scrollable ? MediaQuery.sizeOf(context).height * 0.5 : 180,
          child: EmptyState(
            icon: Icons.quickreply_outlined,
            title: context.l10n.noSavedRepliesTitle,
            message: context.l10n.noSavedRepliesMessage,
          ),
        )
      else if (sections case final sections?)
        for (final section in sections) ...[
          _SectionHeading(section: section),
          const SizedBox(height: Space.sm),
          if (section.replies.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.xs,
                bottom: Space.md,
              ),
              child: Text(
                context.l10n.savedReplySectionEmpty,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).mutedForeground,
                ),
              ),
            ),
          for (final reply in section.replies) ...[
            // Under Uncategorized, a category the list does not know is
            // still named on the card.
            _SavedReplyCard(
              reply: reply,
              showCategory: section.category == null,
            ),
            const SizedBox(height: Space.md),
          ],
          const SizedBox(height: Space.sm),
        ]
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

/// A category's heading in the list: its name (or Uncategorized) and how
/// many of the listed replies it holds.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.section});

  final SavedReplySection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final category = section.category;
    final name = category?.name ?? context.l10n.savedRepliesUncategorized;
    return Padding(
      key: Key('saved-reply-section-${category?.id ?? 'uncategorized'}'),
      padding: const EdgeInsetsDirectional.only(start: Space.xs),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(
              '${section.replies.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedReplyCard extends ConsumerWidget {
  const _SavedReplyCard({required this.reply, this.showCategory = true});

  final SavedReply reply;

  /// Name the reply's category on the card. Off under a category's own
  /// heading, which already says it.
  final bool showCategory;

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
                        if (showCategory && reply.category.isNotEmpty) ...[
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
              if (reply.body.isNotEmpty)
                Text(
                  reply.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              if (reply.asset case final asset?) ...[
                const SizedBox(height: Space.sm),
                SavedReplyFileBadge(asset: asset),
              ],
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
