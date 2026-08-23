/// Lead score, funnel stage, purchase status, sentiment, urgency and the
/// analyzer's summary — the panel the web app shows beside every
/// conversation, reached here the same way orders and customer details are:
/// a bottom sheet opened from the conversation AppBar, because a phone has
/// one column (see `customer_record_sheet.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/intelligence.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../authentication/auth_controller.dart';
import 'intelligence_providers.dart';

/// Opens the intelligence panel for a conversation.
Future<void> showIntelligencePanel(
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
      builder: (context, controller) => _IntelligencePanel(
        conversationId: conversationId,
        scrollController: controller,
      ),
    ),
  );
}

class _IntelligencePanel extends ConsumerStatefulWidget {
  const _IntelligencePanel({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_IntelligencePanel> createState() => _IntelligencePanelState();
}

class _IntelligencePanelState extends ConsumerState<_IntelligencePanel> {
  bool _analyzing = false;

  void _invalidateIntelligence() {
    // Called from child sections after an await (e.g. _setScore(),
    // _decide()) — ref.invalidate() throws "Using ref when a widget is
    // about to or has been unmounted" if this panel's sheet closed while
    // that request was in flight.
    if (!mounted) return;
    ref.invalidate(conversationIntelligenceProvider(widget.conversationId));
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _runAnalyzer() async {
    setState(() => _analyzing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .refreshIntelligence(widget.conversationId);
      _invalidateIntelligence();
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(
      conversationIntelligenceProvider(widget.conversationId),
    );
    final canRefresh = ref.watch(
      canProvider(Perm.conversationRefreshIntelligence),
    );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Intelligence', style: theme.textTheme.titleLarge),
            ),
            if (canRefresh)
              IconButton(
                tooltip: 'Re-run analysis',
                onPressed: _analyzing ? null : _runAnalyzer,
                icon: _analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: LoadingState(label: 'Loading intelligence…'),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: ErrorStateView(
              error: error,
              onRetry: _invalidateIntelligence,
            ),
          ),
          data: (intel) => intel == null
              ? _NotAnalyzedYet(
                  canRefresh: canRefresh,
                  busy: _analyzing,
                  onRun: _runAnalyzer,
                )
              : _IntelligenceContent(
                  conversationId: widget.conversationId,
                  intelligence: intel,
                  onChanged: _invalidateIntelligence,
                  onMessage: _showMessage,
                ),
        ),
      ],
    );
  }
}

class _NotAnalyzedYet extends StatelessWidget {
  const _NotAnalyzedYet({
    required this.canRefresh,
    required this.busy,
    required this.onRun,
  });

  final bool canRefresh;
  final bool busy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.psychology_outlined,
      title: 'Not analyzed yet',
      message:
          'This conversation has no intelligence read yet. It appears '
          'once the analyzer runs, automatically or on demand.',
      action: canRefresh
          ? FilledButton.icon(
              onPressed: busy ? null : onRun,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Run analysis'),
            )
          : null,
    );
  }
}

class _IntelligenceContent extends ConsumerWidget {
  const _IntelligenceContent({
    required this.conversationId,
    required this.intelligence,
    required this.onChanged,
    required this.onMessage,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final VoidCallback onChanged;
  final void Function(String message, {bool isError}) onMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final intel = intelligence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intel.needsHumanReview)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: _ReviewBanner(reason: intel.reviewReason),
          ),

        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            _stageBadge(context, intel.stage),
            _purchaseBadge(context, intel.purchaseStatus),
            if (intel.sentiment.isNotEmpty)
              _sentimentBadge(context, intel.sentiment),
            if (intel.urgency != 'none') _urgencyBadge(context, intel.urgency),
          ],
        ),

        const SizedBox(height: Space.lg),
        _LeadScoreSection(
          conversationId: conversationId,
          intelligence: intel,
          onChanged: onChanged,
          onMessage: onMessage,
        ),

        if (intel.isPurchaseClaimPending) ...[
          const SizedBox(height: Space.lg),
          _PurchaseClaimSection(
            conversationId: conversationId,
            intelligence: intel,
            onChanged: onChanged,
            onMessage: onMessage,
          ),
        ],

        if (intel.summary.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('Summary', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(intel.summary, style: theme.textTheme.bodyMedium),
        ],

        if (intel.nextBestAction.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('Suggested next step', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(intel.nextBestAction, style: theme.textTheme.bodyMedium),
        ],

        if (intel.interestedProducts.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('Interested in', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          _ChipList(values: intel.interestedProducts),
        ],

        if (intel.buyingSignals.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('Buying signals', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          _ChipList(values: intel.buyingSignals),
        ],

        if (intel.objections.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text('Objections', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          _ChipList(values: intel.objections),
        ],

        const SizedBox(height: Space.lg),
        _PurchaseHistorySection(conversationId: conversationId),

        if (intel.analyzedAt != null) ...[
          const SizedBox(height: Space.lg),
          Text(
            'Last analyzed ${formatDateTime(context, intel.analyzedAt)}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: ScenarioColors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: ScenarioColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, size: 18, color: ScenarioColors.warning),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              reason.isEmpty ? 'This conversation needs a human look.' : reason,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipList extends StatelessWidget {
  const _ChipList({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final value in values) StatusBadge(label: value, dense: true),
      ],
    );
  }
}

// --------------------------------------------------------------------------- //
// Lead score
// --------------------------------------------------------------------------- //
class _LeadScoreSection extends ConsumerStatefulWidget {
  const _LeadScoreSection({
    required this.conversationId,
    required this.intelligence,
    required this.onChanged,
    required this.onMessage,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final VoidCallback onChanged;
  final void Function(String message, {bool isError}) onMessage;

  @override
  ConsumerState<_LeadScoreSection> createState() => _LeadScoreSectionState();
}

class _LeadScoreSectionState extends ConsumerState<_LeadScoreSection> {
  bool _busy = false;

  Future<void> _setScore(int? score) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .setLeadScore(widget.conversationId, score);
      widget.onChanged();
      widget.onMessage(
        score == null ? 'Handed back to the analyzer' : 'Lead score updated',
      );
    } on ApiException catch (error) {
      widget.onMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editScore() async {
    final intel = widget.intelligence;
    final controller = TextEditingController(text: intel.leadScore.toString());
    final entered = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set the lead score'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Score (0–100)',
            helperText: "This overrides the analyzer's number.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0 || value > 100) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Not disposed: showDialog's Future resolves the instant Navigator.pop()
    // runs in the Save button, before the AlertDialog's own exit transition
    // has finished animating this TextField off screen. Disposing here raced
    // that still-mounted TextField and threw "A TextEditingController was
    // used after being disposed." Dropping the reference is enough — this
    // controller was never retained beyond this function, so it is
    // collectible as soon as the dialog actually unmounts either way.
    if (entered != null) await _setScore(entered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intel = widget.intelligence;
    final canOverride = ref.watch(canProvider(Perm.intelligenceOverrideScore));

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lead score', style: theme.textTheme.labelMedium),
                  Text(
                    '${intel.leadScore}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (canOverride) ...[
                if (intel.isLeadScoreOverridden)
                  TextButton(
                    onPressed: () => _setScore(null),
                    child: const Text('Reset to AI'),
                  ),
                IconButton(
                  tooltip: 'Set score by hand',
                  onPressed: _editScore,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          StatusBadge(
            label: intel.isLeadScoreOverridden
                ? 'Set by ${intel.leadScoreOverriddenByName.isEmpty ? 'an employee' : intel.leadScoreOverriddenByName}'
                : 'AI-generated',
            tone: intel.isLeadScoreOverridden
                ? BadgeTone.info
                : BadgeTone.neutral,
            dense: true,
          ),
          if (intel.isLeadScoreOverridden) ...[
            const SizedBox(height: Space.xs),
            Text(
              "Analyzer's own read: ${intel.leadScoreAuto}",
              style: theme.textTheme.labelSmall,
            ),
          ],
          if (intel.leadScoreSignals.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            for (final signal in intel.leadScoreSignals)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        signal.label,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      signal.points >= 0
                          ? '+${signal.points}'
                          : '${signal.points}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: signal.points >= 0
                            ? ScenarioColors.success
                            : ScenarioColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Purchase claim
// --------------------------------------------------------------------------- //
class _PurchaseClaimSection extends ConsumerStatefulWidget {
  const _PurchaseClaimSection({
    required this.conversationId,
    required this.intelligence,
    required this.onChanged,
    required this.onMessage,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final VoidCallback onChanged;
  final void Function(String message, {bool isError}) onMessage;

  @override
  ConsumerState<_PurchaseClaimSection> createState() =>
      _PurchaseClaimSectionState();
}

class _PurchaseClaimSectionState extends ConsumerState<_PurchaseClaimSection> {
  bool _busy = false;

  Future<void> _decide(bool confirmed) async {
    final noteController = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          confirmed ? 'Confirm this purchase?' : 'Reject this claim?',
        ),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmed ? 'Confirm' : 'Not yet'),
          ),
        ],
      ),
    );
    final note = noteController.text.trim();
    // Not disposed — see the matching comment in _LeadScoreSectionState's
    // _editScore(): disposing here would race the AlertDialog's still-
    // animating exit transition and can throw a use-after-dispose error.
    if (proceed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .confirmPurchase(
            widget.conversationId,
            confirmed: confirmed,
            note: note,
          );
      widget.onChanged();
      // ref.invalidate() on this State's own ref throws if this sheet
      // closed while confirmPurchase() was in flight.
      if (mounted) {
        ref.invalidate(purchaseConfirmationsProvider(widget.conversationId));
      }
      widget.onMessage(
        confirmed ? 'Purchase confirmed' : 'Recorded as not confirmed',
      );
    } on ApiException catch (error) {
      widget.onMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intel = widget.intelligence;
    final canConfirm = ref.watch(canProvider(Perm.conversationConfirmPurchase));

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: ScenarioColors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: ScenarioColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 16,
                color: ScenarioColors.warning,
              ),
              const SizedBox(width: Space.xs),
              Text(
                'Unconfirmed purchase claim',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          if (intel.purchaseEvidence.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.only(left: Space.sm),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: ScenarioColors.warning, width: 2),
                ),
              ),
              child: Text(
                '"${intel.purchaseEvidence}"',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (canConfirm) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _decide(true),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide(false),
                    child: const Text('Not yet'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Purchase confirmation history
// --------------------------------------------------------------------------- //
class _PurchaseHistorySection extends ConsumerWidget {
  const _PurchaseHistorySection({required this.conversationId});

  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Purchase confirmation history',
        style: theme.textTheme.titleSmall,
      ),
      childrenPadding: const EdgeInsets.only(bottom: Space.sm),
      onExpansionChanged: (expanded) {
        if (expanded) {
          ref.invalidate(purchaseConfirmationsProvider(conversationId));
        }
      },
      children: [
        Consumer(
          builder: (context, ref, _) {
            final async = ref.watch(
              purchaseConfirmationsProvider(conversationId),
            );
            return async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.md),
                child: LoadingState(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text(
                  'Could not load the history.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              data: (confirmations) => confirmations.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Text(
                        'No rulings recorded yet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : Column(
                      children: [
                        for (final confirmation in confirmations)
                          _PurchaseHistoryRow(confirmation: confirmation),
                      ],
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _PurchaseHistoryRow extends StatelessWidget {
  const _PurchaseHistoryRow({required this.confirmation});

  final PurchaseConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                label: confirmation.isConfirmed ? 'Confirmed' : 'Not confirmed',
                tone: confirmation.isConfirmed
                    ? BadgeTone.success
                    : BadgeTone.neutral,
                dense: true,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  confirmation.employeeName.isEmpty
                      ? 'An employee'
                      : confirmation.employeeName,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatDateTime(context, confirmation.decidedAt),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          if (confirmation.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(confirmation.note, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Enum -> badge mapping
// --------------------------------------------------------------------------- //
Widget _stageBadge(BuildContext context, String stage) {
  final tone = switch (stage) {
    'HOT_LEAD' => BadgeTone.success,
    'QUALIFIED_LEAD' => BadgeTone.info,
    'LOST' => BadgeTone.danger,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(stage), tone: tone);
}

Widget _purchaseBadge(BuildContext context, String status) {
  final tone = switch (status) {
    'AGENT_CONFIRMED' => BadgeTone.success,
    'CUSTOMER_SAYS_ORDERED' || 'CUSTOMER_SAYS_PAID' => BadgeTone.warning,
    'INTENT_DETECTED' => BadgeTone.info,
    'REFUND_MENTIONED' => BadgeTone.danger,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(status), tone: tone);
}

Widget _sentimentBadge(BuildContext context, String sentiment) {
  final tone = switch (sentiment) {
    'positive' => BadgeTone.success,
    'negative' => BadgeTone.danger,
    'mixed' => BadgeTone.warning,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(sentiment), tone: tone);
}

Widget _urgencyBadge(BuildContext context, String urgency) {
  final tone = switch (urgency) {
    'high' => BadgeTone.danger,
    'medium' => BadgeTone.warning,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: '${humanizeEnum(urgency)} urgency', tone: tone);
}
