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
        padding: const EdgeInsets.all(Space.lg),
        children: [
          if (canSeeCustomerFields) ...[
            const CustomerFieldsSettingsTab(scrollable: false),
            if (canSeeSavedReplies || canExport) ...[
              const SizedBox(height: Space.xl),
              const Divider(),
              const SizedBox(height: Space.xl),
            ],
          ],
          if (canSeeSavedReplies) ...[
            const SavedRepliesSettingsTab(scrollable: false),
            if (canExport) ...[
              const SizedBox(height: Space.xl),
              const Divider(),
              const SizedBox(height: Space.xl),
            ],
          ],
          if (canExport) const _ExportDataSection(),
        ],
      ),
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
