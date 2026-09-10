/// Manual conversation assignment — the mobile form of the web's "Assign"
/// header dropdown.
///
/// Two actions, both hitting one endpoint (`POST /conversations/{id}/assign/`,
/// documented as *"Assign or release a conversation"*):
///
///  * **Release to the queue** — sends an explicit `assignee_id: null`, which
///    is what the endpoint's own schema documents as the unassign signal
///    ("`assignee_id=null` unassigns; omitting it leaves the assignee alone").
///  * **Assign to an employee** — sends that employee's backend id.
///
/// Gated on `conversation.assign_any`, the capability Swagger names for this
/// exact action: *"Moving anyone else's work needs `conversation.assign_any`."*
/// This deliberately mirrors the capability rather than hard-coding an
/// ADMIN/SUPERVISOR role test, matching how every other write action in this
/// app is gated — and the backend re-checks regardless, so a client that got
/// it wrong produces a clean 403 rather than an unauthorised write.
///
/// "Assign to me" is untouched and still lives in the actions sheet: it needs
/// only `conversation.assign_self`, so an agent without `assign_any` keeps
/// exactly the assignment powers they had before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';

/// Opens the assignment picker for [conversationId].
///
/// [conversation] is the caller's current read of the thread, used only to
/// mark the current assignee in the list — the assignment itself is always
/// re-read from the server's response.
Future<void> showAssignConversationSheet(
  BuildContext context, {
  required int conversationId,
  Conversation? conversation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => _AssignSheet(
        conversationId: conversationId,
        currentAssigneeId: conversation?.assignedTo?.id,
        scrollController: scrollController,
      ),
    ),
  );
}

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({
    required this.conversationId,
    required this.currentAssigneeId,
    required this.scrollController,
  });

  final int conversationId;
  final int? currentAssigneeId;
  final ScrollController scrollController;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  /// Which row is mid-request: an employee id, or [_releaseRowId] for
  /// "Release to the queue". Non-null also means "every row is disabled",
  /// which is what stops a second assignment racing the first.
  int? _pendingRowId;

  /// Sentinel row id for the release action — no employee has a negative id.
  static const _releaseRowId = -1;

  bool get _busy => _pendingRowId != null;

  /// Runs one assignment mutation and applies the server's own answer.
  ///
  /// Nothing is written to local state before the request resolves: on
  /// failure the previous assignment simply stays, because it was never
  /// replaced. On success the returned conversation — the backend's
  /// confirmed truth, not a locally-guessed one — is pushed into the
  /// existing conversation controller, and the inbox is refreshed through
  /// the same `refreshQuietly()` path every other action here uses, so the
  /// active filters (Unassigned / Mine / account filters / search) are
  /// re-evaluated server-side rather than patched locally.
  Future<void> _run(
    int rowId,
    Future<Conversation> Function() action,
    String Function() success,
  ) async {
    if (_busy) return;
    setState(() => _pendingRowId = rowId);
    try {
      final updated = await action();
      if (!mounted) return;
      ref
          .read(conversationControllerProvider(widget.conversationId).notifier)
          .updateConversation(updated);
      ref.read(inboxControllerProvider.notifier).refreshQuietly();
      final message = success();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _pendingRowId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _release() {
    final repository = ref.read(conversationRepositoryProvider);
    _run(
      _releaseRowId,
      () => repository.assign(widget.conversationId, releaseAssignee: true),
      () => context.l10n.releasedToQueueMessage,
    );
  }

  void _assignTo(DirectoryEmployee employee) {
    final repository = ref.read(conversationRepositoryProvider);
    _run(
      employee.id,
      () => repository.assign(
        widget.conversationId,
        // The employee's stable backend id — never a name, email or index.
        assigneeId: employee.id,
      ),
      () => context.l10n.assignedToEmployeeMessage(employee.fullName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employees = ref.watch(employeeDirectoryProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          context.l10n.assignSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.md),

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _pendingRowId == _releaseRowId
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : const Icon(Icons.person_remove_alt_1_outlined),
          title: Text(context.l10n.releaseToQueueAction),
          enabled: !_busy,
          onTap: _busy ? null : _release,
        ),
        const Divider(height: Space.lg),

        employees.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xl),
            child: LoadingState(),
          ),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(employeeDirectoryProvider),
          ),
          data: (list) {
            // Only employees who can actually hold work: the backend keeps
            // deactivated rows in the directory for audit, and assigning to
            // one would be rejected server-side anyway.
            final assignable = list.where((e) => e.isActive).toList();
            if (assignable.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Text(
                  context.l10n.assignNoEmployeesFound,
                  style: theme.textTheme.bodySmall,
                ),
              );
            }
            return Column(
              children: [
                for (final employee in assignable)
                  _EmployeeRow(
                    employee: employee,
                    isCurrent: employee.id == widget.currentAssigneeId,
                    isPending: _pendingRowId == employee.id,
                    enabled: !_busy,
                    onTap: () => _assignTo(employee),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    required this.isCurrent,
    required this.isPending,
    required this.enabled,
    required this.onTap,
  });

  final DirectoryEmployee employee;
  final bool isCurrent;
  final bool isPending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: isPending
          ? const SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : InitialsAvatar(
              initials: employee.initials,
              imageUrl: employee.avatarUrl,
              size: 32,
            ),
      // Employee names are backend data — never translated.
      title: Text(
        employee.fullName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent
            ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: isCurrent
          ? Text(
              context.l10n.assignCurrentAssigneeLabel,
              style: theme.textTheme.labelSmall,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PresenceDot(availability: employee.availability),
          if (isCurrent) ...[
            const SizedBox(width: Space.sm),
            Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
          ],
        ],
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
