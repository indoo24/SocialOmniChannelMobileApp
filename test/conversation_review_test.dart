/// Conversation review: parsing, the three review endpoints, the controller
/// (only `review` changes; assignment, claim and the composer never do), the
/// error messages, and the banner, review sheet and reviewer picker in
/// English, Arabic, light and dark.
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
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_review.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_review.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';

// ---------------------------------------------------------------------------
// A backend that holds one conversation and its review.
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _conversationId = 5;

class _Server {
  /// Assigned to and claimed by Tarek, in the Sales team, one unread.
  final conversation = <String, dynamic>{
    'id': _conversationId,
    'customer': {'id': 7, 'display_name': 'Sarah Connor'},
    'provider': 'INSTAGRAM',
    'status': 'OPEN',
    'priority': 'HIGH',
    'unread_count': 1,
    'message_count': 2,
    'assigned_to': {'id': 9, 'full_name': 'Tarek Lead'},
    'claimed_by': {'id': 9, 'full_name': 'Tarek Lead'},
    'assigned_team': {'id': 4, 'name': 'Sales'},
  };

  final employees = <Map<String, dynamic>>[
    {'id': 1, 'full_name': 'Sam Agent', 'initials': 'SA', 'is_active': true},
    {
      'id': 21,
      'full_name': 'Mona Reviewer',
      'initials': 'MR',
      'role': 'SUPERVISOR',
      'role_display': 'Supervisor',
      'availability': 'ONLINE',
      'is_active': true,
    },
    {
      'id': 22,
      'full_name': 'Omar Quality',
      'initials': 'OQ',
      'role': 'QA',
      'role_display': 'Quality assurance',
      'is_active': true,
    },
    {'id': 23, 'full_name': 'Gone Person', 'is_active': false},
  ];

  /// The pending review, as the server would serialize it; null for none.
  Map<String, dynamic>? review;

  /// The `review` a completed review is answered with (null: none).
  Map<String, dynamic>? reviewAfterComplete;

  /// Every write, as `METHOD path`, and each review request's body.
  final writes = <String>[];
  final reviewBodies = <Object?>[];

  int? failStatus;
  Map<String, dynamic>? failBody;
  bool networkDown = false;
  Completer<void>? holdReview;

  Map<String, dynamic> _conversationJson() => {
    ...conversation,
    'review': review,
  };

  void startReview({int reviewerId = 21, String note = 'Check the refund'}) {
    review = {
      'id': 77,
      'status': 'PENDING',
      'note': note,
      'reviewer_id': reviewerId,
      'reviewer_name': employees.firstWhere(
        (e) => e['id'] == reviewerId,
      )['full_name'],
      'requested_by_id': 1,
      'requested_by_name': 'Sam Agent',
      'requested_at': '2026-10-19T22:43:02Z',
    };
  }

  ApiClient client({void Function(int?)? onSessionExpired}) {
    final client = ApiClient.create(
      cookieJar: CookieJar(),
      onSessionExpired: onSessionExpired,
    );
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Future<ResponseBody> _handle(RequestOptions options) async {
    final path = options.path;
    if (options.method != 'GET') writes.add('${options.method} $path');

    final reviewPath = RegExp(
      r'^/conversations/(\d+)/review/(complete/)?$',
    ).firstMatch(path);
    if (reviewPath != null) {
      reviewBodies.add(options.data);
      final hold = holdReview;
      if (hold != null) await hold.future;
      if (networkDown) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (failStatus != null) return _json(failBody ?? {}, failStatus!);
      final completing = reviewPath.group(2) != null;
      if (completing || options.method == 'DELETE') {
        if (review == null) {
          return _json({
            'error': {
              'code': 'conflict',
              'message': 'There is no review pending',
            },
          }, 409);
        }
        review = completing ? reviewAfterComplete : null;
        return _json(_conversationJson());
      }
      final body = Map<String, dynamic>.from(options.data as Map);
      final keepId = review?['id'];
      startReview(
        reviewerId: body['reviewer_id'] as int,
        note: (body['note'] as String?) ?? '',
      );
      if (keepId != null) review!['id'] = keepId;
      return _json(_conversationJson());
    }
    if (path == '/conversations/$_conversationId/') {
      return _json(_conversationJson());
    }
    if (path == '/conversations/$_conversationId/reply/') {
      return _json({
        'id': 900,
        'direction': 'OUTBOUND',
        'sender_type': 'AGENT',
        'text': (options.data as Map)['text'],
        'delivery_status': 'SENT',
        'sent_at': '2026-10-20T09:00:00Z',
      });
    }
    if (path == '/employees/') {
      final search = (options.queryParameters['search'] as String? ?? '')
          .toLowerCase();
      final rows = [
        for (final e in employees)
          if ((e['full_name'] as String).toLowerCase().contains(search)) e,
      ];
      return _json({'count': rows.length, 'next': null, 'results': rows});
    }
    if (path.contains('/messages/')) return _json({'results': []});
    if (path.contains('/notes/')) return _json([]);
    return _json({});
  }
}

Employee _employee({int id = 1, String role = 'AGENT'}) => Employee(
  id: id,
  email: 'me@acme.test',
  fullName: id == 21 ? 'Mona Reviewer' : 'Sam Agent',
  initials: 'SA',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationChangeStatus},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

ProviderContainer _container(_Server server, {Employee? me}) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWithValue(me ?? _employee()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final _detail = conversationControllerProvider(_conversationId);

Future<Conversation> _open(ProviderContainer c) async {
  c.listen(_detail, (_, _) {});
  return (await c.read(_detail.future)).conversation;
}

Conversation _shown(ProviderContainer c) => c.read(_detail).value!.conversation;

/// Everything a review action must leave alone.
void _expectUntouched(Conversation c) {
  expect(c.assignedTo?.id, 9);
  expect(c.claimedBy?.id, 9);
  expect(c.assignedTeam?.id, 4);
  expect(c.unreadCount, 1);
  expect(c.status, 'OPEN');
  expect(c.priority, 'HIGH');
}

bool _reviewWrite(String w) => w.contains('/review/');

void main() {
  // -------------------------------------------------------------------------
  group('model', () {
    final base = <String, dynamic>{
      'id': 1,
      'customer': {'id': 2, 'display_name': 'Sarah'},
      'provider': 'WHATSAPP',
      'status': 'OPEN',
      'assigned_to': {'id': 9, 'full_name': 'Tarek Lead'},
    };

    test('parses a conversation with a review', () {
      final c = Conversation.fromJson({
        ...base,
        'review': {
          'id': 1,
          'status': 'PENDING',
          'note': 'Please review this conversation.',
          'reviewer_id': 123,
          'reviewer_name': 'Reviewer Name',
          'requested_by_id': 456,
          'requested_by_name': 'Agent Name',
          'requested_at': '2026-10-19T22:43:02Z',
        },
      });
      final review = c.review!;
      expect(review.id, 1);
      expect(review.status, 'PENDING');
      expect(review.note, 'Please review this conversation.');
      expect(review.reviewerId, 123);
      expect(review.reviewerName, 'Reviewer Name');
      expect(review.requestedById, 456);
      expect(review.requestedByName, 'Agent Name');
      expect(
        review.requestedAt!.toUtc(),
        DateTime.utc(2026, 10, 19, 22, 43, 2),
      );
      expect(review.isReviewer(123), isTrue);
      expect(review.isReviewer(456), isFalse);
      expect(c.assignedTo?.id, 9);
    });

    test('no review: missing, null or not an object', () {
      for (final json in [
        base,
        {...base, 'review': null},
        {...base, 'review': 'PENDING'},
        {...base, 'review': <Object>[]},
      ]) {
        final c = Conversation.fromJson(json);
        expect(c.review, isNull);
        expect(c.assignedTo?.id, 9);
        expect(c.status, 'OPEN');
      }
    });

    test('missing and null review fields fall back safely', () {
      final review = ConversationReview.fromJson({
        'id': '3',
        'reviewer_id': null,
        'requested_at': 'not a date',
      })!;
      expect(review.id, 3);
      expect(review.status, '');
      expect(review.note, '');
      expect(review.reviewerId, isNull);
      expect(review.reviewerName, '');
      expect(review.requestedById, isNull);
      expect(review.requestedAt, isNull);
      expect(review.isReviewer(1), isFalse);
    });

    test('copyWith keeps the review unless cleared', () {
      final c = Conversation.fromJson({
        ...base,
        'review': {'id': 1, 'reviewer_id': 5},
      });
      expect(c.copyWith(unreadCount: 0).review?.id, 1);
      expect(c.copyWith(lastCustomerMessageAt: DateTime(2026)).review?.id, 1);
      expect(c.copyWith(isPinned: true).review?.id, 1);
      expect(c.copyWith(clearReview: true).review, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('repository', () {
    test('request: POST review/ with reviewer_id and the note', () async {
      final server = _Server();
      final repo = ConversationRepository(server.client());

      final updated = await repo.requestReview(
        _conversationId,
        reviewerId: 21,
        note: '  Check the refund  ',
      );

      expect(server.writes, ['POST /conversations/5/review/']);
      expect(server.reviewBodies.single, {
        'reviewer_id': 21,
        'note': 'Check the refund',
      });
      expect(updated.review?.reviewerId, 21);
      expect(updated.review?.reviewerName, 'Mona Reviewer');
    });

    test('request without a note sends reviewer_id only', () async {
      final server = _Server();
      final repo = ConversationRepository(server.client());
      await repo.requestReview(_conversationId, reviewerId: 22, note: '   ');
      expect(server.reviewBodies.single, {'reviewer_id': 22});
    });

    test(
      'withdraw is DELETE review/; complete is POST review/complete/',
      () async {
        final server = _Server()..startReview();
        final repo = ConversationRepository(server.client());

        expect((await repo.withdrawReview(_conversationId)).review, isNull);
        server.startReview();
        expect((await repo.completeReview(_conversationId)).review, isNull);

        expect(server.writes, [
          'DELETE /conversations/5/review/',
          'POST /conversations/5/review/complete/',
        ]);
        expect(server.reviewBodies, [null, null]);
      },
    );

    test('errors surface typed; 401 ends the session', () async {
      final server = _Server()
        ..failStatus = 401
        ..failBody = {
          'error': {'code': 'not_authenticated', 'message': 'x'},
        };
      var sessionEnded = 0;
      final repo = ConversationRepository(
        server.client(onSessionExpired: (_) => sessionEnded++),
      );
      await expectLater(
        repo.requestReview(_conversationId, reviewerId: 21),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(sessionEnded, 1);

      server.failBody = {
        'error': {'code': 'refused', 'message': 'Refused.'},
      };
      for (final status in [400, 403, 404, 409]) {
        server.failStatus = status;
        await expectLater(
          repo.completeReview(_conversationId),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', status),
          ),
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('error messages', () {
    ApiException error(int status) =>
        ApiException(statusCode: status, message: 'raw server text', code: 'x');

    for (final (name, l10n) in [
      ('English', AppLocalizationsEn()),
      ('Arabic', AppLocalizationsAr()),
    ]) {
      test('localized, never the raw text — $name', () {
        String msg(int status, {bool requesting = false}) =>
            reviewErrorMessage(l10n, error(status), requesting: requesting);

        expect(
          msg(400, requesting: true),
          l10n.reviewReviewerNotEligibleMessage,
        );
        expect(msg(400), l10n.reviewRequestFailedMessage);
        expect(msg(403), l10n.reviewPermissionDeniedMessage);
        expect(msg(404), l10n.conversationUnavailableMessage);
        expect(msg(409), l10n.reviewNotPendingMessage);
        expect(msg(500), l10n.reviewRequestFailedMessage);
        expect(
          reviewErrorMessage(
            l10n,
            NetworkException('offline'),
            requesting: true,
          ),
          l10n.reviewRequestFailedMessage,
        );
        for (final status in [400, 403, 404, 409, 500]) {
          expect(msg(status, requesting: true), isNot('raw server text'));
        }
      });
    }

    test('only PENDING is translated; other statuses are shown as sent', () {
      expect(reviewStatusText(AppLocalizationsAr(), 'PENDING'), 'قيد الانتظار');
      expect(reviewStatusText(AppLocalizationsEn(), 'pending'), 'Pending');
      expect(reviewStatusText(AppLocalizationsEn(), 'COMPLETED'), 'COMPLETED');
    });

    test('complete is offered to the named reviewer and to an ADMIN only', () {
      const review = ConversationReview(id: 1, reviewerId: 21);
      expect(canCompleteReview(_employee(id: 21), review), isTrue);
      expect(
        canCompleteReview(_employee(id: 3, role: 'ADMIN'), review),
        isTrue,
      );
      expect(canCompleteReview(_employee(), review), isFalse);
      expect(
        canCompleteReview(_employee(id: 3, role: 'SUPERVISOR'), review),
        isFalse,
      );
      expect(canCompleteReview(null, review), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('controller', () {
    test('a request shows the review and nothing else changes', () async {
      final server = _Server();
      final c = _container(server);
      expect((await _open(c)).review, isNull);

      final updated = await c
          .read(conversationReviewProvider.notifier)
          .request(_conversationId, reviewerId: 21, note: 'Check the refund');

      expect(updated, isNotNull);
      final shown = _shown(c);
      expect(shown.review?.reviewerId, 21);
      expect(shown.review?.note, 'Check the refund');
      _expectUntouched(shown);
      expect(server.writes.where((w) => !w.endsWith('/read/')), [
        'POST /conversations/5/review/',
      ]);
    });

    test('retargeting keeps one review, now with the new reviewer', () async {
      final server = _Server()..startReview();
      final c = _container(server);
      expect((await _open(c)).review?.reviewerId, 21);

      await c
          .read(conversationReviewProvider.notifier)
          .request(_conversationId, reviewerId: 22);

      final review = _shown(c).review!;
      expect(review.id, 77);
      expect(review.reviewerId, 22);
      expect(review.reviewerName, 'Omar Quality');
      _expectUntouched(_shown(c));
    });

    test(
      'withdraw clears it; complete shows what the server answers',
      () async {
        final server = _Server()..startReview();
        final c = _container(server);
        await _open(c);
        final reviews = c.read(conversationReviewProvider.notifier);

        await reviews.withdraw(_conversationId);
        expect(_shown(c).review, isNull);
        _expectUntouched(_shown(c));

        server
          ..startReview()
          ..reviewAfterComplete = {
            'id': 77,
            'status': 'COMPLETED',
            'reviewer_id': 21,
            'reviewer_name': 'Mona Reviewer',
          };
        c.invalidate(_detail);
        await _open(c);
        await reviews.complete(_conversationId);
        expect(_shown(c).review?.status, 'COMPLETED');
        _expectUntouched(_shown(c));
        expect(server.writes.where((w) => w.contains('/assign/')), isEmpty);
      },
    );

    test('a refusal changes nothing on screen', () async {
      final server = _Server()..startReview();
      final c = _container(server);
      await _open(c);
      server
        ..failStatus = 403
        ..failBody = {
          'error': {'code': 'permission_denied', 'message': 'No.'},
        };

      await expectLater(
        c.read(conversationReviewProvider.notifier).complete(_conversationId),
        throwsA(isA<ApiException>()),
      );
      expect(_shown(c).review?.reviewerId, 21);
      expect(c.read(conversationReviewProvider), isEmpty);
    });

    test('409: nothing pending — the screen follows the server', () async {
      final server = _Server()..startReview();
      final c = _container(server);
      await _open(c);
      // Someone else withdrew it in the meantime.
      server.review = null;

      await expectLater(
        c.read(conversationReviewProvider.notifier).withdraw(_conversationId),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 409)),
      );
      await pumpEventQueue();
      expect(_shown(c).review, isNull);
    });

    test('a second tap while one is on its way sends nothing', () async {
      final server = _Server()..holdReview = Completer<void>();
      final c = _container(server);
      await _open(c);
      final reviews = c.read(conversationReviewProvider.notifier);

      final first = reviews.request(_conversationId, reviewerId: 21);
      expect(c.read(conversationReviewProvider), {_conversationId});
      expect(await reviews.request(_conversationId, reviewerId: 22), isNull);

      server.holdReview!.complete();
      expect((await first)?.review?.reviewerId, 21);
      expect(server.reviewBodies, hasLength(1));
      expect(c.read(conversationReviewProvider), isEmpty);
    });

    test('sending a reply neither completes nor withdraws a review', () async {
      final server = _Server()..startReview();
      final c = _container(server);
      await _open(c);

      await c.read(_detail.notifier).send('We are on it');

      expect(server.writes, contains('POST /conversations/5/reply/'));
      expect(server.writes.where(_reviewWrite), isEmpty);
      expect(server.review, isNotNull);
      expect(_shown(c).review?.reviewerId, 21);
      expect(_shown(c).review?.status, 'PENDING');
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    Widget app(
      _Server server, {
      Employee? me,
      Locale locale = const Locale('en'),
      ThemeData? theme,
    }) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(me ?? _employee()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: _conversationId),
      ),
    );

    final banner = find.byKey(const Key('conversationReviewBanner'));

    final reviewButton = find.byKey(
      const Key('conversation_actions_sheet_review_button'),
    );
    final pinButton = find.byKey(
      const Key('conversation_actions_sheet_pin_button'),
    );
    Finder titled(Finder button, String title) =>
        find.descendant(of: button, matching: find.text(title));

    Future<void> openActionsSheet(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openReviewButton(WidgetTester tester) async {
      await openActionsSheet(tester);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();
    }

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('request a review from the actions sheet — $label', (
          tester,
        ) async {
          final server = _Server();
          await tester.pumpWidget(
            app(
              server,
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(banner, findsNothing);

          // At the top of the actions sheet, beside the pin, on its row —
          // the two titled buttons are all there is: no Resolve here.
          await openActionsSheet(tester);
          expect(
            tester.getCenter(reviewButton).dy,
            tester.getCenter(pinButton).dy,
          );
          final pinX = tester.getCenter(pinButton).dx;
          final reviewX = tester.getCenter(reviewButton).dx;
          expect(arabic ? reviewX < pinX : reviewX > pinX, isTrue);
          expect(
            find.byKey(const Key('conversation_actions_sheet_resolve_button')),
            findsNothing,
          );
          expect(titled(pinButton, l10n.pinConversationAction), findsOneWidget);
          expect(
            titled(reviewButton, l10n.requestReviewAction),
            findsOneWidget,
          );

          await tester.tap(reviewButton);
          await tester.pumpAndSettle();
          expect(find.text(l10n.reviewExplanation), findsOneWidget);

          // Colleagues only: not the signed-in employee, not a deactivated one.
          expect(find.text('Mona Reviewer'), findsOneWidget);
          expect(find.text('Omar Quality'), findsOneWidget);
          expect(find.text('Sam Agent'), findsNothing);
          expect(find.text('Gone Person'), findsNothing);

          // Nobody chosen yet: said so, and nothing is sent.
          await tester.tap(find.byKey(const Key('requestReviewSubmit')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.reviewReviewerRequired), findsOneWidget);
          expect(server.reviewBodies, isEmpty);

          await tester.tap(find.byKey(const ValueKey('reviewerCandidate_21')));
          await tester.enterText(
            find.byKey(const Key('reviewNoteField')),
            'Check the refund',
          );
          await tester.tap(find.byKey(const Key('requestReviewSubmit')));
          await tester.pumpAndSettle();

          expect(server.reviewBodies.single, {
            'reviewer_id': 21,
            'note': 'Check the refund',
          });
          expect(
            find.text(l10n.reviewRequestedMessage('Mona Reviewer')),
            findsOneWidget,
          );
          expect(banner, findsOneWidget);
          // On the banner — and the review button in the actions sheet
          // behind it follows the same confirmed state.
          expect(
            find.descendant(
              of: banner,
              matching: find.text(l10n.reviewWithReviewer('Mona Reviewer')),
            ),
            findsOneWidget,
          );
          expect(titled(reviewButton, l10n.reviewSectionTitle), findsOneWidget);
          expect(titled(reviewButton, l10n.requestReviewAction), findsNothing);
          expect(find.text(l10n.reviewStatusPending), findsOneWidget);
          // The composer is still there: a review does not lock replying.
          expect(find.byType(EditableText), findsWidgets);
          expect(server.writes.where((w) => w.contains('/assign/')), isEmpty);
          expect(tester.takeException(), isNull);
        });

        testWidgets('the review sheet: details and the reviewer\'s actions — '
            '$label', (tester) async {
          final server = _Server()..startReview();
          await tester.pumpWidget(
            app(
              server,
              me: _employee(id: 21, role: 'SUPERVISOR'),
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(banner);
          await tester.pumpAndSettle();

          expect(find.text('Mona Reviewer'), findsOneWidget);
          expect(find.text('Sam Agent'), findsOneWidget);
          expect(find.text('Check the refund'), findsOneWidget);
          expect(find.text(l10n.completeReviewAction), findsOneWidget);
          expect(find.text(l10n.changeReviewerAction), findsOneWidget);
          expect(find.text(l10n.withdrawReviewAction), findsOneWidget);

          await tester.tap(find.byKey(const Key('completeReviewButton')));
          await tester.pumpAndSettle();

          expect(server.writes.where(_reviewWrite), [
            'POST /conversations/5/review/complete/',
          ]);
          expect(find.text(l10n.reviewCompletedMessage), findsOneWidget);
          expect(banner, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('someone other than the reviewer is not offered Complete', (
      tester,
    ) async {
      final server = _Server()..startReview();
      await tester.pumpWidget(app(server));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completeReviewButton')), findsNothing);
      expect(find.byKey(const Key('withdrawReviewButton')), findsOneWidget);
      expect(find.byKey(const Key('changeReviewerButton')), findsOneWidget);
    });

    testWidgets('an ADMIN may complete someone else\'s review', (tester) async {
      final server = _Server()..startReview();
      await tester.pumpWidget(app(server, me: _employee(id: 3, role: 'ADMIN')));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('completeReviewButton')), findsOneWidget);
    });

    testWidgets('withdraw asks first, then removes the review', (tester) async {
      final server = _Server()..startReview();
      await tester.pumpWidget(app(server));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('withdrawReviewButton')));
      await tester.pumpAndSettle();
      expect(find.text('Withdraw this review?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.writes.where(_reviewWrite), isEmpty);

      await tester.tap(find.byKey(const Key('withdrawReviewButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('withdrawReviewConfirm')));
      await tester.pumpAndSettle();

      expect(server.writes.where(_reviewWrite), [
        'DELETE /conversations/5/review/',
      ]);
      expect(find.text('Review withdrawn'), findsOneWidget);
      expect(banner, findsNothing);
    });

    testWidgets('change reviewer retargets with the same endpoint', (
      tester,
    ) async {
      final server = _Server()..startReview();
      await tester.pumpWidget(app(server));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('changeReviewerButton')));
      await tester.pumpAndSettle();

      expect(find.text('Current reviewer'), findsOneWidget);
      // The pending note is carried over for editing.
      expect(find.text('Check the refund'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reviewerCandidate_22')));
      await tester.tap(find.byKey(const Key('requestReviewSubmit')));
      await tester.pumpAndSettle();

      expect(server.writes.where(_reviewWrite), [
        'POST /conversations/5/review/',
      ]);
      expect(server.reviewBodies.single, {
        'reviewer_id': 22,
        'note': 'Check the refund',
      });
      expect(find.text('Reviewer changed to Omar Quality'), findsOneWidget);
      expect(find.text('Reviewer: Omar Quality'), findsOneWidget);
    });

    testWidgets('400: the localized reason; the sheet stays and can retry', (
      tester,
    ) async {
      final server = _Server()
        ..failStatus = 400
        ..failBody = {
          'error': {'code': 'invalid', 'message': 'reviewer_id: not eligible'},
        };
      await tester.pumpWidget(app(server));
      await tester.pumpAndSettle();
      await openReviewButton(tester);

      await tester.tap(find.byKey(const ValueKey('reviewerCandidate_22')));
      await tester.tap(find.byKey(const Key('requestReviewSubmit')));
      await tester.pumpAndSettle();

      expect(
        find.text("This person can't be asked to review this conversation."),
        findsOneWidget,
      );
      expect(find.textContaining('not eligible'), findsNothing);
      expect(banner, findsNothing);

      // Controls are back; another colleague goes through.
      server.failStatus = null;
      await tester.tap(find.byKey(const ValueKey('reviewerCandidate_21')));
      await tester.tap(find.byKey(const Key('requestReviewSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Review requested from Mona Reviewer'), findsOneWidget);
      expect(banner, findsOneWidget);
    });

    testWidgets('409 on complete: says so and shows what the server holds', (
      tester,
    ) async {
      final server = _Server()..startReview();
      await tester.pumpWidget(app(server, me: _employee(id: 21)));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();

      server.review = null; // completed elsewhere meanwhile
      await tester.tap(find.byKey(const Key('completeReviewButton')));
      await tester.pumpAndSettle();

      expect(
        find.text("There's no review pending on this conversation."),
        findsOneWidget,
      );
      expect(banner, findsNothing);
      expect(find.text('Review completed'), findsNothing);
    });

    testWidgets('offline: the failure is said and the button comes back', (
      tester,
    ) async {
      final server = _Server()
        ..startReview()
        ..networkDown = true;
      await tester.pumpWidget(app(server, me: _employee(id: 21)));
      await tester.pumpAndSettle();
      await tester.tap(banner);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('completeReviewButton')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't update the review. Please try again."),
        findsOneWidget,
      );
      expect(banner, findsOneWidget);

      server.networkDown = false;
      await tester.tap(find.byKey(const Key('completeReviewButton')));
      await tester.pumpAndSettle();
      expect(find.text('Review completed'), findsOneWidget);
    });
  });
}
