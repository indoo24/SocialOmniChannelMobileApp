/// Channel responsibility for the team form, as plain data: what the admin
/// has chosen per channel, how that is read back from the saved rules, and
/// the exact `TeamWrite.responsibilities` it turns into.
///
/// No widgets here — the form and its tests share these rules, and they
/// mirror the web CRM's own team-responsibility state one to one, so the
/// two clients read and write the same thing.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/directory.dart';
import '../../../core/models/routing_policy.dart';

/// `RoutableProviderEnum`, in the order the form lists them.
const routableProviders = ['WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'TIKTOK'];

bool isRoutableProvider(String provider) =>
    routableProviders.contains(provider);

/// What a team handles on one channel. `none` is the provider's absence from
/// `responsibilities` — the backend has no explicit "none" value.
enum ResponsibilityMode { none, all, selected }

/// One channel's choice.
///
/// [connectionIds] is kept while another mode is chosen, so switching from
/// "selected" to "all" and back does not lose the ticks; it only counts —
/// and is only sent — in [ResponsibilityMode.selected].
@immutable
class ChannelResponsibilityDraft {
  const ChannelResponsibilityDraft({
    this.mode = ResponsibilityMode.none,
    this.connectionIds = const {},
    this.strict = false,
  });

  final ResponsibilityMode mode;
  final Set<int> connectionIds;

  /// Flexible (`false`) or strict (`true`) — see
  /// [RoutingResponsibility.strict].
  final bool strict;

  /// The accounts that count: none unless [mode] is selected.
  Set<int> get selectedIds =>
      mode == ResponsibilityMode.selected ? connectionIds : const {};

  ChannelResponsibilityDraft withMode(ResponsibilityMode value) =>
      ChannelResponsibilityDraft(
        mode: value,
        connectionIds: connectionIds,
        strict: strict,
      );

  ChannelResponsibilityDraft withStrict(bool value) =>
      ChannelResponsibilityDraft(
        mode: mode,
        connectionIds: connectionIds,
        strict: value,
      );

  /// Ticks or unticks one account. Ticking always means "selected".
  ChannelResponsibilityDraft toggle(int connectionId) {
    final next = Set<int>.from(selectedIds);
    if (!next.remove(connectionId)) next.add(connectionId);
    return ChannelResponsibilityDraft(
      mode: ResponsibilityMode.selected,
      connectionIds: next,
      strict: strict,
    );
  }

  /// This channel's `TeamResponsibilityInput`, or null for "none".
  TeamResponsibilityInput? toInput(String provider) => switch (mode) {
    ResponsibilityMode.none => null,
    ResponsibilityMode.all => TeamResponsibilityInput(
      provider: provider,
      scope: 'all',
      strict: strict,
    ),
    ResponsibilityMode.selected => TeamResponsibilityInput(
      provider: provider,
      scope: 'selected',
      channelConnectionIds: connectionIds.toList()..sort(),
      strict: strict,
    ),
  };
}

/// One draft per routable provider, keyed by provider.
typedef ResponsibilityDrafts = Map<String, ChannelResponsibilityDraft>;

/// Nothing chosen on any channel — a new team.
ResponsibilityDrafts emptyResponsibilityDrafts() => {
  for (final provider in routableProviders)
    provider: const ChannelResponsibilityDraft(),
};

Iterable<RoutingResponsibility> _activeRulesOf(
  List<RoutingResponsibility> rules,
  int teamId,
) => rules.where((r) => r.isActive && r.teamId == teamId);

/// The team's current choice, read from `GET /routing/responsibilities/` —
/// the only place it can be read, since `Team` carries no responsibilities.
///
/// A provider-wide rule means "all"; channel rules mean "selected" with
/// those accounts, unless a provider-wide rule already covers the channel.
/// Strict if any rule behind the choice is strict. Retired rules, other
/// teams' rules and providers the form cannot show are ignored.
ResponsibilityDrafts seedResponsibilityDrafts(
  List<RoutingResponsibility> rules,
  int teamId,
) {
  final drafts = emptyResponsibilityDrafts();
  final mine = _activeRulesOf(rules, teamId).toList();
  for (final rule in mine) {
    if (rule.isChannelSpecific || !isRoutableProvider(rule.provider)) continue;
    drafts[rule.provider] = ChannelResponsibilityDraft(
      mode: ResponsibilityMode.all,
      strict: rule.strict,
    );
  }
  for (final rule in mine) {
    if (!rule.isChannelSpecific || !isRoutableProvider(rule.provider)) continue;
    final current = drafts[rule.provider]!;
    if (current.mode == ResponsibilityMode.all) continue;
    drafts[rule.provider] = ChannelResponsibilityDraft(
      mode: ResponsibilityMode.selected,
      connectionIds: {...current.selectedIds, rule.channelConnectionId!},
      strict: current.strict || rule.strict,
    );
  }
  return drafts;
}

/// Providers where the team has a provider-wide rule *and* rules for single
/// accounts of it. The provider-wide rule already covers those accounts, so
/// the form shows "all" — and saving any responsibility change retires the
/// redundant single-account rules. Worth saying before it happens.
List<String> redundantRuleProviders(
  List<RoutingResponsibility> rules,
  int teamId,
) {
  final mine = _activeRulesOf(rules, teamId).toList();
  final providerWide = {
    for (final r in mine)
      if (!r.isChannelSpecific) r.provider,
  };
  return [
    for (final provider in routableProviders)
      if (providerWide.contains(provider) &&
          mine.any((r) => r.isChannelSpecific && r.provider == provider))
        provider,
  ];
}

/// `TeamWrite.responsibilities` — the team's complete responsibility, one
/// entry per provider that has any. Account ids are sorted so two equal
/// choices always produce the same payload.
List<Map<String, dynamic>> responsibilitiesPayload(
  ResponsibilityDrafts drafts,
) => [
  for (final provider in routableProviders)
    ?drafts[provider]?.toInput(provider)?.toJson(),
];

/// Whether two choices would save the same thing.
bool sameResponsibilities(ResponsibilityDrafts a, ResponsibilityDrafts b) =>
    jsonEncode(responsibilitiesPayload(a)) ==
    jsonEncode(responsibilitiesPayload(b));

/// The first provider set to "selected" with no account ticked — which the
/// backend would refuse — or null.
String? firstProviderMissingAccounts(ResponsibilityDrafts drafts) {
  for (final provider in routableProviders) {
    final draft = drafts[provider];
    if (draft != null &&
        draft.mode == ResponsibilityMode.selected &&
        draft.connectionIds.isEmpty) {
      return provider;
    }
  }
  return null;
}

/// One account the admin can tick.
@immutable
class ResponsibilityAccountOption {
  const ResponsibilityAccountOption({
    required this.id,
    required this.name,
    required this.connected,
    this.detail = '',
  });

  final int id;
  final String name;

  /// The provider's own account id, shown only to tell apart two accounts
  /// with the same name.
  final String detail;

  /// False for an account that is not `CONNECTED` — or that the team still
  /// has a rule for but no longer appears among the channels at all.
  final bool connected;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$name $detail'.toLowerCase().contains(q);
  }
}

/// The accounts listed under [provider]: every connected channel of it, plus
/// any account the team already has a rule for that is no longer among them
/// — so a saved selection is never silently dropped from view. Sorted by
/// name.
List<ResponsibilityAccountOption> responsibilityAccountOptions({
  required String provider,
  required List<ChannelConnection> channels,
  List<RoutingResponsibility> rules = const [],
  int? teamId,
}) {
  final own = channels
      .where((c) => c.provider.toUpperCase() == provider)
      .toList();
  final options = <ResponsibilityAccountOption>[
    for (final c in own)
      ResponsibilityAccountOption(
        id: c.id,
        name: c.displayName,
        connected: c.status.toUpperCase() == 'CONNECTED',
      ),
  ];
  if (teamId != null) {
    for (final rule in _activeRulesOf(rules, teamId)) {
      final id = rule.channelConnectionId;
      if (id == null || rule.provider != provider) continue;
      if (options.any((o) => o.id == id)) continue;
      options.add(
        ResponsibilityAccountOption(
          id: id,
          name: rule.channelConnectionName,
          connected: false,
        ),
      );
    }
  }

  final nameCounts = <String, int>{};
  for (final o in options) {
    nameCounts[o.name] = (nameCounts[o.name] ?? 0) + 1;
  }
  final result = [
    for (final o in options)
      (nameCounts[o.name] ?? 0) > 1
          ? ResponsibilityAccountOption(
              id: o.id,
              name: o.name,
              connected: o.connected,
              detail:
                  own
                      .where((c) => c.id == o.id)
                      .firstOrNull
                      ?.externalAccountId ??
                  '',
            )
          : o,
  ];
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
