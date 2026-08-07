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
      return ApiException(
        statusCode: status,
        message: (error['message'] as String?) ?? _fallbackFor(status),
        code: (error['code'] as String?) ?? 'error',
        details: error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : const {},
      );
    }

    // DRF's own validation errors are a flat field->messages map rather than
    // Scenario's envelope. Surface the first one instead of "error".
    if (body is Map && body.isNotEmpty) {
      final first = body.values.first;
      final text = first is List && first.isNotEmpty ? first.first : first;
      return ApiException(
        statusCode: status,
        message: text?.toString() ?? _fallbackFor(status),
        code: 'invalid',
        details: Map<String, dynamic>.from(body),
      );
    }

    return ApiException(statusCode: status, message: _fallbackFor(status));
  }

  /// True when the backend refused on permission grounds.
  ///
  /// The UI hides actions the employee cannot perform, but the backend is the
  /// authority — this is the case where the two disagreed and the server won.
  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  /// Per-field messages, for rendering next to form inputs.
  Map<String, String> fieldErrors() {
    final result = <String, String>{};
    details.forEach((field, value) {
      result[field] = value is List && value.isNotEmpty
          ? value.first.toString()
          : value.toString();
    });
    return result;
  }

  static String _fallbackFor(int status) => switch (status) {
        400 => 'That request was not valid.',
        403 => 'You do not have permission to do that.',
        404 => 'Not found.',
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
