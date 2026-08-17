/// A customer's profile, reached from the Customers directory.
///
/// Distinct from `customer_details_screen.dart`, which is keyed by
/// *conversation* and answers "who am I talking to right now?" while an agent
/// is mid-thread. This one is keyed by customer and answers "what is this
/// person's whole history with us?" — including conversations, which the
/// backend filters to the caller's own visibility scope.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../conversations/inbox_screen.dart' show ConversationRow;
import '../authentication/auth_controller.dart';
import 'directory_providers.dart';

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({required this.customerId, super.key});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerDirectoryProvider);
    final conversations = ref.watch(customerConversationsProvider(customerId));
    final employee = ref.watch(currentEmployeeProvider);
    final theme = Theme.of(context);

    // The directory list is the source for the header. Reaching this screen
    // always goes through that list, so it is loaded; a deep link that skips it
    // still renders the conversations below.
    final Customer? customer =
        customers.value?.where((c) => c.id == customerId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(customer?.displayName ?? context.l10n.customerTitle)),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          if (customer != null) ...[
            Row(
              children: [
                InitialsAvatar(
                  initials: customer.displayName.isEmpty
                      ? '?'
                      : customer.displayName[0].toUpperCase(),
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
              value: [customer.city, customer.country]
                  .where((v) => v.isNotEmpty)
                  .join(', '),
            ),
            _Field(
              label: context.l10n.languageLabel,
              value: customer.preferredLanguage.toUpperCase(),
            ),
            _Field(
              label: context.l10n.lastSeenFieldLabel,
              value: formatDateTime(context, customer.lastSeenAt),
            ),
            const Divider(height: Space.xxl),
          ],

          Text(
            context.l10n.conversationsCapsSectionTitle,
            style: theme.textTheme.labelSmall
                ?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
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
            child: Text(value.isEmpty ? '—' : value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
