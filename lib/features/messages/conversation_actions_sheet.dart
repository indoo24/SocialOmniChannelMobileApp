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
import '../../core/utils/formatting.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import 'conversation_controller.dart';

const _statuses = ['OPEN', 'WAITING_CUSTOMER', 'WAITING_INTERNAL', 'RESOLVED', 'CLOSED'];
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
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
    final async =
        ref.watch(conversationControllerProvider(widget.conversationId));
    final employee = ref.watch(currentEmployeeProvider);
    final repository = ref.read(conversationRepositoryProvider);

    final canAssignSelf = employee?.can(Perm.conversationAssignSelf) ?? false;
    final canAssignAny = employee?.can(Perm.conversationAssignAny) ?? false;
    final canChangeStatus = employee?.can(Perm.conversationChangeStatus) ?? false;
    final canChangePriority =
        employee?.can(Perm.conversationChangePriority) ?? false;

    final conversation = async.value?.conversation;
    final isMine =
        conversation != null && employee != null && conversation.isOwnedBy(employee.id);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),

            if (_busy) const LinearProgressIndicator(minHeight: 2),

            if (canAssignSelf && !isMine)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Assign to me'),
                enabled: !_busy,
                onTap: _busy
                    ? null
                    : () => _run(
                          () => repository.assign(
                            widget.conversationId,
                            assigneeId: employee!.id,
                          ),
                          'Assigned to you',
                        ),
              ),

            if (canAssignAny && conversation?.assignedTo != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_remove_alt_1_outlined),
                title: const Text('Unassign'),
                enabled: !_busy,
                onTap: _busy
                    ? null
                    : () => _run(
                          () => repository.assign(widget.conversationId),
                          'Unassigned',
                        ),
              ),

            if (canChangeStatus) ...[
              const Divider(height: Space.xl),
              _Label('Status'),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final status in _statuses)
                    ChoiceChip(
                      label: Text(humanizeEnum(status)),
                      selected: conversation?.status == status,
                      onSelected: _busy
                          ? null
                          : (_) => _run(
                                () => repository.changeStatus(
                                  widget.conversationId,
                                  status,
                                ),
                                'Status updated',
                              ),
                    ),
                ],
              ),
            ],

            if (canChangePriority) ...[
              const SizedBox(height: Space.lg),
              _Label('Priority'),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final priority in _priorities)
                    ChoiceChip(
                      label: Text(humanizeEnum(priority)),
                      selected: conversation?.priority == priority,
                      onSelected: _busy
                          ? null
                          : (_) => _run(
                                () => repository.changePriority(
                                  widget.conversationId,
                                  priority,
                                ),
                                'Priority updated',
                              ),
                    ),
                ],
              ),
            ],

            if (!canAssignSelf &&
                !canAssignAny &&
                !canChangeStatus &&
                !canChangePriority)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Text(
                  'You do not have permission to change this conversation.',
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
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
        ),
      );
}
