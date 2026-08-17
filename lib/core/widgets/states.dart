/// Loading, empty and error states.
///
/// Every list in the app uses these three rather than inventing its own, so a
/// failure looks the same everywhere and always offers the same way out.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../api/api_exception.dart';
import '../theme/tokens.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          if (label != null) ...[
            const SizedBox(height: Space.md),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: Space.lg),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Error display that distinguishes what the user can do about it.
///
/// A network failure is retryable and says so; a 403 is not, and offering
/// "try again" for something that will always be refused is worse than useless.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = error is ApiException ? error as ApiException : null;
    final isNetwork = api is NetworkException;
    final canRetry = onRetry != null && (isNetwork || api == null || api.statusCode >= 500);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: Space.lg),
            Text(
              isNetwork
                  ? context.l10n.noConnectionTitle
                  : context.l10n.genericErrorTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(
              // The backend's own message (api?.message) is server-generated
              // English and not localizable client-side; only the fallback
              // shown when there is no server message is translated.
              api?.message ?? context.l10n.genericErrorFallbackMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (canRetry) ...[
              const SizedBox(height: Space.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.l10n.retryButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline form error, matching the web client's InlineError.
class InlineError extends StatelessWidget {
  const InlineError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton row for the inbox while the first page loads.
class ConversationSkeleton extends StatelessWidget {
  const ConversationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: base, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(140, 12),
                const SizedBox(height: Space.sm),
                bar(double.infinity, 10),
                const SizedBox(height: 6),
                bar(200, 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
