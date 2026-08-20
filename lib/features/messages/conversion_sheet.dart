/// Meta ads reporting for one conversation: what has been sent, and a button
/// to report the current stage now.
///
/// A bottom sheet, the same shape as `showConversationHistorySheet` — read
/// access is open to any active employee (per the guide: "hiding it from the
/// person working the thread would leave 'did Meta get this?' answerable
/// only from the server logs"), and the "Report now" action is gated
/// separately on `conversion.report`, same as `Perm.channelManage` gates
/// mute/unmute one level stricter than `Perm.channelView` gates the tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversion_event.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversion_providers.dart';

/// Opens the conversions sheet.
Future<void> showConversionsSheet(
  BuildContext context, {
  required int conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _ConversionsSheet(
        conversationId: conversationId,
        scrollController: controller,
      ),
    ),
  );
}

class _ConversionsSheet extends ConsumerStatefulWidget {
  const _ConversionsSheet({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ConversionsSheet> createState() => _ConversionsSheetState();
}

class _ConversionsSheetState extends ConsumerState<_ConversionsSheet> {
  bool _reporting = false;

  Future<void> _reportNow() async {
    setState(() => _reporting = true);
    try {
      final result = await ref
          .read(conversationRepositoryProvider)
          .reportConversion(widget.conversationId);
      ref.invalidate(conversationConversionsProvider(widget.conversationId));
      if (!mounted) return;
      // The server's own detail already distinguishes sent from
      // already-reported/skipped/refused — none of the non-`sent` outcomes
      // is an error, so this is always a plain snackbar, never a red one.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.detail)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(
      conversationConversionsProvider(widget.conversationId),
    );
    final canReport = ref.watch(canProvider(Perm.conversionReport));

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.conversionsAction,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (canReport)
              FilledButton.icon(
                onPressed: _reporting ? null : _reportNow,
                icon: _reporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.campaign_outlined, size: 16),
                label: Text(context.l10n.reportConversionAction),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: LoadingState(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(
                conversationConversionsProvider(widget.conversationId),
              ),
            ),
          ),
          data: (conversions) => conversions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Text(
                    context.l10n.conversionsEmpty,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final conversion in conversions)
                      _ConversionRow(conversion: conversion),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ConversionRow extends StatelessWidget {
  const _ConversionRow({required this.conversion});

  final ConversionEvent conversion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (conversion.status) {
      'SENT' => BadgeTone.success,
      'FAILED' || 'UNMATCHABLE' => BadgeTone.danger,
      _ => BadgeTone.neutral,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(
                label: humanizeEnum(conversion.status),
                tone: tone,
                dense: true,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  conversion.eventName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatDateTime(context, conversion.createdAt),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          if (conversion.value.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '${conversion.value} ${conversion.currency}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (conversion.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              conversion.errorMessage,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
