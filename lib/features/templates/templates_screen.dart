/// Templates screen — lists WhatsApp message templates for connected WABAs.
///
/// Ported from the web client's Message Templates screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/models/template.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'create_template_sheet.dart';
import 'templates_providers.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(whatsappChannelsProvider);
    final selectedChannelId = ref.watch(selectedWabaChannelIdProvider);
    final employee = ref.watch(currentEmployeeProvider);
    final canManage = employee?.can(Perm.channelManage) ?? false;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SectionScaffold(
      title: context.l10n.templatesTitle,
      onRefresh: () async {
        ref.invalidate(whatsappChannelsProvider);
        if (selectedChannelId != null) {
          ref.invalidate(templatesForChannelProvider(selectedChannelId));
        }
        await ref.read(whatsappChannelsProvider.future);
      },
      body: channelsAsync.when(
        loading: () => const LoadingState(),
        error: (err, _) => ErrorStateView(
          error: err,
          onRetry: () => ref.invalidate(whatsappChannelsProvider),
        ),
        data: (channels) {
          if (channels.isEmpty) {
            return EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: context.l10n.noWabaAccounts,
              message: context.l10n.noWabaAccountsMessage,
            );
          }

          final effectiveChannelId = selectedChannelId ?? channels.first.id;

          return ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              // Header title and description
              Text(
                context.l10n.templatesTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                context.l10n.templatesSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? ScenarioColors.darkMutedForeground
                      : ScenarioColors.mutedForeground,
                ),
              ),
              const SizedBox(height: Space.lg),

              // WhatsApp Business Account selector card
              _WabaSelectorCard(
                channels: channels,
                selectedChannelId: effectiveChannelId,
                onChanged: (val) {
                  if (val != null) {
                    ref
                        .read(selectedWabaChannelIdProvider.notifier)
                        .select(val);
                  }
                },
              ),
              const SizedBox(height: Space.xl),

              // Subheader: Template count + Refresh + Create template
              _TemplatesSubheader(
                channelId: effectiveChannelId,
                canManage: canManage,
              ),
              const SizedBox(height: Space.md),

              // Templates cards list
              _TemplatesList(channelId: effectiveChannelId),
            ],
          );
        },
      ),
    );
  }
}

/// Card with dropdown to select the active WhatsApp Business Account.
class _WabaSelectorCard extends StatelessWidget {
  const _WabaSelectorCard({
    required this.channels,
    required this.selectedChannelId,
    required this.onChanged,
  });

  final List<ChannelConnection> channels;
  final int selectedChannelId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark ? ScenarioColors.darkBorder : ScenarioColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.wabaAccountLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark
                  ? ScenarioColors.darkMutedForeground
                  : ScenarioColors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: channels.any((c) => c.id == selectedChannelId)
                  ? selectedChannelId
                  : channels.first.id,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: [
                for (final channel in channels)
                  DropdownMenuItem<int>(
                    value: channel.id,
                    child: Text(
                      '${channel.displayName} · ${channel.externalAccountId.isNotEmpty ? channel.externalAccountId : channel.id}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Row displaying template count and action buttons (Refresh, + Create template).
class _TemplatesSubheader extends ConsumerWidget {
  const _TemplatesSubheader({required this.channelId, required this.canManage});

  final int channelId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesForChannelProvider(channelId));
    final count = templatesAsync.value?.length ?? 0;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        Text(
          context.l10n.templatesCount(count),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark
                ? ScenarioColors.darkForeground
                : ScenarioColors.foreground,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                ref.invalidate(templatesForChannelProvider(channelId));
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(context.l10n.refreshAction),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.xs,
                ),
                side: BorderSide(
                  color: isDark
                      ? ScenarioColors.darkBorder
                      : ScenarioColors.border,
                ),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: Space.sm),
              FilledButton.icon(
                onPressed: () {
                  CreateTemplateSheet.show(context, channelId: channelId);
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(context.l10n.createTemplateAction),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  backgroundColor: ScenarioColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.xs,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// List of template cards adapted for mobile screens.
class _TemplatesList extends ConsumerWidget {
  const _TemplatesList({required this.channelId});

  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesForChannelProvider(channelId));

    return templatesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: LoadingState(),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: ErrorStateView(
          error: err,
          onRetry: () => ref.invalidate(templatesForChannelProvider(channelId)),
        ),
      ),
      data: (templates) {
        if (templates.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: EmptyState(
              icon: Icons.article_outlined,
              title: context.l10n.noTemplatesFound,
              message: context.l10n.noTemplatesMessage,
            ),
          );
        }

        return Column(
          children: [
            for (final template in templates) _TemplateCard(template: template),
          ],
        );
      },
    );
  }
}

/// A responsive mobile card rendering template information.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template});

  final WhatsAppTemplate template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark ? ScenarioColors.darkBorder : ScenarioColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Name and Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  template.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              StatusBadge(label: template.status, tone: template.statusTone),
            ],
          ),

          // Message Body Preview
          if (template.body.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? ScenarioColors.darkBackground
                    : ScenarioColors.background,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: isDark
                      ? ScenarioColors.darkBorder
                      : ScenarioColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                template.body,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: Space.md),

          // Metadata Grid: Language, Category, Meta ID
          Row(
            children: [
              _MetaItem(
                label: context.l10n.templateLanguageLabel,
                value: template.language,
              ),
              const SizedBox(width: Space.lg),
              _MetaItem(
                label: context.l10n.templateCategoryLabel,
                value: template.category,
              ),
            ],
          ),
          if (template.id.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            _MetaItem(
              label: context.l10n.templateMetaIdLabel,
              value: template.id,
            ),
          ],

          // Rejection reason banner if rejected
          if (template.rejectedReason.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                color: ScenarioColors.dangerSurface,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                context.l10n.templateRejectedReason(template.rejectedReason),
                style: TextStyle(
                  color: ScenarioColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],

          // Unsupported components warning if any
          if (template.unsupported.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                color: ScenarioColors.warningSurface,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                context.l10n.templateUnsupportedNotice(
                  template.unsupported.join(', '),
                ),
                style: TextStyle(
                  color: ScenarioColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark
                ? ScenarioColors.darkMutedForeground
                : ScenarioColors.mutedForeground,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
