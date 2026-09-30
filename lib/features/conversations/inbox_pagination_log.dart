/// Development-only diagnostics for the Inbox's page-by-page loading.
///
/// Observability only: nothing here changes what is requested, parsed or shown.
/// Every line starts with `[INBOX_PAGINATION]` so it filters cleanly in Android
/// Studio or `adb logcat | findstr INBOX_PAGINATION`, and is a single line of
/// `key=value` pairs so a logcat split cannot separate a value from its event.
///
/// Goes through [AppLog.debug], the project's gate: compiled out of release
/// builds, and never written on a shipped app.
///
/// What is deliberately *not* logged: message text, customer names, phone
/// numbers, cookies, tokens, or the response body. The inbox `search=` term is
/// routinely a customer's name or number, so only its length is written — in
/// the query, the filter summary and the `next` / `previous` URLs alike. The
/// counts and ids that remain describe pages and channels, not people.
library;

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/logging/app_log.dart';
import '../../core/models/conversation.dart' show Paginated;
import '../../core/models/conversation_group.dart';
import 'conversation_repository.dart' show ConversationFilters;

class InboxPaginationLog {
  static const tag = 'INBOX_PAGINATION';

  /// Count / page numbers of the previous response, and the query it answered
  /// (page removed), so a change *within one filter state* can be flagged.
  String? _lastQueryKey;
  int? _lastCount;
  int? _lastTotalPages;

  static void _emit(String event, Map<String, Object?> fields) {
    if (!kDebugMode) return;
    final body = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    AppLog.debug(tag, body.isEmpty ? event : '$event $body');
  }

  static void _warn(String code, Map<String, Object?> fields) =>
      _emit('WARNING $code', fields);

  // -- request -------------------------------------------------------------

  /// A request for [page] is about to be sent to [endpoint].
  void fetchStart({
    required String endpoint,
    required int page,
    required ConversationFilters filters,
    required Map<String, dynamic> query,
  }) => _emit('FETCH_START', {
    'endpoint': endpoint,
    'requestedPage': page,
    'filters': describeFilters(filters),
    'query': describeQuery(query),
  });

  /// The API answered with a page. `httpStatus` is 200 here by construction:
  /// the API client only hands back a body for a successful response, and
  /// raises [ApiException] (see [error]) for anything else.
  void apiResponse({
    required String endpoint,
    required int requestedPage,
    required Paginated<CustomerConversationGroup> result,
    required Map<String, dynamic> query,
  }) {
    if (!kDebugMode) return;
    final hasNext = result.hasMore;
    final hasPrevious = (result.previous ?? '').isNotEmpty;
    _emit('API_RESPONSE', {
      'endpoint': endpoint,
      'requestedPage': requestedPage,
      'httpStatus': 200,
      'responsePage': result.page,
      'count': result.count,
      'pageSize': result.pageSize,
      'totalPages': result.totalPages,
      'resultsLength': result.results.length,
      // Rows the server sent, before per-row parsing: if this is larger than
      // resultsLength, the app dropped rows it could not parse.
      'rawResultsLength': result.rawResultsLength,
      'hasNext': hasNext,
      'hasPrevious': hasPrevious,
      'next': describeUrl(result.next),
      'previous': describeUrl(result.previous),
    });
    _checkResponse(
      requestedPage: requestedPage,
      result: result,
      query: query,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  /// The parsed page, as held in `InboxState.groups`. Counts only.
  void groupsParsed({
    required int requestedPage,
    required int responsePage,
    required int totalPages,
    required List<CustomerConversationGroup> groups,
  }) => _emit('GROUPS_PARSED', {
    'requestedPage': requestedPage,
    'responsePage': responsePage,
    'totalPages': totalPages,
    'groupsCount': groups.length,
    'conversationCountInsideGroups': groups.fold<int>(
      0,
      (sum, g) => sum + g.conversations.length,
    ),
  });

  // -- navigation and refreshes -------------------------------------------

  void pageChange({
    required int fromPage,
    required int toPage,
    required int knownTotalPages,
  }) => _emit('PAGE_CHANGE', {
    'fromPage': fromPage,
    'toPage': toPage,
    'knownTotalPages': knownTotalPages,
  });

  /// A page change that was not attempted — no request is made for it, which
  /// is itself worth knowing when hunting a "page N does not exist" report.
  void pageChangeRefused({
    required int fromPage,
    required int toPage,
    required int knownTotalPages,
    required String reason,
  }) => _emit('PAGE_CHANGE_REFUSED', {
    'fromPage': fromPage,
    'toPage': toPage,
    'knownTotalPages': knownTotalPages,
    'reason': reason,
  });

  /// One of `initial_load`, `filter_change`, `pull_to_refresh`, `realtime`
  /// (the quiet refresh, also used after the agent's own actions) or
  /// `manual_retry`.
  void refresh({required int currentPage, required String reason}) =>
      _emit('REFRESH', {'currentPage': currentPage, 'reason': reason});

  /// A quiet refresh that was held back because the agent is scrolled down.
  void refreshDeferred({required int currentPage, required String reason}) =>
      _emit('REFRESH_DEFERRED', {'currentPage': currentPage, 'reason': reason});

  // -- failures ------------------------------------------------------------

  void error({
    required String endpoint,
    required int requestedPage,
    required int? knownTotalPages,
    required Object error,
  }) {
    if (!kDebugMode) return;
    final status = error is ApiException ? error.statusCode : null;
    _emit('ERROR', {
      'endpoint': endpoint,
      'requestedPage': requestedPage,
      'httpStatus': status ?? 'none',
      'errorType': error.runtimeType,
      // ApiException messages are written to be safe to show (never a raw
      // body). Anything else could carry data, so it is not logged.
      'errorMessage': error is ApiException ? error.message : '<not logged>',
    });
    if (status == 404 && requestedPage > 1) {
      _emit('OUT_OF_RANGE', {
        'endpoint': endpoint,
        'requestedPage': requestedPage,
        'knownTotalPages': knownTotalPages ?? 'unknown',
        'httpStatus': status,
      });
    }
  }

  // -- consistency checks --------------------------------------------------

  void _checkResponse({
    required int requestedPage,
    required Paginated<CustomerConversationGroup> result,
    required Map<String, dynamic> query,
    required bool hasNext,
    required bool hasPrevious,
  }) {
    final page = result.page;
    final totalPages = result.totalPages;

    if (page > 0 && page != requestedPage) {
      _warn('RESPONSE_PAGE_MISMATCH', {
        'requestedPage': requestedPage,
        'responsePage': page,
      });
    }
    if (totalPages > 0 && requestedPage > totalPages) {
      _warn('PAGE_GT_TOTAL', {
        'requestedPage': requestedPage,
        'totalPages': totalPages,
      });
    }
    if (result.results.isEmpty && result.count > 0) {
      _warn('EMPTY_VALID_PAGE', {
        'page': page,
        'totalPages': totalPages,
        'count': result.count,
        'rawResultsLength': result.rawResultsLength,
      });
    }
    if (totalPages > 0 && page >= totalPages && hasNext) {
      _warn('NEXT_ON_LAST_PAGE', {
        'page': page,
        'totalPages': totalPages,
        'next': describeUrl(result.next),
      });
    }
    if (page > 1 && !hasPrevious) {
      _warn('MISSING_PREVIOUS', {
        'page': page,
        'previous': describeUrl(result.previous),
      });
    }

    // The same filters should keep answering with the same totals. (Live
    // traffic legitimately moves `count`; this flags it, it does not judge.)
    final key = _queryKey(query);
    if (_lastQueryKey == key &&
        (_lastCount != result.count || _lastTotalPages != totalPages)) {
      _warn('METADATA_CHANGED', {
        'previousCount': _lastCount,
        'currentCount': result.count,
        'previousTotalPages': _lastTotalPages,
        'currentTotalPages': totalPages,
        'page': page,
      });
    }
    _lastQueryKey = key;
    _lastCount = result.count;
    _lastTotalPages = totalPages;
  }

  // -- redaction -----------------------------------------------------------

  /// The query as sent, with the `search` term reduced to its length.
  static String describeQuery(Map<String, dynamic> query) {
    final safe = <String, Object?>{
      for (final e in query.entries)
        e.key: e.key == 'search' ? _redactedSearch('${e.value}') : e.value,
    };
    return '{${safe.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}';
  }

  /// [ConversationFilters] as flags, never the search text.
  static String describeFilters(ConversationFilters f) =>
      'status=${f.status} priority=${f.priority} provider=${f.provider} '
      'assignedToMe=${f.assignedToMe} unassigned=${f.unassigned} '
      'unread=${f.unread} searchLength=${f.search.trim().length} '
      'accounts=${f.selectedAccounts} '
      'channelConnections=${f.channelConnections}';

  /// A `next` / `previous` URL as path and query, without scheme or host, and
  /// with any `search` value redacted.
  static String describeUrl(String? url) {
    if (url == null || url.isEmpty) return 'null';
    final uri = Uri.tryParse(url);
    if (uri == null) return '<unparseable>';
    final params = <String, String>{
      for (final e in uri.queryParameters.entries)
        e.key: e.key == 'search' ? _redactedSearch(e.value) : e.value,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }

  static String _redactedSearch(String value) =>
      '<redacted:${value.length} chars>';

  /// The query without its page, so two pages of one filter state compare
  /// equal.
  static String _queryKey(Map<String, dynamic> query) {
    final keys = query.keys.where((k) => k != 'page').toList()..sort();
    return keys.map((k) => '$k=${query[k]}').join('&');
  }
}
