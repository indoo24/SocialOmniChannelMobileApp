/// Reproduction harness for the reported crash: opening Customer Details
/// (the orders/facts sheet reached from inside a conversation), adding a
/// detail, and pressing Save (or Cancel).
///
/// `_showAddDetailDialog()` (customer_record_sheet.dart) creates two
/// `TextEditingController`s, hands them to `TextField`s inside a
/// `showDialog` `AlertDialog`, and disposes both immediately once
/// `showDialog`'s Future resolves:
///
///     final saved = await showDialog<bool>(...);
///     if (saved != true) {
///       keyController.dispose();
///       valueController.dispose();
///       return;
///     }
///     ...
///     keyController.dispose();
///     valueController.dispose();
///
/// This is the exact same anti-pattern already found and fixed this session
/// in intelligence_panel.dart's lead-score/purchase-claim dialogs and
/// conversation_screen.dart's delete-message dialog: showDialog's Future
/// resolves the instant Navigator.pop() runs in Save/Cancel's onPressed,
/// before the AlertDialog's own exit transition has finished animating the
/// still-mounted TextFields off screen. Disposing here races that
/// still-mounted subtree and can corrupt the Element tree — which is
/// consistent with the varying assertions reported across this session
/// (TextEditingController-used-after-dispose, Duplicate GlobalKeys,
/// '!semantics.parentDataDirty', and now '_dependents.isEmpty') all being
/// the same underlying mechanism surfacing differently depending on exactly
/// what's mounted at the moment of the premature dispose.
library;

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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/orders/customer_record_sheet.dart';
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
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: const {Perm.orderManage},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () =>
      showCustomerRecordSheet(context, conversationId: 1, customerId: 1),
  child: const Text('open record'),
);

ApiClient _clientFor({
  FutureOr<ResponseBody>? Function(RequestOptions options)? extra,
}) {
  return _stubClient((options) {
    final fromExtra = extra?.call(options);
    if (fromExtra != null) return fromExtra;
    if (options.path.contains('/orders/')) return _json('[]', 200);
    if (options.path.contains('/facts/') && options.method == 'GET') {
      return _json('[]', 200);
    }
    return _json('{}', 200);
  });
}

/// Pumps frame-by-frame across a typical dialog exit-transition duration
/// instead of pumpAndSettle(), so a lifecycle assertion thrown mid-animation
/// is not skipped over.
Future<void> _pumpAcrossExitTransition(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('adding a customer detail and pressing Save does not corrupt the '
      'element tree while the dialog is still exiting', (tester) async {
    final client = _clientFor(
      extra: (options) {
        if (options.path.contains('/facts/') && options.method == 'POST') {
          return _json(
            '{"id": 1, "key": "address", "value": "12 Nile St", '
            '"confidence": 1.0, "source": "EMPLOYEE", "status": '
            '"CONFIRMED", "needs_review": false}',
            201,
          );
        }
        return null;
      },
    );

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open record'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'address');
    await tester.enterText(fields.last, '12 Nile St');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));

    // Do NOT pumpAndSettle() here: fast-forwarding would skip straight
    // past the dialog's exit transition, which is exactly where the
    // reported crash happens.
    await _pumpAcrossExitTransition(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening the add-detail dialog and pressing Cancel does not corrupt '
    'the element tree while the dialog is still exiting',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open record'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _pumpAcrossExitTransition(tester);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeatedly opening/cancelling/saving the add-detail dialog does not throw',
    (tester) async {
      var factIdCounter = 0;
      final client = _clientFor(
        extra: (options) {
          if (options.path.contains('/facts/') && options.method == 'POST') {
            factIdCounter += 1;
            return _json(
              '{"id": $factIdCounter, "key": "note", "value": "v", '
              '"confidence": 1.0, "source": "EMPLOYEE", "status": '
              '"CONFIRMED", "needs_review": false}',
              201,
            );
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open record'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextField);
        await tester.enterText(fields.first, 'note');
        await tester.enterText(fields.last, 'v$i');

        if (i.isEven) {
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        } else {
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        }
        await _pumpAcrossExitTransition(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'closing the whole sheet immediately after Save, before the POST '
    'resolves, does not throw when the provider refresh lands afterward',
    (tester) async {
      // Scenario G from the crash report: a mutation succeeds, but the
      // sheet (not just the dialog) is already gone by the time
      // ref.invalidate(customerFactsProvider(...)) fires and tries to
      // refetch for a widget tree that no longer has a listener.
      final postCompleter = Completer<ResponseBody>();
      final client = _clientFor(
        extra: (options) {
          if (options.path.contains('/facts/') && options.method == 'POST') {
            return postCompleter.future;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _harness(apiClient: client, child: Builder(builder: _openButton)),
      );
      await tester.tap(find.text('open record'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'address');
      await tester.enterText(fields.last, '12 Nile St');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));

      // Let the dialog's own exit transition and the pop settle — the POST
      // is still pending (postCompleter hasn't completed).
      await _pumpAcrossExitTransition(tester);

      // Now close the *outer* Customer Record sheet too, before the POST
      // has resolved — this is the "immediately close the sheet" half of
      // the race.
      Navigator.of(tester.element(find.text('open record'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The POST resolves now, after the sheet (and everything watching
      // customerFactsProvider) is gone. ref.invalidate() still fires.
      postCompleter.complete(
        _json(
          '{"id": 1, "key": "address", "value": "12 Nile St", '
          '"confidence": 1.0, "source": "EMPLOYEE", "status": '
          '"CONFIRMED", "needs_review": false}',
          201,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening the sheet for a different conversation/customer after closing '
    'it once does not throw',
    (tester) async {
      var factIdCounter = 0;
      final client = _clientFor(
        extra: (options) {
          if (options.path.contains('/facts/') && options.method == 'POST') {
            factIdCounter += 1;
            return _json(
              '{"id": $factIdCounter, "key": "note", "value": "v", '
              '"confidence": 1.0, "source": "EMPLOYEE", "status": '
              '"CONFIRMED", "needs_review": false}',
              201,
            );
          }
          return null;
        },
      );

      Widget openButtonFor(int conversationId, int customerId) => Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCustomerRecordSheet(
            context,
            conversationId: conversationId,
            customerId: customerId,
          ),
          child: Text('open $conversationId/$customerId'),
        ),
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [openButtonFor(1, 1), openButtonFor(2, 2)],
          ),
        ),
      );

      for (final label in ['open 1/1', 'open 2/2', 'open 1/1']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.first, 'note');
        await tester.enterText(fields.last, 'v');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await _pumpAcrossExitTransition(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(find.text(label))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
