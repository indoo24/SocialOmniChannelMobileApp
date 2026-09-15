/// Customers screen "Filter by field…" button and modal sheet.
///
/// Two steps, both inside one sheet: pick a custom field definition (from
/// [activeCustomerFieldDefinitionsProvider], the same field-definition system
/// Settings uses to manage them), then enter a value with a control chosen by
/// that field's type — mirroring `custom_fields_section.dart`'s per-type
/// switch, since the type set and options shape are identical. Applying calls
/// `CustomerFieldFilterNotifier`, which `customerDirectoryProvider` watches,
/// so the list always refetches from page 1 with the new
/// `field__<key>[__operator]` query param.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/customer_fields.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../customer_fields/custom_fields_section.dart';
import 'customer_field_filter_state.dart';
import 'directory_providers.dart';

/// Opens the "Filter by field" sheet.
Future<void> showCustomerFieldFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _CustomerFieldFilterSheet(),
  );
}

/// Compact outlined button for the Customers header, matching the Dashboard
/// date-filter button's shape. Shows the active field's label once a filter
/// with a value is applied, and offers a quick clear (×) beside it.
class CustomerFieldFilterButton extends ConsumerWidget {
  const CustomerFieldFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(customerFieldFilterProvider);
    final theme = Theme.of(context);
    final active = filter != null && filter.hasValue;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('customer-field-filter-button'),
          onTap: () => showCustomerFieldFilterSheet(context),
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 15,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.xs),
                Flexible(
                  child: Text(
                    active
                        ? filter.definition.label
                        : context.l10n.customerFieldFilterButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: Space.xs),
                  GestureDetector(
                    key: const Key('customer-field-filter-clear'),
                    onTap: () =>
                        ref.read(customerFieldFilterProvider.notifier).clear(),
                    child: Icon(
                      Icons.close,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ] else
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerFieldFilterSheet extends ConsumerStatefulWidget {
  const _CustomerFieldFilterSheet();

  @override
  ConsumerState<_CustomerFieldFilterSheet> createState() =>
      _CustomerFieldFilterSheetState();
}

class _CustomerFieldFilterSheetState
    extends ConsumerState<_CustomerFieldFilterSheet> {
  CustomerFieldDefinition? _picking;

  @override
  void initState() {
    super.initState();
    final current = ref.read(customerFieldFilterProvider);
    if (current != null) _picking = current.definition;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definitionsAsync = ref.watch(activeCustomerFieldDefinitionsProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.customerFieldFilterTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.md),
            definitionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.lg),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.invalidate(activeCustomerFieldDefinitionsProvider),
              ),
              data: (definitions) {
                if (definitions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.lg),
                    child: Text(
                      context.l10n.customerFieldFilterNoFields,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return _FieldPickerAndValue(
                  definitions: definitions,
                  picking: _picking,
                  onPick: (definition) => setState(() => _picking = definition),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The field dropdown plus the type-appropriate value control, and the
/// Clear/Apply row. Kept as one stateful widget below the async `.when` so it
/// only builds once [definitions] has actually loaded.
class _FieldPickerAndValue extends ConsumerStatefulWidget {
  const _FieldPickerAndValue({
    required this.definitions,
    required this.picking,
    required this.onPick,
  });

  final List<CustomerFieldDefinition> definitions;
  final CustomerFieldDefinition? picking;
  final void Function(CustomerFieldDefinition) onPick;

  @override
  ConsumerState<_FieldPickerAndValue> createState() =>
      _FieldPickerAndValueState();
}

class _FieldPickerAndValueState extends ConsumerState<_FieldPickerAndValue> {
  late final TextEditingController _textController;
  String? _selectValue;
  final Set<String> _multiSelectValues = {};
  String? _rangeFrom;
  String? _rangeTo;
  String? _error;

  CustomerFieldDefinition? get _definition => widget.picking;

  @override
  void initState() {
    super.initState();
    final current = ref.read(customerFieldFilterProvider);
    _textController = TextEditingController(
      text: current?.definition.key == widget.picking?.key
          ? (current?.value ?? '')
          : '',
    );
    if (current != null && current.definition.key == widget.picking?.key) {
      _selectValue = current.value;
      _rangeFrom = current.rangeFrom;
      _rangeTo = current.rangeTo;
      if (current.definition.fieldType == 'MULTI_SELECT' &&
          current.value != null) {
        _multiSelectValues.addAll(current.value!.split(','));
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onDefinitionChanged(CustomerFieldDefinition? definition) {
    if (definition == null) return;
    setState(() {
      widget.onPick(definition);
      _textController.clear();
      _selectValue = null;
      _multiSelectValues.clear();
      _rangeFrom = null;
      _rangeTo = null;
      _error = null;
    });
  }

  Future<void> _pickRangeDate({required bool isFrom}) async {
    final definition = _definition!;
    final currentText = isFrom ? _rangeFrom : _rangeTo;
    final current = currentText == null ? null : DateTime.tryParse(currentText);
    final picked = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final text = definition.fieldType == 'DATETIME'
        ? DateTime(
            picked.year,
            picked.month,
            picked.day,
          ).toUtc().toIso8601String()
        : '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (isFrom) {
        _rangeFrom = text;
      } else {
        _rangeTo = text;
      }
      _error = null;
    });
  }

  void _apply() {
    final definition = _definition;
    if (definition == null) {
      setState(() => _error = context.l10n.customerFieldFilterSelectFieldError);
      return;
    }

    final notifier = ref.read(customerFieldFilterProvider.notifier);
    notifier.select(definition);

    switch (definition.fieldType) {
      case 'DATE':
      case 'DATETIME':
        if ((_rangeFrom == null || _rangeFrom!.isEmpty) &&
            (_rangeTo == null || _rangeTo!.isEmpty)) {
          setState(
            () => _error = context.l10n.customerFieldFilterEnterValueError,
          );
          return;
        }
        if (_rangeFrom != null &&
            _rangeTo != null &&
            _rangeFrom!.isNotEmpty &&
            _rangeTo!.isNotEmpty &&
            _rangeFrom!.compareTo(_rangeTo!) > 0) {
          setState(() => _error = context.l10n.customerFieldFilterInvalidRange);
          return;
        }
        notifier.setRangeFrom(_rangeFrom);
        notifier.setRangeTo(_rangeTo);
      case 'MULTI_SELECT':
        if (_multiSelectValues.isEmpty) {
          setState(
            () => _error = context.l10n.customerFieldFilterSelectValueError,
          );
          return;
        }
        // The endpoint's `__contains` checks one value is present among the
        // customer's choices — send the first selected option; combining
        // several MULTI_SELECT choices in one request isn't part of the
        // documented contract.
        notifier.setValue(_multiSelectValues.first);
      case 'SELECT':
      case 'BOOLEAN':
        if (_selectValue == null || _selectValue!.isEmpty) {
          setState(
            () => _error = context.l10n.customerFieldFilterSelectValueError,
          );
          return;
        }
        notifier.setValue(_selectValue!);
      default:
        final text = _textController.text.trim();
        if (text.isEmpty) {
          setState(
            () => _error = context.l10n.customerFieldFilterEnterValueError,
          );
          return;
        }
        notifier.setValue(text);
    }

    Navigator.of(context).pop();
  }

  void _clear() {
    ref.read(customerFieldFilterProvider.notifier).clear();
    Navigator.of(context).pop();
  }

  Widget _valueControl() {
    final definition = _definition;
    if (definition == null) return const SizedBox.shrink();

    switch (definition.fieldType) {
      case 'BOOLEAN':
        return DropdownButtonFormField<String>(
          key: const Key('customer-field-filter-value'),
          initialValue: _selectValue,
          decoration: InputDecoration(
            labelText: context.l10n.customerFieldFilterValueLabel,
          ),
          items: [
            DropdownMenuItem(
              value: 'true',
              child: Text(context.l10n.customFieldYes),
            ),
            DropdownMenuItem(
              value: 'false',
              child: Text(context.l10n.customFieldNo),
            ),
          ],
          onChanged: (value) => setState(() => _selectValue = value),
        );
      case 'SELECT':
        return DropdownButtonFormField<String>(
          key: const Key('customer-field-filter-value'),
          initialValue: definition.options.any((o) => o.value == _selectValue)
              ? _selectValue
              : null,
          decoration: InputDecoration(
            labelText: context.l10n.customerFieldFilterValueLabel,
          ),
          items: [
            for (final option in definition.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) => setState(() => _selectValue = value),
        );
      case 'MULTI_SELECT':
        return InputDecorator(
          key: const Key('customer-field-filter-value'),
          decoration: InputDecoration(
            labelText: context.l10n.customerFieldFilterValueLabel,
          ),
          child: Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final option in definition.options)
                FilterChip(
                  key: Key('customer-field-filter-option-${option.value}'),
                  label: Text(option.label),
                  selected: _multiSelectValues.contains(option.value),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _multiSelectValues.add(option.value);
                    } else {
                      _multiSelectValues.remove(option.value);
                    }
                  }),
                ),
            ],
          ),
        );
      case 'DATE':
      case 'DATETIME':
        Widget dateField({required bool isFrom, required String label}) {
          final raw = isFrom ? _rangeFrom : _rangeTo;
          final shown = raw == null || raw.isEmpty
              ? context.l10n.customFieldNotSet
              : displayCustomFieldValue(context, definition, raw);
          return InputDecorator(
            key: Key(
              isFrom
                  ? 'customer-field-filter-range-from'
                  : 'customer-field-filter-range-to',
            ),
            decoration: InputDecoration(labelText: label),
            child: InkWell(
              onTap: () => _pickRangeDate(isFrom: isFrom),
              child: Row(
                children: [
                  Expanded(child: Text(shown)),
                  const Icon(Icons.event_outlined, size: 18),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dateField(
              isFrom: true,
              label: context.l10n.customerFieldFilterFromLabel,
            ),
            const SizedBox(height: Space.sm),
            dateField(
              isFrom: false,
              label: context.l10n.customerFieldFilterToLabel,
            ),
          ],
        );
      default:
        return TextField(
          key: const Key('customer-field-filter-value'),
          controller: _textController,
          keyboardType: switch (definition.fieldType) {
            'PHONE' => TextInputType.phone,
            'EMAIL' => TextInputType.emailAddress,
            'NUMBER' => TextInputType.number,
            'DECIMAL' => const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            _ => TextInputType.text,
          },
          decoration: InputDecoration(
            labelText: context.l10n.customerFieldFilterValueLabel,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveFilter = ref.watch(customerFieldFilterProvider) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<CustomerFieldDefinition>(
          key: const Key('customer-field-filter-field-picker'),
          initialValue: widget.picking,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.l10n.customerFieldFilterFieldLabel,
          ),
          items: [
            for (final definition in widget.definitions)
              DropdownMenuItem(
                value: definition,
                child: Text(definition.label),
              ),
          ],
          onChanged: _onDefinitionChanged,
        ),
        if (_definition != null) ...[
          const SizedBox(height: Space.md),
          _valueControl(),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
          ),
        ],
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasActiveFilter)
              TextButton(
                key: const Key('customer-field-filter-reset'),
                onPressed: _clear,
                child: Text(context.l10n.customerFieldFilterReset),
              ),
            const SizedBox(width: Space.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: Space.sm),
            FilledButton(
              key: const Key('customer-field-filter-apply'),
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _apply,
              child: Text(context.l10n.dateFilterApply),
            ),
          ],
        ),
      ],
    );
  }
}
