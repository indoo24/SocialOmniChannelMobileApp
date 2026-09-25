/// Team channel responsibilities: `TeamWrite.responsibilities` construction
/// in the Add/Edit Team sheet, and seeding current state from
/// `GET /api/routing/responsibilities/` (the only source for it, since
/// `Team` itself carries no `responsibilities` field on read).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
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
}
