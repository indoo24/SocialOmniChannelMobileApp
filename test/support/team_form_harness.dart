/// A fake backend and a host page for the shared Create / Edit Team form.
///
/// The backend answers exactly the requests the form makes — active
/// employees, channels, responsibility rules, and the team write — with
/// data shaped like the live API's, and records every request so a test can
/// assert the exact payload.
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
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/team_form_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

ResponseBody jsonBody(Object body, int status) => ResponseBody.fromString(
  body is String ? body : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> employeeJson(
  int id,
  String name, {
  String role = 'Agent',
}) {
  final initials = name
      .split(' ')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0])
      .take(2)
      .join();
  return {
    'id': id,
    'full_name': name,
    'initials': initials,
    'email': 'p$id@acme.test',
    'role': role.toUpperCase(),
    'role_display': role,
    'availability': 'ONLINE',
    'is_active': true,
    'teams': <Object>[],
  };
}

final defaultEmployees = [
  employeeJson(1, 'Sam Admin', role: 'Admin'),
  employeeJson(2, 'Mona Agent'),
  employeeJson(3, 'Omar Agent'),
];

Map<String, dynamic> channelJson(
  int id,
  String provider,
  String name, {
  String status = 'CONNECTED',
  String externalId = '',
}) => {
  'id': id,
  'provider': provider,
  'display_name': name,
  'status': status,
  'is_active': status == 'CONNECTED',
  'external_account_id': externalId,
};

/// Two WhatsApp numbers (one not connected), two Instagram accounts, one
/// TikTok account, no Facebook Page — and the sandbox, which never shows.
final defaultChannels = [
  channelJson(1, 'WHATSAPP', 'Gad', status: 'DISCONNECTED'),
  channelJson(2, 'WHATSAPP', 'Scenario DM'),
  channelJson(3, 'INSTAGRAM', 'Brand IG'),
  channelJson(4, 'INSTAGRAM', 'Shop IG'),
  channelJson(5, 'TIKTOK', 'Tok Shop'),
  channelJson(9, 'MOCK', 'Sandbox'),
];

Map<String, dynamic> providerRule(
  int id,
  int teamId,
  String provider, {
  bool strict = false,
  bool active = true,
}) => {
  'id': id,
  'team': {'id': teamId, 'name': 'Team $teamId', 'is_active': true},
  'employee': null,
  'provider': provider,
  'channel_connection': null,
  'strict': strict,
  'is_active': active,
};

/// A rule naming one account: the backend stores these with a blank
/// top-level provider, the provider only on the nested account.
Map<String, dynamic> accountRule(
  int id,
  int teamId,
  int connectionId,
  String provider,
  String name, {
  bool strict = false,
  bool active = true,
}) => {
  'id': id,
  'team': {'id': teamId, 'name': 'Team $teamId', 'is_active': true},
  'employee': null,
  'provider': '',
  'channel_connection': {
    'id': connectionId,
    'display_name': name,
    'provider': provider,
    'is_active': true,
  },
  'strict': strict,
  'is_active': active,
};

/// Team 5 "Support" as the list sends it: Sam (leader) and Mona.
Team supportTeam({
  List<Map<String, dynamic>>? members,
  List<Map<String, dynamic>>? leaders,
  String color = '#0f766e',
}) => Team.fromJson({
  'id': 5,
  'name': 'Support',
  'description': 'Tier 2',
  'language': 'ar',
  'color': color,
  'is_active': true,
  'member_count': members?.length ?? 2,
  'members':
      members ??
      [
        {'id': 1, 'full_name': 'Sam Admin', 'initials': 'SA'},
        {'id': 2, 'full_name': 'Mona Agent', 'initials': 'MA'},
      ],
  'leaders':
      leaders ??
      [
        {'id': 1, 'full_name': 'Sam Admin', 'initials': 'SA'},
      ],
});

/// The rules team 5 starts with: WhatsApp "Scenario DM" only (strict), and
/// every Instagram account (flexible).
final supportRules = [
  accountRule(11, 5, 2, 'WHATSAPP', 'Scenario DM', strict: true),
  providerRule(12, 5, 'INSTAGRAM'),
];

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

class TeamFormBackend {
  TeamFormBackend({
    List<Map<String, dynamic>>? employees,
    List<Map<String, dynamic>>? channels,
    List<Map<String, dynamic>>? rules,
    this.rulesStatus = 200,
    this.employeesStatus = 200,
    this.write,
  }) : employees = employees ?? defaultEmployees,
       channels = channels ?? defaultChannels,
       rules = rules ?? const [];

  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> channels;
  List<Map<String, dynamic>> rules;
  int rulesStatus;
  int employeesStatus;

  /// Answers `POST /teams/` and `PATCH /teams/{id}/`. Defaults to success.
  FutureOr<ResponseBody> Function(RequestOptions options)? write;

  /// Answers `POST /teams/{id}/membership-impact/`. Defaults to an
  /// organization outside the team-first rollout (nothing to warn about).
  FutureOr<ResponseBody> Function(RequestOptions options)? impact;

  List<RequestOptions> get impactRequests =>
      received.where((r) => r.path.endsWith('/membership-impact/')).toList();

  final List<RequestOptions> received = [];

  List<RequestOptions> get writes => received
      .where(
        (r) =>
            (r.method == 'POST' && r.path == '/teams/') ||
            (r.method == 'PATCH' && r.path.startsWith('/teams/')),
      )
      .toList();

  Map<String, dynamic> get lastWrite =>
      Map<String, dynamic>.from(writes.last.data as Map);

  int requestsTo(String path) => received.where((r) => r.path == path).length;

  Future<ResponseBody> _handle(RequestOptions o) async {
    received.add(o);
    if (o.method == 'POST' && o.path.endsWith('/membership-impact/')) {
      final custom = impact;
      if (custom != null) return custom(o);
      return jsonBody({
        'team_first': false,
        'team_id': 5,
        'team_name': 'Support',
        'affected_conversations': 0,
        'redistributable': 0,
        'stranded': 0,
        'team_active_conversations': 0,
        'leaves_team_without_eligible_employee': false,
        'warning': '',
      }, 200);
    }
    final isWrite =
        (o.method == 'POST' && o.path == '/teams/') ||
        (o.method == 'PATCH' && o.path.startsWith('/teams/'));
    if (isWrite) {
      final custom = write;
      if (custom != null) return custom(o);
      return jsonBody({
        'id': 5,
        'name': (o.data as Map)['name'] ?? 'Support',
        'is_active': true,
        'members': <Object>[],
        'leaders': <Object>[],
        'member_count': 0,
      }, o.method == 'POST' ? 201 : 200);
    }
    if (o.method != 'GET') return jsonBody('{}', 200);
    switch (o.path) {
      case '/employees/':
        if (employeesStatus != 200) {
          return jsonBody({
            'error': {'code': 'error', 'message': 'Server error'},
          }, employeesStatus);
        }
        return jsonBody({
          'count': employees.length,
          'next': null,
          'previous': null,
          'results': employees,
        }, 200);
      case '/channels/':
        return jsonBody({
          'count': channels.length,
          'next': null,
          'previous': null,
          'results': channels,
        }, 200);
      case '/routing/responsibilities/':
        if (rulesStatus != 200) {
          return jsonBody({
            'error': {'code': 'error', 'message': 'Server error'},
          }, rulesStatus);
        }
        return jsonBody(rules, 200);
      case '/teams/':
        return jsonBody({
          'count': 0,
          'next': null,
          'previous': null,
          'results': <Object>[],
        }, 200);
    }
    return jsonBody('{}', 200);
  }

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _Adapter(_handle);
    return client;
  }
}

const adminPermissions = {
  Perm.teamView,
  Perm.teamManage,
  Perm.channelView,
  Perm.routingManage,
};

Employee formAdmin({Set<String> permissions = adminPermissions}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Sam Admin',
  initials: 'SA',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

/// Pumps a page with an "Open" button that opens the form — Edit Team for
/// [team], Create Team otherwise — and opens it.
Future<void> openTeamForm(
  WidgetTester tester,
  TeamFormBackend backend, {
  Team? team,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 2400),
  Set<String> permissions = adminPermissions,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client()),
        currentEmployeeProvider.overrideWithValue(
          formAdmin(permissions: permissions),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => team == null
                    ? showAddTeamSheet(context)
                    : showEditTeamSheet(context, team: team),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view inside the form, then taps it.
Future<void> tapInForm(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('teamFormSave')));
  await tester.pumpAndSettle();
}

/// Expands one channel's section.
Future<void> expandChannel(WidgetTester tester, String provider) =>
    tapInForm(tester, find.byKey(ValueKey('teamChannel_$provider')));

Future<void> chooseMode(WidgetTester tester, String provider, String mode) =>
    tapInForm(
      tester,
      find.byKey(ValueKey('teamChannelMode_${provider}_$mode')),
    );

Future<void> tickAccount(WidgetTester tester, int id) =>
    tapInForm(tester, find.byKey(ValueKey('teamAccountCheck_$id')));

bool accountTicked(WidgetTester tester, int id) =>
    tester
        .widget<Checkbox>(find.byKey(ValueKey('teamAccountCheck_$id')))
        .value ==
    true;

bool memberTicked(WidgetTester tester, int id) =>
    tester
        .widget<Checkbox>(find.byKey(ValueKey('teamMemberCheck_$id')))
        .value ==
    true;

String channelSummary(WidgetTester tester, String provider) => tester
    .widget<Text>(find.byKey(ValueKey('teamChannelSummary_$provider')))
    .data!;

bool saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('teamFormSave')))
        .onPressed !=
    null;
