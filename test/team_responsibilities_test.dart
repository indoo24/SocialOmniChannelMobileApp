/// Team channel responsibility as plain data: reading the saved rules
/// (`GET /routing/responsibilities/`) into the form's per-channel choice,
/// and writing that choice back as `TeamWrite.responsibilities` — the same
/// rules the web CRM's team form follows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/routing_policy.dart';
import 'package:scenario_mobile/features/directory/team_form/team_members_picker.dart';
import 'package:scenario_mobile/features/directory/team_form/team_responsibility_state.dart';

import 'support/team_form_harness.dart';

List<RoutingResponsibility> _rules(List<Map<String, dynamic>> json) =>
    json.map(RoutingResponsibility.fromJson).toList();

List<ChannelConnection> _channels(List<Map<String, dynamic>> json) =>
    json.map(ChannelConnection.fromJson).toList();

void main() {
  group('RoutingResponsibility', () {
    test("a blank provider falls back to the account's own provider", () {
      final rule = RoutingResponsibility.fromJson(
        accountRule(1, 5, 2, 'WHATSAPP', 'Scenario DM'),
      );
      expect(rule.provider, 'WHATSAPP');
      expect(rule.isChannelSpecific, isTrue);
      expect(rule.channelConnectionId, 2);
      expect(rule.channelConnectionName, 'Scenario DM');
      expect(rule.teamId, 5);
    });

    test("a rule's own provider is kept, and normalised to upper case", () {
      final own = RoutingResponsibility.fromJson(providerRule(1, 5, 'TIKTOK'));
      expect(own.provider, 'TIKTOK');
      expect(own.isChannelSpecific, isFalse);

      final lower = RoutingResponsibility.fromJson({
        'id': 2,
        'provider': '',
        'channel_connection': {'id': 3, 'provider': 'instagram'},
        'is_active': true,
      });
      expect(lower.provider, 'INSTAGRAM');
    });

    test('a blank provider with no account stays blank (malformed rule)', () {
      final rule = RoutingResponsibility.fromJson({
        'id': 3,
        'provider': '',
        'channel_connection': null,
        'is_active': true,
      });
      expect(rule.provider, '');
    });

    test('strict is read as sent, and is flexible when absent', () {
      expect(
        RoutingResponsibility.fromJson(
          providerRule(1, 5, 'WHATSAPP', strict: true),
        ).strict,
        isTrue,
      );
      expect(
        RoutingResponsibility.fromJson({
          'id': 1,
          'provider': 'WHATSAPP',
          'is_active': true,
        }).strict,
        isFalse,
      );
    });
  });

  group('TeamResponsibilityInput', () {
    test('always carries strict; account ids only for "selected"', () {
      expect(
        const TeamResponsibilityInput(
          provider: 'TIKTOK',
          scope: 'all',
        ).toJson(),
        {'provider': 'TIKTOK', 'scope': 'all', 'strict': false},
      );
      expect(
        const TeamResponsibilityInput(
          provider: 'WHATSAPP',
          scope: 'selected',
          channelConnectionIds: [2],
          strict: true,
        ).toJson(),
        {
          'provider': 'WHATSAPP',
          'scope': 'selected',
          'channel_connection_ids': [2],
          'strict': true,
        },
      );
    });
  });

  group('seedResponsibilityDrafts', () {
    test('a provider-wide rule is "all"; account rules are "selected"', () {
      final drafts = seedResponsibilityDrafts(_rules(supportRules), 5);
      expect(drafts['WHATSAPP']!.mode, ResponsibilityMode.selected);
      expect(drafts['WHATSAPP']!.connectionIds, {2});
      expect(drafts['WHATSAPP']!.strict, isTrue);
      expect(drafts['INSTAGRAM']!.mode, ResponsibilityMode.all);
      expect(drafts['INSTAGRAM']!.strict, isFalse);
      expect(drafts['FACEBOOK']!.mode, ResponsibilityMode.none);
      expect(drafts['TIKTOK']!.mode, ResponsibilityMode.none);
    });

    test('several account rules are one selection, strict if any is', () {
      final drafts = seedResponsibilityDrafts(
        _rules([
          accountRule(1, 5, 3, 'INSTAGRAM', 'Brand IG'),
          accountRule(2, 5, 4, 'INSTAGRAM', 'Shop IG', strict: true),
        ]),
        5,
      );
      expect(drafts['INSTAGRAM']!.mode, ResponsibilityMode.selected);
      expect(drafts['INSTAGRAM']!.connectionIds, {3, 4});
      expect(drafts['INSTAGRAM']!.strict, isTrue);
    });

    test('a provider-wide rule wins over account rules for that provider', () {
      final drafts = seedResponsibilityDrafts(
        _rules([
          accountRule(1, 5, 2, 'WHATSAPP', 'Scenario DM', strict: true),
          providerRule(2, 5, 'WHATSAPP'),
        ]),
        5,
      );
      expect(drafts['WHATSAPP']!.mode, ResponsibilityMode.all);
      expect(drafts['WHATSAPP']!.strict, isFalse);
    });

    test('retired rules, other teams and unknown providers are ignored', () {
      final drafts = seedResponsibilityDrafts(
        _rules([
          providerRule(1, 5, 'WHATSAPP', active: false),
          providerRule(2, 6, 'TIKTOK'),
          providerRule(3, 5, 'EMAIL'),
        ]),
        5,
      );
      for (final provider in routableProviders) {
        expect(
          drafts[provider]!.mode,
          ResponsibilityMode.none,
          reason: provider,
        );
      }
    });
  });

  test('redundantRuleProviders names providers with both kinds of rule', () {
    final rules = _rules([
      providerRule(1, 5, 'WHATSAPP'),
      accountRule(2, 5, 2, 'WHATSAPP', 'Scenario DM'),
      providerRule(3, 5, 'TIKTOK'),
      accountRule(4, 6, 3, 'INSTAGRAM', 'Brand IG'),
    ]);
    expect(redundantRuleProviders(rules, 5), ['WHATSAPP']);
    expect(redundantRuleProviders(rules, 6), isEmpty);
  });

  group('responsibilitiesPayload', () {
    test('one entry per channel with a choice, in provider order, ids '
        'sorted; "none" is left out', () {
      final drafts = emptyResponsibilityDrafts()
        ..['TIKTOK'] = const ChannelResponsibilityDraft(
          mode: ResponsibilityMode.all,
          strict: true,
        )
        ..['WHATSAPP'] = const ChannelResponsibilityDraft(
          mode: ResponsibilityMode.selected,
          connectionIds: {9, 2},
        );
      expect(responsibilitiesPayload(drafts), [
        {
          'provider': 'WHATSAPP',
          'scope': 'selected',
          'channel_connection_ids': [2, 9],
          'strict': false,
        },
        {'provider': 'TIKTOK', 'scope': 'all', 'strict': true},
      ]);
      expect(responsibilitiesPayload(emptyResponsibilityDrafts()), isEmpty);
    });

    test('ticks survive a switch to "all" and back, but are only sent for '
        '"selected"', () {
      const ticked = ChannelResponsibilityDraft(
        mode: ResponsibilityMode.selected,
        connectionIds: {2},
      );
      final all = ticked.withMode(ResponsibilityMode.all);
      expect(all.selectedIds, isEmpty);
      expect(all.toInput('WHATSAPP')!.toJson(), {
        'provider': 'WHATSAPP',
        'scope': 'all',
        'strict': false,
      });
      expect(all.withMode(ResponsibilityMode.selected).selectedIds, {2});
    });

    test('ticking an account always means "selected"', () {
      const none = ChannelResponsibilityDraft();
      final ticked = none.toggle(3);
      expect(ticked.mode, ResponsibilityMode.selected);
      expect(ticked.selectedIds, {3});
      expect(ticked.toggle(3).selectedIds, isEmpty);
    });

    test('sameResponsibilities compares what would be saved', () {
      final a = seedResponsibilityDrafts(_rules(supportRules), 5);
      final b = {
        ...a,
        'WHATSAPP': a['WHATSAPP']!
            .withMode(ResponsibilityMode.all)
            .withMode(ResponsibilityMode.selected),
      };
      expect(sameResponsibilities(a, b), isTrue);
      expect(
        sameResponsibilities(a, {
          ...a,
          'WHATSAPP': a['WHATSAPP']!.withStrict(false),
        }),
        isFalse,
      );
    });

    test('firstProviderMissingAccounts finds "selected" with nothing '
        'ticked', () {
      final drafts = emptyResponsibilityDrafts()
        ..['INSTAGRAM'] = const ChannelResponsibilityDraft(
          mode: ResponsibilityMode.selected,
        );
      expect(firstProviderMissingAccounts(drafts), 'INSTAGRAM');
      expect(firstProviderMissingAccounts(emptyResponsibilityDrafts()), isNull);
    });
  });

  group('responsibilityAccountOptions', () {
    test("lists the provider's accounts by name, with connection state", () {
      final options = responsibilityAccountOptions(
        provider: 'WHATSAPP',
        channels: _channels(defaultChannels),
      );
      expect(options.map((o) => o.name), ['Gad', 'Scenario DM']);
      expect(options.map((o) => o.connected), [false, true]);
    });

    test('an account the team still has a rule for, but which is gone from '
        'the channels, is kept and shown as not connected', () {
      final options = responsibilityAccountOptions(
        provider: 'WHATSAPP',
        channels: _channels(defaultChannels),
        rules: _rules([accountRule(1, 5, 77, 'WHATSAPP', 'Old line')]),
        teamId: 5,
      );
      final old = options.singleWhere((o) => o.id == 77);
      expect(old.name, 'Old line');
      expect(old.connected, isFalse);
    });

    test("two accounts with one name are told apart by the provider's id", () {
      final options = responsibilityAccountOptions(
        provider: 'WHATSAPP',
        channels: _channels([
          channelJson(1, 'WHATSAPP', 'Sales', externalId: '1001'),
          channelJson(2, 'WHATSAPP', 'Sales', externalId: '1002'),
          channelJson(3, 'WHATSAPP', 'Support', externalId: '1003'),
        ]),
      );
      expect(options.map((o) => o.detail), ['1001', '1002', '']);
      expect(options.first.matches('1002'), isFalse);
      expect(options[1].matches('1002'), isTrue);
    });
  });

  test('teamPersonOptions lists active employees, then current members who '
      'are not among them as inactive', () {
    final options = teamPersonOptions(
      employees: defaultEmployees.map(DirectoryEmployee.fromJson).toList(),
      current: const [
        EmployeeBrief(id: 2, fullName: 'Mona Agent', initials: 'MA'),
        EmployeeBrief(id: 40, fullName: 'Former Person', initials: 'FP'),
      ],
    );
    expect(options.map((o) => o.id), [1, 2, 3, 40]);
    expect(options.last.isActive, isFalse);
    expect(options.first.subtitle, 'Admin');
  });
}
