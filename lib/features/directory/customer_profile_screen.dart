/// A customer's profile, reached from the Customers directory.
///
/// Distinct from `customer_details_screen.dart`, which is keyed by
/// *conversation* and answers "who am I talking to right now?" while an agent
/// is mid-thread. This one is keyed by customer and answers "what is this
/// person's whole history with us?" — contact info, custom fields, every
/// channel they have reached out from, every fact recorded about them, their
/// confirmed purchases and orders, and conversations, which the backend
/// filters to the caller's own visibility scope. Reuses the same widgets the
/// conversation-side record sheet uses for facts and orders
/// (`order_details.dart`'s `RecordedFactTile`/`OrderSummaryCard`) rather than
/// a second implementation of the same cards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/customer_detail.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/export_csv_action.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_screen.dart' show ConversationRow;
import '../customer_fields/custom_fields_section.dart';
import '../orders/order_details.dart';
import 'directory_providers.dart';
import 'edit_customer_sheet.dart';

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({required this.customerId, super.key});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(customerDetailProvider(customerId));
    final conversations = ref.watch(customerConversationsProvider(customerId));
    final employee = ref.watch(currentEmployeeProvider);
    final canEdit = ref.watch(canProvider(Perm.customerManage));
    final canExport = ref.watch(canProvider(Perm.crmExport));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailAsync.value?.displayName ?? context.l10n.customerTitle,
        ),
        actions: [
          if (canEdit && detailAsync.value != null)
            IconButton(
              tooltip: context.l10n.editCustomerTitle,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showEditCustomerSheet(context, customer: detailAsync.value!),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          detailAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.xxl),
              child: LoadingState(),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.invalidate(customerDetailProvider(customerId)),
              ),
            ),
            data: (customer) => _CustomerHeader(customer: customer),
          ),
          // Hidden entirely when the organization defines no custom fields.
          CustomFieldsSection(customerId: customerId),

          if (detailAsync.value != null) ...[
            const Divider(height: Space.xxl),
            _ChannelsSection(identities: detailAsync.value!.identities),

            const Divider(height: Space.xxl),
            _KnownFactsSection(customerId: customerId),

            const Divider(height: Space.xxl),
            _OrdersSection(
              customerId: customerId,
              confirmedPurchaseCount: detailAsync.value!.confirmedPurchaseCount,
              canExport: canExport,
            ),
          ],

          const Divider(height: Space.xxl),
          Text(
            context.l10n.conversationsCapsSectionTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.sm),
          conversations.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: LoadingState(),
            ),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () =>
                  ref.invalidate(customerConversationsProvider(customerId)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(context.l10n.noVisibleConversations),
                );
              }
              return Column(
                children: [
                  for (final conversation in rows)
                    ConversationRow(
                      conversation: conversation,
                      currentEmployeeId: employee?.id,
                      onTap: () =>
                          context.push(Routes.conversation(conversation.id)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.customer});

  final CustomerDetail customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(
              // `.characters.first` rather than `[0]`: a display name can
              // start with an emoji or other multi-code-unit character, and
              // raw UTF-16 indexing would split it mid surrogate pair — a
              // string `TextPainter` then throws "not well-formed UTF-16"
              // trying to render.
              initials: customer.displayName.isEmpty
                  ? '?'
                  : customer.displayName.characters.first.toUpperCase(),
              imageUrl: customer.avatarUrl,
              size: 56,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.displayName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: Space.xs),
                  StatusBadge(
                    label: humanizeEnum(customer.lifecycleStage),
                    dense: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        _Field(label: context.l10n.emailFieldLabel, value: customer.email),
        _Field(label: context.l10n.phoneFieldLabel, value: customer.phone),
        _Field(
          label: context.l10n.locationFieldLabel,
          value: [
            customer.city,
            customer.country,
          ].where((v) => v.isNotEmpty).join(', '),
        ),
        _Field(
          label: context.l10n.languageLabel,
          value: customer.preferredLanguage.toUpperCase(),
        ),
        _Field(
          label: context.l10n.firstSeenFieldLabel,
          value: formatDateTime(context, customer.firstSeenAt),
        ),
        _Field(
          label: context.l10n.lastSeenFieldLabel,
          value: formatDateTime(context, customer.lastSeenAt),
        ),
        if (customer.notes.isNotEmpty)
          _Field(
            label: context.l10n.customerNotesFieldLabel,
            value: customer.notes,
          ),
        // Free-form details only: a typed custom field value is shown by its
        // field in CustomFieldsSection, so it never appears twice, and a
        // recorded fact appears once more, in Known Facts below.
        if (customer.facts.any((fact) => !fact.isTypedField)) ...[
          const SizedBox(height: Space.md),
          Text(
            context.l10n.recordedDetailsSectionTitle,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: Space.xs),
          for (final fact in customer.facts.where((fact) => !fact.isTypedField))
            _Field(label: humanizeEnum(fact.key), value: fact.value),
        ],
      ],
    );
  }
}

/// Every channel account this customer has been reached on: the platform and
/// the account/phone/page identifier where the platform gave one.
class _ChannelsSection extends StatelessWidget {
  const _ChannelsSection({required this.identities});

  final List<CustomerIdentity> identities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.channelsCapsSectionTitle,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        if (identities.isEmpty)
          Text(context.l10n.noChannelsMessage, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final identity in identities)
                Chip(
                  key: Key('customer-channel-${identity.id}'),
                  avatar: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: ConversationBadges.providerColor(identity.provider),
                  ),
                  label: Text(
                    identity.accountLabel.isEmpty
                        ? ConversationBadges.providerLabel(
                            context,
                            identity.provider,
                          )
                        : '${ConversationBadges.providerLabel(context, identity.provider)} · ${identity.accountLabel}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Facts extracted or recorded for this customer — confirmed ones only; a
/// still-pending analyzer suggestion belongs in the conversation record
/// sheet's review tray, not a read profile.
class _KnownFactsSection extends ConsumerWidget {
  const _KnownFactsSection({required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final factsAsync = ref.watch(customerFactsProvider(customerId));
    final recordedFacts = (factsAsync.value ?? const [])
        .where((f) => !f.needsReview && !f.isTypedField)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.knownFactsCapsSectionTitle,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.l10n.knownFactsSectionSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.sm),
        factsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: LoadingState(),
          ),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(customerFactsProvider(customerId)),
          ),
          data: (_) => recordedFacts.isEmpty
              ? Text(
                  context.l10n.noKnownFactsMessage,
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  children: [
                    for (final fact in recordedFacts)
                      RecordedFactTile(fact: fact),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Confirmed purchases and the customer's orders, with the same amount /
/// products / quantity / confirmation-status / confirmed-by presentation the
/// conversation record sheet uses, plus each order's placed-at timestamp.
class _OrdersSection extends ConsumerWidget {
  const _OrdersSection({
    required this.customerId,
    required this.confirmedPurchaseCount,
    required this.canExport,
  });

  final int customerId;
  final int confirmedPurchaseCount;
  final bool canExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    // Orders here are every recorded/confirmed row for this customer, not
    // suggestions still waiting on a human — those live in the conversation
    // record sheet's review tray.
    final orders = (ordersAsync.value ?? const [])
        .where((o) => !o.isSuggestion)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.confirmedPurchasesFieldLabel,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.confirmedPurchasesSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$confirmedPurchaseCount',
                  style: theme.textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.ordersCapsSectionTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canExport)
              ExportCsvAction(
                fileNamePrefix: 'customer-$customerId-orders',
                fetch: () => ref
                    .read(directoryRepositoryProvider)
                    .exportOrdersCsv(customerId: customerId),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        ordersAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: LoadingState(),
          ),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(customerOrdersProvider(customerId)),
          ),
          data: (_) => orders.isEmpty
              ? Text(
                  context.l10n.noOrdersForCustomerMessage,
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  children: [
                    for (final order in orders)
                      OrderSummaryCard(order: order, showPlacedAt: true),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
