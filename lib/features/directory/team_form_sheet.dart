/// Add/Edit Team — `POST /teams/` and `PATCH /teams/{id}/`.
///
/// ADMIN only, server-side (`team.manage`) and in this UI: every entry point
/// that opens this sheet is itself gated on
/// `isAdminProvider && canProvider(Perm.teamManage)` — see `teams_screen.dart`
/// — so reaching this file at all already implies both checks passed.
///
/// Member/leader pickers read `employeeDirectoryProvider` — the same
/// directory data `employees_screen.dart` already loads — rather than a
/// second employee source.
///
/// In edit mode ([existing] != null), only changed fields are diffed and sent
/// via `PATCH /teams/{id}/`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/models/routing_policy.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

/// `RoutableProviderEnum`.
const _routableProviders = ['WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'TIKTOK'];

/// Opens the Add Team sheet.
Future<void> showAddTeamSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _TeamFormSheet(scrollController: controller),
    ),
  );
}

/// Opens the Edit Team sheet, prefilled from [team].
Future<void> showEditTeamSheet(BuildContext context, {required Team team}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _TeamFormSheet(existing: team, scrollController: controller),
    ),
  );
}

class _TeamFormSheet extends ConsumerStatefulWidget {
  const _TeamFormSheet({this.existing, required this.scrollController});

  final Team? existing;
  final ScrollController scrollController;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_TeamFormSheet> createState() => _TeamFormSheetState();
}

class _TeamFormSheetState extends ConsumerState<_TeamFormSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _language = TextEditingController(text: widget.existing?.language);
  late final _color = TextEditingController(text: widget.existing?.color);
  late bool _isActive = widget.existing?.isActive ?? true;
  final Set<int> _memberIds = {};
  final Set<int> _leaderIds = {};

  /// One entry per provider the team is responsible for. A provider absent
  /// here has no responsibility — matches the backend's own "omitted means
  /// none" semantics for `TeamWrite.responsibilities`.
  final Map<String, TeamResponsibilityInput> _responsibilities = {};

  /// Seeded once, the first time [routingResponsibilitiesProvider] resolves
  /// — there is no per-team read endpoint, so this is derived client-side
  /// from the full org list and must not be re-applied on every rebuild
  /// (that would stomp whatever the admin has already changed).
  bool _responsibilitiesSeeded = false;

  /// Whether the admin has touched the responsibilities section this
  /// session. `responsibilities` is only ever sent when true — omitting the
  /// field on edit leaves existing rules untouched (the backend's own
  /// contract), and nothing here can safely diff against "current state"
  /// the way other fields do, since it starts unseeded until the async
  /// fetch resolves.
  bool _responsibilitiesTouched = false;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _memberIds.addAll(widget.existing!.memberIds);
      _leaderIds.addAll(widget.existing!.leaderIds);
    }
  }

  void _seedResponsibilities(List<RoutingResponsibility> all) {
    if (_responsibilitiesSeeded || widget.existing == null) return;
    _responsibilitiesSeeded = true;

    final mine = all.where(
      (r) => r.isActive && r.teamId == widget.existing!.id,
    );
    final byProvider = <String, List<RoutingResponsibility>>{};
    for (final rule in mine) {
      (byProvider[rule.provider] ??= []).add(rule);
    }

    for (final entry in byProvider.entries) {
      final channelSpecific = entry.value
          .where((r) => r.isChannelSpecific)
          .map((r) => r.channelConnectionId!)
          .toList();
      _responsibilities[entry.key] = TeamResponsibilityInput(
        provider: entry.key,
        // A provider-wide rule (no channel_connection) means "all"; every
        // rule this team has for this provider being channel-specific means
        // "selected" with exactly those channels.
        scope: channelSpecific.isEmpty ? 'all' : 'selected',
        channelConnectionIds: channelSpecific,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _language.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.addTeamNameRequiredError);
      return;
    }

    final emptySelected = _responsibilities.values.where(
      (r) => r.scope == 'selected' && r.channelConnectionIds.isEmpty,
    );
    if (emptySelected.isNotEmpty) {
      setState(() => _error = context.l10n.routingChannelScopeRequiredError);
      return;
    }

    final repository = ref.read(directoryRepositoryProvider);

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.isEdit) {
        await repository.updateTeam(widget.existing!.id, _diff());
      } else {
        await repository.createTeam({
          'name': name,
          if (_description.text.trim().isNotEmpty)
            'description': _description.text.trim(),
          if (_language.text.trim().isNotEmpty)
            'language': _language.text.trim(),
          if (_color.text.trim().isNotEmpty) 'color': _color.text.trim(),
          'is_active': _isActive,
          'member_ids': _memberIds.toList(),
          'leader_ids': _leaderIds.toList(),
          if (_responsibilities.isNotEmpty)
            'responsibilities': _responsibilities.values
                .map((r) => r.toJson())
                .toList(),
        });
      }

      // Guarded together — see conversation_actions_sheet.dart's
      // _ActionsSheetState._run(): ref/Navigator use here throws "Using ref
      // when a widget is about to or has been unmounted" if this sheet
      // closed some other way while the request was in flight.
      if (!mounted) return;
      ref.invalidate(teamsProvider);
      ref.invalidate(employeeDirectoryProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? context.l10n.teamUpdatedSnackbar
                : context.l10n.teamAddedSnackbar,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, dynamic> _diff() {
    final existing = widget.existing!;
    final fields = <String, dynamic>{};

    void putString(String key, String current, String original) {
      final trimmed = current.trim();
      if (trimmed != original.trim()) fields[key] = trimmed;
    }

    putString('name', _name.text, existing.name);
    putString('description', _description.text, existing.description);
    putString('language', _language.text, existing.language);
    putString('color', _color.text, existing.color);

    if (_isActive != existing.isActive) fields['is_active'] = _isActive;

    final originalMemberIds = existing.memberIds.toSet();
    if (!_setEquals(_memberIds, originalMemberIds)) {
      fields['member_ids'] = _memberIds.toList();
    }

    final originalLeaderIds = existing.leaderIds.toSet();
    if (!_setEquals(_leaderIds, originalLeaderIds)) {
      fields['leader_ids'] = _leaderIds.toList();
    }

    // Omitted entirely unless the admin actually opened and edited this
    // section — see the field's own doc comment for why nothing here can
    // diff against "current state" the way the fields above do. Sending it
    // untouched would silently overwrite rules this form never displayed
    // (e.g. still loading when the admin hit Save).
    if (_responsibilitiesTouched) {
      fields['responsibilities'] = _responsibilities.values
          .map((r) => r.toJson())
          .toList();
    }

    return fields;
  }

  bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employees = ref.watch(employeeDirectoryProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Text(
          widget.isEdit
              ? context.l10n.editTeamTitle
              : context.l10n.addTeamTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.lg),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.l10n.teamNameFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionFieldLabel,
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _language,
                decoration: InputDecoration(
                  labelText: context.l10n.languageLabel,
                  hintText: 'en',
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _color,
                decoration: InputDecoration(
                  labelText: context.l10n.colorFieldLabel,
                  hintText: '#0F766E',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.activeFieldLabel),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        const SizedBox(height: Space.lg),
        _TeamResponsibilitiesCard(
          responsibilities: _responsibilities,
          seedFrom: widget.isEdit ? _seedResponsibilities : null,
          onChanged: (provider, input) => setState(() {
            _responsibilitiesTouched = true;
            if (input == null) {
              _responsibilities.remove(provider);
            } else {
              _responsibilities[provider] = input;
            }
          }),
        ),
        const SizedBox(height: Space.md),
        Text(context.l10n.leadersFieldLabel, style: theme.textTheme.labelLarge),
        employees.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: LoadingState(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(
              context.l10n.employeesLoadFailedMessage,
              style: theme.textTheme.bodySmall,
            ),
          ),
          data: (rows) => Column(
            children: [
              for (final employee in rows)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(employee.fullName),
                  value: _leaderIds.contains(employee.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _leaderIds.add(employee.id);
                    } else {
                      _leaderIds.remove(employee.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Text(context.l10n.membersFieldLabel, style: theme.textTheme.labelLarge),
        employees.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => const SizedBox.shrink(),
          data: (rows) => Column(
            children: [
              for (final employee in rows)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(employee.fullName),
                  value: _memberIds.contains(employee.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _memberIds.add(employee.id);
                    } else {
                      _memberIds.remove(employee.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}

/// One row per provider: none / all accounts / selected accounts, with a
/// channel picker that appears only for "selected."
///
/// On edit, [seedFrom] is called once real data arrives from
/// [routingResponsibilitiesProvider] — there is no per-team read endpoint,
/// so current state is derived client-side from the full organization list
/// (see `_TeamFormSheetState._seedResponsibilities`). On add, [seedFrom] is
/// null: a new team starts with no responsibilities, same as the backend's
/// own default.
class _TeamResponsibilitiesCard extends ConsumerWidget {
  const _TeamResponsibilitiesCard({
    required this.responsibilities,
    required this.seedFrom,
    required this.onChanged,
  });

  final Map<String, TeamResponsibilityInput> responsibilities;
  final void Function(List<RoutingResponsibility> all)? seedFrom;
  final void Function(String provider, TeamResponsibilityInput? input)
  onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final channels = ref.watch(channelsProvider);
    final allResponsibilities = seedFrom == null
        ? const AsyncValue<List<RoutingResponsibility>>.data([])
        : ref.watch(routingResponsibilitiesProvider);

    allResponsibilities.whenData((rows) => seedFrom?.call(rows));

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.teamResponsibilitiesTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            context.l10n.teamResponsibilitiesDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          if (allResponsibilities.hasError)
            Text(
              context.l10n.teamResponsibilitiesLoadFailedMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else
            for (final provider in _routableProviders) ...[
              _ProviderResponsibilityRow(
                provider: provider,
                current: responsibilities[provider],
                channels: channels.value
                    ?.where(
                      (c) => c.provider.toUpperCase() == provider && c.isActive,
                    )
                    .toList(),
                onChanged: (input) => onChanged(provider, input),
              ),
              if (provider != _routableProviders.last)
                const SizedBox(height: Space.sm),
            ],
        ],
      ),
    );
  }
}

class _ProviderResponsibilityRow extends StatelessWidget {
  const _ProviderResponsibilityRow({
    required this.provider,
    required this.current,
    required this.channels,
    required this.onChanged,
  });

  final String provider;
  final TeamResponsibilityInput? current;
  final List<ChannelConnection>? channels;
  final ValueChanged<TeamResponsibilityInput?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = current?.scope ?? 'none';
    final selectedIds = current?.channelConnectionIds.toSet() ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ConversationBadges.providerIcon(provider),
              size: 18,
              color: ConversationBadges.providerColor(provider),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                ConversationBadges.providerLabel(context, provider),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DropdownButton<String>(
              value: scope,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 'none',
                  child: Text(context.l10n.teamResponsibilityNone),
                ),
                DropdownMenuItem(
                  value: 'all',
                  child: Text(context.l10n.teamResponsibilityAll),
                ),
                DropdownMenuItem(
                  value: 'selected',
                  child: Text(context.l10n.teamResponsibilitySelected),
                ),
              ],
              onChanged: (value) {
                if (value == null || value == 'none') {
                  onChanged(null);
                } else if (value == 'all') {
                  onChanged(
                    TeamResponsibilityInput(provider: provider, scope: 'all'),
                  );
                } else {
                  onChanged(
                    TeamResponsibilityInput(
                      provider: provider,
                      scope: 'selected',
                      channelConnectionIds: selectedIds.toList(),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        if (scope == 'selected') ...[
          const SizedBox(height: Space.xs),
          Padding(
            padding: const EdgeInsets.only(left: Space.xl),
            child: (channels == null || channels!.isEmpty)
                ? Text(
                    context.l10n.teamResponsibilityNoChannelsMessage,
                    style: theme.textTheme.bodySmall,
                  )
                : Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    children: [
                      for (final channel in channels!)
                        FilterChip(
                          label: Text(channel.displayName),
                          selected: selectedIds.contains(channel.id),
                          onSelected: (isSelected) {
                            final updated = Set<int>.from(selectedIds);
                            if (isSelected) {
                              updated.add(channel.id);
                            } else {
                              updated.remove(channel.id);
                            }
                            onChanged(
                              TeamResponsibilityInput(
                                provider: provider,
                                scope: 'selected',
                                channelConnectionIds: updated.toList(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}
