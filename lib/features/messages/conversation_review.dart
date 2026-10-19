/// Conversation review: asking a colleague to look over a conversation.
///
/// `POST /conversations/{id}/review/` asks (or, with a review pending,
/// retargets the request to someone else), `DELETE` on the same path
/// withdraws it, and `POST …/review/complete/` completes it. Each answers
/// with the conversation, and only its `review` is taken from that answer.
///
/// A review is not a transfer. Nothing here touches the assignee, the claim,
/// the team, routing or unread state, and the composer stays as it is: the
/// agent can keep replying while a review is pending, and sending a reply
/// neither completes nor withdraws it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_review.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/states.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/conversation_repository.dart';
import 'conversation_controller.dart';

/// The conversations with a review request on its way.
class ConversationReviewController extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// Asks [reviewerId] to review [conversationId], or retargets the pending
  /// request to them.
  Future<Conversation?> request(
    int conversationId, {
    required int reviewerId,
    String note = '',
  }) => _send(
    conversationId,
    (repository) => repository.requestReview(
      conversationId,
      reviewerId: reviewerId,
      note: note,
    ),
  );

  /// Withdraws the pending review on [conversationId].
  Future<Conversation?> withdraw(int conversationId) => _send(
    conversationId,
    (repository) => repository.withdrawReview(conversationId),
  );

  /// Completes the pending review on [conversationId].
  Future<Conversation?> complete(int conversationId) => _send(
    conversationId,
    (repository) => repository.completeReview(conversationId),
  );

  /// Sends [call] and, once the server has answered, shows the review it
  /// reports in the open conversation.
  ///
  /// Resolves to the server's conversation, or to null without sending
  /// anything when a review request for this conversation is already on its
  /// way. Throws the request's [ApiException] when it fails; nothing on
  /// screen has changed then.
  Future<Conversation?> _send(
    int conversationId,
    Future<Conversation> Function(ConversationRepository repository) call,
  ) async {
    if (state.contains(conversationId)) return null;
    state = {...state, conversationId};
    try {
      final updated = await call(ref.read(conversationRepositoryProvider));
      _show(conversationId, updated.review);
      return updated;
    } on ApiException catch (error) {
      // Nothing pending any more — someone else withdrew or completed it.
      // Show what the server holds now instead of the stale review.
      if (error.statusCode == 409) unawaited(_reload(conversationId));
      rethrow;
    } finally {
      if (ref.mounted) state = {...state}..remove(conversationId);
    }
  }

  void _show(int conversationId, ConversationReview? review) {
    final detail = conversationControllerProvider(conversationId);
    if (ref.exists(detail)) ref.read(detail.notifier).applyReview(review);
  }

  Future<void> _reload(int conversationId) async {
    try {
      final fresh = await ref
          .read(conversationRepositoryProvider)
          .detail(conversationId);
      if (ref.mounted) _show(conversationId, fresh.review);
    } on ApiException {
      // The 409 has already been explained; the next open reloads it.
    }
  }
}

final conversationReviewProvider =
    NotifierProvider<ConversationReviewController, Set<int>>(
      ConversationReviewController.new,
    );

/// Active colleagues matching [search], from `GET /employees/`. Every role
/// can read it. It cannot say who holds `conversation.review`, so the
/// server's answer to the request is what decides who may review.
final reviewerCandidatesProvider = FutureProvider.autoDispose
    .family<List<DirectoryEmployee>, String>((ref, search) async {
      final page = await ref
          .watch(directoryRepositoryProvider)
          .employees(search: search, isActive: true);
      return page.results;
    });

/// What to tell the agent after a failed review action. [requesting] is
/// true for a request or retarget, where a `400` means the chosen person
/// cannot review this conversation.
String reviewErrorMessage(
  AppLocalizations l10n,
  ApiException error, {
  required bool requesting,
}) {
  if (error is NetworkException || error.statusCode >= 500) {
    return l10n.reviewRequestFailedMessage;
  }
  return switch (error.statusCode) {
    400 when requesting => l10n.reviewReviewerNotEligibleMessage,
    403 => l10n.reviewPermissionDeniedMessage,
    404 => l10n.conversationUnavailableMessage,
    409 => l10n.reviewNotPendingMessage,
    _ => l10n.reviewRequestFailedMessage,
  };
}

/// The review status as shown. Only `PENDING` has a translated name; any
/// other value is shown as the server sent it, not guessed at.
String reviewStatusText(AppLocalizations l10n, String status) =>
    switch (status.toUpperCase()) {
      'PENDING' => l10n.reviewStatusPending,
      _ => status,
    };

/// Whether [me], the signed-in employee, may complete [review]: its named
/// reviewer, or an ADMIN overriding. Anyone else is not offered the action;
/// the server checks again either way.
bool canCompleteReview(Employee? me, ConversationReview review) {
  if (me == null) return false;
  return review.isReviewer(me.id) || me.isAdmin;
}

/// The review line above the thread, shown while the conversation has a
/// review. Tapping it opens the review and its actions.
class ConversationReviewBanner extends StatelessWidget {
  const ConversationReviewBanner({
    required this.conversationId,
    required this.review,
    super.key,
  });

  final int conversationId;
  final ConversationReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final title = review.reviewerName.isEmpty
        ? l10n.reviewSectionTitle
        : l10n.reviewWithReviewer(review.reviewerName);
    final status = reviewStatusText(l10n, review.status);

    return Material(
      key: const Key('conversationReviewBanner'),
      color: colors.infoSurface,
      child: InkWell(
        onTap: () => showConversationReviewSheet(
          context,
          conversationId: conversationId,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.rate_review_outlined, size: 18, color: colors.info),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(width: Space.sm),
                _StatusChip(label: status),
              ],
              const SizedBox(width: Space.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.info,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Opens the conversation's review: who it is with, who asked and when,
/// the note, and the actions the signed-in employee is offered.
Future<void> showConversationReviewSheet(
  BuildContext context, {
  required int conversationId,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) =>
        _ReviewSheet(conversationId: conversationId, messenger: messenger),
  );
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.conversationId, required this.messenger});

  final int conversationId;
  final ScaffoldMessengerState messenger;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  String? _error;

  Future<void> _act({
    required Future<Conversation?> Function(ConversationReviewController c)
    action,
    required String Function(AppLocalizations l10n) success,
  }) async {
    final l10n = context.l10n;
    setState(() => _error = null);
    try {
      final updated = await action(
        ref.read(conversationReviewProvider.notifier),
      );
      if (updated == null || !mounted) return;
      Navigator.of(context).pop();
      widget.messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success(l10n))));
    } on SessionExpiredException {
      // The app is already taking the agent back to sign in.
    } on RequestCancelledException {
      // Abandoned on purpose; nothing to report.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = reviewErrorMessage(l10n, error, requesting: false),
      );
    }
  }

  Future<void> _withdraw() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.withdrawReviewConfirmTitle),
        content: Text(l10n.withdrawReviewConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('withdrawReviewConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.withdrawReviewAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _act(
      action: (c) => c.withdraw(widget.conversationId),
      success: (l10n) => l10n.reviewWithdrawnMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final review = ref
        .watch(conversationControllerProvider(widget.conversationId))
        .value
        ?.conversation
        .review;
    final busy = ref
        .watch(conversationReviewProvider)
        .contains(widget.conversationId);

    if (review == null) {
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(l10n.reviewNotPendingMessage),
      );
    }

    final canComplete = canCompleteReview(
      ref.watch(currentEmployeeProvider),
      review,
    );
    final status = reviewStatusText(l10n, review.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.reviewSectionTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status.isNotEmpty) _StatusChip(label: status),
            ],
          ),
          const SizedBox(height: Space.md),
          _Field(label: l10n.reviewReviewerLabel, value: review.reviewerName),
          _Field(
            label: l10n.reviewRequestedByLabel,
            value: review.requestedByName,
          ),
          _Field(
            label: l10n.reviewRequestedAtLabel,
            value: review.requestedAt == null
                ? ''
                : formatDateTime(context, review.requestedAt),
          ),
          if (review.note.trim().isNotEmpty)
            _Field(label: l10n.reviewNoteLabel, value: review.note.trim()),
          const SizedBox(height: Space.md),
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('reviewSheetError'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
          if (canComplete) ...[
            FilledButton.icon(
              key: const Key('completeReviewButton'),
              onPressed: busy
                  ? null
                  : () => _act(
                      action: (c) => c.complete(widget.conversationId),
                      success: (l10n) => l10n.reviewCompletedMessage,
                    ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt),
              label: Text(l10n.completeReviewAction),
            ),
            const SizedBox(height: Space.sm),
          ],
          OutlinedButton.icon(
            key: const Key('changeReviewerButton'),
            onPressed: busy
                ? null
                : () {
                    Navigator.of(context).pop();
                    showRequestReviewSheet(
                      context,
                      conversationId: widget.conversationId,
                      current: review,
                      messenger: widget.messenger,
                    );
                  },
            icon: const Icon(Icons.swap_horiz),
            label: Text(l10n.changeReviewerAction),
          ),
          const SizedBox(height: Space.xs),
          TextButton.icon(
            key: const Key('withdrawReviewButton'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: busy ? null : _withdraw,
            icon: const Icon(Icons.undo),
            label: Text(l10n.withdrawReviewAction),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).mutedForeground,
              ),
            ),
          ),
          Expanded(
            // Names and the note are backend data, never translated.
            // Laid out in their own direction: an English note in the Arabic
            // app keeps its full stop at the end.
            child: Text(
              value.isEmpty ? '—' : value,
              textDirection: textDirectionOf(value),
              textAlign: ambientStartAlign(context),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the reviewer picker: a colleague, an optional note, and Send.
///
/// With [current] set, the pending review is retargeted (the same endpoint;
/// the server keeps one pending review), and its note is offered for
/// editing. [messenger] is where the outcome is reported; by default the
/// one around [context].
Future<void> showRequestReviewSheet(
  BuildContext context, {
  required int conversationId,
  ConversationReview? current,
  ScaffoldMessengerState? messenger,
}) {
  final target = messenger ?? ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _RequestReviewSheet(
      conversationId: conversationId,
      current: current,
      messenger: target,
    ),
  );
}

class _RequestReviewSheet extends ConsumerStatefulWidget {
  const _RequestReviewSheet({
    required this.conversationId,
    required this.current,
    required this.messenger,
  });

  final int conversationId;
  final ConversationReview? current;
  final ScaffoldMessengerState messenger;

  @override
  ConsumerState<_RequestReviewSheet> createState() =>
      _RequestReviewSheetState();
}

class _RequestReviewSheetState extends ConsumerState<_RequestReviewSheet> {
  final _searchController = TextEditingController();
  late final _noteController = TextEditingController(
    text: widget.current?.note ?? '',
  );
  Timer? _debounce;
  String _search = '';
  DirectoryEmployee? _selected;
  bool _showRequired = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) {
      setState(() => _showRequired = true);
      return;
    }
    final l10n = context.l10n;
    final retargeting = widget.current != null;
    setState(() => _error = null);
    try {
      final updated = await ref
          .read(conversationReviewProvider.notifier)
          .request(
            widget.conversationId,
            // The colleague's backend id — never a name or a list position.
            reviewerId: selected.id,
            note: _noteController.text,
          );
      if (updated == null || !mounted) return;
      final name = updated.review?.reviewerName.isNotEmpty == true
          ? updated.review!.reviewerName
          : selected.fullName;
      Navigator.of(context).pop();
      widget.messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              retargeting
                  ? l10n.reviewerChangedMessage(name)
                  : l10n.reviewRequestedMessage(name),
            ),
          ),
        );
    } on SessionExpiredException {
      // The app is already taking the agent back to sign in.
    } on RequestCancelledException {
      // Abandoned on purpose; nothing to report.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = reviewErrorMessage(l10n, error, requesting: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final me = ref.watch(currentEmployeeProvider);
    final busy = ref
        .watch(conversationReviewProvider)
        .contains(widget.conversationId);
    final candidates = ref.watch(reviewerCandidatesProvider(_search));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.current == null
                    ? l10n.requestReviewAction
                    : l10n.changeReviewerAction,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                l10n.reviewExplanation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).mutedForeground,
                ),
              ),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('reviewerSearchField'),
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.searchEmployeesHint,
                  isDense: true,
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                _showRequired && _selected == null
                    ? l10n.reviewReviewerRequired
                    : l10n.reviewChooseReviewerHint,
                key: const Key('reviewerHint'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _showRequired && _selected == null
                      ? theme.colorScheme.error
                      : AppColors.of(context).mutedForeground,
                ),
              ),
              Flexible(
                child: candidates.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: Space.xl),
                    child: LoadingState(),
                  ),
                  error: (error, _) => ErrorStateView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(reviewerCandidatesProvider(_search)),
                  ),
                  data: (list) {
                    // A colleague: someone else, still active.
                    final colleagues = [
                      for (final e in list)
                        if (e.isActive && e.id != me?.id) e,
                    ];
                    if (colleagues.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.lg),
                        child: Text(
                          l10n.reviewNoColleaguesFound,
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final employee in colleagues)
                          _CandidateRow(
                            employee: employee,
                            selected: _selected?.id == employee.id,
                            isCurrent:
                                widget.current?.reviewerId == employee.id,
                            enabled: !busy,
                            onTap: () => setState(() {
                              _selected = employee;
                              _error = null;
                            }),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                key: const Key('reviewNoteField'),
                controller: _noteController,
                enabled: !busy,
                textDirection: inputDirectionOf(_noteController.text),
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.noteOptionalLabel,
                  hintText: l10n.reviewNoteHint,
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                Text(
                  _error!,
                  key: const Key('requestReviewError'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: Space.md),
              FilledButton(
                key: const Key('requestReviewSubmit'),
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.reviewSubmitButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.employee,
    required this.selected,
    required this.isCurrent,
    required this.enabled,
    required this.onTap,
  });

  final DirectoryEmployee employee;
  final bool selected;
  final bool isCurrent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('reviewerCandidate_${employee.id}'),
      contentPadding: EdgeInsets.zero,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: InitialsAvatar(
        initials: employee.initials,
        imageUrl: employee.avatarUrl,
        size: 32,
      ),
      // Employee names are backend data — never translated.
      title: Text(
        employee.fullName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: isCurrent
          ? Text(
              context.l10n.reviewCurrentReviewerLabel,
              style: theme.textTheme.labelSmall,
            )
          : (employee.roleDisplay.isEmpty ? null : Text(employee.roleDisplay)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PresenceDot(availability: employee.availability),
          const SizedBox(width: Space.sm),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
