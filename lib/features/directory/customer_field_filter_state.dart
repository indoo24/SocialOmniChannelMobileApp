/// State and provider for the Customers screen's "Filter by field…" filter.
///
/// One custom field filter active at a time — the backend accepts up to five
/// combined `field__<key>[__operator]` params at once (see
/// `docs/api/openapi.yaml`, `/api/customers/`), but the mobile UI only ever
/// builds one, matching the single-term `search` filter already on this
/// screen. Selecting a different field replaces the old filter outright.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/customer_fields.dart';

/// How the field's value is compared, per `CustomerFieldDefinition.fieldType`:
/// - [equals] — `field__<key>=<value>`: NUMBER, DECIMAL, BOOLEAN, SELECT.
/// - [contains] — `field__<key>__contains=<value>`: TEXT, LONG_TEXT, PHONE,
///   EMAIL, MULTI_SELECT (checks the chosen option is among the customer's).
/// - [range] — `field__<key>__gte=<from>` and/or `field__<key>__lte=<to>`:
///   DATE, DATETIME.
enum CustomerFieldFilterOperator { equals, contains, range }

/// The operator a field's type is filtered with — the mobile side never
/// invents its own filtering behavior, it mirrors the type→operator mapping
/// the endpoint documents.
CustomerFieldFilterOperator operatorForFieldType(String fieldType) {
  switch (fieldType) {
    case 'TEXT':
    case 'LONG_TEXT':
    case 'PHONE':
    case 'EMAIL':
    case 'MULTI_SELECT':
      return CustomerFieldFilterOperator.contains;
    case 'DATE':
    case 'DATETIME':
      return CustomerFieldFilterOperator.range;
    default:
      // NUMBER, DECIMAL, BOOLEAN, SELECT, and any unknown future type.
      return CustomerFieldFilterOperator.equals;
  }
}

/// The active "Filter by field" selection, or absence of one.
@immutable
class CustomerFieldFilter {
  const CustomerFieldFilter({
    required this.definition,
    this.value,
    this.rangeFrom,
    this.rangeTo,
  });

  final CustomerFieldDefinition definition;

  /// The `equals`/`contains` value: a `String` for text-like and SELECT, or
  /// `'true'`/`'false'` for BOOLEAN. Unused for a [CustomerFieldFilterOperator.range] field.
  final String? value;

  /// Range bounds for DATE/DATETIME, as the API's own `YYYY-MM-DD` or ISO
  /// 8601 UTC instant strings. Either may be set alone.
  final String? rangeFrom;
  final String? rangeTo;

  CustomerFieldFilterOperator get operator =>
      operatorForFieldType(definition.fieldType);

  /// True once there is something to actually send to the API.
  bool get hasValue => switch (operator) {
    CustomerFieldFilterOperator.range =>
      (rangeFrom != null && rangeFrom!.isNotEmpty) ||
          (rangeTo != null && rangeTo!.isNotEmpty),
    _ => value != null && value!.isNotEmpty,
  };

  /// Builds the `field__<key>[__operator]` query entries this filter sends.
  /// Empty when [hasValue] is false — nothing to add to the request.
  Map<String, String> toQueryParams() {
    if (!hasValue) return const {};
    final key = definition.key;
    switch (operator) {
      case CustomerFieldFilterOperator.equals:
        return {'field__$key': value!};
      case CustomerFieldFilterOperator.contains:
        return {'field__${key}__contains': value!};
      case CustomerFieldFilterOperator.range:
        return {
          if (rangeFrom != null && rangeFrom!.isNotEmpty)
            'field__${key}__gte': rangeFrom!,
          if (rangeTo != null && rangeTo!.isNotEmpty)
            'field__${key}__lte': rangeTo!,
        };
    }
  }

  CustomerFieldFilter copyWith({
    String? value,
    bool clearValue = false,
    String? rangeFrom,
    bool clearRangeFrom = false,
    String? rangeTo,
    bool clearRangeTo = false,
  }) => CustomerFieldFilter(
    definition: definition,
    value: clearValue ? null : (value ?? this.value),
    rangeFrom: clearRangeFrom ? null : (rangeFrom ?? this.rangeFrom),
    rangeTo: clearRangeTo ? null : (rangeTo ?? this.rangeTo),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerFieldFilter &&
          runtimeType == other.runtimeType &&
          definition.key == other.definition.key &&
          value == other.value &&
          rangeFrom == other.rangeFrom &&
          rangeTo == other.rangeTo;

  @override
  int get hashCode => Object.hash(definition.key, value, rangeFrom, rangeTo);
}

class CustomerFieldFilterNotifier extends Notifier<CustomerFieldFilter?> {
  @override
  CustomerFieldFilter? build() => null;

  void select(CustomerFieldDefinition definition) {
    state = CustomerFieldFilter(definition: definition);
  }

  void setValue(String value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(value: value, clearValue: value.isEmpty);
  }

  void setRangeFrom(String? isoValue) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      rangeFrom: isoValue,
      clearRangeFrom: isoValue == null,
    );
  }

  void setRangeTo(String? isoValue) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(rangeTo: isoValue, clearRangeTo: isoValue == null);
  }

  void clear() => state = null;
}

/// The Customers screen's single active "Filter by field" selection.
final customerFieldFilterProvider =
    NotifierProvider<CustomerFieldFilterNotifier, CustomerFieldFilter?>(
      CustomerFieldFilterNotifier.new,
    );
