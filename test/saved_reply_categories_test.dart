/// Saved-reply categories: the Categories panel (add, rename, delete, order),
/// the replies grouped in the categories' saved order with Uncategorized
/// last, moving a reply between categories, failures and reconciliation —
/// against a stub of `/saved-reply-categories/` and `/saved-replies/`.
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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/saved_replies/saved_replies_settings_screen.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply_picker.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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
  body == null ? '' : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _page(List<Object?> results) => {
  'count': results.length,
  'page': 1,
  'page_size': 100,
  'total_pages': 1,
  'next': null,
  'previous': null,
  'results': results,
};

/// Categories and replies as the backend keeps them.
class _Server {
  _Server({List<Map<String, Object?>>? categories, this.replies = const []})
    : categories =
          categories ??
          [
            _cat(1, 'Returns', 0),
            _cat(2, 'Billing', 1),
            _cat(3, 'Shipping', 2),
          ];

  List<Map<String, Object?>> categories;
  List<Map<String, Object?>> replies;
  final writes = <RequestOptions>[];

  /// The next reorder fails with this status, changing nothing.
  int? failReorder;

  /// Holds reorder answers until completed.
  Completer<void>? holdReorder;

  bool failCategoryList = false;

  static Map<String, Object?> _cat(int id, String name, int position) => {
    'id': id,
    'public_id': 'c$id',
    'name': name,
    'position': position,
  };

  Map<String, Object?> _catJson(Map<String, Object?> c) => {
    ...c,
    'reply_count': replies.where((r) => r['category_id'] == c['id']).length,
  };

  /// Deliberately not in position order: the app must sort by `position`.
  List<Map<String, Object?>> get _categoriesJson => [
    for (final c in categories.reversed) _catJson(c),
  ];

  Map<String, Object?> _replyJson(Map<String, Object?> r) {
    final id = r['category_id'];
    final c = categories.where((c) => c['id'] == id).firstOrNull;
    return {
      ...r,
      'category': c?['name'] ?? r['category'] ?? '',
      'category_position': c?['position'],
    };
  }

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Future<ResponseBody> _handle(RequestOptions o) async {
    final path = o.path;
    if (o.method != 'GET') writes.add(o);
    final body = o.data is Map
        ? Map<String, dynamic>.from(o.data as Map)
        : <String, dynamic>{};

    if (path == '/saved-reply-categories/reorder/') {
      final hold = holdReorder;
      if (hold != null) await hold.future;
      if (failReorder != null) {
        final status = failReorder!;
        failReorder = null;
        return _json({
          'error': {'code': 'error', 'message': 'Server error.', 'details': {}},
        }, status);
      }
      final ids = (body['ids'] as List).cast<int>();
      categories = [
        for (var i = 0; i < ids.length; i++)
          {...categories.firstWhere((c) => c['id'] == ids[i]), 'position': i},
      ];
      return _json(_page(_categoriesJson));
    }
    if (path == '/saved-reply-categories/') {
      if (o.method == 'GET') {
        if (failCategoryList) {
          return _json({
            'error': {'code': 'error', 'message': 'Down.', 'details': {}},
          }, 500);
        }
        return _json(_page(_categoriesJson));
      }
      final name = body['name'] as String;
      if (categories.any(
        (c) => (c['name'] as String).toLowerCase() == name.toLowerCase(),
      )) {
        return _json({
          'error': {
            'code': 'validation_error',
            'message': 'Invalid input.',
            'details': {
              'name': ['A category with this name already exists.'],
            },
          },
        }, 400);
      }
      final created = _cat(
        categories.fold<int>(
              0,
              (m, c) => (c['id'] as int) > m ? c['id'] as int : m,
            ) +
            1,
        name,
        categories.length,
      );
      categories = [...categories, created];
      return _json(_catJson(created), 201);
    }
    final catMatch = RegExp(
      r'^/saved-reply-categories/(\d+)/$',
    ).firstMatch(path);
    if (catMatch != null) {
      final id = int.parse(catMatch.group(1)!);
      if (o.method == 'PATCH') {
        categories = [
          for (final c in categories)
            c['id'] == id ? {...c, 'name': body['name']} : c,
        ];
        return _json(_catJson(categories.firstWhere((c) => c['id'] == id)));
      }
      if (o.method == 'DELETE') {
        categories = [
          for (final c in categories)
            if (c['id'] != id) c,
        ];
        replies = [
          for (final r in replies)
            r['category_id'] == id
                ? {...r, 'category_id': null, 'category': ''}
                : r,
        ];
        return _json(null, 204);
      }
    }
    if (path == '/saved-replies/') {
      if (o.method == 'GET') {
        return _json(_page([for (final r in replies) _replyJson(r)]));
      }
      final created = _reply(
        900,
        body['title'] as String,
        categoryId: body['category_id'] as int?,
      );
      replies = [...replies, created];
      return _json(_replyJson(created), 201);
    }
    final replyMatch = RegExp(r'^/saved-replies/(\d+)/$').firstMatch(path);
    if (replyMatch != null && o.method == 'PATCH') {
      final id = int.parse(replyMatch.group(1)!);
      replies = [
        for (final r in replies) r['id'] == id ? {...r, ...body} : r,
      ];
      return _json(_replyJson(replies.firstWhere((r) => r['id'] == id)));
    }
    return _json({});
  }
}

Map<String, Object?> _reply(
  int id,
  String title, {
  int? categoryId,
  int position = 0,
  String category = '',
}) => {
  'id': id,
  'public_id': 'r$id',
  'title': title,
  'shortcut': '',
  'body': '$title body',
  'category': category,
  'category_id': categoryId,
  'position': position,
  'scope': 'personal',
  'team': null,
  'is_active': true,
  'can_edit': true,
};

Employee _employee({bool manage = true}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, if (manage) Perm.savedReplyManage},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  bool manage = true,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(_employee(manage: manage)),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SavedRepliesSettingsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(int id) => find.byKey(ValueKey('saved-reply-category-$id'));
Finder _section(Object id) => find.byKey(Key('saved-reply-section-$id'));

/// The panel's rows, top to bottom, by id.
List<int> _rowOrder(WidgetTester tester, List<int> ids) {
  final ys = {for (final id in ids) id: tester.getTopLeft(_row(id)).dy};
  return ids.toList()..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

/// The list's sections, top to bottom.
List<Object> _sectionOrder(WidgetTester tester, List<Object> ids) {
  final present = [
    for (final id in ids)
      if (_section(id).evaluate().isNotEmpty) id,
  ];
  final ys = {for (final id in present) id: tester.getTopLeft(_section(id)).dy};
  return present..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

Map<String, dynamic> _bodyOf(RequestOptions o) =>
    Map<String, dynamic>.from(o.data as Map);

void main() {
  // -------------------------------------------------------------------------
  group('grouping', () {
    SavedReply r(int id, {int? cat, int pos = 0, String name = ''}) =>
        SavedReply.fromJson(
          _reply(id, 'R$id', categoryId: cat, position: pos, category: name),
        );
    const cats = [
      SavedReplyCategory(id: 2, name: 'Billing', position: 0),
      SavedReplyCategory(id: 1, name: 'Returns', position: 1),
      SavedReplyCategory(id: 3, name: 'Empty', position: 2),
    ];

    test('sections follow the categories; Uncategorized is last', () {
      final sections = sectionSavedReplies(cats, [
        r(10, cat: 1, pos: 2),
        r(11),
        r(12, cat: 2),
        r(13, cat: 1, pos: 1),
        r(14, cat: 99, name: 'Deleted'), // not among the categories
        r(15, name: 'returns '), // a name only, matching Returns
      ]);
      expect([for (final s in sections) s.category?.id], [2, 1, 3, null]);
      expect(
        [for (final s in sections) s.replies.map((e) => e.id).toList()],
        [
          [12],
          [15, 13, 10], // by position; 15 (0) first
          <int>[],
          [11, 14],
        ],
      );
    });

    test('no uncategorized section when every reply has a category', () {
      final sections = sectionSavedReplies(cats, [r(1, cat: 2)]);
      expect(sections.last.category?.id, 3);
    });

    test('the composer groups in the category order too', () {
      SavedReply p(int id, String cat, int? catPos, {int pos = 0}) =>
          SavedReply.fromJson({
            ..._reply(id, 'R$id', category: cat, position: pos),
            'category_position': catPos,
          });
      final groups = groupSavedRepliesByCategory([
        p(1, 'Returns', 1),
        p(2, '', null),
        p(3, 'Billing', 0, pos: 5),
        p(4, 'Billing', 0, pos: 1),
        p(5, 'Legacy', null),
      ]);
      expect(
        [for (final g in groups) g.category],
        ['Billing', 'Returns', 'Legacy', ''],
      );
      expect([for (final x in groups.first.replies) x.id], [4, 3]);
    });

    test('new fields parse; missing ones default', () {
      final reply = SavedReply.fromJson({
        ..._reply(1, 'X', categoryId: 7, position: 3),
        'category_position': 2,
      });
      expect(reply.categoryId, 7);
      expect(reply.position, 3);
      expect(reply.categoryPosition, 2);
      final old = SavedReply.fromJson({'id': 2, 'title': 'Y', 'body': 'b'});
      expect(old.categoryId, isNull);
      expect(old.position, 0);
      final c = SavedReplyCategory.fromJson({
        'id': 4,
        'name': 'Z',
        'position': 1,
        'reply_count': 6,
      });
      expect((c.id, c.name, c.position, c.replyCount), (4, 'Z', 1, 6));
    });
  });

  // -------------------------------------------------------------------------
  group('panel and sections', () {
    _Server server() => _Server(
      replies: [
        _reply(1, 'Refund policy', categoryId: 1),
        _reply(2, 'Exchange', categoryId: 1, position: 1),
        _reply(3, 'Prices', categoryId: 2),
        _reply(4, 'Hello'),
      ],
    );

    testWidgets('categories in their saved order, with counts; the replies '
        'grouped the same way, Uncategorized last', (tester) async {
      final s = server();
      await _pump(tester, s);

      expect(_rowOrder(tester, [1, 2, 3]), [1, 2, 3]);
      expect(
        find.byKey(const Key('saved-reply-category-1-count')),
        findsOneWidget,
      );
      expect(find.text('2 replies'), findsOneWidget);
      expect(find.text('1 reply'), findsOneWidget);
      expect(find.text('No replies'), findsOneWidget);

      expect(_sectionOrder(tester, [1, 2, 3, 'uncategorized']), [
        1,
        2,
        3,
        'uncategorized',
      ]);
      expect(
        find.descendant(of: _section(3), matching: find.text('SHIPPING')),
        findsOneWidget,
      );
      expect(
        find.text('No saved replies in this category yet.'),
        findsOneWidget,
      );
      // Refund policy above Exchange: their positions.
      expect(
        tester.getTopLeft(find.text('Refund policy')).dy <
            tester.getTopLeft(find.text('Exchange')).dy,
        isTrue,
      );
      // And every reply above Hello, the uncategorized one.
      expect(
        tester.getTopLeft(find.text('Prices')).dy <
            tester.getTopLeft(find.text('Hello')).dy,
        isTrue,
      );
    });

    testWidgets('add: empty and exact duplicates are refused here; the '
        'server\'s refusal is shown; a new one goes last', (tester) async {
      final s = server();
      await _pump(tester, s);
      final field = find.byKey(const Key('saved-reply-category-name'));
      final add = find.byKey(const Key('saved-reply-category-add'));

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);

      await tester.enterText(field, 'Billing');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        find.text('A category with this name already exists.'),
        findsOneWidget,
      );
      expect(s.writes, isEmpty);

      // The server's own rule: case does not make it new.
      await tester.enterText(field, 'billing');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(s.writes.single.path, '/saved-reply-categories/');
      expect(
        find.text('A category with this name already exists.'),
        findsOneWidget,
      );
      expect(_row(4), findsNothing);

      await tester.enterText(field, '  Warranty  ');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(_bodyOf(s.writes.last), {'name': 'Warranty'});
      expect(find.text('Category added'), findsOneWidget);
      expect(_rowOrder(tester, [1, 2, 3, 4]), [1, 2, 3, 4]);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    });

    testWidgets('rename keeps the order and the replies', (tester) async {
      final s = server();
      await _pump(tester, s);

      await tester.tap(find.byKey(const Key('saved-reply-category-2-rename')));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('saved-reply-category-rename-field'));
      expect(tester.widget<TextField>(input).controller!.text, 'Billing');

      await tester.enterText(input, '');
      await tester.tap(
        find.byKey(const Key('saved-reply-category-rename-save')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);

      await tester.enterText(input, 'Payments');
      await tester.tap(
        find.byKey(const Key('saved-reply-category-rename-save')),
      );
      await tester.pumpAndSettle();

      expect(s.writes.single.method, 'PATCH');
      expect(s.writes.single.path, '/saved-reply-categories/2/');
      expect(_bodyOf(s.writes.single), {'name': 'Payments'});
      expect(find.text('Category renamed'), findsOneWidget);
      expect(_rowOrder(tester, [1, 2, 3]), [1, 2, 3]);
      expect(
        find.descendant(of: _section(2), matching: find.text('PAYMENTS')),
        findsOneWidget,
      );
      expect(find.text('Prices'), findsOneWidget);
    });

    testWidgets('delete asks first, says the replies move, and moves them', (
      tester,
    ) async {
      final s = server();
      await _pump(tester, s);

      await tester.tap(find.byKey(const Key('saved-reply-category-1-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Returns”?'), findsOneWidget);
      expect(
        find.text(
          'Its 2 saved replies will move to Uncategorized. The replies '
          'themselves are not deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.writes, isEmpty);

      await tester.tap(find.byKey(const Key('saved-reply-category-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('saved-reply-category-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(s.writes.single.method, 'DELETE');
      expect(s.writes.single.path, '/saved-reply-categories/1/');
      expect(_row(1), findsNothing);
      expect(_section(1), findsNothing);
      // The replies are kept, now uncategorized; no reply was deleted.
      for (final title in ['Refund policy', 'Exchange']) {
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(Card),
            ),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.text(title)).dy >
              tester.getTopLeft(_section('uncategorized')).dy,
          isTrue,
        );
      }
    });

    testWidgets('an empty category says it has no replies before deleting', (
      tester,
    ) async {
      await _pump(tester, server());
      await tester.tap(find.byKey(const Key('saved-reply-category-3-delete')));
      await tester.pumpAndSettle();
      expect(find.text('This category has no saved replies.'), findsOneWidget);
    });

    testWidgets('the arrows reorder, and the order is saved', (tester) async {
      final s = server();
      await _pump(tester, s);

      // The first cannot move up, nor the last down.
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('saved-reply-category-1-up')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('saved-reply-category-3-down')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('saved-reply-category-3-up')));
      await tester.pumpAndSettle();

      expect(s.writes.single.path, '/saved-reply-categories/reorder/');
      expect(_bodyOf(s.writes.single), {
        'ids': [1, 3, 2],
      });
      expect(_rowOrder(tester, [1, 2, 3]), [1, 3, 2]);
      expect(_sectionOrder(tester, [1, 2, 3, 'uncategorized']), [
        1,
        3,
        2,
        'uncategorized',
      ]);

      // Opened again: the server's order, not alphabetical, not as created.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, s);
      expect(_rowOrder(tester, [1, 2, 3]), [1, 3, 2]);
    });

    testWidgets('dragging a category by its handle reorders it', (
      tester,
    ) async {
      final s = server();
      await _pump(tester, s);

      final handle = find.byKey(const Key('saved-reply-category-3-handle'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_bodyOf(s.writes.single), {
        'ids': [3, 1, 2],
      });
      expect(_rowOrder(tester, [1, 2, 3]), [3, 1, 2]);
    });

    testWidgets('a refused reorder: said so, and the server\'s order shown', (
      tester,
    ) async {
      final s = server()..failReorder = 500;
      await _pump(tester, s);

      await tester.tap(find.byKey(const Key('saved-reply-category-1-down')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't save the new order."),
        findsOneWidget,
      );
      expect(_rowOrder(tester, [1, 2, 3]), [1, 2, 3]);
      expect(_sectionOrder(tester, [1, 2, 3]), [1, 2, 3]);
    });

    testWidgets('one reorder at a time: the controls wait for it', (
      tester,
    ) async {
      final s = server()..holdReorder = Completer<void>();
      await _pump(tester, s);

      await tester.tap(find.byKey(const Key('saved-reply-category-1-down')));
      await tester.pump();
      // Shown at once, saving.
      expect(_rowOrder(tester, [1, 2, 3]), [2, 1, 3]);
      expect(
        find.byKey(const Key('saved-reply-categories-saving')),
        findsOneWidget,
      );
      final down = find.byKey(const Key('saved-reply-category-2-down'));
      expect(tester.widget<IconButton>(down).onPressed, isNull);
      await tester.tap(down, warnIfMissed: false);
      await tester.pump();

      s.holdReorder!.complete();
      await tester.pumpAndSettle();
      expect(s.writes, hasLength(1));
      expect(_rowOrder(tester, [1, 2, 3]), [2, 1, 3]);
      expect(
        find.byKey(const Key('saved-reply-categories-saving')),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('replies and categories', () {
    testWidgets('moving a reply to another category: by id, counts follow', (
      tester,
    ) async {
      final s = _Server(replies: [_reply(1, 'Refund policy', categoryId: 1)]);
      await _pump(tester, s);
      expect(find.text('1 reply'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saved-reply-1-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-reply-form-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shipping').last);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('saved-reply-form-save')),
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ListView),
        ),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('saved-reply-form-save')));
      await tester.pumpAndSettle();

      expect(_bodyOf(s.writes.single)['category_id'], 3);
      expect(
        tester.getTopLeft(find.text('Refund policy')).dy >
            tester.getTopLeft(_section(3)).dy,
        isTrue,
      );
      final returns = find.byKey(const Key('saved-reply-category-1-count'));
      final shipping = find.byKey(const Key('saved-reply-category-3-count'));
      expect(tester.widget<Text>(returns).data, 'No replies');
      expect(tester.widget<Text>(shipping).data, '1 reply');
    });

    testWidgets('editing without touching the category leaves it alone', (
      tester,
    ) async {
      final s = _Server(
        replies: [_reply(1, 'Legacy', category: 'Old name only')],
      );
      await _pump(tester, s);
      await tester.tap(find.byKey(const Key('saved-reply-1-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Legacy 2',
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('saved-reply-form-save')),
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ListView),
        ),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('saved-reply-form-save')));
      await tester.pumpAndSettle();

      final body = _bodyOf(s.writes.single);
      expect(body.containsKey('category_id'), isFalse);
      expect(body.containsKey('category'), isFalse);
      // Its name-only category is still shown, under Uncategorized.
      expect(find.text('Category: Old name only'), findsOneWidget);
    });

    testWidgets('a new reply can be filed under a category', (tester) async {
      final s = _Server();
      await _pump(tester, s);
      await tester.tap(find.byKey(const Key('add-saved-reply')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Late delivery',
      );
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-body')),
        'Sorry for the delay.',
      );
      await tester.tap(find.byKey(const Key('saved-reply-form-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shipping').last);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('saved-reply-form-save')),
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ListView),
        ),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('saved-reply-form-save')));
      await tester.pumpAndSettle();

      expect(_bodyOf(s.writes.single)['category_id'], 3);
      expect(
        tester.getTopLeft(find.text('Late delivery')).dy >
            tester.getTopLeft(_section(3)).dy,
        isTrue,
      );
    });

    testWidgets('without saved_reply.manage: no panel, still grouped', (
      tester,
    ) async {
      final s = _Server(
        replies: [_reply(1, 'Prices', categoryId: 2), _reply(2, 'Hi')],
      );
      await _pump(tester, s, manage: false);
      expect(
        find.byKey(const Key('saved-reply-categories-panel')),
        findsNothing,
      );
      expect(_sectionOrder(tester, [1, 2, 3, 'uncategorized']), [
        1,
        2,
        3,
        'uncategorized',
      ]);
    });

    testWidgets('categories that cannot load: the replies as before, and a '
        'retry in the panel', (tester) async {
      final s = _Server(replies: [_reply(1, 'Prices', categoryId: 2)])
        ..failCategoryList = true;
      await _pump(tester, s);
      expect(find.text('Prices'), findsOneWidget);
      expect(_section(2), findsNothing);
      expect(find.text("Couldn't load the categories."), findsOneWidget);

      s.failCategoryList = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(_section(2), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('languages and themes', () {
    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        testWidgets('${dark ? 'dark' : 'light'} '
            '${arabic ? 'Arabic' : 'English'}', (tester) async {
          final s = _Server(
            replies: [
              _reply(1, 'سياسة الاسترجاع', categoryId: 1),
              _reply(2, 'استبدال', categoryId: 1, position: 1),
              _reply(3, 'Hi'),
            ],
          );
          await _pump(
            tester,
            s,
            locale: Locale(arabic ? 'ar' : 'en'),
            theme: dark ? AppTheme.dark : AppTheme.light,
          );
          expect(tester.takeException(), isNull);
          expect(find.text(arabic ? 'الفئات' : 'Categories'), findsOneWidget);
          expect(find.text(arabic ? 'ردّان' : '2 replies'), findsOneWidget);
          expect(
            find.text(arabic ? 'بدون تصنيف' : 'UNCATEGORIZED'),
            findsOneWidget,
          );
          expect(
            Directionality.of(tester.element(_row(1))),
            arabic ? TextDirection.rtl : TextDirection.ltr,
          );
        });
      }
    }

    testWidgets('a narrow phone fits the panel', (tester) async {
      final s = _Server(
        categories: [
          _Server._cat(1, 'A rather long category name for returns', 0),
          _Server._cat(2, 'Billing', 1),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(320, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(s.client()),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SavedRepliesSettingsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_row(1), findsOneWidget);
    });
  });
}
