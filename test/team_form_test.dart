/// The shared Create / Edit Team form: team details, members and leaders,
/// and per-channel responsibility — what it shows, what it sends, and how it
/// behaves when things go wrong.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/team_form_harness.dart';

Finder _byKey(String key) => find.byKey(ValueKey(key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Create team', () {
    testWidgets('sends details, colour, members, leaders and channel '
        'responsibilities', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);

      expect(find.text('Add team'), findsOneWidget);
      expect(find.text('Create team'), findsOneWidget);
      // The web's default colour for a new team.
      expect(find.text('#6366f1'), findsOneWidget);

      await tester.enterText(_byKey('teamFormName'), '  VIP desk ');
      await tester.enterText(_byKey('teamFormDescription'), 'Big accounts');
      await tester.enterText(_byKey('teamFormLanguage'), 'ar');

      await tapInForm(tester, _byKey('teamFormColor'));
      await tester.tap(_byKey('teamColorSwatch_#ef4444'));
      await tester.pump();
      await tester.tap(_byKey('teamColorApply'));
      await tester.pumpAndSettle();
      expect(find.text('#ef4444'), findsOneWidget);

      await tapInForm(tester, _byKey('teamMemberCheck_2'));
      await tapInForm(tester, _byKey('teamMember_3'));
      await tapInForm(tester, _byKey('teamLeader_3'));
      expect(find.text('2 selected · 1 leader'), findsOneWidget);

      await expandChannel(tester, 'WHATSAPP');
      await chooseMode(tester, 'WHATSAPP', 'selected');
      await tickAccount(tester, 2);
      await tapInForm(tester, _byKey('teamChannelStrictOption_WHATSAPP'));
      await expandChannel(tester, 'TIKTOK');
      await chooseMode(tester, 'TIKTOK', 'all');

      await tapSave(tester);

      expect(backend.writes, hasLength(1));
      expect(backend.writes.single.method, 'POST');
      expect(backend.lastWrite, {
        'name': 'VIP desk',
        'description': 'Big accounts',
        'language': 'ar',
        'color': '#ef4444',
        'is_active': true,
        'member_ids': [2, 3],
        'leader_ids': [3],
        'responsibilities': [
          {
            'provider': 'WHATSAPP',
            'scope': 'selected',
            'channel_connection_ids': [2],
            'strict': true,
          },
          {'provider': 'TIKTOK', 'scope': 'all', 'strict': false},
        ],
      });
      expect(find.text('Team added'), findsOneWidget);
      expect(find.text('Add team'), findsNothing);
    });

    testWidgets('a channel set and then set back to "No responsibility" sends '
        'no responsibilities at all', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);
      await tester.enterText(_byKey('teamFormName'), 'VIP');

      await expandChannel(tester, 'INSTAGRAM');
      await chooseMode(tester, 'INSTAGRAM', 'all');
      await chooseMode(tester, 'INSTAGRAM', 'none');
      await tapSave(tester);

      expect(backend.lastWrite.containsKey('responsibilities'), isFalse);
    });
  });

  group('Edit team', () {
    testWidgets('prepopulates every field and the saved responsibilities', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      expect(find.text('Edit team'), findsOneWidget);
      String field(String key) =>
          tester.widget<TextField>(_byKey(key)).controller!.text;
      expect(field('teamFormName'), 'Support');
      expect(field('teamFormDescription'), 'Tier 2');
      expect(field('teamFormLanguage'), 'ar');
      expect(find.text('#0f766e'), findsOneWidget);

      expect(memberTicked(tester, 1), isTrue);
      expect(memberTicked(tester, 2), isTrue);
      expect(memberTicked(tester, 3), isFalse);
      expect(find.byTooltip('Remove Sam Admin as leader'), findsOneWidget);
      expect(find.byTooltip('Make Mona Agent a leader'), findsOneWidget);

      expect(channelSummary(tester, 'WHATSAPP'), '1 account selected');
      expect(channelSummary(tester, 'FACEBOOK'), 'No responsibility');
      expect(channelSummary(tester, 'INSTAGRAM'), 'All Instagram accounts');
      expect(channelSummary(tester, 'TIKTOK'), 'No responsibility');

      // Channels with a choice open expanded, showing it.
      expect(_byKey('teamChannelBody_WHATSAPP'), findsOneWidget);
      expect(_byKey('teamChannelBody_INSTAGRAM'), findsOneWidget);
      expect(_byKey('teamChannelBody_TIKTOK'), findsNothing);
      expect(accountTicked(tester, 2), isTrue);
      expect(accountTicked(tester, 1), isFalse);
      expect(
        tester.widget<Text>(_byKey('teamChannelStrictHint_WHATSAPP')).data,
        startsWith('Work on this account never leaves'),
      );
      expect(
        tester.widget<Text>(_byKey('teamChannelStrictHint_INSTAGRAM')).data,
        startsWith('The people named here are offered'),
      );
      // A disconnected account is labelled, not hidden.
      expect(find.text('Not connected'), findsOneWidget);

      // Nothing changed yet.
      expect(find.text('Save changes'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('editing every detail sends exactly the changed fields', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      await tester.enterText(_byKey('teamFormName'), 'Support VIP');
      await tester.enterText(_byKey('teamFormDescription'), 'Tier 3');
      await tester.enterText(_byKey('teamFormLanguage'), 'en');
      await tapInForm(tester, _byKey('teamFormColor'));
      await tester.enterText(_byKey('teamColorHex'), '#123ABC');
      await tester.tap(_byKey('teamColorApply'));
      await tester.pumpAndSettle();

      await tapInForm(tester, _byKey('teamMemberCheck_2')); // Mona out
      await tapInForm(tester, _byKey('teamMemberCheck_3')); // Omar in
      await tapInForm(tester, _byKey('teamLeader_1')); // Sam no longer leads
      await tapInForm(tester, _byKey('teamLeader_3')); // Omar leads

      await tapSave(tester);

      expect(backend.writes.single.method, 'PATCH');
      expect(backend.writes.single.path, '/teams/5/');
      expect(backend.lastWrite, {
        'name': 'Support VIP',
        'description': 'Tier 3',
        'language': 'en',
        'color': '#123abc',
        'member_ids': [1, 3],
        'leader_ids': [3],
      });
      expect(find.text('Team updated'), findsOneWidget);
    });

    testWidgets('changing responsibilities sends the complete new set', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      await chooseMode(tester, 'WHATSAPP', 'all');
      await tapInForm(tester, _byKey('teamChannelFlexible_WHATSAPP'));
      await chooseMode(tester, 'INSTAGRAM', 'none');
      await tapSave(tester);

      expect(backend.lastWrite, {
        'responsibilities': [
          {'provider': 'WHATSAPP', 'scope': 'all', 'strict': false},
        ],
      });
    });

    testWidgets('selecting and deselecting accounts keeps the channel mode', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      await tickAccount(tester, 1);
      await tickAccount(tester, 2);
      expect(accountTicked(tester, 1), isTrue);
      expect(accountTicked(tester, 2), isFalse);
      expect(channelSummary(tester, 'WHATSAPP'), '1 account selected');
      await tapSave(tester);

      expect(backend.lastWrite, {
        'responsibilities': [
          {
            'provider': 'WHATSAPP',
            'scope': 'selected',
            'channel_connection_ids': [1],
            'strict': true,
          },
          {'provider': 'INSTAGRAM', 'scope': 'all', 'strict': false},
        ],
      });
    });

    testWidgets('changing only a detail never sends responsibilities', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      // Touch a channel and put it back as it was.
      await chooseMode(tester, 'WHATSAPP', 'all');
      await chooseMode(tester, 'WHATSAPP', 'selected');
      await tester.enterText(_byKey('teamFormName'), 'Support 2');
      await tapSave(tester);

      expect(backend.lastWrite, {'name': 'Support 2'});
    });

    testWidgets('a redundant single-account rule is explained before it is '
        'removed', (tester) async {
      final backend = TeamFormBackend(
        rules: [
          providerRule(1, 5, 'WHATSAPP'),
          accountRule(2, 5, 2, 'WHATSAPP', 'Scenario DM'),
        ],
      );
      await openTeamForm(tester, backend, team: supportTeam());

      expect(_byKey('teamResponsibilityRedundant'), findsOneWidget);
      expect(channelSummary(tester, 'WHATSAPP'), 'All WhatsApp numbers');
    });

    testWidgets('someone in the team who is no longer an active employee is '
        'listed as inactive and can be removed', (tester) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(
        tester,
        backend,
        team: supportTeam(
          members: [
            {'id': 1, 'full_name': 'Sam Admin', 'initials': 'SA'},
            {'id': 40, 'full_name': 'Former Person', 'initials': 'FP'},
          ],
        ),
      );

      expect(find.text('Former Person'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(memberTicked(tester, 40), isTrue);

      await tapInForm(tester, _byKey('teamMemberCheck_40'));
      await tapSave(tester);
      expect(backend.lastWrite, {
        'member_ids': [1],
      });
    });
  });

  group('Channel sections', () {
    testWidgets('collapsing a section keeps its values', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);

      expect(_byKey('teamChannelBody_WHATSAPP'), findsNothing);
      await expandChannel(tester, 'WHATSAPP');
      await chooseMode(tester, 'WHATSAPP', 'selected');
      await tickAccount(tester, 2);
      await tapInForm(tester, _byKey('teamChannelStrictOption_WHATSAPP'));

      await expandChannel(tester, 'WHATSAPP'); // collapse
      expect(_byKey('teamChannelBody_WHATSAPP'), findsNothing);
      expect(channelSummary(tester, 'WHATSAPP'), '1 account selected');

      await expandChannel(tester, 'WHATSAPP'); // and open again
      expect(accountTicked(tester, 2), isTrue);
      expect(
        tester.widget<Text>(_byKey('teamChannelStrictHint_WHATSAPP')).data,
        startsWith('Work on this account never leaves'),
      );
    });

    testWidgets('a channel with no connected accounts cannot be set to '
        '"selected", and says so', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);

      await expandChannel(tester, 'FACEBOOK');
      expect(find.text('No Facebook Pages connected yet.'), findsOneWidget);
      expect(
        tester
            .widget<RadioListTile<Object?>>(
              _byKey('teamChannelMode_FACEBOOK_selected'),
            )
            .enabled,
        isFalse,
      );
      // "All" is still allowed: it covers pages connected later.
      await chooseMode(tester, 'FACEBOOK', 'all');
      expect(find.text('Includes accounts connected later.'), findsOneWidget);
    });

    testWidgets('the sandbox channel is never offered', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);
      for (final provider in ['WHATSAPP', 'INSTAGRAM', 'TIKTOK']) {
        await expandChannel(tester, provider);
        await chooseMode(tester, provider, 'selected');
      }
      expect(find.text('Sandbox'), findsNothing);
      expect(find.text('Brand IG'), findsOneWidget);
    });

    testWidgets('many accounts get a search box', (tester) async {
      final backend = TeamFormBackend(
        channels: [
          for (var i = 1; i <= 7; i++)
            channelJson(i, 'WHATSAPP', 'Line $i', externalId: '10$i'),
        ],
      );
      await openTeamForm(tester, backend);
      await expandChannel(tester, 'WHATSAPP');
      await chooseMode(tester, 'WHATSAPP', 'selected');

      await tester.enterText(_byKey('teamChannelSearch_WHATSAPP'), 'line 7');
      await tester.pump();
      expect(find.text('Line 7'), findsOneWidget);
      expect(find.text('Line 1'), findsNothing);

      await tester.enterText(_byKey('teamChannelSearch_WHATSAPP'), 'zzz');
      await tester.pump();
      expect(find.text('No account matches “zzz”.'), findsOneWidget);
    });
  });

  group('Members', () {
    testWidgets('many people get a search box that filters the list', (
      tester,
    ) async {
      final backend = TeamFormBackend(
        employees: [
          for (var i = 1; i <= 10; i++) employeeJson(i, 'Person $i'),
          employeeJson(11, 'Zed Lead'),
        ],
      );
      await openTeamForm(tester, backend);

      await tester.enterText(_byKey('teamMembersSearch'), 'zed');
      await tester.pump();
      expect(find.text('Zed Lead'), findsOneWidget);
      expect(find.text('Person 1'), findsNothing);

      // A tick made while filtered survives clearing the search.
      await tapInForm(tester, _byKey('teamMemberCheck_11'));
      await tester.enterText(_byKey('teamMembersSearch'), '');
      await tester.pump();
      expect(find.text('Person 1'), findsOneWidget);
      expect(memberTicked(tester, 11), isTrue);
    });

    testWidgets('a failed employee load can be retried', (tester) async {
      final backend = TeamFormBackend(employeesStatus: 500);
      await openTeamForm(tester, backend);

      expect(find.text("Couldn't load employees."), findsOneWidget);
      backend.employeesStatus = 200;
      await tapInForm(tester, find.text('Retry'));
      expect(find.text('Mona Agent'), findsOneWidget);
    });
  });

  group('Validation', () {
    testWidgets('a team needs a name — shown under the field, nothing sent', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      await tester.enterText(_byKey('teamFormName'), '   ');
      await tapSave(tester);

      expect(find.text('Enter a team name.'), findsOneWidget);
      expect(backend.writes, isEmpty);

      await tester.enterText(_byKey('teamFormName'), 'Support B');
      await tester.pump();
      expect(find.text('Enter a team name.'), findsNothing);
    });

    testWidgets('"selected" with no account ticked is refused on that '
        'channel', (tester) async {
      final backend = TeamFormBackend();
      await openTeamForm(tester, backend);
      await tester.enterText(_byKey('teamFormName'), 'VIP');

      await expandChannel(tester, 'INSTAGRAM');
      await chooseMode(tester, 'INSTAGRAM', 'selected');
      await expandChannel(tester, 'INSTAGRAM'); // collapsed before saving
      await tapSave(tester);

      expect(backend.writes, isEmpty);
      // Re-opened to show the problem where it is.
      expect(_byKey('teamChannelBody_INSTAGRAM'), findsOneWidget);
      expect(
        find.text(
          'Choose at least one account for Instagram, or pick another option.',
        ),
        findsOneWidget,
      );

      await tickAccount(tester, 3);
      expect(_byKey('teamChannelError_INSTAGRAM'), findsNothing);
      await tapSave(tester);
      expect(backend.writes, hasLength(1));
    });
  });

  group('Server errors', () {
    testWidgets('a field error is shown under its field and the values are '
        'kept', (tester) async {
      final backend = TeamFormBackend(
        write: (_) => jsonBody({
          'error': {
            'code': 'invalid',
            'message': 'The submitted data was invalid.',
            'details': {
              'name': ['A team with this name already exists.'],
            },
          },
        }, 400),
      );
      await openTeamForm(tester, backend);
      await tester.enterText(_byKey('teamFormName'), 'Support');
      await tapInForm(tester, _byKey('teamMemberCheck_2'));
      await tapSave(tester);

      expect(
        find.text('A team with this name already exists.'),
        findsOneWidget,
      );
      expect(find.text('Please fix the highlighted fields.'), findsOneWidget);
      expect(find.text('Add team'), findsOneWidget);
      expect(memberTicked(tester, 2), isTrue);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('a nested responsibilities error reads as a sentence, and the '
        'selection is kept', (tester) async {
      final backend = TeamFormBackend(
        rules: supportRules,
        write: (_) => jsonBody({
          'error': {
            'code': 'invalid',
            'message': 'The submitted data was invalid.',
            'details': {
              'responsibilities': [
                {
                  'channel_connection_ids': ['Account 1 was not found.'],
                },
              ],
            },
          },
        }, 400),
      );
      await openTeamForm(tester, backend, team: supportTeam());
      await tickAccount(tester, 1);
      await tapSave(tester);

      expect(
        tester.widget<Text>(_byKey('teamResponsibilityError')).data,
        'Account 1 was not found.',
      );
      expect(find.textContaining('{channel_connection_ids'), findsNothing);
      expect(accountTicked(tester, 1), isTrue);
    });

    testWidgets('a failure with no field errors shows the server message', (
      tester,
    ) async {
      final backend = TeamFormBackend(
        write: (_) => jsonBody({
          'error': {
            'code': 'permission_denied',
            'message': 'You do not have permission to manage routing.',
          },
        }, 403),
      );
      await openTeamForm(tester, backend);
      await tester.enterText(_byKey('teamFormName'), 'VIP');
      await tapSave(tester);

      expect(
        find.text('You do not have permission to manage routing.'),
        findsOneWidget,
      );
      expect(find.text('Add team'), findsOneWidget);
    });

    testWidgets('while saving, Save shows progress and cannot be pressed '
        'again, and Cancel is held', (tester) async {
      final pending = Completer<ResponseBody>();
      final backend = TeamFormBackend(write: (_) => pending.future);
      await openTeamForm(tester, backend);
      await tester.enterText(_byKey('teamFormName'), 'VIP');

      await tester.pump();
      await tester.tap(_byKey('teamFormSave'));
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      expect(
        find.descendant(
          of: _byKey('teamFormSave'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(_byKey('teamFormCancel')).onPressed,
        isNull,
      );
      await tester.tap(_byKey('teamFormSave'), warnIfMissed: false);
      await tester.pump();

      pending.complete(
        jsonBody({
          'id': 9,
          'name': 'VIP',
          'members': <Object>[],
          'leaders': <Object>[],
        }, 201),
      );
      await tester.pumpAndSettle();
      expect(backend.writes, hasLength(1));
      expect(find.text('Team added'), findsOneWidget);
    });

    testWidgets('when the saved responsibilities cannot be read, they cannot '
        'be changed — but other changes still save', (tester) async {
      final backend = TeamFormBackend(rules: supportRules, rulesStatus: 500);
      await openTeamForm(tester, backend, team: supportTeam());

      expect(_byKey('teamResponsibilitiesFailed'), findsOneWidget);
      expect(_byKey('teamChannel_WHATSAPP'), findsNothing);

      await tester.enterText(_byKey('teamFormDescription'), 'Tier 3');
      await tapSave(tester);
      expect(backend.lastWrite, {'description': 'Tier 3'});
    });

    testWidgets('a failed responsibilities load can be retried', (
      tester,
    ) async {
      final backend = TeamFormBackend(rules: supportRules, rulesStatus: 500);
      await openTeamForm(tester, backend, team: supportTeam());

      backend.rulesStatus = 200;
      await tapInForm(
        tester,
        find.descendant(
          of: _byKey('teamResponsibilitiesFailed'),
          matching: find.text('Retry'),
        ),
      );
      expect(channelSummary(tester, 'WHATSAPP'), '1 account selected');
    });
  });

  group('Permissions', () {
    testWidgets('without routing.manage there is no responsibility section, '
        'no rules request and nothing sent for it', (tester) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(
        tester,
        backend,
        team: supportTeam(),
        permissions: const {'team.view', 'team.manage', 'channel.view'},
      );

      expect(find.text('Channel responsibilities'), findsNothing);
      expect(backend.requestsTo('/routing/responsibilities/'), 0);

      await tester.enterText(_byKey('teamFormName'), 'Support 2');
      await tapSave(tester);
      expect(backend.lastWrite, {'name': 'Support 2'});
    });
  });

  group('Leaving', () {
    testWidgets('with nothing changed, Cancel closes at once', (tester) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());

      await tester.tap(_byKey('teamFormCancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Edit team'), findsNothing);
    });

    testWidgets('with unsaved changes, leaving asks first', (tester) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(tester, backend, team: supportTeam());
      await tickAccount(tester, 1);

      await tester.tap(_byKey('teamFormClose'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit team'), findsOneWidget);
      expect(accountTicked(tester, 1), isTrue);

      await tester.tap(_byKey('teamFormCancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Edit team'), findsNothing);
      expect(backend.writes, isEmpty);
    });
  });

  group('Layout', () {
    testWidgets('Arabic: right-to-left, with the web wording', (tester) async {
      final backend = TeamFormBackend(rules: supportRules);
      await openTeamForm(
        tester,
        backend,
        team: supportTeam(),
        locale: const Locale('ar'),
      );

      expect(find.text('تعديل الفريق'), findsOneWidget);
      expect(
        Directionality.of(tester.element(_byKey('teamFormScroll'))),
        TextDirection.rtl,
      );
      expect(find.text('مسؤولية القنوات'), findsOneWidget);
      expect(
        find.text(
          'حدد القنوات أو الحسابات التي يتولى هذا الفريق استقبال محادثاتها الجديدة.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'يحدد هذا فقط من تُعرض عليه المحادثات الجديدة أولًا، ولا يغيّر من يستطيع رؤية المحادثات.',
        ),
        findsOneWidget,
      );
      expect(channelSummary(tester, 'WHATSAPP'), 'حساب واحد محدد');
      expect(channelSummary(tester, 'INSTAGRAM'), 'كل حسابات Instagram');
      expect(find.text('بدون مسؤولية'), findsWidgets);
      expect(find.text('كل أرقام WhatsApp'), findsOneWidget);
      expect(find.text('أرقام WhatsApp محددة'), findsOneWidget);
      expect(find.text('الوضع'), findsWidgets);
      expect(find.text('مرن'), findsWidgets);
      expect(find.text('صارم'), findsWidgets);
      expect(
        find.text(
          'تُعرض المحادثة أولًا على الأشخاص المذكورين هنا. وإذا لم يستطع أحدهم استلامها تحدّد إعدادات التوزيع من غيرهم يمكنه ذلك.',
        ),
        findsOneWidget,
      );
      expect(find.text('غير مربوط'), findsOneWidget);
      expect(find.text('قائد'), findsWidgets);
      expect(find.text('حفظ التغييرات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label on a small phone: no overflow, Save always on '
          'screen, and the whole form scrolls', (tester) async {
        const screen = Size(320, 568);
        final backend = TeamFormBackend(rules: supportRules);
        await openTeamForm(
          tester,
          backend,
          team: supportTeam(),
          locale: locale,
          size: screen,
        );
        expect(tester.takeException(), isNull);

        Rect saveRect() => tester.getRect(_byKey('teamFormSave'));
        expect(saveRect().bottom, lessThanOrEqualTo(screen.height));

        // Down to the last channel, past members and the open sections.
        await tester.dragUntilVisible(
          _byKey('teamChannel_TIKTOK'),
          _byKey('teamFormScroll'),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        await tester.tap(_byKey('teamChannel_TIKTOK'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_byKey('teamChannelMode_TIKTOK_all'));
        await tester.pumpAndSettle();
        await tester.tap(_byKey('teamChannelMode_TIKTOK_all'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(saveRect().bottom, lessThanOrEqualTo(screen.height));
        expect(saveEnabled(tester), isTrue);

        await tester.tap(_byKey('teamFormSave'));
        await tester.pumpAndSettle();
        expect((backend.lastWrite['responsibilities'] as List).last, {
          'provider': 'TIKTOK',
          'scope': 'all',
          'strict': false,
        });
      });
    }
  });
}
