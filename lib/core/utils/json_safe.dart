/// Parsing helpers for data the app did not produce.
///
/// ## The failure this prevents
///
/// Every model's `fromJson` cast its identifier directly — `json['id'] as int`
/// — and every list mapped its elements the same way: `item as Map`. A cast is
/// not a check. If the value is a string, a double, null, or absent, the cast
/// throws `TypeError`, and `TypeError` is not `ApiException`, so none of the
/// `on ApiException catch` handlers that guard the repositories and controllers
/// catch it. It travels up as an unhandled error: a red screen on the affected
/// widget, an `AsyncError` the retry button cannot clear, or — on the realtime
/// path, where `Message.fromJson` runs on every inbound `message.created`
/// event — a broken conversation view for as long as the offending event keeps
/// arriving.
///
/// Reaching it does not require a malicious server. A serializer change that
/// starts emitting a numeric id as a string, a field that becomes nullable, an
/// error envelope returned with a 200 — each produces the same crash. A
/// compromised backend or an attacker positioned to inject a WebSocket frame
/// can produce it deliberately, which is what makes robustness here a security
/// property and not only a reliability one.
///
/// ## The rule
///
/// Accept what is unambiguously convertible, reject the rest by returning the
/// documented fallback. Never guess: [asInt] parses `"42"` because the wire
/// format for an integer id is genuinely either, but it will not turn `"abc"`
/// or `true` into a number.
library;

class JsonSafe {
  const JsonSafe._();

  /// An integer from an int, a whole double, or a numeric string.
  ///
  /// Returns [fallback] for anything else. Use `-1` (or another impossible id)
  /// as the fallback for identifiers so a malformed record is visibly wrong
  /// rather than silently colliding with a real row at id 0.
  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  /// A nullable integer, for genuinely optional identifiers.
  static int? asIntOrNull(Object? value) {
    if (value is int) return value;
    if (value is double && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// A string map, whatever key type the decoder produced.
  ///
  /// `jsonDecode` yields `Map<String, dynamic>`, but a map that has been
  /// through `Map.from`, a plugin channel, or a nested cast can arrive as
  /// `Map<dynamic, dynamic>` — which `as Map<String, dynamic>` rejects.
  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }

  /// The list elements that are objects, as string maps. Non-object elements
  /// are dropped rather than throwing, so one malformed row in a page does not
  /// cost the whole page.
  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(asMap).toList(growable: false);
  }

  /// Parse every element that survives [asMapList], dropping any that throws.
  ///
  /// The per-element guard is what keeps a single bad record from emptying a
  /// list: an inbox page with one unparseable conversation shows the other
  /// nineteen.
  static List<T> parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) {
    final out = <T>[];
    for (final item in asMapList(value)) {
      try {
        out.add(parse(item));
      } on Object {
        // Skip the element; a malformed row is not a malformed page.
      }
    }
    return out;
  }

  /// The raw elements of a list, or empty when the value is not a list.
  ///
  /// For the sites that pluck one field out of each element rather than
  /// parsing a whole model. `as List?` is not enough on its own: it throws on
  /// a String or a Map, which is exactly the malformed-payload case.
  static List<Object?> asObjectList(Object? value) {
    if (value is! List) return const [];
    return value;
  }

  /// Non-null string, defaulting to [fallback]. Numbers are stringified,
  /// because an id rendered into a label is legitimately either on the wire.
  static String asString(Object? value, {String fallback = ''}) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return fallback;
  }

  /// Strings from a list, dropping non-strings.
  static List<String> asStringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
