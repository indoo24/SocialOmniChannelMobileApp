/// Organization-defined customer fields, from `GET /customers/{id}/fields/`.
///
/// The server owns every rule for these values (`apps/customers/fields.py`):
/// it validates each type and stores one canonical form. This app only chooses
/// a control by [CustomerFieldDefinition.fieldType], sends what the employee
/// entered, and shows the server's message when it is refused — the type rules
/// are deliberately not re-implemented in Dart.
library;

import '../utils/json_safe.dart';

class CustomerFieldOption {
  const CustomerFieldOption({required this.value, required this.label});

  /// What is stored. Stable once customers use it.
  final String value;

  /// What people see.
  final String label;

  factory CustomerFieldOption.fromJson(Map<String, dynamic> json) {
    final value = JsonSafe.asString(json['value']);
    return CustomerFieldOption(
      value: value,
      label: JsonSafe.asString(json['label'], fallback: value),
    );
  }
}

class CustomerFieldDefinition {
  const CustomerFieldDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.fieldType,
    this.options = const [],
    this.required = false,
    this.isActive = true,
    this.helpText = '',
    this.placeholder = '',
  });

  final int id;

  /// Stable machine identifier, e.g. `birth_date`.
  final String key;
  final String label;

  /// TEXT · LONG_TEXT · NUMBER · DECIMAL · DATE · DATETIME · BOOLEAN · SELECT ·
  /// MULTI_SELECT · PHONE · EMAIL. An unknown type from a newer server is
  /// edited as plain text.
  final String fieldType;
  final List<CustomerFieldOption> options;
  final bool required;
  final bool isActive;
  final String helpText;
  final String placeholder;

  String labelForOption(String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  factory CustomerFieldDefinition.fromJson(Map<String, dynamic> json) =>
      CustomerFieldDefinition(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        key: JsonSafe.asString(json['key']),
        label: JsonSafe.asString(json['label']),
        fieldType: JsonSafe.asString(json['field_type'], fallback: 'TEXT'),
        options: JsonSafe.parseList(json['options'], CustomerFieldOption.fromJson),
        required: JsonSafe.asBool(json['required']),
        isActive: JsonSafe.asBool(json['is_active'], fallback: true),
        helpText: JsonSafe.asString(json['help_text']),
        placeholder: JsonSafe.asString(json['placeholder']),
      );
}

class CustomerFieldRow {
  const CustomerFieldRow({
    required this.definition,
    this.value,
    this.factId,
    this.updatedByName = '',
  });

  final CustomerFieldDefinition definition;

  /// As the API sends it: `bool` for yes/no, `int` for whole numbers,
  /// `List<String>` for multiple choice, `String` otherwise. Null when nothing
  /// is recorded — no row exists on the server for it.
  final Object? value;
  final int? factId;
  final String updatedByName;

  bool get hasValue {
    final current = value;
    if (current == null) return false;
    if (current is String) return current.isNotEmpty;
    if (current is List) return current.isNotEmpty;
    return true;
  }

  factory CustomerFieldRow.fromJson(Map<String, dynamic> json) {
    final rawValue = json['value'];
    return CustomerFieldRow(
      definition: CustomerFieldDefinition.fromJson(
        JsonSafe.asMap(json['definition']),
      ),
      value: rawValue is List
          ? rawValue.map((item) => item.toString()).toList()
          : rawValue,
      factId: JsonSafe.asIntOrNull(json['fact_id']),
      updatedByName: JsonSafe.asString(json['updated_by_name']),
    );
  }
}
