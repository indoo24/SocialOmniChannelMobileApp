/// Teams — how conversations are grouped for routing.
///
/// Read-only, for the same reason as Employees: creating and editing a team is
/// gated behind `team.manage` (ADMIN only) on the web, and an org-configuration
/// form is not work anyone does from a phone. What matters here is seeing which
/// team owns what, which every role can already read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/section_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider);

    return SectionScaffold(
      title: context.l10n.navTeams,
      onRefresh: () async {
        ref.invalidate(teamsProvider);
        await ref.read(teamsProvider.future);
      },
      body: teams.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(teamsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: EmptyState(
                    icon: Icons.groups_outlined,
                    title: context.l10n.noTeamsTitle,
                    message: context.l10n.noTeamsMessage,
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            itemCount: rows.length,
            itemBuilder: (context, index) => _TeamCard(team: rows[index]),
          );
        },
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: Space.md),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colorOf(team.color, theme),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!team.isActive)
                  StatusBadge(label: context.l10n.inactiveBadge, dense: true),
              ],
            ),
            if (team.description.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(team.description, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                StatusBadge(
                  label: context.l10n.memberCountBadge(team.memberCount),
                  dense: true,
                  icon: Icons.person_outline,
                ),
                if (team.language.isNotEmpty)
                  StatusBadge(
                    label: team.language.toUpperCase(),
                    dense: true,
                    icon: Icons.translate,
                  ),
              ],
            ),
            if (team.leaderNames.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Text(
                context.l10n.ledByLabel(team.leaderNames.join(', ')),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The backend stores a CSS hex string. Fall back to the theme rather than
  /// throwing on anything unexpected — a bad colour must not blank the screen.
  static Color _colorOf(String value, ThemeData theme) {
    final hex = value.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return theme.colorScheme.primary;
  }
}
