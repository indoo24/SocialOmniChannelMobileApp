import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/template.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/badges.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/templates/templates_repository.dart';
import 'package:scenario_mobile/features/templates/templates_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
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

ApiClient _clientWith(ResponseBody Function(RequestOptions options) handler) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _testEmployee({Set<String> permissions = const {}}) => Employee(
  id: 1,
  email: 'test@example.com',
  fullName: 'Jane Agent',
  initials: 'JA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Scenario'),
);

const _sampleTemplateJson = '''
{
  "id": "4355335634779784",
  "name": "scenario12",
  "language": "en_US",
  "category": "MARKETING",
  "status": "APPROVED",
  "body": "Your request has been received.",
  "rejected_reason": "",
  "variables": 0,
  "can_send": true,
  "unsupported": []
}
''';

const _templatesListResponse = '''
{
  "templates": [
    {
      "id": "4355335634779784",
      "name": "scenario12",
      "language": "en_US",
      "category": "MARKETING",
      "status": "APPROVED",
      "body": "Your request has been received.",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    },
    {
      "id": "1724673956334044",
      "name": "promo_temp",
      "language": "ar",
      "category": "UTILITY",
      "status": "PENDING",
      "body": "طلبك قيد المراجعة.",
      "rejected_reason": "",
      "variables": 1,
      "can_send": false,
      "unsupported": []
    },
    {
      "id": "9999999999999999",
      "name": "bad_template",
      "language": "en_US",
      "category": "MARKETING",
      "status": "REJECTED",
      "body": "Broken message",
      "rejected_reason": "INVALID_FORMAT",
      "variables": 0,
      "can_send": false,
      "unsupported": ["Media header"]
    }
  ]
}
''';

const _sampleWhatsAppChannel = ChannelConnection(
  id: 10,
  provider: 'WHATSAPP',
  displayName: 'Scenario DM',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '1189064717633052',
);

const _sampleWhatsAppChannel2 = ChannelConnection(
  id: 20,
  provider: 'WHATSAPP',
  displayName: 'Secondary Line',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '9988776655443322',
);

void main() {
  group('WhatsAppTemplate Model', () {
    test('parses full template json correctly', () {
      final t = WhatsAppTemplate.fromJson({
        'id': '4355335634779784',
        'name': 'scenario12',
        'language': 'en_US',
        'category': 'MARKETING',
        'status': 'APPROVED',
        'body': 'Your request has been received.',
        'rejected_reason': '',
        'variables': 0,
        'can_send': true,
        'unsupported': [],
      });

      expect(t.id, '4355335634779784');
      expect(t.name, 'scenario12');
      expect(t.language, 'en_US');
      expect(t.category, 'MARKETING');
      expect(t.status, 'APPROVED');
      expect(t.isApproved, isTrue);
      expect(t.isPending, isFalse);
      expect(t.isRejected, isFalse);
      expect(t.statusTone, BadgeTone.success);
      expect(t.body, 'Your request has been received.');
      expect(t.canSend, isTrue);
      expect(t.variables, 0);
      expect(t.unsupported, isEmpty);
    });

    test('parses pending and rejected status with tone correctly', () {
      final pending = WhatsAppTemplate.fromJson({
        'id': '1',
        'name': 'p',
        'language': 'en',
        'category': 'UTILITY',
        'status': 'PENDING',
      });
      expect(pending.isPending, isTrue);
      expect(pending.statusTone, BadgeTone.warning);

      final rejected = WhatsAppTemplate.fromJson({
        'id': '2',
        'name': 'r',
        'language': 'en',
        'category': 'UTILITY',
        'status': 'REJECTED',
        'rejected_reason': 'POLICY_VIOLATION',
        'unsupported': ['Copy-code button'],
      });
      expect(rejected.isRejected, isTrue);
      expect(rejected.statusTone, BadgeTone.danger);
      expect(rejected.rejectedReason, 'POLICY_VIOLATION');
      expect(rejected.unsupported, ['Copy-code button']);
    });
  });

  group('TemplatesRepository', () {
    test(
      'listTemplates calls GET /integrations/whatsapp/{id}/templates/',
      () async {
        final client = _clientWith((options) {
          expect(options.method, 'GET');
          expect(options.path, '/integrations/whatsapp/10/templates/');
          return _json(_templatesListResponse, 200);
        });

        final repo = TemplatesRepository(client);
        final templates = await repo.listTemplates(10);

        expect(templates.length, 3);
        expect(templates[0].name, 'scenario12');
        expect(templates[1].name, 'promo_temp');
        expect(templates[2].name, 'bad_template');
      },
    );

    test(
      'createTemplate calls POST /integrations/whatsapp/{id}/templates/',
      () async {
        final client = _clientWith((options) {
          expect(options.method, 'POST');
          expect(options.path, '/integrations/whatsapp/10/templates/');
          final body = options.data as Map<String, dynamic>;
          expect(body['name'], 'order_update');
          expect(body['category'], 'UTILITY');
          expect(body['language'], 'en_US');
          expect(body['body'], 'Your order has shipped.');
          return _json(_sampleTemplateJson, 201);
        });

        final repo = TemplatesRepository(client);
        final created = await repo.createTemplate(
          10,
          name: 'Order_Update',
          category: 'utility',
          language: 'en_US',
          body: 'Your order has shipped.',
        );

        expect(created.id, '4355335634779784');
        expect(created.name, 'scenario12');
      },
    );

    test(
      'sendConversationTemplate calls POST /conversations/{id}/send-template/',
      () async {
        final client = _clientWith((options) {
          expect(options.method, 'POST');
          expect(options.path, '/conversations/42/send-template/');
          final body = options.data as Map<String, dynamic>;
          expect(body['template_name'], 'hello_world');
          expect(body['language'], 'en_US');
          expect(body['parameters'], ['123']);
          return _json('{"success": true}', 200);
        });

        final repo = TemplatesRepository(client);
        final result = await repo.sendConversationTemplate(
          42,
          templateName: 'hello_world',
          language: 'en_US',
          parameters: ['123'],
        );

        expect(result['success'], isTrue);
      },
    );
  });

  group('TemplatesScreen Widget', () {
    testWidgets('renders WABA account selector and template cards', (
      tester,
    ) async {
      final client = _clientWith((options) {
        if (options.path.contains('/templates/')) {
          return _json(_templatesListResponse, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _testEmployee(permissions: {'channel.view', 'channel.manage'}),
            ),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel, _sampleWhatsAppChannel2],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TemplatesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen title and subtitle
      expect(find.text('Message templates'), findsAtLeastNWidgets(1));
      expect(
        find.text(
          'Pre-approved WhatsApp messages you can send outside the 24-hour window.',
        ),
        findsOneWidget,
      );

      // WABA Selector
      expect(find.text('WhatsApp Business account'), findsOneWidget);
      expect(find.text('Scenario DM · 1189064717633052'), findsOneWidget);

      // Subheader count & buttons
      expect(find.text('3 templates on this account'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Create template'), findsOneWidget);

      // Cards
      expect(find.text('scenario12'), findsOneWidget);
      expect(find.text('promo_temp'), findsOneWidget);
      expect(find.text('bad_template'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('Your request has been received.'), findsOneWidget);
      expect(find.text('4355335634779784'), findsOneWidget);
    });

    testWidgets('hides Create Template button when lacking channel.manage', (
      tester,
    ) async {
      final client = _clientWith((options) {
        return _json(_templatesListResponse, 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _testEmployee(permissions: {'channel.view'}), // No channel.manage
            ),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TemplatesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Create template'), findsNothing);
    });

    testWidgets('shows empty state when no templates exist on account', (
      tester,
    ) async {
      final client = _clientWith((options) {
        return _json('{"templates": []}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _testEmployee(permissions: {'channel.view', 'channel.manage'}),
            ),
            channelsProvider.overrideWith(
              (ref) async => [_sampleWhatsAppChannel],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TemplatesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0 templates on this account'), findsOneWidget);
      expect(find.text('No templates found'), findsOneWidget);
    });

    testWidgets('shows empty state when no WhatsApp channels are connected', (
      tester,
    ) async {
      final client = _clientWith((options) {
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _testEmployee(permissions: {'channel.view'}),
            ),
            channelsProvider.overrideWith(
              (ref) async => [], // No channels
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TemplatesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No WhatsApp accounts connected'), findsOneWidget);
    });

    testWidgets(
      'tapping Create template opens CreateTemplateSheet without layout errors',
      (tester) async {
        final client = _clientWith((options) {
          return _json(_templatesListResponse, 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(
                _testEmployee(permissions: {'channel.view', 'channel.manage'}),
              ),
              channelsProvider.overrideWith(
                (ref) async => [_sampleWhatsAppChannel],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const TemplatesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final createBtn = find.text('Create template');
        expect(createBtn, findsOneWidget);
        await tester.tap(createBtn);
        await tester.pumpAndSettle();

        expect(find.text('Create message template'), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Submit for review'), findsOneWidget);
      },
    );
  });
}
