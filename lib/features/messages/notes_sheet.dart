/// Internal notes for one conversation — visible to the team, never sent to
/// the customer.
///
/// A bottom sheet, the same shape as `showConversationHistorySheet`/
/// `showConversionsSheet`: read access is open to any active employee, and
/// writing a note is gated separately on `conversation.note`, matching how
/// `Perm.conversionReport` gates Conversions' own write action one level
/// stricter than the read.
///
/// Kept deliberately apart from `ConversationState`/the message thread:
/// notes are their own conversation-scoped resource (`notesControllerProvider`,
/// keyed by conversation id, the same shape as `conversationConversionsProvider`),
/// never merged into `state.messages` and never sent through
/// `ConversationRepository.reply()`/the provider messaging path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/message.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'notes_controller.dart';

/// Opens the internal notes sheet for a conversation.
Future<void> showInternalNotesSheet(
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
      builder: (context, controller) => _NotesSheet(
        conversationId: conversationId,
        scrollController: controller,
      ),
    ),
  );
}

class _NotesSheet extends ConsumerStatefulWidget {
  const _NotesSheet({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends ConsumerState<_NotesSheet> {
  final _bodyController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    // Safe here, unlike the one-shot AlertDialogs elsewhere in this app:
    // this controller lives for the sheet's own State lifetime, so dispose()
    // only ever runs once this widget is actually gone, not while some
    // other still-animating route is racing it.
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(notesControllerProvider(widget.conversationId).notifier)
          .addNote(body);
      if (!mounted) return;
      // Only cleared on confirmed success — a failed post leaves the draft
      // in place so nothing typed is lost.
      _bodyController.clear();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(notesControllerProvider(widget.conversationId));
    final canWrite = ref.watch(canProvider(Perm.conversationNote));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text(
            context.l10n.internalNotesTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const LoadingState(),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(
                  notesControllerProvider(widget.conversationId),
                ),
              ),
            ),
            data: (notes) => notes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: EmptyState(
                      icon: Icons.sticky_note_2_outlined,
                      title: context.l10n.internalNotesEmpty,
                    ),
                  )
                : CustomScrollView(
                    controller: widget.scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.lg,
                          0,
                          Space.lg,
                          Space.md,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _NoteRow(note: notes[index]),
                            childCount: notes.length,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (canWrite)
          _NoteComposer(
            controller: _bodyController,
            submitting: _submitting,
            error: _error,
            onSubmit: _submit,
          ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final InternalNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(initials: note.authorInitials, size: 32),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
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
                      Expanded(
                        child: Text(
                          note.authorName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatDateTime(context, note.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(note.body, style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteComposer extends StatelessWidget {
  const _NoteComposer({
    required this.controller,
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.sm,
        ),
        decoration: BoxDecoration(
          color: ScenarioColors.warningSurface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null) ...[
              Text(
                error!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: Space.xs),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: context.l10n.internalNoteInputHint,
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                SizedBox(
                  width: 44,
                  height: 44,
                  // A blank/whitespace-only draft must not enable Send —
                  // ValueListenableBuilder tracks the field live (the
                  // controller is a ValueNotifier<TextEditingValue>) rather
                  // than only checking at submit time.
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton.filled(
                      onPressed: submitting || value.text.trim().isEmpty
                          ? null
                          : onSubmit,
                      icon: submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
