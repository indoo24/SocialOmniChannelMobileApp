/// Create/edit forms for knowledge bases and sources, and the confirm step
/// before a delete.
///
/// Each form waits for the server and closes only on success; a refusal
/// keeps what was typed and shows the server's reason, next to the field it
/// names when it names one. The client-side checks mirror the schema's
/// required fields only — the server stays the authority.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_knowledge_repository.dart';

/// Asks before a destructive action. Resolves to true only on confirm.
Future<bool> confirmKnowledgeDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton(
          key: const Key('ai-confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(title),
        ),
      ],
    ),
  );
  return confirmed == true;
}

void showKnowledgeSnack(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

// --------------------------------------------------------------------------- //
// Knowledge base
// --------------------------------------------------------------------------- //

/// New knowledge base, or rename/describe [existing].
Future<void> showKnowledgeBaseForm(
  BuildContext context, {
  KnowledgeBase? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _KnowledgeBaseForm(existing: existing),
  );
}

class _KnowledgeBaseForm extends ConsumerStatefulWidget {
  const _KnowledgeBaseForm({this.existing});

  final KnowledgeBase? existing;

  @override
  ConsumerState<_KnowledgeBaseForm> createState() => _KnowledgeBaseFormState();
}

class _KnowledgeBaseFormState extends ConsumerState<_KnowledgeBaseForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fieldErrors = {'name': l10n.aiKnowledgeBaseNameRequired});
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    final controller = ref.read(knowledgeBasesProvider.notifier);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await controller.create(
          name: name,
          description: _description.text.trim(),
        );
      } else {
        await controller.edit(
          existing.id,
          name: name,
          description: _description.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showKnowledgeSnack(context, l10n.aiKnowledgeBaseSaved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrors = error.fieldErrors();
        _error = aiErrorMessage(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? l10n.aiEditKnowledgeBase : l10n.aiNewKnowledgeBase,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.lg),
            _DirectionalField(
              key: const Key('kb-form-name'),
              controller: _name,
              label: l10n.aiKnowledgeBaseName,
              hint: l10n.aiKnowledgeBaseNamePlaceholder,
              maxLength: AiKnowledgeRepository.maxBaseNameLength,
              errorText: _fieldErrors['name'],
              autofocus: !isEdit,
            ),
            const SizedBox(height: Space.md),
            _DirectionalField(
              key: const Key('kb-form-description'),
              controller: _description,
              label: l10n.aiKnowledgeBaseDescription,
              hint: l10n.aiKnowledgeBaseDescriptionPlaceholder,
              errorText: _fieldErrors['description'],
              maxLines: 3,
            ),
            if (_error != null &&
                !_fieldErrors.keys.any({'name', 'description'}.contains)) ...[
              const SizedBox(height: Space.md),
              InlineError(message: _error!),
            ],
            const SizedBox(height: Space.lg),
            _FormActions(
              submitKey: const Key('kb-form-save'),
              submitting: _submitting,
              submitLabel: isEdit
                  ? l10n.saveAction
                  : l10n.aiCreateKnowledgeBase,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Source
// --------------------------------------------------------------------------- //

/// Add a source of [sourceType] to [knowledgeBaseId], or edit [existing]
/// (whose type cannot change).
Future<void> showKnowledgeSourceForm(
  BuildContext context, {
  required String knowledgeBaseId,
  required String sourceType,
  KnowledgeSource? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _KnowledgeSourceForm(
      knowledgeBaseId: knowledgeBaseId,
      sourceType: existing?.sourceType ?? sourceType,
      existing: existing,
    ),
  );
}

class _KnowledgeSourceForm extends ConsumerStatefulWidget {
  const _KnowledgeSourceForm({
    required this.knowledgeBaseId,
    required this.sourceType,
    this.existing,
  });

  final String knowledgeBaseId;
  final String sourceType;
  final KnowledgeSource? existing;

  bool get isQa => sourceType == KnowledgeSourceType.manualQa;

  @override
  ConsumerState<_KnowledgeSourceForm> createState() =>
      _KnowledgeSourceFormState();
}

class _KnowledgeSourceFormState extends ConsumerState<_KnowledgeSourceForm> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _question = TextEditingController(text: widget.existing?.question);
  late final _answer = TextEditingController(text: widget.existing?.answer);
  late final _body = TextEditingController(text: widget.existing?.body);
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _title.dispose();
    _question.dispose();
    _answer.dispose();
    _body.dispose();
    super.dispose();
  }

  Map<String, String> _missing() {
    final l10n = context.l10n;
    return widget.isQa
        ? {
            if (_question.text.trim().isEmpty)
              'question': l10n.aiQuestionRequired,
            if (_answer.text.trim().isEmpty) 'answer': l10n.aiAnswerRequired,
          }
        : {
            if (_title.text.trim().isEmpty) 'title': l10n.aiTitleRequired,
            if (_body.text.trim().isEmpty) 'body': l10n.aiContentRequired,
          };
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final missing = _missing();
    if (missing.isNotEmpty) {
      setState(() => _fieldErrors = missing);
      return;
    }
    final l10n = context.l10n;
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    final controller = ref.read(
      knowledgeSourcesProvider(widget.knowledgeBaseId).notifier,
    );
    final title = _title.text.trim();
    final question = _question.text.trim();
    final answer = _answer.text.trim();
    final body = _body.text.trim();
    try {
      final existing = widget.existing;
      if (existing == null) {
        await controller.create(
          sourceType: widget.sourceType,
          title: title,
          question: question,
          answer: answer,
          body: body,
        );
      } else {
        await controller.edit(
          existing,
          title: title,
          question: question,
          answer: answer,
          body: body,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showKnowledgeSnack(context, l10n.aiSourceSaved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrors = error.fieldErrors();
        _error = aiErrorMessage(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.existing != null;
    final heading = widget.isQa
        ? (isEdit ? l10n.aiEditQa : l10n.aiAddQa)
        : (isEdit ? l10n.aiEditText : l10n.aiAddText);
    // A field error the form has no field for still has to be seen.
    final shownFields = widget.isQa
        ? const {'question', 'answer', 'title'}
        : const {'title', 'body'};
    final unplacedError =
        _error != null && !_fieldErrors.keys.any(shownFields.contains);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.lg),
            if (widget.isQa) ...[
              _DirectionalField(
                key: const Key('source-form-question'),
                controller: _question,
                label: l10n.aiQuestion,
                hint: l10n.aiQuestionPlaceholder,
                errorText: _fieldErrors['question'],
                autofocus: !isEdit,
                maxLines: 2,
              ),
              const SizedBox(height: Space.md),
              _DirectionalField(
                key: const Key('source-form-answer'),
                controller: _answer,
                label: l10n.aiAnswer,
                hint: l10n.aiAnswerPlaceholder,
                helper: l10n.aiAnswerHint,
                errorText: _fieldErrors['answer'],
                maxLines: 5,
              ),
              const SizedBox(height: Space.md),
              _DirectionalField(
                key: const Key('source-form-title'),
                controller: _title,
                label: l10n.aiSourceTitleOptional,
                hint: l10n.aiSourceTitlePlaceholder,
                maxLength: AiKnowledgeRepository.maxSourceTitleLength,
                errorText: _fieldErrors['title'],
              ),
            ] else ...[
              _DirectionalField(
                key: const Key('source-form-title'),
                controller: _title,
                label: l10n.aiSourceTitle,
                hint: l10n.aiSourceTitlePlaceholder,
                maxLength: AiKnowledgeRepository.maxSourceTitleLength,
                errorText: _fieldErrors['title'],
                autofocus: !isEdit,
              ),
              const SizedBox(height: Space.md),
              _DirectionalField(
                key: const Key('source-form-body'),
                controller: _body,
                label: l10n.aiContent,
                hint: l10n.aiContentPlaceholder,
                errorText: _fieldErrors['body'],
                maxLines: 8,
              ),
            ],
            if (unplacedError) ...[
              const SizedBox(height: Space.md),
              InlineError(message: _error!),
            ],
            const SizedBox(height: Space.lg),
            _FormActions(
              submitKey: const Key('source-form-save'),
              submitting: _submitting,
              submitLabel: l10n.saveAction,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Shared pieces
// --------------------------------------------------------------------------- //

/// A text field that runs in its content's own direction once typed in, so
/// Arabic knowledge reads right in the English app and the reverse.
class _DirectionalField extends StatefulWidget {
  const _DirectionalField({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;

  @override
  State<_DirectionalField> createState() => _DirectionalFieldState();
}

class _DirectionalFieldState extends State<_DirectionalField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      maxLength: widget.maxLength,
      minLines: 1,
      maxLines: widget.maxLines,
      textDirection: inputDirectionOf(widget.controller.text),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 3,
        errorText: widget.errorText,
        errorMaxLines: 4,
        alignLabelWithHint: widget.maxLines > 1,
      ),
    );
  }
}

class _FormActions extends StatelessWidget {
  const _FormActions({
    required this.submitKey,
    required this.submitting,
    required this.submitLabel,
    required this.onSubmit,
  });

  final Key submitKey;
  final bool submitting;
  final String submitLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: submitting ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: FilledButton(
            key: submitKey,
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(submitLabel),
          ),
        ),
      ],
    );
  }
}

/// Asks before leaving a form with unsaved changes. Resolves to true when
/// the person chose to discard them.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.aiUnsavedTitle),
        content: Text(l10n.aiUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.aiUnsavedKeepEditing),
          ),
          FilledButton(
            key: const Key('ai-discard-changes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.aiUnsavedDiscard),
          ),
        ],
      );
    },
  );
  return discard == true;
}
