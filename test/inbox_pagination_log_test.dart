/// `[INBOX_PAGINATION]` diagnostics: enough to tell, from a device log alone,
/// what page was asked for, from which endpoint, with what query, what the API
/// said back, and how many groups the app parsed — without writing any
/// customer data. Observability only: these tests also confirm the logging
/// does not change what the controller does.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_pagination_log.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';

// Personal data the fixtures carry — none of it may reach a log line.
const _phone = '+201069171483';
const _name = 'Mona Hassan';
const _preview = 'my card number is 4111';

Map<String, dynamic> _group(int i) => {
  'group_key': 'WHATSAPP_$i',
  'customer': {'id': i, 'display_name': '$_name $i', 'phone': _phone},
  'conversation_count': 1,
  'providers': ['WHATSAPP'],
  'conversations': [
    {
      'id': i,
      'customer': {'id': i, 'display_name': '$_name $i', 'phone': _phone},
      'provider': 'WHATSAPP',
      'channel_id': 5,
      'channel_name': 'Line 5',
      'status': 'OPEN',
      'priority': 'NORMAL',
      'unread_count': 0,
      'message_count': 1,
      'last_message_preview': _preview,
    },
  ],
};

typedef _Tamper =
    Map<String, dynamic> Function(int page, Map<String, dynamic> response);

class _Server implements HttpClientAdapter {
  _Server(
    this.groups, {
    this.reportedTotalPages,
    this.tamper,
    this.failPages = const {},
  });

  int groups;
  final int? reportedTotalPages;
  final _Tamper? tamper;
  final Set<int> failPages;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    if (!options.uri.path.endsWith('/conversations/grouped/')) return _json({});
    final q = options.uri.queryParameters;
    final size = int.tryParse(q['page_size'] ?? '') ?? 30;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    if (failPages.contains(page)) {
      return _json({
        'error': {'code': 'server_error', 'message': 'Boom.'},
      }, 500);
    }
    final actual = groups == 0 ? 1 : (groups + size - 1) ~/ size;
    if (page > actual) {
      return _json({
        'error': {'code': 'not_found', 'message': 'Invalid page.'},
      }, 404);
    }
    final start = (page - 1) * size;
    final end = (start + size).clamp(0, groups);
    final total = reportedTotalPages ?? actual;
    var body = <String, dynamic>{
      'count': groups,
      'page': page,
      'page_size': size,
      'total_pages': total,
      'next': page < total
          ? 'https://x.test/api/conversations/grouped/?page=${page + 1}'
                '&search=$_name'
          : null,
      'previous': page > 1
          ? 'https://x.test/api/conversations/grouped/?page=${page - 1}'
          : null,
      'results': [for (var i = start + 1; i <= end; i++) _group(i)],
    };
    if (tamper != null) body = tamper!(page, body);
    return _json(body);
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

final _employee = Employee(
  id: 7,
  email: 'agent@acme.test',
  fullName: 'Agent',
  initials: 'AG',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

ProviderContainer _container(_Server server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWith((ref) => _employee),
      channelsProvider.overrideWith((ref) async => const <ChannelConnection>[]),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

InboxController _inbox(ProviderContainer c) =>
    c.read(inboxControllerProvider.notifier);

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() => debugPrint = originalDebugPrint);

  List<String> pagination() =>
      logs.where((l) => l.startsWith('[INBOX_PAGINATION]')).toList();

  List<String> events(String event) =>
      pagination().where((l) => l.contains('] $event ')).toList();

  bool has(String event, List<String> parts) =>
      events(event).any((line) => parts.every((part) => line.contains(part)));

  group('a full navigation leaves a readable trail', () {
    test('request, response, parse and page change for each page', () async {
      final container = _container(_Server(90)); // 3 pages of 30
      await container.read(inboxControllerProvider.future);
      await _inbox(container).goToPage(2);
      await _inbox(container).goToPage(3);

      // The endpoint and the query actually sent.
      expect(
        has('FETCH_START', [
          'endpoint=/conversations/grouped/',
          'requestedPage=2',
          'query={page: 2}',
        ]),
        isTrue,
      );
      // What the API said back, and the status.
      expect(
        has('API_RESPONSE', [
          'endpoint=/conversations/grouped/',
          'requestedPage=2',
          'httpStatus=200',
          'responsePage=2',
          'count=90',
          'pageSize=30',
          'totalPages=3',
          'resultsLength=30',
          'rawResultsLength=30',
          'hasNext=true',
          'hasPrevious=true',
        ]),
        isTrue,
      );
      // What the app parsed: counts only.
      expect(
        has('GROUPS_PARSED', [
          'requestedPage=2',
          'responsePage=2',
          'totalPages=3',
          'groupsCount=30',
          'conversationCountInsideGroups=30',
        ]),
        isTrue,
      );
      expect(
        has('PAGE_CHANGE', ['fromPage=1', 'toPage=2', 'knownTotalPages=3']),
        isTrue,
      );
      expect(
        has('PAGE_CHANGE', ['fromPage=2', 'toPage=3', 'knownTotalPages=3']),
        isTrue,
      );
      // The flat endpoint is never the one called.
      expect(
        pagination().any((l) => l.contains('endpoint=/conversations/ ')),
        isFalse,
      );
      // A healthy run raises no warning.
      expect(pagination().any((l) => l.contains('WARNING')), isFalse);
    });

    test(
      'a page past the known total is refused, and the log says so',
      () async {
        final container = _container(_Server(90));
        await container.read(inboxControllerProvider.future);
        final requestsBefore = events('FETCH_START').length;

        await _inbox(container).goToPage(4);

        expect(
          has('PAGE_CHANGE_REFUSED', [
            'fromPage=1',
            'toPage=4',
            'knownTotalPages=3',
            'reason=outside_known_total_pages',
          ]),
          isTrue,
        );
        expect(events('FETCH_START').length, requestsBefore);
      },
    );
  });

  group('refresh reasons', () {
    test('initial_load, realtime, pull_to_refresh, filter_change, '
        'manual_retry', () async {
      final server = _Server(90, failPages: {2});
      final container = _container(server);
      await container.read(inboxControllerProvider.future);
      expect(has('REFRESH', ['currentPage=1', 'reason=initial_load']), isTrue);

      await _inbox(container).refreshQuietly();
      expect(has('REFRESH', ['reason=realtime']), isTrue);

      await _inbox(container).refresh();
      expect(has('REFRESH', ['reason=pull_to_refresh']), isTrue);

      // Page 2 fails once; the retry is logged as manual_retry.
      await _inbox(container).goToPage(2);
      server.failPages.clear();
      await _inbox(container).retryPage();
      expect(has('REFRESH', ['currentPage=2', 'reason=manual_retry']), isTrue);

      container
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      await container.read(inboxControllerProvider.future);
      expect(has('REFRESH', ['reason=filter_change']), isTrue);
    });
  });

  group('errors', () {
    test('an HTTP failure names the status and error type', () async {
      final container = _container(_Server(90, failPages: {2}));
      await container.read(inboxControllerProvider.future);

      await _inbox(container).goToPage(2);

      expect(
        has('ERROR', [
          'endpoint=/conversations/grouped/',
          'requestedPage=2',
          'httpStatus=500',
          'errorType=ApiException',
          'errorMessage=',
        ]),
        isTrue,
      );
      expect(events('OUT_OF_RANGE'), isEmpty);
    });

    test('a genuinely out-of-range page is called out — the server said 404, '
        'nothing was dropped client-side', () async {
      // The server reports 592 pages but only has 3: asking for page 4 gets
      // a real 404. That is what "page 593 does not exist" looks like.
      final container = _container(_Server(90, reportedTotalPages: 592));
      await container.read(inboxControllerProvider.future);

      await _inbox(container).goToPage(4);

      expect(
        has('OUT_OF_RANGE', [
          'requestedPage=4',
          'knownTotalPages=592',
          'httpStatus=404',
        ]),
        isTrue,
      );
    });
  });

  group('inconsistency warnings', () {
    Future<void> load(_Server server, {int goTo = 1}) async {
      final container = _container(server);
      await container.read(inboxControllerProvider.future);
      if (goTo != 1) await _inbox(container).goToPage(goTo);
    }

    test('RESPONSE_PAGE_MISMATCH', () async {
      await load(
        _Server(90, tamper: (page, r) => page == 2 ? {...r, 'page': 5} : r),
        goTo: 2,
      );
      expect(
        has('WARNING RESPONSE_PAGE_MISMATCH', [
          'requestedPage=2',
          'responsePage=5',
        ]),
        isTrue,
      );
    });

    test('PAGE_GT_TOTAL', () async {
      // Asks for page 3 (reported total 4 while it is being asked), then the
      // response claims only 2 pages.
      await load(
        _Server(
          90,
          reportedTotalPages: 4,
          tamper: (page, r) => page == 3 ? {...r, 'total_pages': 2} : r,
        ),
        goTo: 3,
      );
      expect(
        has('WARNING PAGE_GT_TOTAL', ['requestedPage=3', 'totalPages=2']),
        isTrue,
      );
    });

    test('EMPTY_VALID_PAGE', () async {
      await load(
        _Server(90, tamper: (page, r) => page == 2 ? {...r, 'results': []} : r),
        goTo: 2,
      );
      expect(
        has('WARNING EMPTY_VALID_PAGE', [
          'page=2',
          'totalPages=3',
          'count=90',
          'rawResultsLength=0',
        ]),
        isTrue,
      );
    });

    test('rows the app could not parse are visible as raw > parsed', () async {
      await load(
        _Server(
          90,
          tamper: (page, r) => {
            ...r,
            'results': [
              {'group_key': 'no-threads', 'customer': {}, 'conversations': []},
              ...(r['results'] as List).take(29),
            ],
          },
        ),
      );
      expect(
        has('API_RESPONSE', ['resultsLength=29', 'rawResultsLength=30']),
        isTrue,
      );
    });

    test('NEXT_ON_LAST_PAGE', () async {
      await load(
        _Server(
          90,
          tamper: (page, r) =>
              page == 3 ? {...r, 'next': 'https://x.test/?page=4'} : r,
        ),
        goTo: 3,
      );
      expect(
        has('WARNING NEXT_ON_LAST_PAGE', ['page=3', 'totalPages=3']),
        isTrue,
      );
    });

    test('MISSING_PREVIOUS', () async {
      await load(
        _Server(
          90,
          tamper: (page, r) => page == 2 ? {...r, 'previous': null} : r,
        ),
        goTo: 2,
      );
      expect(
        has('WARNING MISSING_PREVIOUS', ['page=2', 'previous=null']),
        isTrue,
      );
    });

    test('METADATA_CHANGED — same filters, different totals', () async {
      final server = _Server(90);
      final container = _container(server);
      await container.read(inboxControllerProvider.future);

      server.groups = 120; // the list grew between two responses
      await _inbox(container).refreshQuietly();

      expect(
        has('WARNING METADATA_CHANGED', [
          'previousCount=90',
          'currentCount=120',
          'previousTotalPages=3',
          'currentTotalPages=4',
          'page=1',
        ]),
        isTrue,
      );
    });

    test('a different filter state is not a metadata change', () async {
      final server = _Server(90);
      final container = _container(server);
      await container.read(inboxControllerProvider.future);

      server.groups = 20;
      container
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      await container.read(inboxControllerProvider.future);

      expect(events('WARNING METADATA_CHANGED'), isEmpty);
    });
  });

  group('no personal data in the log', () {
    test(
      'search text, names, phone numbers and previews never appear',
      () async {
        final container = _container(_Server(90));
        container
            .read(inboxFiltersProvider.notifier)
            .update(const ConversationFilters(search: _name));
        await container.read(inboxControllerProvider.future);
        await _inbox(container).goToPage(2);

        final all = pagination().join('\n');
        expect(all, isNotEmpty);
        for (final secret in [
          _name,
          'Mona',
          'Hassan',
          _phone,
          '1069171483',
          _preview,
          'card number',
        ]) {
          expect(all, isNot(contains(secret)), reason: '"$secret" leaked');
        }
        // The search term is accounted for by its length only — in the query,
        // the filter summary and the `next` URL the server echoed it in.
        expect(all, contains('search: <redacted:11 chars>'));
        expect(all, contains('searchLength=11'));
        expect(all, contains('search=<redacted:11 chars>'));
      },
    );

    test('helpers redact directly', () {
      expect(
        InboxPaginationLog.describeQuery({'page': 3, 'search': 'Mona'}),
        '{page: 3, search: <redacted:4 chars>}',
      );
      expect(
        InboxPaginationLog.describeUrl(
          'https://scenariomnchnl.tech/api/conversations/grouped/'
          '?page=2&search=01069171483',
        ),
        '/api/conversations/grouped/?page=2&search=<redacted:11 chars>',
      );
      expect(InboxPaginationLog.describeUrl(null), 'null');
    });
  });
}
