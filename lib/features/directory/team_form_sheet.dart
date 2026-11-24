/// Create Team and Edit Team — one shared form, `POST /teams/` and
/// `PATCH /teams/{id}/`.
///
/// Laid out like the web CRM's team dialog: team details (name, description,
/// language, colour), members with leaders, and channel responsibilities.
/// The pieces live in `team_form/`:
///   * `team_info_fields.dart` — name, description, language, colour;
///   * `team_members_picker.dart` — `member_ids` / `leader_ids`;
///   * `channel_responsibility_section.dart` — the per-channel sections;
///   * `team_responsibility_state.dart` — the channel logic as plain data.
///
/// Who may open it: every entry point is gated on
/// `isAdminProvider && canProvider(Perm.teamManage)` (see `teams_screen.dart`).
/// Channel responsibilities additionally need `routing.manage` — the backend
/// requires it to send `responsibilities` at all — so without it that
/// section is not shown and the field is never sent, as on the web.
///
/// Edit sends only what changed. `responsibilities` is the team's complete
/// channel responsibility, so it is sent only when the admin changed it —
/// omitting it leaves the saved rules untouched (the backend's contract).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/logging/app_log.dart';
import '../../core/models/directory.dart';
import '../../core/models/employee.dart';
import '../../core/models/routing_policy.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../ai_knowledge/knowledge_forms.dart' show confirmDiscardChanges;
import '../authentication/auth_controller.dart';
import 'directory_providers.dart';
import 'team_form/channel_responsibility_section.dart';
import 'team_form/team_info_fields.dart';
import 'team_form/team_members_picker.dart';
import 'team_form/team_responsibility_state.dart';

/// Development-only diagnostics. Logs ids, providers, scopes and status
/// codes — never names or anything about a customer.
void _log(String message) =>
    AppLog.debug('TEAM_CHANNEL_RESPONSIBILITY', message);

/// Opens Create Team.
Future<void> showAddTeamSheet(BuildContext context) =>
    _showTeamFormSheet(context, null);

/// Opens Edit Team, prefilled from [team].
Future<void> showEditTeamSheet(BuildContext context, {required Team team}) =>
    _showTeamFormSheet(context, team);

/// A tall sheet with its own header and footer. It is not drag-dismissed:
/// a drag would close it straight past the unsaved-changes check, which
/// only the back button, a tap outside and Cancel go through.
Future<void> _showTeamFormSheet(BuildContext context, Team? team) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => TeamFormSheet(team: team),
  );
}

class TeamFormSheet extends ConsumerStatefulWidget {
  const TeamFormSheet({this.team, super.key});

  /// Null for Create Team.
  final Team? team;

  bool get isEdit => team != null;

  @override
  ConsumerState<TeamFormSheet> createState() => _TeamFormSheetState();
}

class _TeamFormSheetState extends ConsumerState<TeamFormSheet> {
  // ---- Team details -------------------------------------------------------
  late final String _initialName = widget.team?.name ?? '';
  late final String _initialDescription = widget.team?.description ?? '';
  late final String _initialLanguage = widget.team?.language ?? '';

  /// The web shows the default colour for a team that has none; so does
  /// this form. It is only sent when it differs from what the team has.
  late final String _initialColor = (widget.team?.color ?? '').trim().isEmpty
      ? defaultTeamColor
      : widget.team!.color.trim();

  late final _name = TextEditingController(text: _initialName);
  late final _description = TextEditingController(text: _initialDescription);
  late final _language = TextEditingController(text: _initialLanguage);
  late String _color = _initialColor;

  // ---- Members and leaders -----------------------------------------------
  late final Set<int> _initialMemberIds = {
    ...?widget.team?.memberIds,
    ...?widget.team?.members.map((m) => m.id),
  };
  late final Set<int> _initialLeaderIds = {
    ...?widget.team?.leaderIds,
    ...?widget.team?.leaders.map((m) => m.id),
  };
  late final Set<int> _memberIds = {..._initialMemberIds};
  late final Set<int> _leaderIds = {..._initialLeaderIds};

  // ---- Channel responsibilities -------------------------------------------

  /// What the team has saved — empty for a new team, read once from the
  /// rules for an existing one. Null until those rules have loaded.
  ResponsibilityDrafts? _baseline;

  /// The admin's choice. Null until they change something, so nothing is
  /// sent for a section they never touched.
  ResponsibilityDrafts? _edited;

  /// Expanded channels. Starts with every channel that has a choice.
  final Set<String> _expanded = {};

  final Map<String, GlobalKey> _channelKeys = {
    for (final p in routableProviders) p: GlobalKey(),
  };
  final _nameKey = GlobalKey();

  // ---- Submission ---------------------------------------------------------
  bool _submitting = false;
  String? _banner;
  Map<String, String> _fieldErrors = const {};
  Map<String, String> _channelErrors = const {};
  String? _responsibilitiesError;

  @override
  void initState() {
    super.initState();
    if (!widget.isEdit) _baseline = emptyResponsibilityDrafts();
    for (final c in [_name, _description, _language]) {
      c.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    // Rebuild for the dirty state, and clear a field's error once edited.
    setState(() {
      if (_fieldErrors.isNotEmpty) {
        _fieldErrors = {
          for (final e in _fieldErrors.entries)
            if (!_fieldChanged(e.key)) e.key: e.value,
        };
      }
    });
  }

  final Map<String, String> _errorSnapshot = {};

  bool _fieldChanged(String field) {
    final now = switch (field) {
      'name' => _name.text,
      'description' => _description.text,
      'language' => _language.text,
      _ => null,
    };
    if (now == null) return false;
    return _errorSnapshot[field] != now;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _language.dispose();
    super.dispose();
  }

  bool get _canManageRouting => ref.read(canProvider(Perm.routingManage));

  ResponsibilityDrafts? get _drafts => _edited ?? _baseline;

  void _seed(List<RoutingResponsibility> rules) {
    if (_baseline != null || widget.team == null) return;
    final seeded = seedResponsibilityDrafts(rules, widget.team!.id);
    _baseline = seeded;
    _expanded.addAll([
      for (final p in routableProviders)
        if (seeded[p]!.mode != ResponsibilityMode.none) p,
    ]);
    _log(
      'SEED teamId=${widget.team!.id} '
      'seeded=${responsibilitiesPayload(seeded)}',
    );
  }

  bool get _responsibilitiesChanged {
    final edited = _edited;
    final baseline = _baseline;
    if (edited == null || baseline == null) return false;
    return !sameResponsibilities(edited, baseline);
  }

  /// Whether `responsibilities` goes in the request.
  bool get _sendResponsibilities {
    if (!_canManageRouting || _edited == null) return false;
    return widget.isEdit
        ? _responsibilitiesChanged
        : responsibilitiesPayload(_edited!).isNotEmpty;
  }

  bool get _dirty =>
      _name.text.trim() != _initialName.trim() ||
      _description.text.trim() != _initialDescription.trim() ||
      _language.text.trim() != _initialLanguage.trim() ||
      _color != _initialColor ||
      !_sameSet(_memberIds, _initialMemberIds) ||
      !_sameSet(_leaderIds, _initialLeaderIds) ||
      _responsibilitiesChanged;

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _toggle(Set<int> ids, int id, String errorKey) => setState(() {
    if (!ids.remove(id)) ids.add(id);
    _fieldErrors = {..._fieldErrors}..remove(errorKey);
  });

  void _changeChannel(String provider, ChannelResponsibilityDraft draft) {
    final current = _drafts;
    if (current == null) return;
    _log(
      'SELECT teamId=${widget.team?.id ?? 'new'} channel=$provider '
      'mode=${draft.mode.name} ids=${draft.selectedIds.toList()} '
      'strict=${draft.strict}',
    );
    setState(() {
      _edited = {...current, provider: draft};
      _channelErrors = {..._channelErrors}..remove(provider);
      _responsibilitiesError = null;
    });
  }

  void _toggleExpanded(String provider) => setState(() {
    if (!_expanded.remove(provider)) _expanded.add(provider);
  });

  Map<String, dynamic> _createBody() {
    final description = _description.text.trim();
    final language = _language.text.trim();
    return {
      'name': _name.text.trim(),
      if (description.isNotEmpty) 'description': description,
      if (language.isNotEmpty) 'language': language,
      'color': _color,
      'is_active': true,
      'member_ids': _memberIds.toList()..sort(),
      'leader_ids': _leaderIds.toList()..sort(),
      if (_sendResponsibilities)
        'responsibilities': responsibilitiesPayload(_edited!),
    };
  }

  Map<String, dynamic> _editBody() {
    final fields = <String, dynamic>{};
    void putText(String key, String now, String before) {
      if (now.trim() != before.trim()) fields[key] = now.trim();
    }

    putText('name', _name.text, _initialName);
    putText('description', _description.text, _initialDescription);
    putText('language', _language.text, _initialLanguage);
    if (_color != _initialColor) fields['color'] = _color;
    if (!_sameSet(_memberIds, _initialMemberIds)) {
      fields['member_ids'] = _memberIds.toList()..sort();
    }
    if (!_sameSet(_leaderIds, _initialLeaderIds)) {
      fields['leader_ids'] = _leaderIds.toList()..sort();
    }
    if (_sendResponsibilities) {
      fields['responsibilities'] = responsibilitiesPayload(_edited!);
    }
    return fields;
  }

  /// Local checks, before any request. Returns false and shows the errors
  /// when something is wrong.
  bool _validate() {
    final l10n = context.l10n;
    final fieldErrors = <String, String>{};
    final channelErrors = <String, String>{};
    if (_name.text.trim().isEmpty) {
      fieldErrors['name'] = l10n.addTeamNameRequiredError;
    }
    final drafts = _drafts;
    if (_canManageRouting && _edited != null && drafts != null) {
      for (final provider in routableProviders) {
        final draft = drafts[provider]!;
        if (draft.mode == ResponsibilityMode.selected &&
            draft.connectionIds.isEmpty) {
          channelErrors[provider] = l10n.teamResponsibilityChooseAccount(
            ConversationBadges.providerLabel(context, provider),
          );
        }
      }
    }
    if (fieldErrors.isEmpty && channelErrors.isEmpty) return true;

    _snapshotErrorFields(fieldErrors.keys);
    setState(() {
      _fieldErrors = fieldErrors;
      _channelErrors = channelErrors;
      _expanded.addAll(channelErrors.keys);
      _banner = null;
    });
    _revealFirstError(
      fieldErrors.containsKey('name')
          ? _nameKey
          : _channelKeys[firstProviderMissingAccounts(drafts!)],
    );
    return false;
  }

  void _snapshotErrorFields(Iterable<String> fields) {
    _errorSnapshot
      ..clear()
      ..addAll({
        for (final f in fields)
          f: switch (f) {
            'name' => _name.text,
            'description' => _description.text,
            'language' => _language.text,
            _ => '',
          },
      });
  }

  void _revealFirstError(GlobalKey? key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key?.currentContext;
      if (target == null || !target.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0.1,
          duration: const Duration(milliseconds: 250),
        ),
      );
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    final repository = ref.read(directoryRepositoryProvider);
    final body = widget.isEdit ? _editBody() : _createBody();
    setState(() {
      _submitting = true;
      _banner = null;
      _fieldErrors = const {};
      _channelErrors = const {};
      _responsibilitiesError = null;
    });
    _log(
      'SUBMIT teamId=${widget.team?.id ?? 'new'} fields=${body.keys.toList()} '
      'responsibilities=${body['responsibilities']}',
    );
    try {
      if (widget.isEdit) {
        await repository.updateTeam(widget.team!.id, body);
      } else {
        await repository.createTeam(body);
      }
      _log('RESULT teamId=${widget.team?.id ?? 'new'} ok');
      // Guarded together: ref and Navigator must not be used once this
      // sheet has closed some other way while the request was in flight.
      if (!mounted) return;
      ref.invalidate(teamsProvider);
      ref.invalidate(employeeDirectoryProvider);
      // Settings and the next form read the saved rules from here.
      if (body.containsKey('responsibilities')) {
        ref.invalidate(routingResponsibilitiesProvider);
      }
      final messenger = ScaffoldMessenger.of(context);
      final message = widget.isEdit
          ? context.l10n.teamUpdatedSnackbar
          : context.l10n.teamAddedSnackbar;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      _log(
        'RESULT teamId=${widget.team?.id ?? 'new'} '
        'status=${error.statusCode} code=${error.code}',
      );
      if (!mounted) return;
      _showServerErrors(error);
    } catch (error) {
      _log('RESULT teamId=${widget.team?.id ?? 'new'} failed=$error');
      if (!mounted) return;
      setState(() => _banner = context.l10n.genericErrorTitle);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static const _fieldNames = {
    'name',
    'description',
    'language',
    'color',
    'member_ids',
    'leader_ids',
  };

  void _showServerErrors(ApiException error) {
    final fieldErrors = <String, String>{};
    for (final entry in error.fieldErrors().entries) {
      if (_fieldNames.contains(entry.key)) fieldErrors[entry.key] = entry.value;
    }
    final responsibilities = error.details.containsKey('responsibilities')
        ? _firstText(error.details['responsibilities']) ?? error.message
        : null;
    final hasFieldErrors = fieldErrors.isNotEmpty || responsibilities != null;

    _snapshotErrorFields(fieldErrors.keys);
    setState(() {
      _fieldErrors = fieldErrors;
      _responsibilitiesError = responsibilities;
      _banner = error.isForbidden || !hasFieldErrors
          ? error.message
          : context.l10n.teamFormFixFields;
    });
    if (fieldErrors.containsKey('name')) _revealFirstError(_nameKey);
  }

  /// The first readable message in a nested DRF error.
  static String? _firstText(Object? value) {
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is List) {
      for (final item in value) {
        final text = _firstText(item);
        if (text != null) return text;
      }
    }
    if (value is Map) {
      for (final item in value.values) {
        final text = _firstText(item);
        if (text != null) return text;
      }
    }
    return null;
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final canManageRouting = ref.watch(canProvider(Perm.routingManage));

    // ---- data ----
    final employees = ref.watch(teamFormEmployeesProvider);
    final people = employees.whenData(
      (rows) => teamPersonOptions(
        employees: rows,
        current: [...?widget.team?.members, ...?widget.team?.leaders],
      ),
    );

    AsyncValue<List<RoutingResponsibility>> rules = const AsyncValue.data([]);
    if (canManageRouting && widget.isEdit) {
      rules = ref.watch(teamFormResponsibilitiesProvider);
      if (rules.hasValue && !rules.isLoading) _seed(rules.requireValue);
    }
    final channels = canManageRouting
        ? ref.watch(channelsProvider)
        : const AsyncValue<List<ChannelConnection>>.data([]);

    final dirty = _dirty;
    final canSave = !_submitting && (!widget.isEdit || dirty);

    return PopScope(
      canPop: !dirty && !_submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitting) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              _Header(
                title: widget.isEdit ? l10n.editTeamTitle : l10n.addTeamTitle,
                colorPreview: parseTeamColor(_color),
                onClose: _submitting ? null : _cancel,
              ),
              Divider(height: 1, color: colors.border),
              Expanded(
                child: ListView(
                  key: const ValueKey('teamFormScroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.lg,
                    Space.xl,
                  ),
                  children: [
                    Text(
                      l10n.teamFormRoutingNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    TeamInfoFields(
                      nameKey: _nameKey,
                      name: _name,
                      description: _description,
                      language: _language,
                      color: _color,
                      enabled: !_submitting,
                      errors: _fieldErrors,
                      onColorChanged: (value) => setState(() {
                        _color = value;
                        _fieldErrors = {..._fieldErrors}..remove('color');
                      }),
                    ),
                    const _SectionGap(),
                    TeamMembersPicker(
                      people: people,
                      memberIds: _memberIds,
                      leaderIds: _leaderIds,
                      enabled: !_submitting,
                      errors: _fieldErrors,
                      onToggleMember: (id) =>
                          _toggle(_memberIds, id, 'member_ids'),
                      onToggleLeader: (id) =>
                          _toggle(_leaderIds, id, 'leader_ids'),
                      onRetry: () => ref.invalidate(teamFormEmployeesProvider),
                    ),
                    if (canManageRouting) ...[
                      const _SectionGap(),
                      _responsibilities(context, rules, channels),
                    ],
                  ],
                ),
              ),
              _Footer(
                banner: _banner,
                submitting: _submitting,
                saveLabel: widget.isEdit
                    ? l10n.teamFormSaveChangesAction
                    : l10n.teamFormCreateAction,
                onSave: canSave ? _submit : null,
                onCancel: _submitting ? null : _cancel,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _responsibilities(
    BuildContext context,
    AsyncValue<List<RoutingResponsibility>> rules,
    AsyncValue<List<ChannelConnection>> channels,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final drafts = _drafts;

    if (drafts == null) {
      // Edit, and the saved rules have not arrived (or failed).
      if (rules.hasError && !rules.isLoading) {
        return Column(
          key: const ValueKey('teamResponsibilitiesFailed'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.teamResponsibilitiesTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.xs),
            InlineError(message: l10n.teamResponsibilitiesLoadFailedMessage),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () =>
                    ref.invalidate(teamFormResponsibilitiesProvider),
                child: Text(l10n.retryMessageAction),
              ),
            ),
          ],
        );
      }
      return Semantics(
        label: l10n.teamResponsibilitiesTitle,
        child: Container(
          key: const ValueKey('teamResponsibilitiesLoading'),
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.of(context).muted,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final rows = (channels.value ?? const <ChannelConnection>[])
        .where((c) => c.provider.toUpperCase() != 'MOCK')
        .toList();
    final ruleRows = rules.value ?? const <RoutingResponsibility>[];
    final teamId = widget.team?.id;
    return ChannelResponsibilitySection(
      drafts: drafts,
      accounts: {
        for (final p in routableProviders)
          p: responsibilityAccountOptions(
            provider: p,
            channels: rows,
            rules: ruleRows,
            teamId: teamId,
          ),
      },
      accountsLoading: channels.isLoading && !channels.hasValue,
      accountsFailed: channels.hasError && !channels.hasValue,
      expanded: _expanded,
      onToggleExpanded: _toggleExpanded,
      onChanged: _changeChannel,
      enabled: !_submitting,
      providerErrors: _channelErrors,
      error: _responsibilitiesError,
      redundantProviders: teamId == null
          ? const []
          : redundantRuleProviders(ruleRows, teamId),
      sectionKeys: _channelKeys,
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Divider(height: 1, color: AppColors.of(context).border),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.colorPreview,
    required this.onClose,
  });

  final String title;
  final Color? colorPreview;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.md,
        Space.xs,
        Space.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: colorPreview ?? theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('teamFormClose'),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Always on screen, under the scrolling content: the error banner, Cancel
/// and Save.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.banner,
    required this.submitting,
    required this.saveLabel,
    required this.onSave,
    required this.onCancel,
  });

  final String? banner;
  final bool submitting;
  final String saveLabel;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null) ...[
              InlineError(message: banner!),
              const SizedBox(height: Space.md),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('teamFormCancel'),
                    onPressed: onCancel,
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('teamFormSave'),
                    onPressed: onSave,
                    child: submitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            saveLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
