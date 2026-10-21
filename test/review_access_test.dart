/// Who gets the Need review tab, its count, and the reviewer list.
///
/// The rule is the backend's capability, not a role label: `conversation.review`,
/// which `API.md` and the live OpenAPI give to ADMIN and SUPERVISOR only. A
/// team leader, an agent and QA do not hold it, so they get no Need review tab
/// (not a disabled one), no review count request, and no way to select the
/// filter. The reviewer list is the server's own (`GET /conversations/reviewers/`).
///
/// These are unit, widget and stub-server tests. The stub follows the
/// documented endpoints; none of this proves the real server enforces the
/// policy, which was read from its published schema and not exercised with
/// an unauthorized account (see `docs/MOBILE_BACKEND_SYNC.md`, R5).
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
import 'package:scenario_mobile/core/session/session_reset.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/review_count.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';

// ---------------------------------------------------------------------------
// Employees, with the capabilities each role really holds.
// ---------------------------------------------------------------------------

/// `conversation.review` is held by ADMIN and SUPERVISOR (`API.md`, §Roles &
/// capabilities); everyone who talks to customers can reply.
Employee _employeeWithRole(String role, {int id = 1}) => Employee(
  id: id,
  email: 'e$id@acme.test',
  fullName: 'Employee $id',
  initials: 'E$id',
  role: role,
  roleDisplay: role,
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    if (role == 'ADMIN' || role == 'SUPERVISOR') Perm.conversationReview,
  },
  visibilityScope: 'ALL',
);

const _roles = ['ADMIN', 'SUPERVISOR', 'TEAM_LEADER', 'AGENT', 'QA'];
const _mayReview = {'ADMIN', 'SUPERVISOR'};

/// Who is signed in, switchable from a test.
class _Who extends Notifier<Employee?> {
  @override
  Employee? build() => _employeeWithRole('SUPERVISOR');

  void signInAs(Employee? e) => state = e;

  /// What `AuthController` does to end a session: its own state first, then
  /// the session reset, from its own `ref`.
  void signOutLikeAuthController() {
    state = null;
    clearSessionScopedState(ref);
  }
}

final _whoProvider = NotifierProvider<_Who, Employee?>(_Who.new);

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

class _Server {
  int countRequests = 0;
  int reviewerRequests = 0;
  final reviewerPages = <Object>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((o) {
      final path = o.uri.path;
      if (path.endsWith('/conversations/counts/')) {
        countRequests++;
        return _json({'all': 5, 'review_mine': 4});
      }
      if (path.endsWith('/conversations/reviewers/')) {
        reviewerRequests++;
        final page = int.parse('${o.queryParameters['page'] ?? 1}');
        return _json(reviewerPages[page - 1]);
      }
      return _json({'count': 0, 'results': []});
    });
    return client;
  }
}

ProviderContainer _container(_Server server, {Employee? me}) {
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWith((ref) => ref.watch(_whoProvider)),
    ],
  );
  addTearDown(c.dispose);
  if (me != null) c.read(_whoProvider.notifier).signInAs(me);
  return c;
}

Widget _bar(
  ProviderContainer c, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: InboxQuickFilterBar()),
  ),
);

const _needsReview = Key('quick_filter_needs_review');

/// The tabs in the order drawn, by key.
List<String> _tabKeysInOrder(WidgetTester tester, {required bool rtl}) {
  final keys = [
    for (final f in InboxQuickFilter.values)
      'quick_filter_${switch (f) {
        InboxQuickFilter.needsReview => 'needs_review',
        _ => f.name,
      }}',
  ];
  final shown = [
    for (final k in keys)
      if (find.byKey(Key(k)).evaluate().isNotEmpty) k,
  ];
  shown.sort((a, b) {
    final ax = tester.getCenter(find.byKey(Key(a))).dx;
    final bx = tester.getCenter(find.byKey(Key(b))).dx;
    return rtl ? bx.compareTo(ax) : ax.compareTo(bx);
  });
  return shown;
}

void main() {
  // -------------------------------------------------------------------------
  group('which tabs a capability gets', () {
    test('with the capability: All, Mine, Need review, Unread, Resolved, '
        'then Unassigned and Open', () {
      expect(visibleQuickFilters(canReview: true), [
        InboxQuickFilter.all,
        InboxQuickFilter.mine,
        InboxQuickFilter.needsReview,
        InboxQuickFilter.unread,
        InboxQuickFilter.resolved,
        InboxQuickFilter.unassigned,
        InboxQuickFilter.open,
      ]);
    });

    test('without it: the same tabs in the same order, Need review gone', () {
      expect(visibleQuickFilters(canReview: false), [
        InboxQuickFilter.all,
        InboxQuickFilter.mine,
        InboxQuickFilter.unread,
        InboxQuickFilter.resolved,
        InboxQuickFilter.unassigned,
        InboxQuickFilter.open,
      ]);
    });
  });

  // -------------------------------------------------------------------------
  group('the bar, by role', () {
    for (final role in _roles) {
      final sees = _mayReview.contains(role);
      testWidgets('$role ${sees ? 'sees' : 'does not see'} Need review, with '
          'the others in order', (tester) async {
        final c = _container(_Server(), me: _employeeWithRole(role));
        await tester.pumpWidget(_bar(c));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_needsReview),
          sees ? findsOneWidget : findsNothing,
          reason: role,
        );
        // Not merely disabled: the label is nowhere on screen either.
        expect(
          find.text(AppLocalizationsEn().needsReviewFilter),
          sees ? findsOneWidget : findsNothing,
        );
        expect(_tabKeysInOrder(tester, rtl: false), [
          'quick_filter_all',
          'quick_filter_mine',
          if (sees) 'quick_filter_needs_review',
          'quick_filter_unread',
          'quick_filter_resolved',
          'quick_filter_unassigned',
          'quick_filter_open',
        ]);
      });
    }

    testWidgets('it follows the capability, not the role label', (
      tester,
    ) async {
      // A "SUPERVISOR" the server did not give the capability to.
      final label = _employeeWithRole('SUPERVISOR');
      final withoutCapability = Employee(
        id: label.id,
        email: label.email,
        fullName: label.fullName,
        initials: label.initials,
        role: 'SUPERVISOR',
        roleDisplay: 'Supervisor',
        availability: 'ONLINE',
        permissions: const {Perm.conversationReply},
        visibilityScope: 'ALL',
      );
      final c = _container(_Server(), me: withoutCapability);
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      expect(find.byKey(_needsReview), findsNothing);

      // And an "AGENT" the server did give it to.
      final granted = Employee(
        id: 2,
        email: 'g@acme.test',
        fullName: 'Granted',
        initials: 'G',
        role: 'AGENT',
        roleDisplay: 'Agent',
        availability: 'ONLINE',
        permissions: const {Perm.conversationReply, Perm.conversationReview},
        visibilityScope: 'ALL',
      );
      c.read(_whoProvider.notifier).signInAs(granted);
      await tester.pumpAndSettle();
      expect(find.byKey(_needsReview), findsOneWidget);
    });

    testWidgets('signed out: no Need review', (tester) async {
      final c = _container(_Server());
      c.read(_whoProvider.notifier).signInAs(null);
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      expect(find.byKey(_needsReview), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic' : 'English'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('an agent\'s tabs read All, Mine, Unread, Resolved — '
            '$label', (tester) async {
          final c = _container(_Server(), me: _employeeWithRole('AGENT'));
          await tester.pumpWidget(
            _bar(
              c,
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          expect(_tabKeysInOrder(tester, rtl: arabic), [
            'quick_filter_all',
            'quick_filter_mine',
            'quick_filter_unread',
            'quick_filter_resolved',
            'quick_filter_unassigned',
            'quick_filter_open',
          ]);
          expect(find.text(l10n.needsReviewFilter), findsNothing);
        });

        testWidgets('a supervisor\'s tabs, Need review third — $label', (
          tester,
        ) async {
          final c = _container(_Server(), me: _employeeWithRole('SUPERVISOR'));
          await tester.pumpWidget(
            _bar(
              c,
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(_tabKeysInOrder(tester, rtl: arabic).take(5), [
            'quick_filter_all',
            'quick_filter_mine',
            'quick_filter_needs_review',
            'quick_filter_unread',
            'quick_filter_resolved',
          ]);
          expect(find.text(l10n.needsReviewFilter), findsOneWidget);
        });
      }
    }

    testWidgets('a narrow screen without Need review scrolls without '
        'overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final c = _container(_Server(), me: _employeeWithRole('AGENT'));
      await tester.pumpWidget(_bar(c, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the count', () {
    for (final role in _roles) {
      final sees = _mayReview.contains(role);
      testWidgets(
        '$role: ${sees ? 'asked for and shown' : 'never asked for, '
                  'no badge'}',
        (tester) async {
          final server = _Server();
          final c = _container(server, me: _employeeWithRole(role));
          await tester.pumpWidget(_bar(c));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('review_count_badge')),
            sees ? findsOneWidget : findsNothing,
          );
          expect(server.countRequests, sees ? 1 : 0, reason: role);
          if (sees) expect(await c.read(reviewCountProvider(1).future), 4);
        },
      );
    }

    testWidgets('an agent who is re-read (resume, socket, push) is still '
        'never asked', (tester) async {
      final server = _Server();
      final c = _container(server, me: _employeeWithRole('AGENT'));
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        c.invalidate(reviewCountProvider);
        await tester.pumpAndSettle();
      }
      expect(server.countRequests, 0);
    });
  });

  // -------------------------------------------------------------------------
  group('selection stays valid', () {
    test('an agent cannot select Need review', () {
      final c = _container(_Server(), me: _employeeWithRole('AGENT'));
      final filters = c.read(inboxFiltersProvider.notifier);
      filters.selectQuickFilter(InboxQuickFilter.unread);
      filters.selectQuickFilter(InboxQuickFilter.needsReview);

      final state = c.read(inboxFiltersProvider);
      expect(state.needsMyReview, isFalse);
      // Left as it was, not cleared.
      expect(state.activeQuickFilter, InboxQuickFilter.unread);
      expect(state.toQuery(1, 1).containsKey('review'), isFalse);
    });

    testWidgets('losing the capability while Need review is selected goes '
        'back to All and keeps search and accounts', (tester) async {
      final c = _container(_Server(), me: _employeeWithRole('SUPERVISOR'));
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      final filters = c.read(inboxFiltersProvider.notifier);
      filters.update(
        const ConversationFilters(
          search: 'refund',
          selectedAccounts: {'WHATSAPP': 5},
          channelConnections: [5],
        ),
      );
      filters.selectQuickFilter(InboxQuickFilter.needsReview);
      await tester.pumpAndSettle();
      expect(c.read(inboxFiltersProvider).needsMyReview, isTrue);
      expect(c.read(inboxFiltersProvider).toQuery(1, 1)['review'], 'mine');

      // Role changed, or someone else signed in.
      c.read(_whoProvider.notifier).signInAs(_employeeWithRole('AGENT'));
      await tester.pumpAndSettle();

      final state = c.read(inboxFiltersProvider);
      expect(state.needsMyReview, isFalse);
      expect(state.activeQuickFilter, InboxQuickFilter.all);
      expect(state.toQuery(1, 1).containsKey('review'), isFalse);
      expect(state.search, 'refund');
      expect(state.channelConnections, [5]);
    });

    testWidgets('a role that changed while the inbox was away is put right '
        'when it comes back', (tester) async {
      final c = _container(_Server(), me: _employeeWithRole('SUPERVISOR'));
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.needsReview);
      c.read(_whoProvider.notifier).signInAs(_employeeWithRole('AGENT'));
      expect(c.read(inboxFiltersProvider).needsMyReview, isTrue);

      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();

      expect(c.read(inboxFiltersProvider).needsMyReview, isFalse);
      expect(find.byKey(_needsReview), findsNothing);
    });

    test('losing the capability on another tab changes nothing', () {
      final c = _container(_Server(), me: _employeeWithRole('SUPERVISOR'));
      final filters = c.read(inboxFiltersProvider.notifier);
      filters.selectQuickFilter(InboxQuickFilter.resolved);
      c.read(_whoProvider.notifier).signInAs(_employeeWithRole('AGENT'));
      expect(
        c.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.resolved,
      );
    });

    testWidgets('the bar drops the tab and shows All selected', (tester) async {
      final c = _container(_Server(), me: _employeeWithRole('SUPERVISOR'));
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_needsReview));
      await tester.pumpAndSettle();
      expect(
        c.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.needsReview,
      );

      c.read(_whoProvider.notifier).signInAs(_employeeWithRole('AGENT'));
      await tester.pumpAndSettle();

      expect(find.byKey(_needsReview), findsNothing);
      expect(
        c.read(inboxFiltersProvider).activeQuickFilter,
        InboxQuickFilter.all,
      );
      final all = find.descendant(
        of: find.byKey(const Key('quick_filter_all')),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(all, findsOneWidget);
    });

    test('the other tabs ask the server exactly what they did before, for an '
        'agent', () {
      final c = _container(_Server(), me: _employeeWithRole('AGENT'));
      ConversationFilters tab(InboxQuickFilter f) {
        c.read(inboxFiltersProvider.notifier).selectQuickFilter(f);
        return c.read(inboxFiltersProvider);
      }

      expect(tab(InboxQuickFilter.all).toQuery(1, 7), {'page': 1});
      expect(tab(InboxQuickFilter.mine).toQuery(1, 7), {
        'page': 1,
        'assigned_to': 7,
      });
      expect(tab(InboxQuickFilter.unread).toQuery(1, 7), {
        'page': 1,
        'unread': true,
      });
      expect(tab(InboxQuickFilter.resolved).toQuery(1, 7), {
        'page': 1,
        'status': 'RESOLVED',
      });
    });
  });

  // -------------------------------------------------------------------------
  // The auth controller ends a session by invalidating the inbox providers
  // from its own ref. If anything in the inbox's dependency chain depended on
  // who is signed in, Riverpod would call that a circular dependency
  // ("CircularDependencyError ... InboxController") at sign-out.
  group('signing out with the real inbox', () {
    test('no CircularDependencyError, and the state is reset', () async {
      final server = _Server();
      final c = _container(server, me: _employeeWithRole('SUPERVISOR'));
      c.listen(inboxControllerProvider, (_, _) {});
      await c.read(inboxControllerProvider.future);
      c
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.needsReview);
      await c.read(inboxControllerProvider.future);

      c.read(_whoProvider.notifier).signOutLikeAuthController();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(inboxFiltersProvider).needsMyReview, isFalse);
    });

    testWidgets('with the tab bar on screen as well', (tester) async {
      final server = _Server();
      final c = _container(server, me: _employeeWithRole('SUPERVISOR'));
      c.listen(inboxControllerProvider, (_, _) {});
      await tester.pumpWidget(_bar(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_needsReview));
      await tester.pumpAndSettle();

      c.read(_whoProvider.notifier).signOutLikeAuthController();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(_needsReview), findsNothing);
    });

    test('and again as a different employee', () async {
      final server = _Server();
      final c = _container(server, me: _employeeWithRole('SUPERVISOR'));
      c.listen(inboxControllerProvider, (_, _) {});
      await c.read(inboxControllerProvider.future);
      c.read(_whoProvider.notifier).signOutLikeAuthController();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      c.read(_whoProvider.notifier).signInAs(_employeeWithRole('AGENT'));
      await c.read(inboxControllerProvider.future);
      c.read(_whoProvider.notifier).signOutLikeAuthController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  // -------------------------------------------------------------------------
  group('the reviewer list (GET /conversations/reviewers/)', () {
    Map<String, dynamic> brief(int id, String name) => {
      'id': id,
      'full_name': name,
      'initials': name.substring(0, 1),
      'avatar_url': '',
      'availability': 'ONLINE',
    };

    test('a plain array is one page', () async {
      final server = _Server()
        ..reviewerPages.add([brief(21, 'Mona'), brief(22, 'Omar')]);
      final c = _container(server, me: _employeeWithRole('AGENT'));
      final list = await c.read(conversationRepositoryProvider).reviewers();
      expect([for (final e in list) e.id], [21, 22]);
      expect(list.first.fullName, 'Mona');
      expect(server.reviewerRequests, 1);
    });

    test('a paginated answer is read to the end, without duplicates', () async {
      final server = _Server()
        ..reviewerPages.addAll([
          {
            'count': 3,
            'next': 'https://x.test/?page=2',
            'results': [brief(21, 'Mona'), brief(22, 'Omar')],
          },
          {
            'count': 3,
            'next': null,
            'results': [brief(22, 'Omar'), brief(23, 'Nour')],
          },
        ]);
      final c = _container(server, me: _employeeWithRole('AGENT'));
      final list = await c.read(conversationRepositoryProvider).reviewers();
      expect([for (final e in list) e.id], [21, 22, 23]);
      expect(server.reviewerRequests, 2);
    });

    test(
      'rows without a usable id, or that are malformed, are dropped',
      () async {
        final server = _Server()
          ..reviewerPages.add([
            brief(21, 'Mona'),
            {'full_name': 'No id'},
            {'id': 0, 'full_name': 'Zero'},
            'not a row',
          ]);
        final c = _container(server, me: _employeeWithRole('AGENT'));
        final list = await c.read(conversationRepositoryProvider).reviewers();
        expect([for (final e in list) e.id], [21]);
      },
    );

    test('nobody listed is an empty list, not an error', () async {
      final server = _Server()..reviewerPages.add(<Object>[]);
      final c = _container(server, me: _employeeWithRole('AGENT'));
      expect(await c.read(conversationRepositoryProvider).reviewers(), isEmpty);
    });
  });
}
