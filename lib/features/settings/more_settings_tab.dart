/// The "More settings" tab in SettingsScreen — groups Customer Fields,
/// Saved Replies, and Data Export into a unified view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/customer_fields.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/csv_export.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../customer_fields/customer_fields_settings_screen.dart';
import '../directory/directory_providers.dart';
import '../saved_replies/saved_replies_providers.dart';
import '../saved_replies/saved_replies_settings_screen.dart';
import '../saved_replies/saved_reply.dart';

class MoreSettingsTab extends ConsumerWidget {
  const MoreSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSeeCustomerFields = ref.watch(canProvider(Perm.customerView));
    final canSeeSavedReplies = ref.watch(canProvider(Perm.conversationReply));
    final canExport = ref.watch(canProvider(Perm.crmExport));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(customerFieldDefinitionsProvider);
        ref.invalidate(manageableSavedRepliesProvider);
        await Future.wait([
          if (canSeeCustomerFields)
            ref
                .read(customerFieldDefinitionsProvider.future)
                .catchError((_) => <CustomerFieldDefinition>[]),
          if (canSeeSavedReplies)
            ref
                .read(manageableSavedRepliesProvider.future)
                .catchError((_) => <SavedReply>[]),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Horizontal padding moves onto each section's own surface below, so
        // the card edges sit where this padding used to and the content keeps
        // exactly the width it had before — the inner field/reply cards are
        // unchanged and must not get narrower on a 320px phone.
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          // Each section gets its own surface rather than a shared column
          // split by a 1px Divider: Customer fields and Saved replies are
          // unrelated settings that happen to share a tab, and read as one
          // long list when the only thing between them is a hairline.
          if (canSeeCustomerFields) ...[
            const _SettingsSection(
              key: Key('more-section-customer-fields'),
              child: CustomerFieldsSettingsTab(scrollable: false),
            ),
            if (canSeeSavedReplies || canExport)
              const SizedBox(height: Space.xl),
          ],
          if (canSeeSavedReplies) ...[
            const _SettingsSection(
              key: Key('more-section-saved-replies'),
              child: SavedRepliesSettingsTab(scrollable: false),
            ),
            if (canExport) const SizedBox(height: Space.xl),
          ],
          if (canExport)
            const _SettingsSection(
              key: Key('more-section-export-data'),
              child: _ExportDataSection(),
            ),
        ],
      ),
    );
  }
}

/// One self-contained block on the More tab.
///
/// The card surface plus the gap between instances is what makes Customer
/// fields, Saved replies and Export data read as separate settings rather
/// than one long scroll. The section's own heading and controls come from
/// [child] — this only supplies the surface, so nothing inside is
/// restyled or duplicated.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      // The card sits where the list's own horizontal padding used to, and
      // pads its content by the same amount vertically. Horizontal padding is
      // deliberately smaller than Space.lg: on a 320px screen the inner
      // customer-field and saved-reply cards are already at their minimum,
      // and taking another 32px off the content width overflows them.
      margin: const EdgeInsets.symmetric(horizontal: Space.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.lg,
      ),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark ? ScenarioColors.darkBorder : ScenarioColors.border,
        ),
      ),
      child: child,
    );
  }
}

class _ExportDataSection extends ConsumerStatefulWidget {
  const _ExportDataSection();

  @override
  ConsumerState<_ExportDataSection> createState() => _ExportDataSectionState();
}

class _ExportDataSectionState extends ConsumerState<_ExportDataSection> {
  bool _exportingConversations = false;
  bool _exportingCustomers = false;

  Future<void> _exportConversations() async {
    if (_exportingConversations) return;
    setState(() => _exportingConversations = true);
    try {
      final employee = ref.read(currentEmployeeProvider);
      await exportCsvAndShare(
        context,
        fetch: () => ref
            .read(conversationRepositoryProvider)
            .exportCsv(currentEmployeeId: employee?.id),
        fileNamePrefix: 'conversations',
      );
    } finally {
      if (mounted) setState(() => _exportingConversations = false);
    }
  }

  Future<void> _exportCustomers() async {
    if (_exportingCustomers) return;
    setState(() => _exportingCustomers = true);
    try {
      await exportCsvAndShare(
        context,
        fetch: () => ref.read(directoryRepositoryProvider).exportCustomersCsv(),
        fileNamePrefix: 'customers',
      );
    } finally {
      if (mounted) setState(() => _exportingCustomers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.exportDataSectionTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          context.l10n.exportDataSectionDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.lg),
        Card(
          key: const Key('export-conversations-card'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.exportConversationsCsvAction,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  context.l10n.exportConversationsSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.md),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _buildConversationsButton(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Card(
          key: const Key('export-customers-card'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.exportCustomersCsvAction,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  context.l10n.exportCustomersSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.md),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _buildCustomersButton(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConversationsButton(BuildContext context) {
    return FilledButton.icon(
      key: const Key('export-conversations-csv-button'),
      onPressed: _exportingConversations ? null : _exportConversations,
      icon: _exportingConversations
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(context.l10n.exportActionLabel),
    );
  }

  Widget _buildCustomersButton(BuildContext context) {
    return FilledButton.icon(
      key: const Key('export-customers-csv-button'),
      onPressed: _exportingCustomers ? null : _exportCustomers,
      icon: _exportingCustomers
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(context.l10n.exportActionLabel),
    );
  }
}
