/// Typed failures.
///
/// The backend returns a consistent envelope for errors::
///
///     {"error": {"code": "...", "message": "...", "details": {...}}}
///
/// The message is written for a human and is safe to display — the backend is
/// careful never to leak tokens or internals into it — so the UI shows it
/// rather than inventing its own wording and losing the specific advice the
/// server actually gave.
///
/// The one exception is a server-side object dump arriving *as* the message:
/// sign-in has been seen returning the Python repr
/// `[ErrorDetail(string='…', code='invalid_credentials')]`, which breaks the
/// contract above. [ApiException.fromResponse] never passes such text through
/// as [ApiException.message]; it keeps any code named inside it and falls back
/// to plain wording instead.
library;

class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.code = 'error',
    this.details = const {},
  });

  final int statusCode;
  final String message;
  final String code;
  final Map<String, dynamic> details;

  factory ApiException.fromResponse(int status, dynamic body) {
    if (body is Map && body['error'] is Map) {
      final error = Map<String, dynamic>.from(body['error'] as Map);
      final rawDetails = error['details'] is Map
          ? Map<String, dynamic>.from(error['details'] as Map)
          : const <String, dynamic>{};
      var rawMessage = error['message'] as String?;

      // An object dump is not a message. Drop it as display text — treating it
      // like an absent message, so the details fallback below still gets its
      // chance — but keep any code it names: that is the backend's real reason.
      String? embeddedCode;
      if (rawMessage != null && _looksInternal(rawMessage)) {
        embeddedCode = _embeddedCode.firstMatch(rawMessage)?.group(1);
        rawMessage = null;
      }
      // Same for a dump inside details — but only a dump. Scanning clean
      // details would let ordinary text containing "code='…'" re-route the
      // error.
      final detailsText = rawDetails.toString();
      if (embeddedCode == null && _looksInternal(detailsText)) {
        embeddedCode = _embeddedCode.firstMatch(detailsText)?.group(1);
      }

      // A specific envelope code wins as sent. Only a generic one is upgraded,
      // and only to a code the backend itself wrote into the dump.
      final envelopeCode = error['code'] as String?;
      final code =
          (envelopeCode == null || _genericCodes.contains(envelopeCode)) &&
              embeddedCode != null
          ? embeddedCode
          : (envelopeCode ?? 'error');

      // If the backend envelope provided the generic headline "The submitted data was invalid."
      // (or empty), check whether details contains specific field-level validation errors.
      // If so, surface the first specific field error as the message fallback, so components
      // relying on error.message show helpful advice rather than the generic placeholder.
      String resolvedMessage = rawMessage ?? _fallbackFor(status);
      if ((rawMessage == null ||
              rawMessage.trim().isEmpty ||
              rawMessage == 'The submitted data was invalid.') &&
          rawDetails.isNotEmpty) {
        final firstFieldMsg = _extractFirstMessage(rawDetails);
        if (firstFieldMsg != null && firstFieldMsg.isNotEmpty) {
          resolvedMessage = firstFieldMsg;
        }
      }

      return ApiException(
        statusCode: status,
        message: resolvedMessage,
        code: code,
        details: rawDetails,
      );
    }

    // DRF's own validation errors are a flat field->messages map rather than
    // Scenario's envelope. Surface the first one instead of "error".
    if (body is Map && body.isNotEmpty) {
      final details = Map<String, dynamic>.from(body);
      final firstMsg = _extractFirstMessage(details);
      return ApiException(
        statusCode: status,
        message: firstMsg ?? _fallbackFor(status),
        code: 'invalid',
        details: details,
      );
    }

    return ApiException(statusCode: status, message: _fallbackFor(status));
  }

  /// Codes that only say "the input was wrong" — too generic to route on.
  static const _genericCodes = {'error', 'invalid', 'validation_error'};

  /// The `code='…'` a DRF `ErrorDetail` repr carries.
  static final _embeddedCode = RegExp(r"code='([A-Za-z0-9_]+)'");

  /// True for a server-side object dump rather than prose: a DRF
  /// `ErrorDetail` repr, a Python traceback, a class repr. Kept narrow on
  /// purpose — a false positive would hide a real message a user needs.
  static bool _looksInternal(String text) =>
      text.contains('ErrorDetail(') ||
      text.contains('Traceback (most recent call last)') ||
      text.contains("<class '");

  static String? _extractFirstMessage(Map<String, dynamic> map) {
    for (final entry in map.entries) {
      final val = entry.value;
      if (val is List && val.isNotEmpty) {
        final strings = val
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty && !_looksInternal(s))
            .toList();
        if (strings.isNotEmpty) return strings.join('\n');
      } else if (val is String &&
          val.trim().isNotEmpty &&
          !_looksInternal(val)) {
        return val.trim();
      } else if (val is Map) {
        final nested = _extractFirstMessage(Map<String, dynamic>.from(val));
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// True when the backend refused on permission grounds.
  ///
  /// The UI hides actions the employee cannot perform, but the backend is the
  /// authority — this is the case where the two disagreed and the server won.
  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  /// Per-field messages, for rendering next to form inputs.
  ///
  /// Multiple errors for a single field are joined with `\n` so that all
  /// validation requirements from the server are visible to the user.
  Map<String, String> fieldErrors() {
    final result = <String, String>{};
    details.forEach((field, value) {
      if (value is List && value.isNotEmpty) {
        final strings = value
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (strings.isNotEmpty) {
          result[field] = strings.join('\n');
        }
      } else if (value is String && value.trim().isNotEmpty) {
        result[field] = value.trim();
      } else if (value != null && value is! Map) {
        result[field] = value.toString();
      }
    });
    return result;
  }

  /// Returns a list of all validation messages for [field].
  List<String> fieldErrorList(String field) {
    final val = details[field];
    if (val is List) {
      return val
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (val is String && val.trim().isNotEmpty) {
      return [val.trim()];
    } else if (val != null && val is! Map) {
      return [val.toString()];
    }
    return const [];
  }

  /// Returns the joined validation message for [field], or null if no error.
  String? fieldError(String field) {
    final list = fieldErrorList(field);
    return list.isEmpty ? null : list.join('\n');
  }

  /// Convenience helper to extract password validation errors from [details].
  ///
  /// Checks `password`, `new_password` (if [includeNewPassword]), and
  /// `current_password` (if [includeCurrentPassword]).
  String? passwordError({
    bool includeNewPassword = true,
    bool includeCurrentPassword = false,
  }) {
    final pass = fieldError('password');
    if (pass != null) return pass;

    if (includeNewPassword) {
      final newPass = fieldError('new_password');
      if (newPass != null) return newPass;
    }

    if (includeCurrentPassword) {
      final currPass = fieldError('current_password');
      if (currPass != null) return currPass;
    }

    return null;
  }

  static String _fallbackFor(int status) => switch (status) {
    400 => 'That request was not valid.',
    403 => 'You do not have permission to do that.',
    404 => 'Not found.',
    // Usually the reverse proxy's own refusal (an HTML page, not the
    // envelope), so there is no server message to show instead.
    413 => 'That file is too large to send.',
    429 => 'Too many requests. Please wait a moment.',
    >= 500 => 'The server had a problem. Please try again.',
    _ => 'Something went wrong.',
  };

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// The session lapsed or was never established.
///
/// Distinct from a generic 401 body because the app reacts to it structurally:
/// clear credentials, return to login, preserve where the user was going.
class SessionExpiredException extends ApiException {
  SessionExpiredException()
    : super(
        statusCode: 401,
        code: 'session_expired',
        message: 'Your session has expired. Please sign in again.',
      );
}

/// Transport failed — no connection, timeout, DNS, TLS.
///
/// Separated from ApiException because it is retryable and the UI says so,
/// whereas a 400 will fail identically no matter how many times it is sent.
class NetworkException extends ApiException {
  NetworkException(String message)
    : super(statusCode: 0, code: 'network', message: message);

  bool get isRetryable => true;
}

/// The caller abandoned the request on purpose (a cancelled upload, a
/// screen that closed mid-transfer). Not a failure: nothing to show, nothing
/// to retry.
class RequestCancelledException extends ApiException {
  RequestCancelledException()
    : super(statusCode: 0, code: 'cancelled', message: 'Cancelled.');
}
