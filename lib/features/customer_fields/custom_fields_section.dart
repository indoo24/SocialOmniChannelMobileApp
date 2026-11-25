/// A customer's custom fields: shown wherever the customer is, edited with
/// `customer.manage`.
///
/// Renders nothing when the organization defines no fields, so an organization
/// that never uses them sees exactly what it saw before. Definitions are
/// managed on the web; this app only fills them in.
///
/// Type rules are the server's. The edit sheet picks a control by type, checks
/// nothing but "required and empty", and shows the server's own message under
/// each field it refuses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/customer_fields.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/key_value_row.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../directory/directory_providers.dart';

/// How a value reads. Empty when nothing is recorded.
String displayCustomFieldValue(
  BuildContext context,
  CustomerFieldDefinition definition,
  Object? value,
) {
  if (value == null) return '';
  switch (definition.fieldType) {
    case 'BOOLEAN':
      return value == true
          ? context.l10n.customFieldYes
          : context.l10n.customFieldNo;
    case 'SELECT':
      return definition.labelForOption(value.toString());
    case 'MULTI_SELECT':
      final values = value is List ? value : [value];
      return values
          .map((item) => definition.labelForOption(item.toString()))
          .join('، ');
    case 'DATETIME':
      final moment = DateTime.tryParse(value.toString());
      return moment == null
          ? value.toString()
          : formatDateTime(context, moment.toLocal());
    default:
      return value.toString();
  }
}

class CustomFieldsSection extends ConsumerWidget {
  const CustomFieldsSection({required this.customerId, super.key});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(customerFieldsProvider(customerId)).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    final canEdit = ref.watch(canProvider(Perm.customerManage));
    final theme = Theme.of(context);

    return Column(
      key: const Key('custom-fields-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.customFieldsSectionTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canEdit)
              IconButton(
                key: const Key('custom-fields-edit'),
                tooltip: context.l10n.customFieldsEditTooltip,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => showEditCustomFieldsSheet(
                  context,
                  customerId: customerId,
                  rows: rows,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        // The same flexible label/value row as the conversation details:
        // nothing cut, whatever the label or the system text size.
        for (final row in rows)
          KeyValueRow(
            label: row.definition.label,
            value: row.hasValue
                ? displayCustomFieldValue(context, row.definition, row.value)
                : '',
          ),
      ],
    );
  }
}

Future<void> showEditCustomFieldsSheet(
  BuildContext context, {
  required int customerId,
  required List<CustomerFieldRow> rows,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => _EditCustomFieldsSheet(
        customerId: customerId,
        rows: rows,
        scrollController: controller,
      ),
    ),
  );
}

class _EditCustomFieldsSheet extends ConsumerStatefulWidget {
  const _EditCustomFieldsSheet({
    required this.customerId,
    required this.rows,
    required this.scrollController,
  });

  final int customerId;
  final List<CustomerFieldRow> rows;
  final ScrollController scrollController;

  @override
  ConsumerState<_EditCustomFieldsSheet> createState() =>
      _EditCustomFieldsSheetState();
}

class _EditCustomFieldsSheetState
    extends ConsumerState<_EditCustomFieldsSheet> {
  /// Current entry per key: `String` for text-like and single choices ("" is
  /// not set), `String` "true"/"false"/"" for yes/no, `List<String>` for
  /// multiple choice.
  late final Map<String, Object> _inputs = {
    for (final row in widget.rows) row.definition.key: _initialInput(row),
  };
  late final Map<String, TextEditingController> _controllers = {
    for (final row in widget.rows)
      if (_usesTextField(row.definition.fieldType))
        row.definition.key: TextEditingController(
          text: _inputs[row.definition.key]! as String,
        ),
  };
  Map<String, String> _errors = {};
  String? _formError;
  bool _submitting = false;

  static bool _usesTextField(String type) =>
      !{'BOOLEAN', 'SELECT', 'MULTI_SELECT', 'DATE', 'DATETIME'}.contains(type);

  static Object _initialInput(CustomerFieldRow row) {
    final value = row.value;
    switch (row.definition.fieldType) {
      case 'MULTI_SELECT':
        return value is List
            ? value.map((item) => item.toString()).toList()
            : <String>[];
      case 'BOOLEAN':
        return value == null ? '' : (value == true ? 'true' : 'false');
      default:
        return value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// What the API receives for [key]; null clears the field.
  Object? _outgoing(CustomerFieldDefinition definition) {
    final key = definition.key;
    final input = _controllers[key]?.text ?? _inputs[key];
    switch (definition.fieldType) {
      case 'BOOLEAN':
        return input == '' ? null : input == 'true';
      case 'MULTI_SELECT':
        final chosen = input is List ? input.cast<String>() : const <String>[];
        return chosen.isEmpty ? null : chosen;
      default:
        final text = (input ?? '').toString().trim();
        return text.isEmpty ? null : text;
    }
  }

  static String _comparable(Object? value) {
    if (value == null) return 'null';
    if (value is List) {
      return ([...value.map((item) => item.toString())]..sort()).join(' ');
    }
    return value.toString();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final missing = <String, String>{};
    final changes = <String, Object?>{};
    for (final row in widget.rows) {
      final next = _outgoing(row.definition);
      if (next == null && row.definition.required) {
        missing[row.definition.key] = context.l10n.customFieldRequired;
      }
      if (_comparable(next) != _comparable(row.value)) {
        changes[row.definition.key] = next;
      }
    }
    if (missing.isNotEmpty) {
      setState(() => _errors = missing);
      return;
    }
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _submitting = true;
      _errors = {};
      _formError = null;
    });
    try {
      final rows = await ref
          .read(directoryRepositoryProvider)
          .saveCustomerFields(widget.customerId, changes);
      if (!mounted) return;
      ref.invalidate(customerFieldsProvider(widget.customerId));
      ref.invalidate(customerFactsProvider(widget.customerId));
      ref.invalidate(customerDetailProvider(widget.customerId));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.customFieldsSaved)));
      assert(rows.isNotEmpty || widget.rows.isEmpty);
    } on ApiException catch (error) {
      if (!mounted) return;
      final values = error.details['values'];
      final perField = <String, String>{};
      if (values is Map) {
        values.forEach((key, messages) {
          perField[key.toString()] = messages is List && messages.isNotEmpty
              ? messages.first.toString()
              : messages.toString();
        });
      }
      setState(() {
        _errors = perField;
        _formError = perField.isEmpty ? error.message : null;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickDate(CustomerFieldDefinition definition) async {
    final current = DateTime.tryParse(
      (_inputs[definition.key] as String?) ?? '',
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: context.l10n.customFieldPickDate,
    );
    if (picked == null || !mounted) return;
    final text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => _inputs[definition.key] = text);
  }

  Future<void> _pickDateTime(CustomerFieldDefinition definition) async {
    final current = DateTime.tryParse(
      (_inputs[definition.key] as String?) ?? '',
    )?.toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: context.l10n.customFieldPickDateTime,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    // Sent as a UTC instant, so the server never has to guess a timezone.
    final moment = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).toUtc();
    setState(() => _inputs[definition.key] = moment.toIso8601String());
  }

  Widget _control(CustomerFieldRow row) {
    final definition = row.definition;
    final key = definition.key;
    final error = _errors[key];
    final helper = definition.helpText.isEmpty ? null : definition.helpText;
    final label = definition.required
        ? '${definition.label} *'
        : definition.label;

    InputDecoration decoration() => InputDecoration(
      labelText: label,
      hintText: definition.placeholder.isEmpty ? null : definition.placeholder,
      helperText: helper,
      errorText: error,
    );

    switch (definition.fieldType) {
      case 'BOOLEAN':
        return DropdownButtonFormField<String>(
          key: Key('custom-field-$key'),
          initialValue: _inputs[key] as String,
          decoration: decoration(),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.l10n.customFieldNotSet),
            ),
            DropdownMenuItem(
              value: 'true',
              child: Text(context.l10n.customFieldYes),
            ),
            DropdownMenuItem(
              value: 'false',
              child: Text(context.l10n.customFieldNo),
            ),
          ],
          onChanged: (value) => setState(() => _inputs[key] = value ?? ''),
        );
      case 'SELECT':
        final current = _inputs[key] as String;
        return DropdownButtonFormField<String>(
          key: Key('custom-field-$key'),
          initialValue: definition.options.any((o) => o.value == current)
              ? current
              : '',
          decoration: decoration(),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.l10n.customFieldNotSet),
            ),
            for (final option in definition.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) => setState(() => _inputs[key] = value ?? ''),
        );
      case 'MULTI_SELECT':
        final chosen = (_inputs[key] as List).cast<String>();
        return InputDecorator(
          key: Key('custom-field-$key'),
          decoration: decoration(),
          child: Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final option in definition.options)
                FilterChip(
                  key: Key('custom-field-$key-${option.value}'),
                  label: Text(option.label),
                  selected: chosen.contains(option.value),
                  onSelected: (selected) => setState(() {
                    _inputs[key] = selected
                        ? [...chosen, option.value]
                        : chosen
                              .where((value) => value != option.value)
                              .toList();
                  }),
                ),
            ],
          ),
        );
      case 'DATE':
      case 'DATETIME':
        final raw = _inputs[key] as String;
        final shown = raw.isEmpty
            ? context.l10n.customFieldNotSet
            : displayCustomFieldValue(context, definition, raw);
        return InputDecorator(
          key: Key('custom-field-$key'),
          decoration: decoration(),
          child: Row(
            children: [
              Expanded(child: Text(shown)),
              IconButton(
                tooltip: definition.fieldType == 'DATE'
                    ? context.l10n.customFieldPickDate
                    : context.l10n.customFieldPickDateTime,
                icon: const Icon(Icons.event_outlined, size: 20),
                onPressed: _submitting
                    ? null
                    : () => definition.fieldType == 'DATE'
                          ? _pickDate(definition)
                          : _pickDateTime(definition),
              ),
              if (raw.isNotEmpty)
                IconButton(
                  tooltip: context.l10n.customFieldClear,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _inputs[key] = ''),
                ),
            ],
          ),
        );
      default:
        return TextField(
          key: Key('custom-field-$key'),
          controller: _controllers[key],
          enabled: !_submitting,
          minLines: definition.fieldType == 'LONG_TEXT' ? 2 : 1,
          maxLines: definition.fieldType == 'LONG_TEXT' ? 6 : 1,
          keyboardType: switch (definition.fieldType) {
            'PHONE' => TextInputType.phone,
            'EMAIL' => TextInputType.emailAddress,
            'NUMBER' => TextInputType.number,
            'DECIMAL' => const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            'LONG_TEXT' => TextInputType.multiline,
            _ => TextInputType.text,
          },
          decoration: decoration(),
        );
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
          context.l10n.customFieldsEditTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_formError != null) ...[
          Text(_formError!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: Space.md),
        ],
        for (final row in widget.rows) ...[
          _control(row),
          const SizedBox(height: Space.md),
        ],
        const SizedBox(height: Space.md),
        FilledButton(
          key: const Key('custom-fields-save'),
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
    );
  }
}
