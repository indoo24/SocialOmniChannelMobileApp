/// Add/Edit a customer field definition — `POST /customer-fields/` and
/// `PATCH /customer-fields/{id}/`.
///
/// Every entry point that opens this sheet is itself gated on
/// `Perm.customerFieldManage` — see `customer_fields_settings_screen.dart` —
/// so reaching this file at all already implies that check passed; the
/// backend still enforces it independently.
///
/// The key is immutable once a field exists: in edit mode it is shown
/// read-only, and is never sent in the update payload. On create it is left
/// for the server to derive from the label unless the admin opts to set one
/// explicitly, matching `CustomerFieldDefinitionWrite`'s own contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/customer_fields.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';

final _keyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

String fieldTypeLabel(BuildContext context, String type) => switch (type) {
  'TEXT' => context.l10n.fieldTypeText,
  'LONG_TEXT' => context.l10n.fieldTypeLongText,
  'NUMBER' => context.l10n.fieldTypeNumber,
  'DECIMAL' => context.l10n.fieldTypeDecimal,
  'DATE' => context.l10n.fieldTypeDate,
  'DATETIME' => context.l10n.fieldTypeDatetime,
  'BOOLEAN' => context.l10n.fieldTypeBoolean,
  'SELECT' => context.l10n.fieldTypeSelect,
  'MULTI_SELECT' => context.l10n.fieldTypeMultiSelect,
  'PHONE' => context.l10n.fieldTypePhone,
  'EMAIL' => context.l10n.fieldTypeEmail,
  _ => type,
};

/// Opens the Add field sheet.
Future<void> showAddCustomerFieldSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _CustomerFieldFormSheet(scrollController: controller),
    ),
  );
}

/// Opens the Edit field sheet, prefilled from [field]. The key is read-only.
Future<void> showEditCustomerFieldSheet(
  BuildContext context, {
  required CustomerFieldDefinition field,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => _CustomerFieldFormSheet(
        existing: field,
        scrollController: controller,
      ),
    ),
  );
}

class _CustomerFieldFormSheet extends ConsumerStatefulWidget {
  const _CustomerFieldFormSheet({
    this.existing,
    required this.scrollController,
  });

  final CustomerFieldDefinition? existing;
  final ScrollController scrollController;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_CustomerFieldFormSheet> createState() =>
      _CustomerFieldFormSheetState();
}

class _CustomerFieldFormSheetState
    extends ConsumerState<_CustomerFieldFormSheet> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _key = TextEditingController(text: widget.existing?.key);
  late final _helpText = TextEditingController(text: widget.existing?.helpText);
  late final _placeholder = TextEditingController(
    text: widget.existing?.placeholder,
  );
  late String _fieldType =
      widget.existing?.fieldType ?? kCustomerFieldTypes.first;
  late bool _required = widget.existing?.required ?? false;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _helpText.dispose();
    _placeholder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = context.l10n.fieldLabelRequiredError);
      return;
    }

    final key = _key.text.trim();
    if (!widget.isEdit && key.isNotEmpty && !_keyPattern.hasMatch(key)) {
      setState(() => _error = context.l10n.fieldKeyInvalidError);
      return;
    }

    final repository = ref.read(directoryRepositoryProvider);

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.isEdit) {
        await repository.updateCustomerFieldDefinition(
          widget.existing!.id,
          label: label,
          fieldType: _fieldType,
          required: _required,
          helpText: _helpText.text.trim(),
          placeholder: _placeholder.text.trim(),
        );
      } else {
        await repository.createCustomerFieldDefinition(
          label: label,
          fieldType: _fieldType,
          key: key.isEmpty ? null : key,
          required: _required,
          helpText: _helpText.text.trim(),
          placeholder: _placeholder.text.trim(),
        );
      }

      if (!mounted) return;
      ref.invalidate(customerFieldDefinitionsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? context.l10n.fieldUpdatedSnackbar
                : context.l10n.fieldAddedSnackbar,
          ),
        ),
      );
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

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          widget.isEdit
              ? context.l10n.editFieldTitle
              : context.l10n.addFieldTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          key: const Key('field-form-label'),
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.fieldLabelFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: const Key('field-form-key'),
          controller: _key,
          enabled: !widget.isEdit,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
          ],
          decoration: InputDecoration(
            labelText: context.l10n.fieldKeyFieldLabel,
            helperText: widget.isEdit
                ? context.l10n.fieldKeyHelperTextFixed
                : context.l10n.fieldKeyHelperTextGenerated,
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: Space.md),
        DropdownButtonFormField<String>(
          key: const Key('field-form-type'),
          initialValue: _fieldType,
          decoration: InputDecoration(
            labelText: context.l10n.fieldTypeFieldLabel,
          ),
          items: [
            for (final type in kCustomerFieldTypes)
              DropdownMenuItem(
                value: type,
                child: Text(fieldTypeLabel(context, type)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _fieldType = value);
          },
        ),
        const SizedBox(height: Space.sm),
        SwitchListTile(
          key: const Key('field-form-required'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.fieldRequiredToggleLabel),
          subtitle: Text(context.l10n.fieldRequiredToggleHelper),
          value: _required,
          onChanged: (value) => setState(() => _required = value),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: const Key('field-form-help-text'),
          controller: _helpText,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.fieldHelpTextFieldLabel,
            hintText: context.l10n.fieldHelpTextFieldHint,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          key: const Key('field-form-placeholder'),
          controller: _placeholder,
          decoration: InputDecoration(
            labelText: context.l10n.fieldPlaceholderFieldLabel,
            hintText: context.l10n.fieldPlaceholderFieldHint,
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: Space.md),
            FilledButton(
              key: const Key('field-form-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(context.l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
}
