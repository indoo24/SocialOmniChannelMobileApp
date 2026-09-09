/// Redesigned Customer Intelligence presentation widget for Flutter mobile.
///
/// Matches the target reference design:
/// - Top header with sparkle icon, title, and refresh icon.
/// - Subtle disclaimer / info card.
/// - Lead score card with prominent score / 100, horizontal progress bar,
///   Edit / Auto / Meta action buttons, score override history, and expandable signals.
/// - Responsive 2-column attributes grid (Stage, Confidence, Purchase status,
///   Sentiment, Intent, Urgency).
/// - Buying signals list with empty state.
/// - Multiline summary.
/// - Recommended next action highlighted card.
/// - Preserved review banners, purchase claims, interested products, objections,
///   and Meta conversion history.
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
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversion_providers.dart';
import 'intelligence_providers.dart';

/// The full redesigned Customer Intelligence view.
class CustomerIntelligenceView extends ConsumerStatefulWidget {
  const CustomerIntelligenceView({
    required this.conversationId,
    required this.intelligence,
    this.onChanged,
    this.onMessage,
    this.showHeader = true,
    super.key,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final VoidCallback? onChanged;
  final void Function(String message, {bool isError})? onMessage;
  final bool showHeader;

  @override
  ConsumerState<CustomerIntelligenceView> createState() =>
      _CustomerIntelligenceViewState();
}

class _CustomerIntelligenceViewState
    extends ConsumerState<CustomerIntelligenceView> {
  bool _analyzing = false;
  bool _busyScore = false;
  bool _reportingMeta = false;
  bool _signalsExpanded = false;

  void _notifyMessage(String message, {bool isError = false}) {
    if (widget.onMessage != null) {
      widget.onMessage!(message, isError: isError);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _triggerChanged() {
    if (widget.onChanged != null) {
      widget.onChanged!();
      return;
    }
    if (!mounted) return;
    ref.invalidate(conversationIntelligenceProvider(widget.conversationId));
  }

  Future<void> _runAnalyzer() async {
    setState(() => _analyzing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .refreshIntelligence(widget.conversationId);
      _triggerChanged();
    } on ApiException catch (error) {
      _notifyMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _setScore(int? score) async {
    setState(() => _busyScore = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .setLeadScore(widget.conversationId, score);
      _triggerChanged();
      if (!mounted) return;
      _notifyMessage(
        score == null
            ? context.l10n.handedBackToAnalyzerMessage
            : context.l10n.leadScoreUpdatedMessage,
      );
    } on ApiException catch (error) {
      _notifyMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyScore = false);
    }
  }

  Future<void> _editScore() async {
    final intel = widget.intelligence;
    final controller = TextEditingController(text: intel.leadScore.toString());
    final entered = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.setLeadScoreDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.leadScoreRangeFieldLabel,
            helperText: dialogContext.l10n.leadScoreFieldHelper,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0 || value > 100) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: Text(dialogContext.l10n.commonSave),
          ),
        ],
      ),
    );
    // Preserved fix from tests: do not call controller.dispose() synchronously
    // to avoid throwing during dialog exit transition.
    if (entered != null) await _setScore(entered);
  }

  Future<void> _reportConversion() async {
    setState(() => _reportingMeta = true);
    try {
      final result = await ref
          .read(conversationRepositoryProvider)
          .reportConversion(widget.conversationId);
      if (!mounted) return;
      ref.invalidate(conversationConversionsProvider(widget.conversationId));
      _notifyMessage(result.detail);
    } on ApiException catch (error) {
      _notifyMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _reportingMeta = false);
    }
  }

  Color _scoreColor(int score) {
    if (score >= 75) return ScenarioColors.danger;
    if (score >= 50) return const Color(0xFF8B5CF6); // violet
    if (score >= 20) return const Color(0xFF0284C7); // sky
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final intel = widget.intelligence;
    final canRefresh = ref.watch(
      canProvider(Perm.conversationRefreshIntelligence),
    );
    final canOverride = ref.watch(canProvider(Perm.intelligenceOverrideScore));
    final canReportConversion = ref.watch(canProvider(Perm.conversionReport));

    final versionStr = intel.analysisVersion.isNotEmpty
        ? intel.analysisVersion
        : context.l10n.intelligenceTheAnalyzer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP HEADER (Optional if wrapped by external header)
        if (widget.showHeader) ...[
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  context.l10n.customerIntelligenceSectionTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canRefresh)
                IconButton(
                  tooltip: context.l10n.rerunAnalysisTooltip,
                  onPressed: _analyzing ? null : _runAnalyzer,
                  visualDensity: VisualDensity.compact,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
        ],

        // 2. DISCLAIMER / INFO CARD
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm + 2,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  )
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  context.l10n.intelligenceDisclaimer(versionStr),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),

        // PRESERVED: Needs human review banner
        if (intel.needsHumanReview) ...[
          _ReviewBanner(reason: intel.reviewReason),
          const SizedBox(height: Space.md),
        ],

        // PRESERVED: Purchase claim pending ruling
        if (intel.isPurchaseClaimPending) ...[
          _PurchaseClaimSection(
            conversationId: widget.conversationId,
            intelligence: intel,
            onChanged: _triggerChanged,
            onMessage: _notifyMessage,
          ),
          const SizedBox(height: Space.md),
        ],

        // PRESERVED: Agent confirmed purchase alert
        if (intel.isAgentConfirmed) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: ScenarioColors.successSurface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: ScenarioColors.success.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: ScenarioColors.success,
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      context.l10n.confirmedMetric,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ScenarioColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.setByEmployeeLabel(
                    intel.confirmedByName.isEmpty
                        ? context.l10n.anEmployeeLabel
                        : intel.confirmedByName,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (intel.purchaseConfirmationNote.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '"${intel.purchaseConfirmationNote}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.md),
        ],

        // 3. LEAD SCORE SECTION
        // Header Row: LEAD SCORE on left, actions on right
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              context.l10n.leadScoreFieldLabel.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (_busyScore || _reportingMeta)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (canOverride)
                _InlineAction(
                  icon: Icons.edit_outlined,
                  label: context.l10n.editAction,
                  tooltip: context.l10n.setScoreByHandTooltip,
                  onPressed: _editScore,
                ),
              if (canOverride && intel.isLeadScoreOverridden) ...[
                const SizedBox(width: 4),
                _InlineAction(
                  icon: Icons.undo_rounded,
                  label: context.l10n.autoScoreAction,
                  tooltip: context.l10n.returnToAutoScoreTooltip(
                    intel.leadScoreAuto,
                  ),
                  onPressed: () => _setScore(null),
                ),
              ],
              if (canReportConversion) ...[
                const SizedBox(width: 4),
                _InlineAction(
                  icon: Icons.near_me_outlined,
                  label: context.l10n.metaScoreAction,
                  tooltip: context.l10n.sendStageToMetaTooltip,
                  onPressed: _reportConversion,
                ),
              ],
            ],
          ],
        ),
        const SizedBox(height: Space.xs),

        // Prominent Score Display: 20   / 100
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${intel.leadScore}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _scoreColor(intel.leadScore),
              ),
            ),
            const SizedBox(width: Space.xs),
            Text(
              '/ 100',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Horizontal Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            value: (intel.leadScore / 100.0).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
            valueColor: AlwaysStoppedAnimation<Color>(
              _scoreColor(intel.leadScore),
            ),
          ),
        ),

        // Score History / Source (if overridden)
        if (intel.isLeadScoreOverridden) ...[
          const SizedBox(height: Space.xs + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.edit_outlined,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  context.l10n.scoreOverriddenDetail(
                    intel.leadScore,
                    intel.leadScoreOverriddenByName.isNotEmpty
                        ? intel.leadScoreOverriddenByName
                        : context.l10n.anEmployeeLabel,
                    intel.leadScoreOverriddenAt != null
                        ? formatDateTime(context, intel.leadScoreOverriddenAt)
                        : '—',
                    intel.leadScoreAuto,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],

        // Expandable signals behind score
        if (intel.leadScoreSignals.isNotEmpty) ...[
          const SizedBox(height: Space.xs + 2),
          InkWell(
            onTap: () => setState(() => _signalsExpanded = !_signalsExpanded),
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _signalsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _signalsExpanded
                          ? context.l10n.hideSignalsBehindScore(
                              intel.leadScoreSignals.length,
                            )
                          : context.l10n.showSignalsBehindScore(
                              intel.leadScoreSignals.length,
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_signalsExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  for (final signal in intel.leadScoreSignals)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.sm,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.4)
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              signal.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.xs),
                          Text(
                            signal.points >= 0
                                ? '+${signal.points}'
                                : '${signal.points}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: signal.points >= 0
                                  ? ScenarioColors.success
                                  : ScenarioColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],

        const SizedBox(height: Space.lg),

        // 4. INTELLIGENCE ATTRIBUTES (Responsive 2-column layout)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AttributeItem(
                    label: context.l10n.stageFieldLabel.toUpperCase(),
                    valueWidget: _stageBadge(context, intel.stage),
                  ),
                  const SizedBox(height: Space.md),
                  _AttributeItem(
                    label: context.l10n.purchaseStatusLabel.toUpperCase(),
                    valueWidget: intel.purchaseStatus.toUpperCase() == 'NONE'
                        ? Text(
                            context.l10n.noneValue,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : _purchaseBadge(context, intel.purchaseStatus),
                  ),
                  const SizedBox(height: Space.md),
                  _AttributeItem(
                    label: context.l10n.intentFieldLabel.toUpperCase(),
                    valueText: humanizeEnum(intel.intentStrength),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            // Right column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AttributeItem(
                    label: context.l10n.confidenceFieldLabel.toUpperCase(),
                    valueText: '${(intel.confidence * 100).round()}%',
                  ),
                  const SizedBox(height: Space.md),
                  _AttributeItem(
                    label: context.l10n.sentimentFieldLabel.toUpperCase(),
                    valueWidget: intel.sentiment.isNotEmpty
                        ? _sentimentBadge(context, intel.sentiment)
                        : Text(
                            '—',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(height: Space.md),
                  _AttributeItem(
                    label: context.l10n.urgencyFieldLabel.toUpperCase(),
                    valueText: humanizeEnum(intel.urgency),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: Space.lg),

        // 5. BUYING SIGNALS
        Text(
          context.l10n.buyingSignalsLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        if (intel.buyingSignals.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final signal in intel.buyingSignals)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.north_east,
                        size: 14,
                        color: ScenarioColors.success,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          signal,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Text(
              context.l10n.noBuyingSignalsMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

        const SizedBox(height: Space.lg),

        // 6. SUMMARY
        Text(
          context.l10n.intelligenceSummaryLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          intel.summary.isNotEmpty ? intel.summary : '—',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
        ),

        // 7. RECOMMENDED NEXT ACTION
        if (intel.nextBestAction.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.sm + 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        context.l10n.recommendedNextActionTitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  intel.nextBestAction,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],

        // PRESERVED: Interested products & Objections chips
        if (intel.interestedProducts.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text(
            context.l10n.interestedInLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final p in intel.interestedProducts)
                StatusBadge(label: p, dense: true),
            ],
          ),
        ],

        if (intel.objections.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text(
            context.l10n.objectionsLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final o in intel.objections)
                StatusBadge(label: o, tone: BadgeTone.danger, dense: true),
            ],
          ),
        ],

        // PRESERVED: Meta conversions history
        _MetaConversionsSection(conversationId: widget.conversationId),

        // Timestamp
        if (intel.analyzedAt != null) ...[
          const SizedBox(height: Space.lg),
          Text(
            context.l10n.lastAnalyzedLabel(
              formatDateTime(context, intel.analyzedAt),
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// INLINE ACTION BUTTON (Edit, Auto, Meta)
// ---------------------------------------------------------------------------
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: theme.colorScheme.primary),
              const SizedBox(width: 3),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ATTRIBUTE ITEM (Label + Value)
// ---------------------------------------------------------------------------
class _AttributeItem extends StatelessWidget {
  const _AttributeItem({required this.label, this.valueText, this.valueWidget})
    : assert(valueText != null || valueWidget != null);

  final String label;
  final String? valueText;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
            letterSpacing: 0.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (valueWidget != null)
          valueWidget!
        else
          Text(
            valueText ?? '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PRESERVED SUBSECTIONS: Review Banner & Purchase Claims
// ---------------------------------------------------------------------------
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.sm),
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
          Icon(Icons.flag_outlined, size: 16, color: ScenarioColors.warning),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              reason.isEmpty ? context.l10n.reviewBannerDefaultReason : reason,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

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
      builder: (dialogContext) => AlertDialog(
        title: Text(
          confirmed
              ? dialogContext.l10n.confirmPurchaseDialogTitle
              : dialogContext.l10n.rejectPurchaseDialogTitle,
        ),
        content: TextField(
          controller: noteController,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.noteOptionalLabel,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmed
                  ? dialogContext.l10n.confirmAction
                  : dialogContext.l10n.notYetButton,
            ),
          ),
        ],
      ),
    );
    final note = noteController.text.trim();
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
      if (!mounted) return;
      ref.invalidate(purchaseConfirmationsProvider(widget.conversationId));
      widget.onMessage(
        confirmed
            ? context.l10n.purchaseConfirmedMessage
            : context.l10n.purchaseNotConfirmedMessage,
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
      padding: const EdgeInsets.all(Space.sm),
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
              Expanded(
                child: Text(
                  context.l10n.unconfirmedPurchaseClaimLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (intel.purchaseEvidence.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
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
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _decide(true),
                    icon: const Icon(Icons.check, size: 14),
                    label: Text(context.l10n.confirmAction),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide(false),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(context.l10n.notYetButton),
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

// ---------------------------------------------------------------------------
// PRESERVED: Meta Conversions Section
// ---------------------------------------------------------------------------
class _MetaConversionsSection extends ConsumerWidget {
  const _MetaConversionsSection({required this.conversationId});

  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationConversionsProvider(conversationId));
    final conversions = async.value;
    if (conversions == null || conversions.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.lg),
        Text(
          context.l10n.conversionsAction.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        for (final conversion in conversions)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    conversion.eventName.isNotEmpty
                        ? conversion.eventName
                        : humanizeEnum(conversion.sourceStage),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
                StatusBadge(
                  label: conversion.status.toLowerCase(),
                  tone: conversion.status.toUpperCase() == 'SENT'
                      ? BadgeTone.success
                      : BadgeTone.warning,
                  dense: true,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BADGE HELPERS
// ---------------------------------------------------------------------------
Widget _stageBadge(BuildContext context, String stage) {
  final tone = switch (stage.toUpperCase()) {
    'HOT_LEAD' => BadgeTone.success,
    'QUALIFIED_LEAD' => BadgeTone.info,
    'LOST' => BadgeTone.danger,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(stage), tone: tone, dense: true);
}

Widget _purchaseBadge(BuildContext context, String status) {
  final tone = switch (status.toUpperCase()) {
    'AGENT_CONFIRMED' => BadgeTone.success,
    'CUSTOMER_SAYS_ORDERED' || 'CUSTOMER_SAYS_PAID' => BadgeTone.warning,
    'INTENT_DETECTED' => BadgeTone.info,
    'REFUND_MENTIONED' => BadgeTone.danger,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(status), tone: tone, dense: true);
}

Widget _sentimentBadge(BuildContext context, String sentiment) {
  final s = sentiment.toLowerCase();
  final tone = switch (s) {
    'positive' => BadgeTone.success,
    'negative' => BadgeTone.danger,
    'mixed' => BadgeTone.warning,
    _ => BadgeTone.neutral,
  };
  return StatusBadge(label: humanizeEnum(sentiment), tone: tone, dense: true);
}
