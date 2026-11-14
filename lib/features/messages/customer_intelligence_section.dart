/// Customer intelligence — the analyzer's read of a conversation, laid out
/// the way the web client's conversation panel lays it out:
///
/// 1. Header with refresh (optional; the conversation sheet draws its own).
/// 2. A muted banner: where this came from, and that it is a suggestion.
/// 3. "Possible purchase detected" while a customer's claim awaits a ruling:
///    who claims what, the quoted evidence, Confirm purchase / Not yet, an
///    optional note sent with the decision, and what confirming records.
/// 4. Lead score: Edit / Auto / Meta, the score out of 100 and its bar.
/// 5. The signals behind the score, expandable.
/// 6. A two-column grid: stage, confidence, purchase status, sentiment,
///    intent, urgency.
///
/// Then what the web shows below it — interested products, objections,
/// buying signals, summary, recommended next action, Meta conversions and
/// when it was last analysed.
///
/// Every value comes from [ConversationIntelligence]; every action is an
/// existing repository call (`refreshIntelligence`, `setLeadScore`,
/// `confirmPurchase`, `reportConversion`) behind its existing permission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/intelligence.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversion_providers.dart';
import 'intelligence_providers.dart';

/// The customer intelligence view for one conversation.
class CustomerIntelligenceView extends ConsumerStatefulWidget {
  const CustomerIntelligenceView({
    required this.conversationId,
    required this.intelligence,
    this.customerName,
    this.onChanged,
    this.onMessage,
    this.showHeader = true,
    super.key,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;

  /// Who the purchase claim is from, for "{name} says they have paid". When
  /// not known the alert says "The customer".
  final String? customerName;
  final VoidCallback? onChanged;
  final void Function(String message, {bool isError})? onMessage;
  final bool showHeader;

  @override
  ConsumerState<CustomerIntelligenceView> createState() =>
      _CustomerIntelligenceViewState();
}

/// Which lead-score action is in flight, so only that button spins.
enum _ScoreBusy { none, edit, auto, meta }

class _CustomerIntelligenceViewState
    extends ConsumerState<CustomerIntelligenceView> {
  bool _analyzing = false;
  _ScoreBusy _scoreBusy = _ScoreBusy.none;
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
    setState(
      () => _scoreBusy = score == null ? _ScoreBusy.auto : _ScoreBusy.edit,
    );
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
      if (mounted) setState(() => _scoreBusy = _ScoreBusy.none);
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
    // The controller is left to the GC: disposing it here, while the dialog
    // is still animating out, throws (see intelligence_lead_score_dialog_test).
    if (entered != null) await _setScore(entered);
  }

  Future<void> _reportConversion() async {
    setState(() => _scoreBusy = _ScoreBusy.meta);
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
      if (mounted) setState(() => _scoreBusy = _ScoreBusy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final intel = widget.intelligence;
    final canRefresh = ref.watch(
      canProvider(Perm.conversationRefreshIntelligence),
    );

    final version = intel.analysisVersion.isNotEmpty
        ? intel.analysisVersion
        : context.l10n.intelligenceTheAnalyzer;

    const gap = SizedBox(height: Space.lg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header — the conversation sheet passes showHeader: false and
        //    draws the same title and refresh in its own section card.
        if (widget.showHeader) ...[
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  context.l10n.customerIntelligenceSectionTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
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

        // 2. Where this came from, and that it is a suggestion.
        _ExtractionBanner(text: context.l10n.intelligenceDisclaimer(version)),

        if (intel.needsHumanReview) ...[
          const SizedBox(height: Space.md),
          _ReviewBanner(reason: intel.reviewReason),
        ],

        // 3. A purchase claim awaiting a ruling.
        if (intel.isPurchaseClaimPending) ...[
          const SizedBox(height: Space.md),
          _PurchaseAlert(
            conversationId: widget.conversationId,
            intelligence: intel,
            customerName: widget.customerName,
            onChanged: _triggerChanged,
            onMessage: _notifyMessage,
          ),
        ],

        if (intel.isAgentConfirmed) ...[
          const SizedBox(height: Space.md),
          _PurchaseConfirmedCard(intelligence: intel),
        ],

        gap,

        // 4 & 5. Lead score, its bar, and the signals behind it.
        _LeadScoreSection(
          intelligence: intel,
          busy: _scoreBusy,
          signalsExpanded: _signalsExpanded,
          onToggleSignals: () =>
              setState(() => _signalsExpanded = !_signalsExpanded),
          onEdit: _editScore,
          onAuto: () => _setScore(null),
          onMeta: _reportConversion,
        ),

        gap,

        // 6. The attributes grid.
        _InsightsGrid(intelligence: intel),

        // What the web shows below the grid, in its order.
        if (intel.interestedProducts.isNotEmpty) ...[
          gap,
          _SectionLabel(context.l10n.interestedInLabel),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final p in intel.interestedProducts)
                StatusBadge(
                  label: p,
                  tone: BadgeTone.info,
                  icon: Icons.sell_outlined,
                  dense: true,
                ),
            ],
          ),
        ],

        if (intel.objections.isNotEmpty) ...[
          gap,
          _SectionLabel(context.l10n.objectionsLabel),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final o in intel.objections)
                StatusBadge(label: o, tone: BadgeTone.danger, dense: true),
            ],
          ),
        ],

        gap,
        _SectionLabel(context.l10n.buyingSignalsLabel),
        if (intel.buyingSignals.isNotEmpty)
          for (final signal in intel.buyingSignals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.north_east,
                      size: 13,
                      color: colors.success,
                    ),
                  ),
                  const SizedBox(width: Space.xs + 2),
                  Expanded(
                    child: Text(
                      signal,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            )
        else
          Text(
            context.l10n.noBuyingSignalsMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.mutedForeground,
              fontStyle: FontStyle.italic,
            ),
          ),

        gap,
        _SectionLabel(context.l10n.intelligenceSummaryLabel),
        Text(
          intel.summary.isNotEmpty ? intel.summary : '—',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
        ),

        if (intel.nextBestAction.isNotEmpty) ...[
          gap,
          _NextActionCard(text: intel.nextBestAction),
        ],

        _MetaConversionsSection(conversationId: widget.conversationId),

        if (intel.analyzedAt != null) ...[
          gap,
          Text(
            context.l10n.lastAnalyzedLabel(
              formatDateTime(context, intel.analyzedAt),
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// A section heading: small, uppercase (in scripts that have case), muted.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs + 2),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.6,
          color: AppColors.of(context).mutedForeground,
        ),
      ),
    );
  }
}

/// The muted "Generated from conversation text by … verify before acting"
/// line.
class _ExtractionBanner extends StatelessWidget {
  const _ExtractionBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const ValueKey('intelExtractionBanner'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.info_outline,
              size: 13,
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(width: Space.xs + 2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.45,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const ValueKey('intelReviewBanner'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, size: 15, color: colors.warning),
          const SizedBox(width: Space.xs + 2),
          Expanded(
            child: Text(
              reason.isEmpty ? context.l10n.reviewBannerDefaultReason : reason,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Possible purchase detected
// ---------------------------------------------------------------------------

/// The customer says they ordered or paid, and nobody has ruled on it.
///
/// Confirm purchase and Not yet are `POST /confirm-purchase/` with
/// `confirmed` true or false; "Add note" opens the optional note that goes
/// with either decision (the web's `confirmationNote`, 255 characters).
/// Not yet does not delete the claim: the server keeps it on record and
/// stops asking.
class _PurchaseAlert extends ConsumerStatefulWidget {
  const _PurchaseAlert({
    required this.conversationId,
    required this.intelligence,
    required this.customerName,
    required this.onChanged,
    required this.onMessage,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final String? customerName;
  final VoidCallback onChanged;
  final void Function(String message, {bool isError}) onMessage;

  @override
  ConsumerState<_PurchaseAlert> createState() => _PurchaseAlertState();
}

class _PurchaseAlertState extends ConsumerState<_PurchaseAlert> {
  final _note = TextEditingController();
  bool _noteOpen = false;

  /// The decision in flight — true confirm, false not yet — or null.
  bool? _deciding;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool confirmed) async {
    if (_deciding != null) return;
    setState(() => _deciding = confirmed);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .confirmPurchase(
            widget.conversationId,
            confirmed: confirmed,
            note: _note.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(purchaseConfirmationsProvider(widget.conversationId));
      widget.onMessage(
        confirmed
            ? context.l10n.purchaseConfirmedMessage
            : context.l10n.purchaseNotConfirmedMessage,
      );
      _note.clear();
      setState(() => _noteOpen = false);
      // Last: the refetch it starts may take this alert away.
      widget.onChanged();
    } on ApiException catch (error) {
      widget.onMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final intel = widget.intelligence;
    final canConfirm = ref.watch(canProvider(Perm.conversationConfirmPurchase));
    // Text on the warning surface: the warning hue taken toward the
    // foreground, so it reads in light and dark alike.
    final ink = Color.lerp(colors.warning, colors.foreground, 0.6)!;
    final small = theme.textTheme.bodySmall?.copyWith(color: ink, height: 1.45);

    final name = (widget.customerName ?? '').trim().isEmpty
        ? context.l10n.theCustomerLabel
        : widget.customerName!.trim();
    final explanation =
        intel.purchaseStatus.toUpperCase() == 'CUSTOMER_SAYS_PAID'
        ? context.l10n.purchaseClaimSaysPaid(name)
        : context.l10n.purchaseClaimSaysOrdered(name);
    final busy = _deciding != null;

    return Container(
      key: const ValueKey('purchaseAlert'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.warning.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: colors.warning,
              ),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  context.l10n.possiblePurchaseTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          if (!canConfirm) ...[
            const SizedBox(height: Space.xs + 2),
            Text(
              context.l10n.needsConfirmRightsMessage,
              key: const ValueKey('purchaseAlertNoRights'),
              style: small,
            ),
          ] else ...[
            const SizedBox(height: Space.xs + 2),
            Text(
              explanation,
              key: const ValueKey('purchaseAlertExplanation'),
              style: small,
            ),
            if (intel.purchaseEvidence.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Container(
                key: const ValueKey('purchaseAlertQuote'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 2,
                  vertical: Space.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.12),
                  border: BorderDirectional(
                    start: BorderSide(color: colors.warning, width: 2),
                  ),
                ),
                child: Text(
                  '“${intel.purchaseEvidence}”',
                  style: small?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (_noteOpen) ...[
              const SizedBox(height: Space.sm + 2),
              TextField(
                key: const ValueKey('purchaseNoteField'),
                controller: _note,
                autofocus: true,
                enabled: !busy,
                maxLength: 255,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  filled: true,
                  fillColor: colors.surface,
                  hintText: context.l10n.purchaseNotePlaceholder,
                  labelText: context.l10n.noteOptionalLabel,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.sm + 2,
                    vertical: Space.sm + 2,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(
                      color: colors.warning.withValues(alpha: 0.55),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(
                      color: colors.warning.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Space.sm + 2),
            // Wraps on a narrow phone rather than squeeze or clip a label.
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('confirmPurchaseButton'),
                  onPressed: busy ? null : () => _decide(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  icon: _deciding == true
                      ? const _ButtonSpinner(color: Colors.white)
                      : const Icon(Icons.check, size: 16),
                  label: Text(context.l10n.confirmPurchaseAction),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('rejectPurchaseButton'),
                  onPressed: busy ? null : () => _decide(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.foreground,
                    backgroundColor: colors.surface,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    side: BorderSide(color: colors.border),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  icon: _deciding == false
                      ? const _ButtonSpinner()
                      : const Icon(Icons.close, size: 16),
                  label: Text(context.l10n.notYetButton),
                ),
                if (!_noteOpen)
                  TextButton.icon(
                    key: const ValueKey('addPurchaseNoteButton'),
                    onPressed: busy
                        ? null
                        : () => setState(() => _noteOpen = true),
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                      textStyle: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(context.l10n.addNoteAction),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.confirmingRecordsHint,
              key: const ValueKey('purchaseAlertFootnote'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: ink.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

/// An employee has confirmed the purchase.
class _PurchaseConfirmedCard extends StatelessWidget {
  const _PurchaseConfirmedCard({required this.intelligence});

  final ConversationIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final intel = intelligence;
    final ink = Color.lerp(colors.success, colors.foreground, 0.55)!;
    final name = intel.confirmedByName.isEmpty
        ? context.l10n.anEmployeeLabel
        : intel.confirmedByName;
    return Container(
      key: const ValueKey('purchaseConfirmedCard'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.successSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: colors.success),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  context.l10n.purchaseConfirmedMessage,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            intel.purchaseConfirmedAt == null
                ? context.l10n.purchaseConfirmedBy(name)
                : context.l10n.purchaseConfirmedByOn(
                    name,
                    formatDateTime(context, intel.purchaseConfirmedAt),
                  ),
            style: theme.textTheme.bodySmall?.copyWith(color: ink),
          ),
          if (intel.purchaseConfirmationNote.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              '“${intel.purchaseConfirmationNote}”',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 & 5. Lead score
// ---------------------------------------------------------------------------

class _LeadScoreSection extends ConsumerWidget {
  const _LeadScoreSection({
    required this.intelligence,
    required this.busy,
    required this.signalsExpanded,
    required this.onToggleSignals,
    required this.onEdit,
    required this.onAuto,
    required this.onMeta,
  });

  final ConversationIntelligence intelligence;
  final _ScoreBusy busy;
  final bool signalsExpanded;
  final VoidCallback onToggleSignals;
  final VoidCallback onEdit;
  final VoidCallback onAuto;
  final VoidCallback onMeta;

  /// The web's bands: rose from 75, violet from 50, sky from 20, slate below.
  static Color scoreColor(int score) {
    if (score >= 75) return const Color(0xFFE11D48);
    if (score >= 50) return const Color(0xFF7C3AED);
    if (score >= 20) return const Color(0xFF0284C7);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final intel = intelligence;
    final canOverride = ref.watch(canProvider(Perm.intelligenceOverrideScore));
    final canReport = ref.watch(canProvider(Perm.conversionReport));
    final working = busy != _ScoreBusy.none;
    final score = intel.leadScore.clamp(0, 100);
    final tint = scoreColor(score);

    return Column(
      key: const ValueKey('leadScoreSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Heading at the start, actions at the end; the actions drop to their
        // own line when a narrow phone cannot fit both.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: Space.xs,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.sm),
              child: Text(
                context.l10n.intelligenceLeadScoreTitle.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: colors.mutedForeground,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canOverride)
                  _ScoreAction(
                    key: const ValueKey('leadScoreEdit'),
                    icon: Icons.edit_outlined,
                    label: context.l10n.editAction,
                    tooltip: context.l10n.setScoreByHandTooltip,
                    loading: busy == _ScoreBusy.edit,
                    onPressed: working ? null : onEdit,
                  ),
                if (canOverride && intel.isLeadScoreOverridden)
                  _ScoreAction(
                    key: const ValueKey('leadScoreAuto'),
                    icon: Icons.undo_rounded,
                    label: context.l10n.autoScoreAction,
                    tooltip: context.l10n.returnToAutoScoreTooltip(
                      intel.leadScoreAuto,
                    ),
                    loading: busy == _ScoreBusy.auto,
                    onPressed: working ? null : onAuto,
                  ),
                if (canReport)
                  _ScoreAction(
                    key: const ValueKey('leadScoreMeta'),
                    icon: Icons.near_me_outlined,
                    label: context.l10n.metaScoreAction,
                    tooltip: context.l10n.sendStageToMetaTooltip,
                    loading: busy == _ScoreBusy.meta,
                    onPressed: working ? null : onMeta,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Space.xs),

        // The number at the start, "/ 100" at the end, as on the web.
        Row(
          key: const ValueKey('leadScoreValue'),
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${intel.leadScore}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: tint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '/ 100',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs + 2),
        Semantics(
          label: context.l10n.intelligenceLeadScoreTitle,
          value: '${intel.leadScore} / 100',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              key: const ValueKey('leadScoreBar'),
              // Never quite empty, so a 0 still shows where the bar starts.
              value: (score < 2 ? 2 : score) / 100.0,
              minHeight: 6,
              backgroundColor: colors.muted,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ),

        if (intel.isLeadScoreOverridden) ...[
          const SizedBox(height: Space.xs + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Icon(
                  Icons.edit_outlined,
                  size: 12,
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(width: Space.xs + 2),
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
                    height: 1.4,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ],

        if (intel.leadScoreSignals.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Semantics(
            button: true,
            expanded: signalsExpanded,
            child: InkWell(
              key: const ValueKey('scoreSignalsToggle'),
              onTap: onToggleSignals,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: ConstrainedBox(
                // A comfortable tap target for a one-line toggle.
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: signalsExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        signalsExpanded
                            ? context.l10n.hideSignalsBehindScore(
                                intel.leadScoreSignals.length,
                              )
                            : context.l10n.showSignalsBehindScore(
                                intel.leadScoreSignals.length,
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (signalsExpanded)
            Column(
              key: const ValueKey('scoreSignalsList'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final signal in intel.leadScoreSignals)
                  Container(
                    key: ValueKey('scoreSignal_${signal.signal}'),
                    margin: const EdgeInsets.only(bottom: Space.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: Space.xs + 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.muted.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            signal.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          signal.points > 0
                              ? '+${signal.points}'
                              : '${signal.points}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: signal.points >= 0
                                ? colors.success
                                : colors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// Edit / Auto / Meta: compact, but a full-height tap target.
class _ScoreAction extends StatelessWidget {
  const _ScoreAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // No compact density: it would take 8px off the 36px minimum.
          textStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: loading ? const _ButtonSpinner() : Icon(icon, size: 15),
        label: Text(label),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Attributes grid
// ---------------------------------------------------------------------------

/// Stage | Confidence, Purchase status | Sentiment, Intent | Urgency — two
/// columns, each row as tall as its taller cell so the pairs stay aligned.
class _InsightsGrid extends StatelessWidget {
  const _InsightsGrid({required this.intelligence});

  final ConversationIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final intel = intelligence;
    final l10n = context.l10n;

    Widget plain(String text) => Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    Widget muted(String text) => Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
    );
    Widget badge((String, BadgeTone) value) =>
        StatusBadge(label: value.$1, tone: value.$2, dense: true);

    final cells = <(String, String, Widget)>[
      (
        'stage',
        l10n.stageFieldLabel,
        badge(IntelligenceLabels.stage(context, intel.stage)),
      ),
      (
        'confidence',
        l10n.confidenceFieldLabel,
        plain('${(intel.confidence * 100).round()}%'),
      ),
      (
        'purchase',
        l10n.purchaseStatusLabel,
        intel.purchaseStatus.toUpperCase() == 'NONE'
            ? muted(l10n.noneValue)
            : badge(IntelligenceLabels.purchase(context, intel.purchaseStatus)),
      ),
      (
        'sentiment',
        l10n.sentimentFieldLabel,
        intel.sentiment.isEmpty
            ? muted('—')
            : badge(IntelligenceLabels.sentiment(context, intel.sentiment)),
      ),
      (
        'intent',
        l10n.intentFieldLabel,
        plain(IntelligenceLabels.level(context, intel.intentStrength)),
      ),
      (
        'urgency',
        l10n.urgencyFieldLabel,
        plain(IntelligenceLabels.level(context, intel.urgency)),
      ),
    ];

    return Column(
      key: const ValueKey('insightsGrid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cells.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = i; j < i + 2; j++) ...[
                if (j > i) const SizedBox(width: Space.md),
                Expanded(
                  child: _GridCell(
                    key: ValueKey('insight_${cells[j].$1}'),
                    label: cells[j].$2,
                    value: cells[j].$3,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.label, required this.value, super.key});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            letterSpacing: 0.5,
            color: AppColors.of(context).mutedForeground,
          ),
        ),
        const SizedBox(height: Space.xs),
        value,
      ],
    );
  }
}

/// Localized labels and tones for the analyzer's values — the web's
/// `enums.stage`, `enums.purchase`, `enums.sentiment` and `enums.level`.
/// A value the app does not know yet is shown humanized rather than hidden.
abstract final class IntelligenceLabels {
  static (String, BadgeTone) stage(BuildContext context, String value) {
    final upper = value.toUpperCase();
    final tone = switch (upper) {
      'LEAD' || 'QUALIFIED_LEAD' => BadgeTone.info,
      'HOT_LEAD' => BadgeTone.danger,
      'PURCHASE_INTENT' => BadgeTone.warning,
      'PURCHASED' || 'AGENT_CONFIRMED' => BadgeTone.success,
      _ => BadgeTone.neutral,
    };
    final label = switch (upper) {
      'LEAD' => context.l10n.stageLead,
      'UNCERTAIN' => context.l10n.stageUncertain,
      // The inbox's own stage names, so a stage reads the same everywhere.
      _ => ConversationBadges.stage(context, upper).$1,
    };
    return (label, tone);
  }

  static (String, BadgeTone) purchase(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value.toUpperCase()) {
      'INTENT_DETECTED' => (l10n.purchaseStatusIntentDetected, BadgeTone.info),
      'CUSTOMER_SAYS_ORDERED' => (
        l10n.purchaseStatusSaysOrdered,
        BadgeTone.warning,
      ),
      'CUSTOMER_SAYS_PAID' => (l10n.purchaseStatusSaysPaid, BadgeTone.warning),
      'AGENT_CONFIRMED' => (
        l10n.purchaseStatusAgentConfirmed,
        BadgeTone.success,
      ),
      'CANCELLED' => (l10n.purchaseStatusCancelled, BadgeTone.neutral),
      'REFUND_MENTIONED' => (
        l10n.purchaseStatusRefundMentioned,
        BadgeTone.danger,
      ),
      'NONE' => (l10n.noneValue, BadgeTone.neutral),
      _ => (humanizeEnum(value), BadgeTone.neutral),
    };
  }

  static (String, BadgeTone) sentiment(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value.toLowerCase()) {
      'positive' => (l10n.sentimentPositive, BadgeTone.success),
      'neutral' => (l10n.sentimentNeutral, BadgeTone.neutral),
      'negative' => (l10n.sentimentNegative, BadgeTone.danger),
      'mixed' => (l10n.sentimentMixed, BadgeTone.warning),
      _ => (humanizeEnum(value), BadgeTone.neutral),
    };
  }

  /// Intent strength and urgency: none / low / medium / high.
  static String level(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value.toLowerCase()) {
      'none' || '' => l10n.noneValue,
      'low' => l10n.levelLow,
      'medium' => l10n.levelMedium,
      'high' => l10n.levelHigh,
      _ => humanizeEnum(value),
    };
  }
}

// ---------------------------------------------------------------------------
// Below the grid
// ---------------------------------------------------------------------------

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: primary),
              const SizedBox(width: Space.xs + 2),
              Expanded(
                child: Text(
                  context.l10n.recommendedNextActionTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

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
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.lg),
        _SectionLabel(context.l10n.conversionsAction),
        for (final conversion in conversions)
          Container(
            margin: const EdgeInsets.only(bottom: Space.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: Space.xs + 1,
            ),
            decoration: BoxDecoration(
              color: colors.muted.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    conversion.eventName.isNotEmpty
                        ? conversion.eventName
                        : humanizeEnum(conversion.sourceStage),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.sm),
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
