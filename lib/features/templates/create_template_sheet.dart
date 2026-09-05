/// Bottom sheet for creating and submitting a new WhatsApp template to Meta.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'templates_providers.dart';

class CreateTemplateSheet extends ConsumerStatefulWidget {
  const CreateTemplateSheet({required this.channelId, super.key});

  final int channelId;

  static Future<bool?> show(BuildContext context, {required int channelId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateTemplateSheet(channelId: channelId),
    );
  }

  @override
  ConsumerState<CreateTemplateSheet> createState() =>
      _CreateTemplateSheetState();
}

class _CreateTemplateSheetState extends ConsumerState<CreateTemplateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bodyController = TextEditingController();

  String _category = 'MARKETING';
  String _language = 'en_US';
  bool _submitting = false;
  String? _errorMessage;

  static final _nameRegex = RegExp(r'^[a-z0-9_]{1,512}$');

  static const _categories = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];

  static const _languages = [
    ('en_US', 'English (US) — en_US'),
    ('ar', 'Arabic — ar'),
    ('en', 'English — en'),
    ('es', 'Spanish — es'),
    ('fr', 'French — fr'),
    ('de', 'German — de'),
    ('pt_BR', 'Portuguese (BR) — pt_BR'),
    ('tr', 'Turkish — tr'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _errorMessage = null;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(templatesRepositoryProvider)
          .createTemplate(
            widget.channelId,
            name: _nameController.text,
            category: _category,
            language: _language,
            body: _bodyController.text,
          );

      // Invalidate the cache so the fresh pending template appears in the list
      ref.invalidate(templatesForChannelProvider(widget.channelId));

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.templateSubmittedSnackbar),
            backgroundColor: ScenarioColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, bottomInset),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.lg),
        ),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Space.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),

              // Title & Subtitle
              Text(
                context.l10n.createTemplateTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                context.l10n.createTemplateSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? ScenarioColors.darkMutedForeground
                      : ScenarioColors.mutedForeground,
                ),
              ),
              const SizedBox(height: Space.lg),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: ScenarioColors.dangerSurface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: ScenarioColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: ScenarioColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: ScenarioColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
              ],

              // Name Field
              TextFormField(
                controller: _nameController,
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: context.l10n.templateNameLabel,
                  helperText: context.l10n.templateNameHelper,
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  final text = (val ?? '').trim();
                  if (text.isEmpty) {
                    return context.l10n.fieldRequiredError;
                  }
                  if (!_nameRegex.hasMatch(text)) {
                    return context.l10n.templateInvalidNameError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: Space.md),

              // Category & Language in a responsive layout
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: InputDecoration(
                        labelText: context.l10n.templateCategoryLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final cat in _categories)
                          DropdownMenuItem(value: cat, child: Text(cat)),
                      ],
                      onChanged: _submitting
                          ? null
                          : (val) {
                              if (val != null) setState(() => _category = val);
                            },
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _language,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.templateLanguageLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final (code, _) in _languages)
                          DropdownMenuItem(
                            value: code,
                            child: Text(code, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (val) {
                              if (val != null) setState(() => _language = val);
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),

              // Body Field
              TextFormField(
                controller: _bodyController,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 6,
                maxLength: 1024,
                decoration: InputDecoration(
                  labelText: context.l10n.templateBodyLabel,
                  hintText: context.l10n.templateBodyHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  final text = (val ?? '').trim();
                  if (text.isEmpty) {
                    return context.l10n.templateEmptyBodyError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: Space.lg),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: Space.sm),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: ScenarioColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.md,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.l10n.submitForReviewAction),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}
