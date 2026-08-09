/// Customers — everyone who has contacted this organization.
///
/// The web client opens a drawer beside the table; a phone pushes a detail
/// screen instead. Same rows, same search, same lifecycle vocabulary.
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
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import 'directory_providers.dart';
import 'directory_search_field.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerDirectoryProvider);

    return SectionScaffold(
      title: 'Customers',
      titleWidget: _searching
          ? DirectorySearchField(
              hint: 'Search name, email, phone or handle',
              onSubmitted: (value) =>
                  ref.read(customerSearchProvider.notifier).update(value),
            )
          : null,
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() => _searching = !_searching);
            if (!_searching) ref.read(customerSearchProvider.notifier).clear();
          },
        ),
      ],
      onRefresh: () async {
        ref.invalidate(customerDirectoryProvider);
        await ref.read(customerDirectoryProvider.future);
      },
      body: customers.when(
        loading: () => ListView.separated(
          itemCount: 8,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, _) => const ConversationSkeleton(),
        ),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(customerDirectoryProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: const EmptyState(
                    icon: Icons.people_outline,
                    title: 'No customers',
                    message: 'Customers appear the first time they message you.',
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
            itemBuilder: (context, index) => _CustomerRow(customer: rows[index]),
          );
        },
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xs,
      ),
      leading: InitialsAvatar(
        initials: _initials(customer.displayName),
        imageUrl: customer.avatarUrl,
      ),
      title: Text(
        customer.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              StatusBadge(
                label: humanizeEnum(customer.lifecycleStage),
                dense: true,
              ),
              StatusBadge(
                label: '${customer.conversationCount} chat'
                    '${customer.conversationCount == 1 ? '' : 's'}',
                dense: true,
                icon: Icons.forum_outlined,
              ),
              for (final provider in customer.providers)
                StatusBadge(
                  label: ConversationBadges.providerLabel(provider),
                  dense: true,
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: customer.lastSeenAt == null
          ? null
          : Text(
              formatRelativeTime(customer.lastSeenAt),
              style: theme.textTheme.labelSmall,
            ),
      onTap: () => context.push(Routes.customerProfile(customer.id)),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}
