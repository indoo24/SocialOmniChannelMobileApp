/// Assignment, status and priority actions.
///
/// Every option here is *presented* according to the employee's permissions
/// and *decided* by the backend. The app never validates an assignment itself —
/// it asks, and shows the server's answer, including its refusal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';
import 'conversation_history_sheet.dart';
import 'conversion_sheet.dart';

const _statuses = [
  'OPEN',
  'WAITING_CUSTOMER',
  'WAITING_INTERNAL',
  'RESOLVED',
  'CLOSED',
];
const _priorities = ['URGENT', 'HIGH', 'NORMAL', 'LOW'];

Future<void> showConversationActionsSheet(
  BuildContext context, {
  required int conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ActionsSheet(conversationId: conversationId),
  );
}

class _ActionsSheet extends ConsumerStatefulWidget {
  const _ActionsSheet({required this.conversationId});

  final int conversationId;

  @override
  ConsumerState<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends ConsumerState<_ActionsSheet> {
  bool _busy = false;

  /// Runs a backend action and reports the outcome honestly.
  ///
  /// A 403 here means the UI offered something the backend refuses. That is
  /// shown as-is rather than hidden: the server's message says why, and
  /// swallowing it would leave the agent thinking the tap did nothing.
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(conversationControllerProvider(widget.conversationId));
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
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

    final conversation = async.value?.conversation;
    final isMine =
        conversation != null &&
        employee != null &&
        conversation.isOwnedBy(employee.id);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.actionsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.md),

            if (_busy) const LinearProgressIndicator(minHeight: 2),

            // Open to any active employee — no permission gate, unlike the
            // mutating actions below. The sheets themselves gate their own
            // write actions (reporting a conversion) separately.
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
              const Divider(height: Space.xl),
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
              const SizedBox(height: Space.lg),
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
              const SizedBox(height: Space.lg),
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
                            selected: conversation?.category?.id == category.id,
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
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Text(
                  context.l10n.noPermissionToChange,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
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
