/// One channel's automatic-reply limits — the per-connection fields of
/// `GET/PUT /ai/agent-settings/` (`AIAgentSetting` / `AIAgentSettingUpdate`):
/// the session and daily caps, when a new session starts, what the AI does
/// when it is let back in, how much evidence a reply needs, the topics that
/// always go to a person, and the handoff rules.
///
/// The channel's mode (Off / Suggest / Automatic) is not changed here; it
/// stays on the AI & Knowledge tab, beside its readiness checks.
///
/// Edits are held until Save, which sends only what changed. Leaving with
/// unsaved changes asks first.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_activity_screen.dart' show AiNotAvailable;
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_knowledge_settings_tab.dart' show canManageAiKnowledgeProvider;
import 'ai_metric_widgets.dart';
import 'knowledge_forms.dart';

typedef _Range = ({int min, int max});

class AiChannelSettingsScreen extends ConsumerStatefulWidget {
  const AiChannelSettingsScreen({required this.connectionId, super.key});

  final int connectionId;

  @override
  ConsumerState<AiChannelSettingsScreen> createState() =>
      _AiChannelSettingsScreenState();
}

class _AiChannelSettingsScreenState
    extends ConsumerState<AiChannelSettingsScreen> {
  /// The channel as the form was filled from it.
  AiAgentSetting? _baseline;

  final _maxTurns = TextEditingController();
  final _idleHours = TextEditingController();
  final _dailyCap = TextEditingController();
  final _newTopic = TextEditingController();
  String _resume = '';
  String _grounding = '';
  List<String> _topics = const [];
  bool? _handoffOnRestricted;
  bool _showFloor = false;
  String? _topicError;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _maxTurns.dispose();
    _idleHours.dispose();
    _dailyCap.dispose();
    _newTopic.dispose();
    super.dispose();
  }

  void _fill(AiAgentSetting row) {
    _baseline = row;
    _maxTurns.text = '${row.maxAutoTurns}';
    _idleHours.text = '${row.autoSessionIdleHours}';
    _dailyCap.text = '${row.dailyAutoSendLimit}';
    _resume = row.resumeBehaviour;
    _grounding = row.groundingProfile;
    _topics = List.of(row.extraRestrictedTopics);
    _handoffOnRestricted = row.handoffOnRestrictedTopic;
    _fieldErrors = const {};
    _error = null;
  }

  static int? _inRange(String text, _Range range) {
    final value = int.tryParse(text.trim());
    return value == null || value < range.min || value > range.max
        ? null
        : value;
  }

  bool get _numbersValid =>
      _inRange(_maxTurns.text, AiAgentSetting.maxAutoTurnsRange) != null &&
      _inRange(_idleHours.text, AiAgentSetting.autoSessionIdleHoursRange) !=
          null &&
      _inRange(_dailyCap.text, AiAgentSetting.dailyAutoSendLimitRange) != null;

  /// What a save would send: only the fields that differ from [_baseline],
  /// keyed as `AIAgentSettingUpdate` names them. Numbers that are not valid
  /// are left out — Save is off until they are.
  Map<String, Object> get _changes {
    final base = _baseline;
    if (base == null) return const {};
    final maxTurns = _inRange(_maxTurns.text, AiAgentSetting.maxAutoTurnsRange);
    final idle = _inRange(
      _idleHours.text,
      AiAgentSetting.autoSessionIdleHoursRange,
    );
    final cap = _inRange(
      _dailyCap.text,
      AiAgentSetting.dailyAutoSendLimitRange,
    );
    return {
      if (maxTurns != null && maxTurns != base.maxAutoTurns)
        'max_auto_turns': maxTurns,
      if (idle != null && idle != base.autoSessionIdleHours)
        'auto_session_idle_hours': idle,
      if (cap != null && cap != base.dailyAutoSendLimit)
        'daily_auto_send_limit': cap,
      if (_resume != base.resumeBehaviour) 'resume_behaviour': _resume,
      if (_grounding != base.groundingProfile) 'grounding_profile': _grounding,
      if (!_sameTopics(_topics, base.extraRestrictedTopics))
        'extra_restricted_topics': _topics,
      if (_handoffOnRestricted != null &&
          _handoffOnRestricted != base.handoffOnRestrictedTopic)
        'handoff_on_restricted_topic': _handoffOnRestricted!,
    };
  }

  static bool _sameTopics(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _dirty =>
      _baseline != null && (_changes.isNotEmpty || !_numbersValid);

  void _addTopic() {
    final l10n = context.l10n;
    final topic = _newTopic.text.trim();
    String? error;
    if (topic.isEmpty) {
      return;
    } else if (topic.runes.length > AiAgentSetting.maxRestrictedTopicLength) {
      error = l10n.aiChannelTopicTooLong(
        AiAgentSetting.maxRestrictedTopicLength,
      );
    } else if ([
      ..._topics,
      ...?_baseline?.lockedRestrictedTopics,
    ].any((t) => t.toLowerCase() == topic.toLowerCase())) {
      error = l10n.aiChannelTopicDuplicate;
    } else if (_topics.length >= AiAgentSetting.maxRestrictedTopics) {
      error = l10n.aiChannelTooManyTopics(AiAgentSetting.maxRestrictedTopics);
    }
    setState(() {
      _topicError = error;
      if (error == null) {
        _topics = [..._topics, topic];
        _newTopic.clear();
      }
    });
  }

  Future<void> _save() async {
    final changes = _changes;
    if (_saving || changes.isEmpty || !_numbersValid) return;
    final l10n = context.l10n;
    setState(() {
      _saving = true;
      _fieldErrors = const {};
      _error = null;
    });
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .updateSettings(widget.connectionId, changes);
      if (!mounted) return;
      final saved = _rowIn(ref.read(agentSettingsProvider).value);
      setState(() {
        if (saved != null) _fill(saved);
        _saving = false;
      });
      showKnowledgeSnack(context, l10n.aiChannelSaved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = error.fieldErrors();
        _error = aiErrorMessage(context, error);
      });
    }
  }

  AiAgentSetting? _rowIn(List<AiAgentSetting>? rows) {
    for (final row in rows ?? const <AiAgentSetting>[]) {
      if (row.connectionId == widget.connectionId) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!ref.watch(canManageAiKnowledgeProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiPolicyChannelsTitle)),
        body: const AiNotAvailable(),
      );
    }
    final settings = ref.watch(agentSettingsProvider);
    final row = _rowIn(settings.value);
    if (_baseline == null && row != null && row.hasChannelConfig) _fill(row);

    final dirty = _dirty;
    final Widget body;
    if (_baseline != null) {
      body = _form(context, _baseline!);
    } else if (settings.isLoading) {
      body = const LoadingState();
    } else if (settings.hasError) {
      final error = settings.error!;
      body = error is ApiException && error.isNotFound
          ? const AiNotAvailable()
          : ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(agentSettingsProvider),
            );
    } else if (row == null) {
      body = const AiNotAvailable();
    } else {
      body = EmptyState(
        key: const Key('ai-channel-config-unavailable'),
        icon: Icons.tune,
        title: l10n.aiChannelConfigUnavailable,
      );
    }

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // `pop` itself is not held back by this PopScope.
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(row?.connectionName ?? l10n.aiPolicyChannelsTitle),
        ),
        bottomNavigationBar: _baseline == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(Space.md),
                child: FilledButton(
                  key: const Key('ai-channel-save'),
                  onPressed: dirty && _numbersValid && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.saveAction),
                ),
              ),
        body: body,
      ),
    );
  }

  Widget _form(BuildContext context, AiAgentSetting row) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final provider = row.provider.toUpperCase();
    const gap = SizedBox(height: Space.md);

    Widget numberField(
      Key key,
      TextEditingController controller,
      String field,
      String label,
      String hint,
      _Range range,
    ) {
      final invalid = _inRange(controller.text, range) == null;
      return TextField(
        key: key,
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 3,
          errorMaxLines: 3,
          errorText:
              _fieldErrors[field] ??
              (invalid
                  ? l10n.aiChannelNumberInvalid(range.min, range.max)
                  : null),
        ),
      );
    }

    final handledFields = {
      'max_auto_turns',
      'auto_session_idle_hours',
      'daily_auto_send_limit',
      'extra_restricted_topics',
    };

    return ListView(
      key: const Key('ai-channel-settings'),
      padding: const EdgeInsets.all(Space.md),
      children: [
        Row(
          children: [
            Icon(
              ConversationBadges.providerIcon(provider),
              color: ConversationBadges.providerGlyphColor(context, provider),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                ConversationBadges.providerLabel(context, provider),
                style: theme.textTheme.bodySmall,
              ),
            ),
            StatusBadge(
              key: const Key('ai-channel-mode'),
              label: aiModeLabel(context, row.mode),
              tone: row.mode == AiAssistMode.auto
                  ? BadgeTone.warning
                  : BadgeTone.neutral,
            ),
          ],
        ),
        gap,
        AiSectionCard(
          title: l10n.aiPolicyChannelsTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              numberField(
                const Key('ai-channel-max-turns'),
                _maxTurns,
                'max_auto_turns',
                l10n.aiChannelMaxTurns,
                l10n.aiChannelMaxTurnsHint(
                  AiAgentSetting.maxAutoTurnsRange.min,
                  AiAgentSetting.maxAutoTurnsRange.max,
                ),
                AiAgentSetting.maxAutoTurnsRange,
              ),
              gap,
              numberField(
                const Key('ai-channel-idle-hours'),
                _idleHours,
                'auto_session_idle_hours',
                l10n.aiChannelSessionIdle,
                l10n.aiChannelSessionIdleHint(
                  AiAgentSetting.autoSessionIdleHoursRange.min,
                  AiAgentSetting.autoSessionIdleHoursRange.max,
                ),
                AiAgentSetting.autoSessionIdleHoursRange,
              ),
              gap,
              numberField(
                const Key('ai-channel-daily-cap'),
                _dailyCap,
                'daily_auto_send_limit',
                l10n.aiChannelDailyCap,
                l10n.aiChannelDailyCapHint(
                  AiAgentSetting.dailyAutoSendLimitRange.min,
                  AiAgentSetting.dailyAutoSendLimitRange.max,
                ),
                AiAgentSetting.dailyAutoSendLimitRange,
              ),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          title: l10n.aiChannelResume,
          child: _Choices(
            groupKey: 'resume',
            values: AiResumeBehaviour.values,
            current: _resume,
            enabled: !_saving,
            label: (v) => switch (v) {
              AiResumeBehaviour.ask => l10n.aiResumeAsk,
              AiResumeBehaviour.wait => l10n.aiResumeWait,
              _ => v,
            },
            onChanged: (v) => setState(() => _resume = v),
          ),
        ),
        gap,
        AiSectionCard(
          title: l10n.aiChannelGrounding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Choices(
                groupKey: 'grounding',
                values: AiGroundingProfile.values,
                current: _grounding,
                enabled: !_saving,
                label: (v) => aiGroundingLabel(context, v),
                hint: (v) => aiGroundingHint(context, v),
                badge: (v) => v == AiGroundingProfile.balanced
                    ? l10n.aiGroundingRecommended
                    : null,
                onChanged: (v) => setState(() => _grounding = v),
              ),
              if (row.groundingFloor != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('ai-channel-floor-toggle'),
                    onPressed: () => setState(() => _showFloor = !_showFloor),
                    icon: Icon(
                      _showFloor ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(l10n.aiGroundingShowFloor),
                  ),
                ),
              if (_showFloor && row.groundingFloor != null)
                Text(
                  // The floor is for the profile as saved; it moves only
                  // once a new profile is.
                  l10n.aiGroundingFloor('${row.groundingFloor}'),
                  key: const Key('ai-channel-floor'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
        gap,
        AiSectionCard(
          title: l10n.aiChannelTopics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: colors.mutedForeground,
                  ),
                  for (final topic in row.lockedRestrictedTopics)
                    StatusBadge(label: topic, dense: true, subtle: true),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                l10n.aiChannelLockedTopicsHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final topic in _topics)
                    InputChip(
                      key: Key('ai-topic-$topic'),
                      label: Text(topic, textDirection: textDirectionOf(topic)),
                      onDeleted: _saving
                          ? null
                          : () => setState(
                              () => _topics = [
                                for (final t in _topics)
                                  if (t != topic) t,
                              ],
                            ),
                      deleteButtonTooltipMessage: l10n.aiChannelRemoveTopic(
                        topic,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('ai-channel-new-topic'),
                      controller: _newTopic,
                      enabled: !_saving,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addTopic(),
                      onChanged: (_) => setState(() => _topicError = null),
                      textDirection: inputDirectionOf(_newTopic.text),
                      decoration: InputDecoration(
                        hintText: l10n.aiChannelTopicPlaceholder,
                        errorText:
                            _topicError ??
                            _fieldErrors['extra_restricted_topics'],
                        errorMaxLines: 3,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  OutlinedButton.icon(
                    key: const Key('ai-channel-add-topic'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _saving ? null : _addTopic,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.aiChannelAddTopic),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (row.handoffRules.isNotEmpty) ...[
          gap,
          AiSectionCard(
            title: l10n.aiChannelHandoffRules,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final rule in row.handoffRules)
                  _HandoffRuleRow(
                    rule: rule,
                    enabled: rule.locked
                        ? true
                        : (_handoffOnRestricted ?? rule.enabled),
                    onChanged: rule.locked || _saving
                        ? null
                        : (v) => setState(() => _handoffOnRestricted = v),
                  ),
              ],
            ),
          ),
        ],
        if (_error != null &&
            !_fieldErrors.keys.any(handledFields.contains)) ...[
          gap,
          InlineError(message: _error!),
        ],
        const SizedBox(height: Space.xl),
      ],
    );
  }
}

/// A radio list: each choice with its label, an optional line under it, and
/// an optional badge ("Recommended").
class _Choices extends StatelessWidget {
  const _Choices({
    required this.groupKey,
    required this.values,
    required this.current,
    required this.enabled,
    required this.label,
    required this.onChanged,
    this.hint,
    this.badge,
  });

  final String groupKey;
  final List<String> values;
  final String current;
  final bool enabled;
  final String Function(String) label;
  final String Function(String)? hint;
  final String? Function(String)? badge;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // A value this app does not know is still shown as the server has it.
    final options = [
      ...values,
      if (current.isNotEmpty && !values.contains(current)) current,
    ];
    return RadioGroup<String>(
      groupValue: current,
      onChanged: (v) {
        if (enabled && v != null) onChanged(v);
      },
      child: Column(
        children: [
          for (final value in options)
            RadioListTile<String>(
              key: Key('ai-$groupKey-$value'),
              value: value,
              enabled: enabled,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Wrap(
                spacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(label(value)),
                  if (badge?.call(value) case final text?)
                    StatusBadge(label: text, dense: true, tone: BadgeTone.info),
                ],
              ),
              subtitle: switch (hint?.call(value)) {
                final text? when text.isNotEmpty => Text(text),
                _ => null,
              },
            ),
        ],
      ),
    );
  }
}

class _HandoffRuleRow extends StatelessWidget {
  const _HandoffRuleRow({
    required this.rule,
    required this.enabled,
    required this.onChanged,
  });

  final AiHandoffRule rule;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      key: Key('ai-handoff-${rule.reason}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              rule.locked ? Icons.lock_outline : Icons.shield_outlined,
              size: 16,
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      aiHandoffReasonLabel(context, rule.reason),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rule.locked)
                      StatusBadge(label: l10n.aiHandoffAlwaysOn, dense: true),
                  ],
                ),
                if (rule.why.isNotEmpty)
                  Text(
                    rule.why,
                    textDirection: textDirectionOf(rule.why),
                    textAlign: ambientStartAlign(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          if (!rule.locked)
            Switch(
              key: Key('ai-handoff-${rule.reason}-switch'),
              value: enabled,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
