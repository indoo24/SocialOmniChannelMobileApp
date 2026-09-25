/// Saved replies *definitions* management (the Settings admin tab), not the
/// composer's read-only picker (`test/saved_replies_test.dart`): listing,
/// add, edit with a read-only scope, validation, delete with confirmation,
/// the empty state, error handling, and permission gating —
/// `GET/POST/PATCH/DELETE /saved-replies/`.
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
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/saved_replies/saved_replies_settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _reply({
  required int id,
  required String title,
  String shortcut = '',
  String body = 'Body text',
  String category = '',
  String scope = 'personal',
  Map<String, Object?>? team,
  bool isActive = true,
  bool canEdit = true,
}) => {
  'id': id,
  'public_id': 'uuid-$id',
  'title': title,
  'shortcut': shortcut,
  'body': body,
  'category': category,
  'scope': scope,
  'team': team,
  'is_active': isActive,
  'can_edit': canEdit,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

Finder _sheetScrollable() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(ListView),
);

Future<void> _scrollToAndTapSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byKey(const Key('saved-reply-form-save')),
    _sheetScrollable(),
    const Offset(0, -300),
  );
  await tester.tap(find.byKey(const Key('saved-reply-form-save')));
  await tester.pumpAndSettle();
}

class _Server {
  _Server({List<Map<String, Object?>>? replies, this.extra})
    : replies = replies ?? [];

  List<Map<String, Object?>> replies;
  final FutureOr<ResponseBody?> Function(RequestOptions options)? extra;
  final writes = <RequestOptions>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) async {
      final path = options.path;
      if (options.method != 'GET') writes.add(options);

      if (extra != null) {
        final result = await extra!(options);
        if (result != null) return result;
      }

      if (path == '/saved-replies/' && options.method == 'GET') {
        return _json({
          'count': replies.length,
          'page': 1,
          'page_size': 100,
          'total_pages': 1,
          'next': null,
          'previous': null,
          'results': replies,
        });
      }
      if (path == '/saved-replies/' && options.method == 'POST') {
        final body = Map<String, dynamic>.from(options.data as Map);
        final created = _reply(
          id: replies.length + 100,
          title: body['title'] as String,
          body: body['body'] as String,
          shortcut: body['shortcut'] as String? ?? '',
          category: body['category'] as String? ?? '',
          scope: body['scope'] as String? ?? 'personal',
        );
        replies = [...replies, created];
        return _json(created, 201);
      }
      if (path.startsWith('/saved-replies/') &&
          path.endsWith('/') &&
          options.method == 'PATCH') {
        final id = int.parse(path.split('/')[2]);
        final bodyMap = Map<String, dynamic>.from(options.data as Map);
        final index = replies.indexWhere((r) => r['id'] == id);
        final updated = Map<String, Object?>.from(replies[index]);
        bodyMap.forEach((key, value) => updated[key] = value);
        replies = [...replies]..[index] = updated;
        return _json(updated);
      }
      if (path.startsWith('/saved-replies/') &&
          path.endsWith('/') &&
          options.method == 'DELETE') {
        final id = int.parse(path.split('/')[2]);
        final index = replies.indexWhere((r) => r['id'] == id);
        final updated = Map<String, Object?>.from(replies[index]);
        updated['is_active'] = false;
        replies = [...replies]..[index] = updated;
        return _json(updated);
      }
      return _json({});
    });
    return client;
  }
}

Employee _employee({
  Set<String> permissions = const {
    Perm.conversationReply,
    Perm.savedReplyManage,
  },
}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

Widget _harness(ApiClient client, {Employee? employee}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SavedRepliesSettingsTab()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listing', () {
    testWidgets('loads and shows every reply from the API', (tester) async {
      final server = _Server(
        replies: [
          _reply(id: 1, title: 'Thanks', shortcut: 'thanks', scope: 'personal'),
          _reply(
            id: 2,
            title: 'Welcome',
            body: 'Hello there',
            scope: 'organization',
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Saved replies'), findsWidgets);
      expect(find.text('Thanks'), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Shortcut: /thanks'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no replies', (
      tester,
    ) async {
      final server = _Server();

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('No saved replies yet.'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows a retryable error state on failure', (tester) async {
      final server = _Server(
        extra: (options) {
          if (options.path == '/saved-replies/' && options.method == 'GET') {
            return _json({
              'error': {'code': 'error', 'message': 'boom'},
            }, 500);
          }
          return null;
        },
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a disabled reply shows the disabled badge, dimmed', (
      tester,
    ) async {
      final server = _Server(
        replies: [_reply(id: 1, title: 'Old reply', isActive: false)],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('a reply without can_edit shows no edit/delete actions', (
      tester,
    ) async {
      final server = _Server(
        replies: [_reply(id: 1, title: 'Team reply', canEdit: false)],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('saved-reply-1-edit')), findsNothing);
      expect(find.byKey(const Key('saved-reply-1-delete')), findsNothing);
    });

    testWidgets('without conversation.reply, shows a permission-denied state', (
      tester,
    ) async {
      final server = _Server();

      await tester.pumpWidget(
        _harness(server.client(), employee: _employee(permissions: {})),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("You don't have permission to view saved replies."),
        findsOneWidget,
      );
    });

    testWidgets(
      'without saved_reply.manage, the scope dropdown omits Everyone',
      (tester) async {
        final server = _Server();
        await tester.pumpWidget(
          _harness(
            server.client(),
            employee: _employee(permissions: {Perm.conversationReply}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('add-saved-reply')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('saved-reply-form-scope')));
        await tester.pumpAndSettle();

        expect(find.text('Personal').hitTestable(), findsWidgets);
        expect(find.text('Everyone'), findsNothing);
      },
    );
  });

  group('add reply', () {
    Future<void> openAddSheet(WidgetTester tester, _Server server) async {
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-saved-reply')));
      await tester.pumpAndSettle();
    }

    testWidgets('rejects an empty title without a request', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await _scrollToAndTapSave(tester);

      expect(find.text('Enter a title.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('rejects empty body text without a request', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Thanks',
      );
      await _scrollToAndTapSave(tester);

      expect(find.text('Enter the reply text.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('creates a reply and refreshes the list', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Thanks',
      );
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-shortcut')),
        'thanks',
      );
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-body')),
        'Thanks for reaching out.',
      );
      await _scrollToAndTapSave(tester);

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'POST');
      final body = server.writes.single.data as Map;
      expect(body['title'], 'Thanks');
      expect(body['shortcut'], 'thanks');
      expect(body['body'], 'Thanks for reaching out.');
      expect(body['scope'], 'personal');
      expect(find.text('Saved reply added'), findsOneWidget);
      expect(find.text('Thanks'), findsOneWidget);
    });

    testWidgets('an admin can choose Everyone as the scope', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Welcome',
      );
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-body')),
        'Welcome!',
      );
      await tester.tap(find.byKey(const Key('saved-reply-form-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everyone').last);
      await tester.pumpAndSettle();

      await _scrollToAndTapSave(tester);

      final body = server.writes.single.data as Map;
      expect(body['scope'], 'organization');
    });

    testWidgets('shows the server refusal on a validation error', (
      tester,
    ) async {
      final server = _Server(
        extra: (options) {
          if (options.path == '/saved-replies/' && options.method == 'POST') {
            return _json({
              'error': {
                'code': 'invalid',
                'message': 'That shortcut is already used.',
                'details': {
                  'shortcut': ['That shortcut is already used.'],
                },
              },
            }, 400);
          }
          return null;
        },
      );
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Thanks',
      );
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-body')),
        'Thanks!',
      );
      await _scrollToAndTapSave(tester);

      expect(find.text('That shortcut is already used.'), findsOneWidget);
      expect(find.text('New saved reply'), findsNWidgets(2));
    });
  });

  group('edit reply', () {
    testWidgets('loads existing values and keeps the scope read-only', (
      tester,
    ) async {
      final server = _Server(
        replies: [
          _reply(
            id: 1,
            title: 'Thanks',
            shortcut: 'thanks',
            body: 'Thanks a lot!',
            category: 'General',
            scope: 'organization',
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-edit')));
      await tester.pumpAndSettle();

      expect(find.text('Edit saved reply'), findsOneWidget);
      final titleField = tester.widget<TextField>(
        find.byKey(const Key('saved-reply-form-title')),
      );
      expect(titleField.controller!.text, 'Thanks');

      final bodyField = tester.widget<TextField>(
        find.byKey(const Key('saved-reply-form-body')),
      );
      expect(bodyField.controller!.text, 'Thanks a lot!');

      // Scope has no dropdown in edit mode — shown as read-only text.
      expect(find.byKey(const Key('saved-reply-form-scope')), findsNothing);
      expect(find.text('Everyone'), findsWidgets);
    });

    testWidgets('saving an edit never sends scope', (tester) async {
      final server = _Server(
        replies: [_reply(id: 1, title: 'Thanks', scope: 'organization')],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Thanks a lot',
      );
      await _scrollToAndTapSave(tester);

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'PATCH');
      final body = server.writes.single.data as Map;
      expect(body.containsKey('scope'), isFalse);
      expect(body['title'], 'Thanks a lot');
      expect(find.text('Saved reply updated'), findsOneWidget);
    });
  });

  group('delete reply', () {
    testWidgets('shows a confirmation dialog before deleting', (tester) async {
      final server = _Server(replies: [_reply(id: 1, title: 'Thanks')]);

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete saved reply?'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('deletes only after confirmation and refreshes the list', (
      tester,
    ) async {
      final server = _Server(replies: [_reply(id: 1, title: 'Thanks')]);

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'DELETE');
      expect(server.writes.single.path, '/saved-replies/1/');
      expect(find.text('Saved reply deleted'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('cancelling the dialog sends nothing', (tester) async {
      final server = _Server(replies: [_reply(id: 1, title: 'Thanks')]);

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(server.writes, isEmpty);
      expect(find.text('Thanks'), findsOneWidget);
    });

    testWidgets('a failed delete shows an error and keeps the reply active', (
      tester,
    ) async {
      final server = _Server(
        replies: [_reply(id: 1, title: 'Thanks')],
        extra: (options) {
          if (options.path == '/saved-replies/1/' &&
              options.method == 'DELETE') {
            return _json({
              'error': {'code': 'error', 'message': 'Could not delete.'},
            }, 500);
          }
          return null;
        },
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Could not delete.'), findsOneWidget);
      expect(find.text('Disabled'), findsNothing);
    });
  });

  group('Arabic / RTL', () {
    testWidgets('renders Arabic labels and RTL directionality', (tester) async {
      final server = _Server(
        replies: [_reply(id: 1, title: 'شكراً', shortcut: 'thanks')],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.client()),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SavedRepliesSettingsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الردود المحفوظة'), findsWidgets);
      expect(find.text('شكراً'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('شكراً'))),
        TextDirection.rtl,
      );
    });
  });
}
