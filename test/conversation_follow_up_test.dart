import 'dart:async';
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
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _employee({bool canChangeCategory = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    if (canChangeCategory) Perm.conversationChangeCategory,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

void main() {
  group('ConversationRepository.followUp', () {
    test('marks conversation as follow-up with a date', () async {
      RequestOptions? capturedOptions;
      final client = _stubClient((options) {
        if (options.path.contains('/follow-up/')) {
          capturedOptions = options;
          return _json('''{
              "id": 42,
              "customer": {"id": 7, "display_name": "Sarah Connor"},
              "provider": "WHATSAPP",
              "status": "OPEN",
              "is_follow_up": true,
              "follow_up_date": "2026-09-15T00:00:00Z"
            }''', 200);
        }
        return _json('{}', 200);
      });

      final repo = ConversationRepository(client);
      final result = await repo.followUp(
        42,
        isFollowUp: true,
        followUpDate: '2026-09-15',
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.path, equals('/conversations/42/follow-up/'));
      expect(capturedOptions!.method, equals('POST'));
      expect(capturedOptions!.data, {
        'is_follow_up': true,
        'follow_up_date': '2026-09-15',
      });
      expect(result.isFollowUp, isTrue);
      expect(result.followUpDate, isNotNull);
    });

    test('marks conversation as follow-up without date', () async {
      RequestOptions? capturedOptions;
      final client = _stubClient((options) {
        if (options.path.contains('/follow-up/')) {
          capturedOptions = options;
          return _json('''{
              "id": 42,
              "customer": {"id": 7, "display_name": "Sarah Connor"},
              "provider": "WHATSAPP",
              "status": "OPEN",
              "is_follow_up": true,
              "follow_up_date": null
            }''', 200);
        }
        return _json('{}', 200);
      });

      final repo = ConversationRepository(client);
      final result = await repo.followUp(42, isFollowUp: true);

      expect(capturedOptions!.data, {'is_follow_up': true});
      expect(result.isFollowUp, isTrue);
    });

    test(
      'clears follow-up date with null while keeping follow-up true',
      () async {
        RequestOptions? capturedOptions;
        final client = _stubClient((options) {
          if (options.path.contains('/follow-up/')) {
            capturedOptions = options;
            return _json('''{
              "id": 42,
              "customer": {"id": 7, "display_name": "Sarah Connor"},
              "provider": "WHATSAPP",
              "status": "OPEN",
              "is_follow_up": true,
              "follow_up_date": null
            }''', 200);
          }
          return _json('{}', 200);
        });

        final repo = ConversationRepository(client);
        final result = await repo.followUp(
          42,
          isFollowUp: true,
          clearFollowUpDate: true,
        );

        expect(capturedOptions!.data, {
          'is_follow_up': true,
          'follow_up_date': null,
        });
        expect(result.isFollowUp, isTrue);
        expect(result.followUpDate, isNull);
      },
    );

    test('completely removes follow-up with is_follow_up: false', () async {
      RequestOptions? capturedOptions;
      final client = _stubClient((options) {
        if (options.path.contains('/follow-up/')) {
          capturedOptions = options;
          return _json('''{
              "id": 42,
              "customer": {"id": 7, "display_name": "Sarah Connor"},
              "provider": "WHATSAPP",
              "status": "OPEN",
              "is_follow_up": false,
              "follow_up_date": null
            }''', 200);
        }
        return _json('{}', 200);
      });

      final repo = ConversationRepository(client);
      final result = await repo.followUp(42, isFollowUp: false);

      expect(capturedOptions!.data, {'is_follow_up': false});
      expect(result.isFollowUp, isFalse);
    });
  });

  group('ConversationScreen Follow-up UI', () {
    testWidgets(
      'Follow-up flag and Assignee avatar are positioned before 3-dot Actions button',
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

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ConversationScreen(conversationId: 42),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Unflagged state shows outline flag
        expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
        // 2. Assignee avatar is shown
        expect(find.text('JD'), findsOneWidget);
        // 3. 3-dot Actions button is shown
        expect(find.byIcon(Icons.more_vert), findsOneWidget);

        // Verify order: Flag position < Assignee position < 3-dot Actions position
        final flagOffset = tester.getCenter(find.byIcon(Icons.flag_outlined));
        final assigneeOffset = tester.getCenter(find.text('JD'));
        final actionsOffset = tester.getCenter(find.byIcon(Icons.more_vert));

        expect(flagOffset.dx, lessThan(assigneeOffset.dx));
        expect(assigneeOffset.dx, lessThan(actionsOffset.dx));
      },
    );

    testWidgets(
      'Flagged conversation renders active flag color and dialog allows editing/clearing follow-up',
      (tester) async {
        RequestOptions? followUpRequest;

        final client = _stubClient((options) {
          if (options.path.contains('/conversations/42/follow-up/')) {
            followUpRequest = options;
            return _json('''{
                "id": 42,
                "customer": {
                  "id": 7,
                  "display_name": "Sarah Connor",
                  "initials": "SC"
                },
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false,
                "follow_up_date": null
              }''', 200);
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
                "is_follow_up": true,
                "follow_up_date": "2026-09-15T00:00:00Z"
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ConversationScreen(conversationId: 42),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Flagged state shows filled flag
        final flagFinder = find.byIcon(Icons.flag_rounded);
        expect(flagFinder, findsOneWidget);

        // Tap flag to open dialog
        await tester.tap(flagFinder);
        await tester.pumpAndSettle();

        expect(find.text('Edit follow-up'), findsOneWidget);
        expect(find.text('Remove follow-up'), findsOneWidget);

        // Tap Remove follow-up
        await tester.tap(find.text('Remove follow-up'));
        await tester.pumpAndSettle();

        expect(followUpRequest, isNotNull);
        expect(followUpRequest!.data, {'is_follow_up': false});
      },
    );

    testWidgets(
      'User without conversation.change_category cannot tap Follow-up button',
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
                "provider": "WHATSAPP",
                "status": "OPEN",
                "is_follow_up": false
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(
                _employee(canChangeCategory: false),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ConversationScreen(conversationId: 42),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final flagFinder = find.byIcon(Icons.flag_outlined);
        expect(flagFinder, findsOneWidget);

        await tester.tap(flagFinder);
        await tester.pumpAndSettle();

        // Dialog should NOT open
        expect(find.text('Follow up'), findsNothing);
        expect(find.text('Mark as follow-up'), findsNothing);
      },
    );
  });

  group('InboxScreen Follow-up Badge', () {
    testWidgets(
      'renders follow-up badge with formatted date for is_follow_up: true and hides for false',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/counts/')) {
            return _json('{"total": 2, "unread": 0, "unassigned": 0}', 200);
          }
          if (options.path.contains('/conversations/')) {
            return _json('''{
                "count": 2,
                "next": null,
                "previous": null,
                "results": [
                  {
                    "id": 101,
                    "customer": {
                      "id": 1,
                      "display_name": "Alice Smith",
                      "initials": "AS"
                    },
                    "provider": "WHATSAPP",
                    "status": "OPEN",
                    "is_follow_up": true,
                    "follow_up_date": "2026-09-15T00:00:00Z"
                  },
                  {
                    "id": 102,
                    "customer": {
                      "id": 2,
                      "display_name": "Bob Jones",
                      "initials": "BJ"
                    },
                    "provider": "TELEGRAM",
                    "status": "OPEN",
                    "is_follow_up": false,
                    "follow_up_date": null
                  }
                ]
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const InboxScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Conversation 101 has follow-up flag icon and formatted date
        expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
        expect(find.text('15 Sep'), findsOneWidget);

        // Conversation 102 does NOT render follow-up flag
        expect(find.text('Bob Jones'), findsOneWidget);
      },
    );

    testWidgets(
      'renders fallback label when is_follow_up: true but follow_up_date is null',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/conversations/counts/')) {
            return _json('{"total": 1, "unread": 0, "unassigned": 0}', 200);
          }
          if (options.path.contains('/conversations/')) {
            return _json('''{
                "count": 1,
                "next": null,
                "previous": null,
                "results": [
                  {
                    "id": 101,
                    "customer": {
                      "id": 1,
                      "display_name": "Alice Smith",
                      "initials": "AS"
                    },
                    "provider": "WHATSAPP",
                    "status": "OPEN",
                    "is_follow_up": true,
                    "follow_up_date": null
                  }
                ]
              }''', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const InboxScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Conversation 101 has follow-up flag icon and fallback label "Follow up"
        expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
        expect(find.text('Follow up'), findsOneWidget);
      },
    );

    testWidgets('renders without overflow in dark theme and RTL (Arabic)', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/conversations/counts/')) {
          return _json('{"total": 1, "unread": 0, "unassigned": 0}', 200);
        }
        if (options.path.contains('/conversations/')) {
          return _json('''{
                "count": 1,
                "next": null,
                "previous": null,
                "results": [
                  {
                    "id": 101,
                    "customer": {
                      "id": 1,
                      "display_name": "سارة محمد",
                      "initials": "سم"
                    },
                    "provider": "WHATSAPP",
                    "status": "OPEN",
                    "priority": "URGENT",
                    "is_follow_up": true,
                    "follow_up_date": "2026-09-15T00:00:00Z"
                  }
                ]
              }''', 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InboxScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
      expect(find.text('سارة محمد'), findsOneWidget);
    });
  });
}
