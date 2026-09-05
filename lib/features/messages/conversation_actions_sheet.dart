/// Comprehensive Conversation Actions & Data Bottom Sheet.
///
/// Combines Customer Details data, Intelligence data, Orders data, and
/// Conversation actions into a single scrollable bottom sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/employee.dart';
import '../../core/models/intelligence.dart';
import '../../core/models/performance.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';
import 'conversation_history_sheet.dart';
import 'conversion_sheet.dart';
import 'intelligence_providers.dart';
import 'notes_sheet.dart';
import '../orders/order_and_fact_dialogs.dart';

const _statuses = [
  'OPEN',
  'WAITING_CUSTOMER',
  'WAITING_INTERNAL',
  'RESOLVED',
  'CLOSED',
];
const _priorities = ['URGENT', 'HIGH', 'NORMAL', 'LOW'];

/// Opens the comprehensive data and actions bottom sheet for a conversation.
Future<void> showConversationActionsSheet(
  BuildContext context, {
  required int conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _ActionsSheet(
        conversationId: conversationId,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ActionsSheet extends ConsumerStatefulWidget {
  const _ActionsSheet({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends ConsumerState<_ActionsSheet> {
  bool _busy = false;
  bool _analyzing = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(conversationControllerProvider(widget.conversationId));
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _runAnalyzer() async {
    setState(() => _analyzing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .refreshIntelligence(widget.conversationId);
      if (mounted) {
        ref.invalidate(conversationIntelligenceProvider(widget.conversationId));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(
      conversationControllerProvider(widget.conversationId),
    );
    final employee = ref.watch(currentEmployeeProvider);
    final repository = ref.read(conversationRepositoryProvider);

    final canAssignSelf = employee?.can(Perm.conversationAssignSelf) ?? false;
    final canAssignAny = employee?.can(Perm.conversationAssignAny) ?? false;
    final canChangeStatus =
        employee?.can(Perm.conversationChangeStatus) ?? false;
    final canChangePriority =
        employee?.can(Perm.conversationChangePriority) ?? false;
    final canChangeCategory =
        employee?.can(Perm.conversationChangeCategory) ?? false;
    final canRefreshIntel =
        employee?.can(Perm.conversationRefreshIntelligence) ?? false;
    final canManageOrders = employee?.can(Perm.orderManage) ?? false;

    final conversation = async.value?.conversation;
    final isMine =
        conversation != null &&
        employee != null &&
        conversation.isOwnedBy(employee.id);

    final customerId = conversation?.customer.id;
    final intelAsync = ref.watch(
      conversationIntelligenceProvider(widget.conversationId),
    );
    final ordersAsync = ref.watch(
      conversationOrdersProvider(widget.conversationId),
    );
    final factsAsync = customerId != null
        ? ref.watch(customerFactsProvider(customerId))
        : null;

    final facts = factsAsync?.value ?? const [];
    final orders = ordersAsync.value ?? const [];
    final ordersPending =
        facts.where((f) => f.needsReview).length +
        orders.where((o) => o.isSuggestion).length;
    final intel = intelAsync.value;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        if (_busy || _analyzing)
          const Padding(
            padding: EdgeInsets.only(bottom: Space.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),

        // ------------------------------------------------------------
        // 1. CUSTOMER DETAILS SECTION
        // ------------------------------------------------------------
        _SectionCard(
          title: context.l10n.customerDetailsTitle,
          icon: Icons.person_outline,
          trailing: (canManageOrders && customerId != null)
              ? TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.commonAdd),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xs,
                      vertical: 2,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => showRecordCustomerDetailDialog(
                    context,
                    ref: ref,
                    customerId: customerId,
                    conversationId: widget.conversationId,
                  ),
                )
              : null,
          child: conversation == null
              ? const LoadingState()
              : _CustomerDetailsView(conversation: conversation, facts: facts),
        ),
        const SizedBox(height: Space.lg),

        // ------------------------------------------------------------
        // 2. INTELLIGENCE SECTION
        // ------------------------------------------------------------
        _SectionCard(
          title: context.l10n.intelligenceSectionTitle,
          icon: Icons.insights_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (intel?.needsHumanReview == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ScenarioColors.warning,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    context.l10n.reviewFieldLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
              if (canRefreshIntel)
                IconButton(
                  tooltip: context.l10n.rerunAnalysisTooltip,
                  icon: _analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: _analyzing ? null : _runAnalyzer,
                ),
            ],
          ),
          child: intelAsync.when(
            loading: () =>
                LoadingState(label: context.l10n.loadingIntelligenceLabel),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(
                conversationIntelligenceProvider(widget.conversationId),
              ),
            ),
            data: (data) => data == null
                ? _NotAnalyzedYet(
                    canRefresh: canRefreshIntel,
                    busy: _analyzing,
                    onRun: _runAnalyzer,
                  )
                : _IntelligenceView(intelligence: data),
          ),
        ),
        const SizedBox(height: Space.lg),

        // ------------------------------------------------------------
        // 3. ORDERS & RECORDED DATA SECTION
        // ------------------------------------------------------------
        _SectionCard(
          title: context.l10n.ordersTitle,
          icon: Icons.inventory_2_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ordersPending > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ScenarioColors.warning,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '$ordersPending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
              if (canManageOrders && customerId != null)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.orderButton),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xs,
                      vertical: 2,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => showRecordOrderDialog(
                    context,
                    ref: ref,
                    customerId: customerId,
                    conversationId: widget.conversationId,
                  ),
                ),
            ],
          ),
          child: ordersAsync.when(
            loading: () => const LoadingState(),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(
                conversationOrdersProvider(widget.conversationId),
              ),
            ),
            data: (orderList) => _OrdersDataView(
              orders: orderList,
              facts: facts,
              conversationId: widget.conversationId,
              customerId: customerId,
              canManage: canManageOrders,
            ),
          ),
        ),
        const SizedBox(height: Space.lg),

        // ------------------------------------------------------------
        // 4. ACTIONS SECTION
        // ------------------------------------------------------------
        _SectionCard(
          title: context.l10n.actionsTitle,
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(context.l10n.conversationHistoryAction),
                onTap: () => showConversationHistorySheet(
                  context,
                  conversationId: widget.conversationId,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(context.l10n.internalNotesAction),
                onTap: () => showInternalNotesSheet(
                  context,
                  conversationId: widget.conversationId,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.campaign_outlined),
                title: Text(context.l10n.conversionsAction),
                onTap: () => showConversionsSheet(
                  context,
                  conversationId: widget.conversationId,
                ),
              ),

              if (canAssignSelf && !isMine)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(context.l10n.assignToMe),
                  enabled: !_busy,
                  onTap: _busy
                      ? null
                      : () => _run(
                          () => repository.assign(
                            widget.conversationId,
                            assigneeId: employee!.id,
                          ),
                          context.l10n.assignedToYouMessage,
                        ),
                ),

              if (canAssignAny && conversation?.assignedTo != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_remove_alt_1_outlined),
                  title: Text(context.l10n.unassignAction),
                  enabled: !_busy,
                  onTap: _busy
                      ? null
                      : () => _run(
                          () => repository.assign(widget.conversationId),
                          context.l10n.unassignedMessage,
                        ),
                ),

              if (canChangeStatus) ...[
                const Divider(height: Space.lg),
                _Label(context.l10n.statusSection),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final status in _statuses)
                      ChoiceChip(
                        label: Text(
                          ConversationBadges.status(context, status).$1,
                        ),
                        selected: conversation?.status == status,
                        onSelected: _busy
                            ? null
                            : (_) => _run(
                                () => repository.changeStatus(
                                  widget.conversationId,
                                  status,
                                ),
                                context.l10n.statusUpdatedMessage,
                              ),
                      ),
                  ],
                ),
              ],

              if (canChangePriority) ...[
                const SizedBox(height: Space.md),
                _Label(context.l10n.prioritySection),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final priority in _priorities)
                      ChoiceChip(
                        label: Text(
                          ConversationBadges.priority(context, priority).$1,
                        ),
                        selected: conversation?.priority == priority,
                        onSelected: _busy
                            ? null
                            : (_) => _run(
                                () => repository.changePriority(
                                  widget.conversationId,
                                  priority,
                                ),
                                context.l10n.priorityUpdatedMessage,
                              ),
                      ),
                  ],
                ),
              ],

              if (canChangeCategory) ...[
                const SizedBox(height: Space.md),
                _Label(context.l10n.categorySection),
                Consumer(
                  builder: (context, ref, _) {
                    final categories = ref.watch(categoriesProvider);
                    return categories.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: Space.sm),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (options) => Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          ChoiceChip(
                            label: Text(context.l10n.categoryNoneOption),
                            selected: conversation?.category == null,
                            onSelected: _busy
                                ? null
                                : (_) => _run(
                                    () => repository.changeCategory(
                                      widget.conversationId,
                                      null,
                                    ),
                                    context.l10n.categoryUpdatedMessage,
                                  ),
                          ),
                          for (final category in options)
                            ChoiceChip(
                              label: Text(category.label),
                              selected:
                                  conversation?.category?.id == category.id,
                              onSelected: _busy
                                  ? null
                                  : (_) => _run(
                                      () => repository.changeCategory(
                                        widget.conversationId,
                                        category.id,
                                      ),
                                      context.l10n.categoryUpdatedMessage,
                                    ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              if (!canAssignSelf &&
                  !canAssignAny &&
                  !canChangeStatus &&
                  !canChangePriority &&
                  !canChangeCategory)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: Text(
                    context.l10n.noPermissionToChange,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SECTION CARD WRAPPER
// ---------------------------------------------------------------------------
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : theme.colorScheme.surface;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Icon(
                            widget.icon,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  widget.trailing!,
                  const SizedBox(width: Space.xs),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. CUSTOMER DETAILS VIEW
// ---------------------------------------------------------------------------
class _CustomerDetailsView extends StatelessWidget {
  const _CustomerDetailsView({
    required this.conversation,
    this.facts = const [],
  });

  final Conversation conversation;
  final List<CustomerFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = conversation.customer;
    final recordedFacts = facts.where((f) => !f.needsReview).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(
              initials: customer.initials,
              imageUrl: customer.avatarUrl,
              size: 44,
              provider: conversation.provider,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _ChannelPill(provider: conversation.provider),
                      if (conversation.channelName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            conversation.channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),

        // Key-Value rows table
        _KeyValueRow(
          label: context.l10n.statusSection,
          value: ConversationBadges.status(context, conversation.status).$1,
        ),
        _KeyValueRow(
          label: context.l10n.prioritySection,
          value: ConversationBadges.priority(context, conversation.priority).$1,
        ),
        _KeyValueRow(
          label: context.l10n.categoryFieldLabel,
          value: conversation.category?.label ?? '—',
        ),
        _KeyValueRow(
          label: context.l10n.assignedToFieldLabel,
          value:
              conversation.assignedTo?.fullName ?? context.l10n.unassignedBadge,
        ),
        if (conversation.assignedTeam != null)
          _KeyValueRow(
            label: context.l10n.teamFieldLabel,
            value: conversation.assignedTeam!.name,
          ),
        _KeyValueRow(
          label: context.l10n.messagesFieldLabel,
          value: '${conversation.messageCount}',
        ),
        if (conversation.startedAt != null)
          _KeyValueRow(
            label: context.l10n.startedFieldLabel,
            value: formatDateTime(context, conversation.startedAt),
          ),
        if (conversation.lastMessageAt != null)
          _KeyValueRow(
            label: context.l10n.lastMessageFieldLabel,
            value: formatDateTime(context, conversation.lastMessageAt),
          ),
        if (customer.lifecycleStage.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.lifecycleFieldLabel,
            value: humanizeEnum(customer.lifecycleStage),
          ),
        if (customer.preferredLanguage.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.languageLabel,
            value: customer.preferredLanguage,
          ),
        if (customer.phone.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.phoneFieldLabel,
            value: customer.phone,
          ),
        if (customer.email.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.emailFieldLabel,
            value: customer.email,
          ),
        if (customer.city.isNotEmpty || customer.country.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.localeName.startsWith('ar')
                ? 'الموقع'
                : 'Location',
            value: [
              if (customer.city.isNotEmpty) customer.city,
              if (customer.country.isNotEmpty) customer.country,
            ].join(', '),
          ),

        if (recordedFacts.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          const Divider(height: 1),
          const SizedBox(height: Space.sm),
          for (final fact in recordedFacts)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: '${humanizeEnum(fact.key)}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: fact.value),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    StatusBadge(
                      label: fact.source == 'EMPLOYEE'
                          ? context.l10n.employeeSourceBadge
                          : fact.source,
                      tone: fact.source == 'EMPLOYEE'
                          ? BadgeTone.success
                          : BadgeTone.neutral,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. INTELLIGENCE VIEW
// ---------------------------------------------------------------------------
class _IntelligenceView extends StatelessWidget {
  const _IntelligenceView({required this.intelligence});

  final ConversationIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intel = intelligence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intel.needsHumanReview)
          Container(
            margin: const EdgeInsets.only(bottom: Space.sm),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: ScenarioColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: ScenarioColors.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: ScenarioColors.warning,
                  size: 18,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    intel.reviewReason.isNotEmpty
                        ? intel.reviewReason
                        : context.l10n.reviewBannerDefaultReason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ScenarioColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Badges Wrap
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            StatusBadge(
              label: humanizeEnum(intel.stage),
              tone: BadgeTone.info,
              dense: true,
            ),
            StatusBadge(
              label: humanizeEnum(intel.purchaseStatus),
              tone: intel.purchaseStatus.toUpperCase() == 'CONFIRMED'
                  ? BadgeTone.success
                  : BadgeTone.neutral,
              dense: true,
            ),
            if (intel.sentiment.isNotEmpty)
              StatusBadge(
                label: humanizeEnum(intel.sentiment),
                tone: intel.sentiment.toLowerCase() == 'positive'
                    ? BadgeTone.success
                    : (intel.sentiment.toLowerCase() == 'negative'
                          ? BadgeTone.danger
                          : BadgeTone.neutral),
                dense: true,
              ),
            if (intel.urgency.isNotEmpty && intel.urgency != 'none')
              StatusBadge(
                label: '${intel.urgency} urgency',
                tone: intel.urgency.toLowerCase() == 'high'
                    ? BadgeTone.danger
                    : BadgeTone.warning,
                dense: true,
              ),
          ],
        ),
        const SizedBox(height: Space.md),

        // Lead score card
        Container(
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: intel.leadScore >= 70
                      ? ScenarioColors.success
                      : (intel.leadScore >= 40
                            ? ScenarioColors.warning
                            : theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  '${intel.leadScore}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.leadScoreFieldLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      intel.isLeadScoreOverridden
                          ? context.l10n.setByEmployeeLabel(
                              intel.leadScoreOverriddenByName.isNotEmpty
                                  ? intel.leadScoreOverriddenByName
                                  : context.l10n.anEmployeeLabel,
                            )
                          : context.l10n.aiGeneratedLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // AI Summary
        if (intel.summary.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(
            context.l10n.intelligenceSummaryLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(intel.summary, style: theme.textTheme.bodySmall),
        ],

        // Next best action
        if (intel.nextBestAction.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.suggestedNextStepLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        intel.nextBestAction,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Signals / Objections
        if (intel.interestedProducts.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(
            context.l10n.interestedInLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in intel.interestedProducts)
                StatusBadge(label: p, dense: true),
            ],
          ),
        ],
        if (intel.buyingSignals.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(
            context.l10n.buyingSignalsLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final s in intel.buyingSignals)
                StatusBadge(label: s, tone: BadgeTone.success, dense: true),
            ],
          ),
        ],
        if (intel.objections.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(
            context.l10n.objectionsLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final o in intel.objections)
                StatusBadge(label: o, tone: BadgeTone.danger, dense: true),
            ],
          ),
        ],
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
    return Column(
      children: [
        Text(
          context.l10n.notAnalyzedYetMessage,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (canRefresh) ...[
          const SizedBox(height: Space.sm),
          FilledButton.icon(
            onPressed: busy ? null : onRun,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(context.l10n.runAnalysisButton),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. ORDERS DATA VIEW
// ---------------------------------------------------------------------------
class _OrdersDataView extends StatelessWidget {
  const _OrdersDataView({
    required this.orders,
    required this.facts,
    required this.conversationId,
    required this.customerId,
    required this.canManage,
  });

  final List<Order> orders;
  final List<CustomerFact> facts;
  final int conversationId;
  final int? customerId;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestedFacts = facts.where((f) => f.needsReview).toList();
    final realOrders = orders.where((o) => !o.isSuggestion).toList();
    final suggestedOrders = orders.where((o) => o.isSuggestion).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Suggestions from chat
        if (suggestedFacts.isNotEmpty || suggestedOrders.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: Space.md),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: ScenarioColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
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
                      Icons.auto_awesome,
                      size: 16,
                      color: ScenarioColors.warning,
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      context.l10n.suggestedFromChatTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ScenarioColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                for (final fact in suggestedFacts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${fact.key}: ${fact.value}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final order in suggestedOrders)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Order #${order.id} · ${order.totalAmount} ${order.currency}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Orders List
        if (realOrders.isEmpty)
          Text(
            context.l10n.noOrdersRecordedMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final order in realOrders)
            _LiveOrderCard(
              order: order,
              conversationId: conversationId,
              canManage: canManage,
            ),
      ],
    );
  }
}

/// One order card in the live Orders section — the actual per-order state
/// (confirm/cancel busy flag) that `_OrdersDataView` itself, a
/// `StatelessWidget`, has no room to hold.
///
/// A pending order (`isClaim` — `SUGGESTED` or `RECORDED`, i.e. not yet
/// attested) shows who recorded it and the same "not counted as a sale"
/// wording, Confirm and cancel actions the web card shows; a resolved order
/// (`CONFIRMED`/`CANCELLED`/`REFUNDED`) shows only its resulting state,
/// matching `Order.isClaim` — the backend's own answer to "is this still
/// pending," never reconstructed from `status` locally.
class _LiveOrderCard extends ConsumerStatefulWidget {
  const _LiveOrderCard({
    required this.order,
    required this.conversationId,
    required this.canManage,
  });

  final Order order;
  final int conversationId;
  final bool canManage;

  @override
  ConsumerState<_LiveOrderCard> createState() => _LiveOrderCardState();
}

class _LiveOrderCardState extends ConsumerState<_LiveOrderCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(conversationOrdersProvider(widget.conversationId));
      ref.invalidate(performanceProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirms, then cancels — same `showDialog<bool>` confirm-then-act shape
  /// as `conversation_screen.dart`'s `_confirmDeleteMessage`. Cancelling is
  /// destructive (no undo from this screen), so it gets the same treatment
  /// as deactivating an employee/team rather than firing straight from the
  /// icon tap.
  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.cancelOrderConfirmTitle),
        content: Text(dialogContext.l10n.cancelOrderConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.keepOrderAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.cancelOrderTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    await _run(
      () => ref.read(directoryRepositoryProvider).cancelOrder(widget.order.id),
      context.l10n.orderCancelledMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.xs),
              Text(
                'Order #${order.id}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // A pending order names who recorded it — the badge alone
              // ("Recorded") doesn't carry attribution the way the web
              // card's header does.
              if (order.isClaim && order.recordedByName.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    context.l10n.recordedByMessage(order.recordedByName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
              StatusBadge(
                label: order.statusDisplay.isNotEmpty
                    ? order.statusDisplay
                    : order.status,
                tone: switch (order.status.toUpperCase()) {
                  'CONFIRMED' => BadgeTone.success,
                  'SUGGESTED' => BadgeTone.warning,
                  'CANCELLED' || 'REFUNDED' => BadgeTone.neutral,
                  _ => BadgeTone.info,
                },
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${order.totalAmount} ${order.currency}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}× ${item.productName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      item.lineTotal,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: Space.xs),
          Text(
            order.isClaim
                ? context.l10n.notCountedAsSaleMessage
                : order.isConfirmed
                ? context.l10n.confirmedByMessage(
                    order.confirmedByName.isEmpty
                        ? context.l10n.confirmedByUnknownEmployee
                        : order.confirmedByName,
                  )
                : '',
            style: theme.textTheme.labelSmall,
          ),

          if (widget.canManage && order.isClaim) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(directoryRepositoryProvider)
                                .confirmOrder(order.id),
                            context.l10n.orderConfirmedMessage,
                          ),
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(context.l10n.confirmAction),
                  ),
                ),
                const SizedBox(width: Space.sm),
                IconButton(
                  tooltip: context.l10n.cancelOrderTooltip,
                  onPressed: _busy ? null : _confirmCancel,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
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
// CHANNEL PILL & LABELS
// ---------------------------------------------------------------------------
class _ChannelPill extends StatelessWidget {
  const _ChannelPill({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _providerStyle(provider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3.5),
          Text(
            ConversationBadges.providerLabel(context, provider),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color) _providerStyle(String provider) {
    return switch (provider.toUpperCase()) {
      'WHATSAPP' => (Icons.chat, const Color(0xFF25D366)),
      'TELEGRAM' => (Icons.send, const Color(0xFF229ED9)),
      'FACEBOOK' || 'MESSENGER' => (Icons.facebook, const Color(0xFF1877F2)),
      'INSTAGRAM' => (Icons.camera_alt, const Color(0xFFE4405F)),
      _ => (Icons.forum_outlined, ScenarioColors.mutedForeground),
    };
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
