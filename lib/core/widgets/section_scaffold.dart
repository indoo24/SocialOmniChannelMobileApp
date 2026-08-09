/// Scaffold for a top-level section — the screens the drawer navigates to.
///
/// Exists so every section gets the drawer, the hamburger and the connection
/// banner without restating them, and so none can quietly forget one. Screens
/// reached by pushing (a conversation, a customer) use a plain `Scaffold` with
/// a back arrow instead: a drawer on a pushed screen gives two conflicting ways
/// out of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/conversations/inbox_screen.dart' show realtimeStatusProvider;
import '../realtime/realtime_client.dart';
import '../theme/tokens.dart';
import 'app_drawer.dart';

class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.titleWidget,
    this.floatingActionButton,
    this.onRefresh,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// Replaces the title outright — the inbox swaps in a search field.
  final Widget? titleWidget;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final content = onRefresh == null
        ? body
        : RefreshIndicator(onRefresh: onRefresh!, child: body);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: titleWidget ?? Text(title),
        actions: actions,
        bottom: const ConnectionBanner(),
      ),
      body: content,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Thin strip shown when realtime is down, so nobody trusts a stale list.
class ConnectionBanner extends ConsumerWidget implements PreferredSizeWidget {
  const ConnectionBanner({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).value;
    if (status != RealtimeStatus.disconnected) {
      return const SizedBox.shrink();
    }

    return Material(
      color: ScenarioColors.warningSurface,
      child: SizedBox(
        height: 22,
        width: double.infinity,
        child: Center(
          child: Text(
            'Reconnecting…',
            style: TextStyle(
              fontSize: 11,
              color: ScenarioColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a route is opened that the signed-in role cannot use.
///
/// The drawer does not offer these, so this is the deep-link case: a
/// notification or a shared link pointing somewhere the role has no business.
/// An explicit refusal beats a silent redirect — the person knows the screen
/// exists and that their role, not a bug, is why they cannot see it.
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({required this.sectionLabel, super.key});

  final String sectionLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SectionScaffold(
      title: sectionLabel,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: Space.lg),
              Text("You don't have access", style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              Text(
                'Your role does not include $sectionLabel. Ask an administrator '
                'if you need it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading used across the dashboard and analytics screens.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Metric tile. The mobile form of the web dashboard's MetricCard.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = MetricTone.neutral,
    this.hint,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final MetricTone tone;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (foreground, surface) = switch (tone) {
      MetricTone.neutral => (theme.colorScheme.onSurfaceVariant, theme.colorScheme.surfaceContainerHighest),
      MetricTone.success => (ScenarioColors.success, ScenarioColors.successSurface),
      MetricTone.warning => (ScenarioColors.warning, ScenarioColors.warningSurface),
      MetricTone.danger => (ScenarioColors.danger, ScenarioColors.dangerSurface),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(icon, size: 14, color: foreground),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(
                  hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum MetricTone { neutral, success, warning, danger }
