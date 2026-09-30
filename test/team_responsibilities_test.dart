/// Team channel responsibilities: `TeamWrite.responsibilities` construction
/// in the Add/Edit Team sheet, and seeding current state from
/// `GET /api/routing/responsibilities/` (the only source for it, since
/// `Team` itself carries no `responsibilities` field on read).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/routing_policy.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/team_form_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Finder _sheetScrollable() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(ListView),
);

Future<void> _scrollToAndTapSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Save'),
    _sheetScrollable(),
    const Offset(0, -400),
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Future<void> _scrollToErrorBanner(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byType(InlineError),
    _sheetScrollable(),
    const Offset(0, 400),
  );
  await tester.pumpAndSettle();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _channelsJson = '''
{
  "count": 3, "next": null, "previous": null,
  "results": [
    {"id": 1, "provider": "WHATSAPP", "display_name": "Sales Line",
     "status": "CONNECTED", "is_active": true},
    {"id": 2, "provider": "WHATSAPP", "display_name": "Support Line",
     "status": "CONNECTED", "is_active": true},
    {"id": 3, "provider": "INSTAGRAM", "display_name": "Brand IG",
     "status": "CONNECTED", "is_active": true}
  ]
}
''';

_StubAdapter _adapter({
  FutureOr<ResponseBody> Function(RequestOptions options)? extra,
  String responsibilitiesJson = '[]',
}) {
  return _StubAdapter((options) async {
    final path = options.path;
    if (extra != null) {
      final result = await extra(options);
      if (result.statusCode != 599) return result;
    }
    if (path == '/channels/' && options.method == 'GET') {
      return _json(_channelsJson, 200);
    }
    if (path == '/routing/responsibilities/' && options.method == 'GET') {
      return _json(responsibilitiesJson, 200);
    }
    if (path == '/employees/' && options.method == 'GET') {
      return _json(
        '{"count": 0, "next": null, "previous": null, "results": []}',
        200,
      );
    }
    return _json('{}', 200);
  });
}

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Employee _adminEmployee() => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.teamView, Perm.teamManage},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_adminEmployee()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

const _team = Team(
  id: 5,
  name: 'Support',
  color: '#0F766E',
  language: 'en',
  isActive: true,
  memberCount: 2,
  leaderNames: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Team responsibilities — display', () {
    testWidgets('a new team shows None for every provider', (tester) async {
      final client = _clientFrom(_adapter());

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddTeamSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Channel responsibilities'),
        _sheetScrollable(),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Channel responsibilities'), findsOneWidget);
      expect(find.text('None'), findsNWidgets(4));
    });

    testWidgets(
      'an existing team with a whole-provider rule shows All accounts',
      (tester) async {
        final client = _clientFrom(
          _adapter(
            responsibilitiesJson: '''
              [
                {"id": 1, "team": {"id": 5, "name": "Support", "is_active": true},
                 "employee": null, "provider": "WHATSAPP",
                 "channel_connection": null, "is_active": true}
              ]
            ''',
          ),
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEditTeamSheet(ctx, team: _team),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Channel responsibilities'),
          _sheetScrollable(),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();

        expect(find.text('All accounts'), findsOneWidget);
        expect(find.text('None'), findsNWidgets(3));
      },
    );

    testWidgets(
      'an existing team with channel-specific rules shows Selected accounts '
      'and pre-checks the right channels',
      (tester) async {
        final client = _clientFrom(
          _adapter(
            responsibilitiesJson: '''
              [
                {"id": 1, "team": {"id": 5, "name": "Support", "is_active": true},
                 "employee": null, "provider": "WHATSAPP",
                 "channel_connection": {"id": 1, "display_name": "Sales Line",
                   "provider": "WHATSAPP", "is_active": true},
                 "is_active": true}
              ]
            ''',
          ),
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEditTeamSheet(ctx, team: _team),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Channel responsibilities'),
          _sheetScrollable(),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();

        expect(find.text('Selected accounts'), findsOneWidget);
        expect(find.text('Sales Line'), findsOneWidget);
        expect(find.text('Support Line'), findsOneWidget);

        final salesLineChip = tester.widget<FilterChip>(
          find.ancestor(
            of: find.text('Sales Line'),
            matching: find.byType(FilterChip),
          ),
        );
        expect(salesLineChip.selected, isTrue);

        final supportLineChip = tester.widget<FilterChip>(
          find.ancestor(
            of: find.text('Support Line'),
            matching: find.byType(FilterChip),
          ),
        );
        expect(supportLineChip.selected, isFalse);
      },
    );

    testWidgets(
      'a retired (inactive) responsibility rule is not shown as current',
      (tester) async {
        final client = _clientFrom(
          _adapter(
            responsibilitiesJson: '''
              [
                {"id": 1, "team": {"id": 5, "name": "Support", "is_active": true},
                 "employee": null, "provider": "WHATSAPP",
                 "channel_connection": null, "is_active": false}
              ]
            ''',
          ),
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEditTeamSheet(ctx, team: _team),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Channel responsibilities'),
          _sheetScrollable(),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();

        expect(find.text('None'), findsNWidgets(4));
      },
    );
  });

  group('Team responsibilities — submission', () {
    testWidgets('Add Team omits responsibilities when nothing was set', (
      tester,
    ) async {
      RequestOptions? captured;
      final adapter = _adapter(
        extra: (options) {
          if (options.path == '/teams/' && options.method == 'POST') {
            captured = options;
            return _json(
              '{"id": 9, "name": "New Team", "color": "", "language": "",'
              ' "is_active": true, "members": [], "leaders": []}',
              201,
            );
          }
          return ResponseBody.fromString('', 599);
        },
      );
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddTeamSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Team name'),
        'New Team',
      );

      await _scrollToAndTapSave(tester);

      expect(captured, isNotNull);
      final data = captured!.data as Map<String, dynamic>;
      expect(data.containsKey('responsibilities'), isFalse);
    });

    testWidgets(
      'Add Team sends an all-accounts rule for a provider set to All',
      (tester) async {
        RequestOptions? captured;
        final adapter = _adapter(
          extra: (options) {
            if (options.path == '/teams/' && options.method == 'POST') {
              captured = options;
              return _json(
                '{"id": 9, "name": "New Team", "color": "", "language": "",'
                ' "is_active": true, "members": [], "leaders": []}',
                201,
              );
            }
            return ResponseBody.fromString('', 599);
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showAddTeamSheet(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Team name'),
          'New Team',
        );

        await tester.dragUntilVisible(
          find.text('Channel responsibilities'),
          _sheetScrollable(),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();

        // First dropdown row is WhatsApp — pick "All accounts".
        await tester.tap(find.text('None').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('All accounts').last);
        await tester.pumpAndSettle();

        await _scrollToAndTapSave(tester);

        expect(captured, isNotNull);
        final data = captured!.data as Map<String, dynamic>;
        final responsibilities = data['responsibilities'] as List<dynamic>;
        expect(responsibilities, hasLength(1));
        expect(responsibilities.single, {
          'provider': 'WHATSAPP',
          'scope': 'all',
        });
      },
    );

    testWidgets('Selected scope with no channel picked is rejected locally', (
      tester,
    ) async {
      final client = _clientFrom(_adapter());

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddTeamSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Team name'),
        'New Team',
      );

      await tester.dragUntilVisible(
        find.text('Channel responsibilities'),
        _sheetScrollable(),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('None').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selected accounts').last);
      await tester.pumpAndSettle();

      await _scrollToAndTapSave(tester);
      await _scrollToErrorBanner(tester);

      expect(find.text('Choose at least one channel.'), findsOneWidget);
    });

    testWidgets(
      'Edit Team omits responsibilities when the section was never touched',
      (tester) async {
        RequestOptions? captured;
        final adapter = _adapter(
          responsibilitiesJson: '''
            [
              {"id": 1, "team": {"id": 5, "name": "Support", "is_active": true},
               "employee": null, "provider": "TIKTOK",
               "channel_connection": null, "is_active": true}
            ]
          ''',
          extra: (options) {
            if (options.path == '/teams/5/' && options.method == 'PATCH') {
              captured = options;
              return _json(
                '{"id": 5, "name": "Support", "color": "", "language": "",'
                ' "is_active": true, "members": [], "leaders": []}',
                200,
              );
            }
            return ResponseBody.fromString('', 599);
          },
        );
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showEditTeamSheet(ctx, team: _team),
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Touch an unrelated field only.
        await tester.enterText(
          find.widgetWithText(TextField, 'Support'),
          'Support Renamed',
        );

        await _scrollToAndTapSave(tester);

        expect(captured, isNotNull);
        final data = captured!.data as Map<String, dynamic>;
        expect(data.containsKey('responsibilities'), isFalse);
        expect(data['name'], 'Support Renamed');
      },
    );
  });

  _registerBackendShapeTests();
}

// ---------------------------------------------------------------------------
// The shape the real backend sends
// ---------------------------------------------------------------------------
//
// A rule that names one specific account carries a BLANK top-level `provider`
// (the write contract allows `''` exactly when `channel_connection_id` is
// given); the provider is only on the nested `channel_connection`. The
// fixtures above put `"provider": "WHATSAPP"` on such a rule, which the real
// API does not do — that is how the bug below went unnoticed.

/// "Ayat": responsible for one specific WhatsApp account (id 1, Sales Line).
const _ayatRule = '''
{"id": 7, "team": {"id": 5, "name": "Ayat", "is_active": true},
 "employee": null, "provider": "",
 "channel_connection": {"id": 1, "display_name": "Sales Line",
   "provider": "WHATSAPP", "is_active": true},
 "is_active": true}
''';

String _rules(List<String> rows) => '[${rows.join(',')}]';

const _teamJson =
    '{"id": 5, "name": "Support", "color": "", "language": "",'
    ' "is_active": true, "members": [], "leaders": []}';

Future<void> _openEdit(WidgetTester tester, _StubAdapter adapter) async {
  await tester.pumpWidget(
    _harness(
      apiClient: _clientFrom(adapter),
      child: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showEditTeamSheet(ctx, team: _team),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.dragUntilVisible(
    find.text('Channel responsibilities'),
    _sheetScrollable(),
    const Offset(0, -400),
  );
  await tester.pumpAndSettle();
}

/// An adapter that records the team PATCH and answers it, over [base].
_StubAdapter _capturingPatch(
  _StubAdapter base,
  void Function(RequestOptions) onPatch,
) => _StubAdapter((options) async {
  if (options.path == '/teams/5/' && options.method == 'PATCH') {
    onPatch(options);
    return _json(_teamJson, 200);
  }
  return base.handler(options);
});

/// Tap the chip for [account] (an account name under a "Selected accounts"
/// row).
Future<void> _tapAccount(WidgetTester tester, String account) async {
  await tester.ensureVisible(find.text(account));
  await tester.tap(find.text(account));
  await tester.pumpAndSettle();
}

FilterChip _chip(WidgetTester tester, String account) =>
    tester.widget<FilterChip>(
      find.ancestor(of: find.text(account), matching: find.byType(FilterChip)),
    );

void _expectNoBlankProvider(List<dynamic> responsibilities) {
  const routable = {'WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'TIKTOK'};
  for (final r in responsibilities) {
    final provider = (r as Map)['provider'];
    expect(provider, isNotNull);
    expect(provider, isNot(''));
    expect(routable, contains(provider));
  }
}

/// Saves the sheet. `ensureVisible` rather than a fixed drag: with an account
/// list expanded the sheet is taller, and a fixed drag can stop short.
Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void _registerBackendShapeTests() {
  group('RoutingResponsibility — provider of a channel-specific rule', () {
    test("a blank provider falls back to the account's own provider", () {
      final rule = RoutingResponsibility.fromJson(
        jsonDecode(_ayatRule) as Map<String, dynamic>,
      );

      expect(rule.provider, 'WHATSAPP');
      expect(rule.isChannelSpecific, isTrue);
      expect(rule.channelConnectionId, 1);
      expect(rule.channelConnectionName, 'Sales Line');
      expect(rule.teamId, 5);
    });

    test("a rule's own provider is kept, and normalised to upper case", () {
      final own = RoutingResponsibility.fromJson({
        'id': 1,
        'team': {'id': 5, 'name': 'T'},
        'provider': 'TIKTOK',
        'channel_connection': null,
        'is_active': true,
      });
      expect(own.provider, 'TIKTOK');
      expect(own.isChannelSpecific, isFalse);

      final lower = RoutingResponsibility.fromJson({
        'id': 2,
        'provider': '',
        'channel_connection': {'id': 3, 'provider': 'instagram'},
        'is_active': true,
      });
      expect(lower.provider, 'INSTAGRAM');
    });

    test('a blank provider with no account stays blank (malformed rule)', () {
      final rule = RoutingResponsibility.fromJson({
        'id': 3,
        'provider': '',
        'channel_connection': null,
        'is_active': true,
      });
      expect(rule.provider, '');
    });
  });

  group('Team responsibilities — backend-shaped data', () {
    testWidgets('the WhatsApp assignment the backend holds is shown, with the '
        'account pre-selected', (tester) async {
      await _openEdit(
        tester,
        _adapter(responsibilitiesJson: _rules([_ayatRule])),
      );

      // WhatsApp is no longer "None": it is "Selected accounts" …
      expect(find.text('Selected accounts'), findsOneWidget);
      expect(find.text('None'), findsNWidgets(3));
      // … listing the real accounts from the backend, the right one checked.
      expect(_chip(tester, 'Sales Line').selected, isTrue);
      expect(_chip(tester, 'Support Line').selected, isFalse);
    });

    testWidgets('choosing another account sends the exact payload the backend '
        'expects', (tester) async {
      RequestOptions? captured;
      await _openEdit(
        tester,
        _capturingPatch(
          _adapter(responsibilitiesJson: _rules([_ayatRule])),
          (o) => captured = o,
        ),
      );

      await _tapAccount(tester, 'Support Line'); // add a second account
      await _save(tester);

      expect(captured, isNotNull);
      final data = captured!.data as Map<String, dynamic>;
      final responsibilities = data['responsibilities'] as List<dynamic>;
      expect(responsibilities, [
        {
          'provider': 'WHATSAPP',
          'scope': 'selected',
          'channel_connection_ids': [1, 2],
        },
      ]);
      _expectNoBlankProvider(responsibilities);
    });

    testWidgets("None is sent as the provider's absence — never null and "
        'never an empty string', (tester) async {
      RequestOptions? captured;
      await _openEdit(
        tester,
        _capturingPatch(
          _adapter(responsibilitiesJson: _rules([_ayatRule])),
          (o) => captured = o,
        ),
      );

      // WhatsApp: Selected accounts -> None.
      await tester.tap(find.text('Selected accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      await _save(tester);

      final data = captured!.data as Map<String, dynamic>;
      // The list is the team's complete responsibility: empty means none.
      expect(data['responsibilities'], isEmpty);
      expect(jsonEncode(data), isNot(contains('"provider":""')));
      expect(jsonEncode(data), isNot(contains('null')));
    });

    testWidgets('a rule whose provider cannot be determined is never sent '
        'back', (tester) async {
      RequestOptions? captured;
      await _openEdit(
        tester,
        _capturingPatch(
          _adapter(
            responsibilitiesJson: _rules([
              '{"id": 1, "team": {"id": 5, "name": "Support"}, '
                  '"employee": null, "provider": "", '
                  '"channel_connection": null, "is_active": true}',
              '{"id": 2, "team": {"id": 5, "name": "Support"}, '
                  '"employee": null, "provider": "TIKTOK", '
                  '"channel_connection": null, "is_active": true}',
            ]),
          ),
          (o) => captured = o,
        ),
      );

      // Touch WhatsApp so the section is sent.
      await tester.tap(find.text('None').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All accounts').last);
      await tester.pumpAndSettle();
      await _save(tester);

      final responsibilities =
          (captured!.data as Map<String, dynamic>)['responsibilities']
              as List<dynamic>;
      expect(
        {for (final r in responsibilities) (r as Map)['provider']: r},
        {
          'TIKTOK': {'provider': 'TIKTOK', 'scope': 'all'},
          'WHATSAPP': {'provider': 'WHATSAPP', 'scope': 'all'},
        },
      );
      _expectNoBlankProvider(responsibilities);
    });

    testWidgets('Messenger, Instagram and TikTok are read and written as '
        'before, alongside a WhatsApp change', (tester) async {
      RequestOptions? captured;
      await _openEdit(
        tester,
        _capturingPatch(
          _adapter(
            responsibilitiesJson: _rules([
              '{"id": 1, "team": {"id": 5, "name": "Support"}, '
                  '"employee": null, "provider": "FACEBOOK", '
                  '"channel_connection": null, "is_active": true}',
              // Instagram: account-specific, so a blank provider on the wire.
              '{"id": 2, "team": {"id": 5, "name": "Support"}, '
                  '"employee": null, "provider": "", '
                  '"channel_connection": {"id": 3, "display_name": "Brand IG", '
                  '"provider": "INSTAGRAM", "is_active": true}, '
                  '"is_active": true}',
              '{"id": 3, "team": {"id": 5, "name": "Support"}, '
                  '"employee": null, "provider": "TIKTOK", '
                  '"channel_connection": null, "is_active": true}',
            ]),
          ),
          (o) => captured = o,
        ),
      );

      expect(find.text('All accounts'), findsNWidgets(2)); // Messenger, TikTok
      expect(find.text('Selected accounts'), findsOneWidget); // Instagram
      expect(find.text('None'), findsOneWidget); // WhatsApp

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All accounts').last);
      await tester.pumpAndSettle();
      await _save(tester);

      final responsibilities =
          (captured!.data as Map<String, dynamic>)['responsibilities']
              as List<dynamic>;
      expect(
        {for (final r in responsibilities) (r as Map)['provider']: r},
        {
          'FACEBOOK': {'provider': 'FACEBOOK', 'scope': 'all'},
          'INSTAGRAM': {
            'provider': 'INSTAGRAM',
            'scope': 'selected',
            'channel_connection_ids': [3],
          },
          'TIKTOK': {'provider': 'TIKTOK', 'scope': 'all'},
          'WHATSAPP': {'provider': 'WHATSAPP', 'scope': 'all'},
        },
      );
      _expectNoBlankProvider(responsibilities);
    });

    testWidgets('a saved change is still there after reopening the team', (
      tester,
    ) async {
      // The backend's rules change when the PATCH lands, as they really do.
      var rules = _rules([_ayatRule]);
      final base = _adapter();
      final adapter = _StubAdapter((options) async {
        if (options.path == '/routing/responsibilities/' &&
            options.method == 'GET') {
          return _json(rules, 200);
        }
        if (options.path == '/teams/5/' && options.method == 'PATCH') {
          rules = _rules([
            '{"id": 8, "team": {"id": 5, "name": "Support"}, '
                '"employee": null, "provider": "", '
                '"channel_connection": {"id": 2, "display_name": '
                '"Support Line", "provider": "WHATSAPP", "is_active": true}, '
                '"is_active": true}',
          ]);
          return _json(_teamJson, 200);
        }
        return base.handler(options);
      });
      await _openEdit(tester, adapter);

      // Move the team from Sales Line to Support Line, and save.
      await _tapAccount(tester, 'Sales Line'); // off
      await _tapAccount(tester, 'Support Line'); // on
      await _save(tester);

      // Reopen the same team: the new selection must come back.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Channel responsibilities'),
        _sheetScrollable(),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(_chip(tester, 'Support Line').selected, isTrue);
      expect(_chip(tester, 'Sales Line').selected, isFalse);
    });

    testWidgets('a backend validation error is shown readably, and the '
        'selection is kept', (tester) async {
      final base = _adapter(responsibilitiesJson: _rules([_ayatRule]));
      final adapter = _StubAdapter((options) async {
        if (options.path == '/teams/5/' && options.method == 'PATCH') {
          // A nested serializer reports per-item errors: a LIST of field
          // maps under `responsibilities`.
          return _json(
            '{"error": {"code": "invalid", "message": '
            '"The submitted data was invalid.", "details": '
            '{"responsibilities": [{"provider": '
            '["\\"\\" is not a valid choice."]}]}}}',
            400,
          );
        }
        return base.handler(options);
      });
      await _openEdit(tester, adapter);

      await _tapAccount(tester, 'Support Line');
      await _save(tester);
      await _scrollToErrorBanner(tester);

      // The reason, as a sentence — not the raw map `{provider: [...]}`.
      expect(find.text('"" is not a valid choice.'), findsOneWidget);
      expect(find.textContaining('{provider'), findsNothing);

      // And the admin's selection is still there, not reset to "None".
      await tester.dragUntilVisible(
        find.text('Channel responsibilities'),
        _sheetScrollable(),
        const Offset(0, -200),
      );
      expect(find.text('Selected accounts'), findsOneWidget);
    });
  });
}
