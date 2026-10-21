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
import '../../core/models/performance.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/customer_conversation_group_sheet.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'assign_conversation_sheet.dart';
import 'conversation_controller.dart';
import 'conversation_review.dart'
    show showConversationReviewSheet, showRequestReviewSheet;
import 'conversation_history_sheet.dart';
import 'conversion_sheet.dart';
import 'customer_intelligence_section.dart';
import 'intelligence_providers.dart';
import 'notes_sheet.dart';
import '../customer_fields/custom_fields_section.dart';
import '../directory/edit_customer_sheet.dart';
import '../directory/save_to_contacts.dart';
import '../orders/customer_data_sheet.dart';
import '../orders/order_and_fact_dialogs.dart';
import '../orders/order_details.dart';
import '../conversations/conversation_pin.dart';

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
  bool _editing = false;

  /// Opens the existing Edit customer sheet for [customerId].
  ///
  /// `showEditCustomerSheet` takes a full [CustomerDetail], which a
  /// conversation does not carry — its `customer` is the lightweight
  /// list-shaped record. So fetch the detail first (the same
  /// `GET /customers/{id}/` the profile screen uses) and hand that over,
  /// rather than reimplementing the form against the thinner model. The PATCH
  /// and every validation rule stay exactly where they already are.
  Future<void> _openEditCustomer(int customerId) async {
    setState(() => _editing = true);
    try {
      final customer = await ref
          .read(directoryRepositoryProvider)
          .customerDetail(customerId);
      if (!mounted) return;
      await showEditCustomerSheet(context, customer: customer);
      if (!mounted) return;
      // The sheet saved through updateCustomer(); refresh what this sheet
      // shows so the new values are visible behind it.
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(conversationControllerProvider(widget.conversationId));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  /// Runs [action], then closes the sheet and confirms with [success] — or,
  /// when [onSuccess] is given, lets it confirm instead.
  Future<void> _run(
    Future<void> Function() action,
    String success, {
    void Function(BuildContext context)? onSuccess,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(conversationControllerProvider(widget.conversationId));
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      Navigator.of(context).pop();
      if (onSuccess != null) {
        onSuccess(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
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
    // Editing contact details is `customer.manage`, the same permission the
    // customer profile screen gates its own edit button on.
    final canEditCustomer = employee?.can(Perm.customerManage) ?? false;

    final conversation = async.value?.conversation;
    final isMine =
        conversation != null &&
        employee != null &&
        conversation.isOwnedBy(employee.id);

    /// Who may hand this thread back to the queue.
    ///
    /// Mirrors the endpoint's own split: releasing what you already hold
    /// needs only `assign_self`, while taking a thread off somebody else
    /// needs `assign_any`. Either way there has to be an assignee to remove.
    final canRelease =
        conversation?.assignedTo != null &&
        (canAssignAny || (canAssignSelf && isMine));

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
        // TOP QUICK ACTIONS: PIN AND REVIEW
        // ------------------------------------------------------------
        // Resolve lives in the conversation's top bar.
        if (conversation != null) ...[
          Row(
            children: [
              Expanded(child: _SheetPinButton(conversation: conversation)),
              // Asking for a review needs `conversation.reply` (the server
              // refuses anyone without it), so it is not offered to them. An
              // existing review can still be opened.
              if (conversation.review != null ||
                  ref.watch(canProvider(Perm.conversationReply))) ...[
                const SizedBox(width: Space.sm),
                Expanded(child: _SheetReviewButton(conversation: conversation)),
              ],
            ],
          ),
          const SizedBox(height: Space.lg),
        ],

        // ------------------------------------------------------------
        // 1. CONTACT SECTION
        // ------------------------------------------------------------
        // Contact = how to reach this customer (email, phone, location,
        // language) plus their custom field values, and the conversation
        // metadata that has always lived here. Recorded facts moved out to
        // the Customer data card below — see `customer_data_sheet.dart`.
        _SectionCard(
          title: context.l10n.contactSectionTitle,
          icon: Icons.person_outline,
          trailing: conversation == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Offered even without a number, so tapping it can say
                    // why there is nothing to save.
                    SaveToContactsButton(
                      name: conversation.customer.displayName,
                      phone: _customerPhone(ref, conversation.customer),
                      compact: true,
                    ),
                    if (canEditCustomer && customerId != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _editing
                            ? null
                            : () => _openEditCustomer(customerId),
                        child: Text(context.l10n.contactEditButton),
                      ),
                  ],
                ),
          child: conversation == null
              ? const LoadingState()
              : _CustomerDetailsView(conversation: conversation),
        ),
        const SizedBox(height: Space.lg),

        // ------------------------------------------------------------
        // 1b. CUSTOMER DATA SECTION
        // ------------------------------------------------------------
        // Details a human recorded about the customer. A preview here, the
        // full scrollable list behind the chevron.
        if (customerId != null) ...[
          _SectionCard(
            title: context.l10n.customerDataTitle,
            icon: Icons.fact_check_outlined,
            trailing: IconButton(
              icon: const Icon(Icons.chevron_right),
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.customerDataTitle,
              onPressed: () => showCustomerDataSheet(
                context,
                customerId: customerId,
                conversationId: widget.conversationId,
                canManage: canManageOrders,
              ),
            ),
            child: _CustomerDataPreview(
              facts: facts,
              loading: factsAsync?.isLoading ?? false,
              onOpen: () => showCustomerDataSheet(
                context,
                customerId: customerId,
                conversationId: widget.conversationId,
                canManage: canManageOrders,
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
        ],

        // ------------------------------------------------------------
        // 2. INTELLIGENCE SECTION
        // ------------------------------------------------------------
        _SectionCard(
          title: context.l10n.customerIntelligenceSectionTitle,
          icon: Icons.auto_awesome,
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
                : CustomerIntelligenceView(
                    conversationId: widget.conversationId,
                    intelligence: data,
                    showHeader: false,
                    onChanged: () {
                      ref.invalidate(
                        conversationIntelligenceProvider(widget.conversationId),
                      );
                      ref.invalidate(
                        conversationControllerProvider(widget.conversationId),
                      );
                    },
                  ),
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

              // Manual assignment to a specific employee, plus release —
              // `conversation.assign_any` is the capability Swagger names for
              // "moving anyone else's work". The picker itself lives in
              // assign_conversation_sheet.dart.
              if (canAssignAny)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.people_alt_outlined),
                  title: Text(context.l10n.assignAction),
                  subtitle: Text(
                    conversation?.assignedTo?.fullName ??
                        context.l10n.unassignedBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_busy,
                  onTap: _busy
                      ? null
                      : () => showAssignConversationSheet(
                          context,
                          conversationId: widget.conversationId,
                          conversation: conversation,
                        ),
                ),

              // Releasing back to the queue. The endpoint splits this across
              // both capabilities, in its own words: "Claiming for yourself,
              // or *releasing what you already hold*, needs
              // `conversation.assign_self`. Moving anyone else's work needs
              // `conversation.assign_any`."
              //
              // So an agent may hand back their own thread with nothing more
              // than assign_self — they just cannot take someone else's off
              // them. `canRelease` mirrors exactly that split rather than
              // requiring assign_any for every release.
              if (canRelease)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_remove_alt_1_outlined),
                  title: Text(context.l10n.releaseToQueueAction),
                  enabled: !_busy,
                  onTap: _busy
                      ? null
                      : () => _run(
                          // `releaseAssignee` sends an explicit
                          // `assignee_id: null`. Passing no assignee at all
                          // omits the key, which the backend reads as "leave
                          // the assignee alone" — so this action used to be a
                          // silent no-op.
                          () => repository.assign(
                            widget.conversationId,
                            releaseAssignee: true,
                          ),
                          context.l10n.releasedToQueueMessage,
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

/// The customer's number as the backend has it. The conversation's `customer`
/// carries no identities, so when it has no stored phone, fall back to the
/// WhatsApp number on the customer detail. Empty when neither exists.
String _customerPhone(WidgetRef ref, CustomerBrief customer) {
  if (customer.phone.isNotEmpty) return customer.phone;
  if (customer.id <= 0) return '';
  return ref.watch(customerDetailProvider(customer.id)).value?.displayPhone ??
      '';
}

// ---------------------------------------------------------------------------
// 1. CUSTOMER DETAILS VIEW
// ---------------------------------------------------------------------------
class _CustomerDetailsView extends ConsumerWidget {
  const _CustomerDetailsView({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final customer = conversation.customer;
    final phone = _customerPhone(ref, customer);

    final inboxState = ref.watch(inboxControllerProvider).value;
    final groups = inboxState?.groups ?? const [];
    final matchingGroup = groups
        .where(
          (g) =>
              customer.id > 0 &&
              g.customer.id == customer.id &&
              g.isMultiConversation,
        )
        .firstOrNull;

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
        if (conversation.claimedBy != null)
          _KeyValueRow(
            label: context.l10n.claimedByFieldLabel,
            value: conversation.claimedBy!.fullName,
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
        if (conversation.firstResponseAt != null)
          _KeyValueRow(
            label: context.l10n.firstResponseFieldLabel,
            value: formatDateTime(context, conversation.firstResponseAt),
          ),
        if (conversation.lastAgentMessageAt != null)
          _KeyValueRow(
            label: context.l10n.lastAgentMessageFieldLabel,
            value: formatDateTime(context, conversation.lastAgentMessageAt),
          ),
        if (conversation.resolvedAt != null)
          _KeyValueRow(
            label: context.l10n.resolvedFieldLabel,
            value: formatDateTime(context, conversation.resolvedAt),
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
        if (phone.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.phoneFieldLabel,
            value: phone,
            ltr: true,
          ),
        if (customer.email.isNotEmpty)
          _KeyValueRow(
            label: context.l10n.emailFieldLabel,
            value: customer.email,
            ltr: true,
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

        if (customer.id > 0) ...[
          const SizedBox(height: Space.sm),
          CustomFieldsSection(customerId: customer.id),
        ],

        if (matchingGroup != null) ...[
          const SizedBox(height: Space.md),
          const Divider(height: 1),
          const SizedBox(height: Space.sm),
          Material(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(Radii.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () {
                Navigator.of(context).pop();
                CustomerConversationGroupSheet.show(
                  context,
                  group: matchingGroup,
                  currentConversationId: conversation.id,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.whatsappConversationsGroupTitle,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            context.l10n.groupedConversationsCount(
                              matchingGroup.conversations.length,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The first few recorded customer details, inline in the conversation sheet.
///
/// A preview, not the list: the full set is in the Customer data sheet behind
/// the chevron, which scrolls. Capped so a customer with thirty recorded facts
/// cannot push Intelligence, Orders and Actions off the screen.
class _CustomerDataPreview extends StatelessWidget {
  const _CustomerDataPreview({
    required this.facts,
    required this.loading,
    required this.onOpen,
  });

  final List<CustomerFact> facts;
  final bool loading;
  final VoidCallback onOpen;

  static const _previewLimit = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorded = recordedCustomerFacts(facts);

    if (recorded.isEmpty) {
      if (loading) return const LoadingState();
      return Text(
        context.l10n.customerDataEmpty,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final shown = recorded.take(_previewLimit).toList();
    final hidden = recorded.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final fact in shown) CustomerDataRow(fact: fact),
        if (hidden > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 2),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onOpen,
              child: Text(context.l10n.customerDataMoreCount(hidden)),
            ),
          ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final String label;
  final String value;

  /// For phone numbers and e-mail addresses: always left-to-right, so in
  /// Arabic a leading `+` stays in front of the number.
  final bool ltr;

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
              textDirection: ltr && value.isNotEmpty ? TextDirection.ltr : null,
              textAlign: ltr ? ambientStartAlign(context) : null,
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

          OrderDetailsLines(
            order: order,
            showFulfilment: !(widget.canManage && order.canMoveFulfilment),
          ),
          if (widget.canManage && order.canMoveFulfilment)
            OrderFulfilmentPicker(
              order: order,
              busy: _busy,
              onChanged: (value) => _run(
                () => ref
                    .read(directoryRepositoryProvider)
                    .updateOrderFulfilment(order.id, value),
                context.l10n.orderFulfilmentUpdatedMessage,
              ),
            ),

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

/// Pin / unpin for the signed-in employee. The title follows the state the
/// server confirmed (this sheet shows the conversation's controller), and
/// the button waits while a request is on its way.
class _SheetPinButton extends ConsumerWidget {
  const _SheetPinButton({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(pinningProvider).contains(conversation.id);
    final (label, icon) = pinActionLabel(context.l10n, conversation.isPinned);
    return _SheetQuickAction(
      key: const Key('conversation_actions_sheet_pin_button'),
      icon: icon,
      label: label,
      selected: conversation.isPinned,
      busy: busy,
      onPressed: () => toggleConversationPin(
        context,
        conversationId: conversation.id,
        currentlyPinned: conversation.isPinned,
      ),
    );
  }
}

/// Request a review when there is none; open the pending one otherwise,
/// highlighted as a pinned pin is.
class _SheetReviewButton extends StatelessWidget {
  const _SheetReviewButton({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final review = conversation.review;
    return _SheetQuickAction(
      key: const Key('conversation_actions_sheet_review_button'),
      icon: review == null ? Icons.rate_review_outlined : Icons.rate_review,
      label: review == null
          ? l10n.requestReviewAction
          : l10n.reviewSectionTitle,
      selected: review != null,
      onPressed: () => review == null
          ? showRequestReviewSheet(context, conversationId: conversation.id)
          : showConversationReviewSheet(
              context,
              conversationId: conversation.id,
            ),
    );
  }
}

/// An icon with its title, outlined; tinted in the primary colour while
/// [selected]. A spinner stands in for the icon while [busy].
class _SheetQuickAction extends StatelessWidget {
  const _SheetQuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        foregroundColor: selected
            ? colors.primary
            : Theme.of(context).colorScheme.onSurface,
        backgroundColor: selected
            ? colors.primary.withValues(alpha: 0.08)
            : null,
        side: BorderSide(
          color: selected
              ? colors.primary.withValues(alpha: 0.5)
              : colors.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
