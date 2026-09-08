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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path.contains('/intelligence/')) {
      return _json('{}', 200);
    }
    if (options.path.contains('/orders/')) {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/categories/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/facts/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/read/')) {
      return _json('{"success": true}', 200);
    }
    return handler(options);
  });
  return client;
}

Employee _employee({bool canChangeStatus = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationChangeCategory,
    if (canChangeStatus) Perm.conversationChangeStatus,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _buildHarness({
  required ApiClient client,
  Employee? employee,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ConversationScreen(conversationId: 42),
    ),
  );
}

void main() {
  group('ConversationScreen Resolved Button in Actions Bottom Sheet', () {
    testWidgets(
      'Resolved button is removed from header and displayed at the top of the Actions sheet',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "assigned_to": {
                  "id": 2,
                  "full_name": "John Doe",
                  "initials": "JD"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildHarness(client: client));
        await tester.pumpAndSettle();

        // 1. Resolved button is NOT in the header AppBar (freeing up huge space)
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byKey(const Key('conversation_resolve_button')),
          ),
          findsNothing,
        );

        // 2. Open Actions bottom sheet via 3-dots button in header
        final actionsBtn = find.byIcon(Icons.more_vert);
        expect(actionsBtn, findsOneWidget);
        await tester.tap(actionsBtn);
        await tester.pumpAndSettle();

        // 3. Now the Resolved button is visible at the top of the actions sheet
        final resolveBtn = find.byKey(const Key('conversation_resolve_button'));
        expect(resolveBtn, findsOneWidget);
        expect(
          find.descendant(of: resolveBtn, matching: find.text('Resolved')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: resolveBtn,
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Tapping Resolved button calls existing resolve API with status: RESOLVED and updates status',
      (tester) async {
        RequestOptions? capturedStatusRequest;
        String currentStatus = 'OPEN';

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/status/')) {
            capturedStatusRequest = options;
            currentStatus = 'RESOLVED';
            return _json('{"status": "RESOLVED"}', 200);
          }
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "$currentStatus",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildHarness(client: client));
        await tester.pumpAndSettle();

        // Initially status badge in header is Open
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Open'),
          ),
          findsOneWidget,
        );

        // Open Actions bottom sheet
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Tap Resolved button at top of sheet
        final resolveBtn = find.byKey(const Key('conversation_resolve_button'));
        await tester.tap(resolveBtn);
        await tester.pumpAndSettle();

        // Verify API was called
        expect(capturedStatusRequest, isNotNull);
        expect(capturedStatusRequest!.method, equals('POST'));
        expect(
          capturedStatusRequest!.path,
          equals('/conversations/42/status/'),
        );

        final dynamic rawData = capturedStatusRequest!.data;
        final data = rawData is String
            ? jsonDecode(rawData) as Map<String, dynamic>
            : (rawData as Map).cast<String, dynamic>();
        expect(data['status'], equals('RESOLVED'));

        // Bottom sheet was dismissed and header status is updated to Resolved
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Open'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Resolved'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Loading state shows spinner while request is in flight',
      (tester) async {
        int statusCallCount = 0;
        final completer = Completer<ResponseBody>();

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/status/')) {
            statusCallCount++;
            return completer.future;
          }
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildHarness(client: client));
        await tester.pumpAndSettle();

        // Open Actions bottom sheet
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        final resolveBtn = find.byKey(const Key('conversation_resolve_button'));

        // 1st tap
        await tester.tap(resolveBtn);
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // Trigger onTap and enter loading state

        // Expect 1 call so far
        expect(statusCallCount, equals(1));

        // Loading spinner is rendered inside the button
        expect(
          find.descendant(
            of: resolveBtn,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );

        // Complete the request
        completer.complete(_json('{"status": "RESOLVED"}', 200));
        await tester.pumpAndSettle();

        // Bottom sheet closed upon success
        expect(
          find.byKey(const Key('conversation_resolve_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Failed response keeps the existing conversation status and displays error message',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/status/')) {
            return _json(
              '{"detail": "Unable to resolve this conversation"}',
              400,
            );
          }
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_buildHarness(client: client));
        await tester.pumpAndSettle();

        // Initially status badge in header is Open
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Open'),
          ),
          findsOneWidget,
        );

        // Open Actions bottom sheet
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Tap Resolved button
        final resolveBtn = find.byKey(const Key('conversation_resolve_button'));
        await tester.tap(resolveBtn);
        await tester.pumpAndSettle();

        // Error snackbar is shown
        expect(
          find.text('Unable to resolve this conversation'),
          findsOneWidget,
        );

        // Header status badge remains OPEN
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Open'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'User without conversation.change_status cannot trigger resolve API call',
      (tester) async {
        int statusCallCount = 0;

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/status/')) {
            statusCallCount++;
            return _json('{"status": "RESOLVED"}', 200);
          }
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          _buildHarness(
            client: client,
            employee: _employee(canChangeStatus: false),
          ),
        );
        await tester.pumpAndSettle();

        // Open Actions bottom sheet
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        final resolveBtn = find.byKey(const Key('conversation_resolve_button'));
        expect(resolveBtn, findsOneWidget);

        // Tap Resolved button
        await tester.tap(resolveBtn);
        await tester.pumpAndSettle();

        // API should not be called
        expect(statusCallCount, equals(0));
        // Status in header remains OPEN
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Open'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('RTL (Arabic) displays localized text and respects layout', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _buildHarness(client: client, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      // Open Actions bottom sheet
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Localized Arabic text "تم الحل"
      final resolveBtn = find.byKey(const Key('conversation_resolve_button'));
      expect(resolveBtn, findsOneWidget);
      expect(
        find.descendant(of: resolveBtn, matching: find.text('تم الحل')),
        findsOneWidget,
      );
    });

    testWidgets(
      'Conversation header has ample room and does not overflow on narrow screen with 1.3x text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/conversations/42/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor Very Long Name",
                  "initials": "SC",
                  "phone": "01015959336"
                },
                "channel_name": "Scenario DM",
                "assigned_to": {
                  "id": 2,
                  "full_name": "John Doe",
                  "initials": "JD"
                },
                "provider": "WHATSAPP",
                "status": "WAITING_CUSTOMER",
                "is_follow_up": true
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
              size: Size(360, 640),
            ),
            child: _buildHarness(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Header actions are cleanly spaced
        expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
        expect(find.text('JD'), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);

        // Open actions sheet and verify it also renders without exception
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('conversation_resolve_button')),
          findsOneWidget,
        );
      },
    );
  });
}
