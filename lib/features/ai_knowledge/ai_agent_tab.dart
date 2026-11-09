/// AI Agent & Automatic Replies — the AI section's third tab: what automatic
/// replies do by default, and for every channel its mode (Off / Suggest /
/// Automatic), what it replies with, its readiness, and its limits.
///
/// Like the web, each choice is saved the moment it is made — one field per
/// `PUT`, which the backend records as one audit row each — and the screen
/// shows what the server answered. Only the typed values (the daily cap, a
/// new topic, the holding-message instructions) wait for their Save.
///
/// Fields: `default_auto_reply_policy` and `fallback_instructions` on
/// `PUT /ai/policy/`; `mode`, `auto_reply_policy`, `daily_auto_send_limit`,
/// `grounding_profile`, `resume_behaviour`, `extra_restricted_topics` and
/// `handoff_on_restricted_topic` on `PUT /ai/agent-settings/`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/knowledge.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_direction.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_base_tab.dart' show AiConflictsCard;
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_metric_widgets.dart';
import 'knowledge_forms.dart';

class AiAgentTab extends ConsumerWidget {
  const AiAgentTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(agentSettingsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(agentSettingsProvider);
        ref.invalidate(aiPolicyProvider);
        ref.invalidate(knowledgeConflictsProvider);
        await ref
            .read(agentSettingsProvider.future)
            .then<Object?>((v) => v, onError: (_) => null);
      },
      child: ListView(
        key: const Key('ai-agent'),
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        children: [
          AiTabHint(l10n.aiAgentTabHint),
          AiHeadedSection(
            icon: Icons.auto_awesome,
            title: l10n.aiAssistTitle,
            child: Text(
              l10n.aiAssistHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          const _DefaultPolicyCard(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('ai-agent-organization-settings'),
              onPressed: () => context.push(Routes.aiPolicy),
              icon: const Icon(Icons.policy_outlined, size: 18),
              label: Text(l10n.aiOrganizationSettings),
            ),
          ),
          const SizedBox(height: Space.sm),
          AiConflictsCard(
            onOpenKnowledge: () => ref
                .read(aiSectionProvider.notifier)
                .select(AiSection.knowledge),
          ),
          settings.when(
            loading: () => const SizedBox(height: 120, child: LoadingState()),
            error: (error, _) => ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(agentSettingsProvider),
            ),
            data: (rows) => rows.isEmpty
                ? Text(
                    l10n.aiAssistNoConnections,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final row in rows) ...[
                        _ChannelCard(key: ValueKey(row.connectionId), row: row),
                        const SizedBox(height: Space.sm),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// The organization default
// --------------------------------------------------------------------------- //

/// Automatic AI replies: the default every channel follows unless it says
/// otherwise, and — for "Always reply" — the tone of the holding message.
class _DefaultPolicyCard extends ConsumerStatefulWidget {
  const _DefaultPolicyCard();

  @override
  ConsumerState<_DefaultPolicyCard> createState() => _DefaultPolicyCardState();
}

class _DefaultPolicyCardState extends ConsumerState<_DefaultPolicyCard> {
  final _instructions = TextEditingController();

  /// The saved instructions the field was last filled from.
  String? _filledFrom;
  bool _saving = false;

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, Object> changes) async {
    if (_saving) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref.read(aiPolicyProvider.notifier).save(changes);
      if (mounted) showKnowledgeSnack(context, l10n.aiPolicySaved);
    } on ApiException catch (error) {
      if (mounted) {
        final field = error.fieldError('fallback_instructions');
        showKnowledgeSnack(
          context,
          field ?? aiErrorMessage(context, error),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final policy = ref.watch(aiPolicyProvider);
    final p = policy.value;
    if (p == null) {
      return policy.hasError
          ? ErrorStateView(
              error: policy.error!,
              onRetry: () => ref.invalidate(aiPolicyProvider),
            )
          : const SizedBox(height: 80, child: LoadingState());
    }
    // A server that does not send the default has nothing to show here.
    if (p.defaultAutoReplyPolicy.isEmpty) return const SizedBox.shrink();

    // Follow the saved text until someone starts editing it.
    if (_filledFrom != p.fallbackInstructions &&
        (_filledFrom == null || _instructions.text == _filledFrom)) {
      _instructions.text = p.fallbackInstructions;
      _filledFrom = p.fallbackInstructions;
    }
    final edited = _instructions.text != p.fallbackInstructions;

    return AiSectionCard(
      key: const Key('ai-default-policy'),
      title: l10n.aiAutoRepliesHeading,
      subtitle: l10n.aiAutoRepliesDefaultHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiChoiceCards(
            groupKey: 'default-policy',
            values: AiAutoReplyPolicy.organizationValues,
            current: p.defaultAutoReplyPolicy,
            enabled: !_saving,
            label: (v) => aiReplyPolicyLabel(context, v),
            hint: (v) => aiReplyPolicyHint(context, v),
            badge: (v) => v == AiAutoReplyPolicy.knowledgeOnly
                ? l10n.aiGroundingRecommended
                : null,
            onChanged: (v) => _save({'default_auto_reply_policy': v}),
          ),
          if (p.defaultAutoReplyPolicy == AiAutoReplyPolicy.alwaysReply) ...[
            const Divider(height: Space.xl),
            TextField(
              key: const Key('ai-fallback-instructions'),
              controller: _instructions,
              enabled: !_saving,
              minLines: 2,
              maxLines: 5,
              maxLength: AiOrganizationPolicy.maxFallbackInstructionsLength,
              textDirection: inputDirectionOf(_instructions.text),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.aiFallbackInstructionsLabel,
                hintText: l10n.aiFallbackInstructionsPlaceholder,
                helperText: l10n.aiFallbackInstructionsHint,
                helperMaxLines: 4,
                alignLabelWithHint: true,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('ai-fallback-instructions-save'),
                onPressed: edited && !_saving
                    ? () => _save({
                        'fallback_instructions': _instructions.text.trim(),
                      })
                    : null,
                child: Text(l10n.saveAction),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.support_agent,
                  size: 14,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    l10n.aiFallbackHandsOffHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// One channel
// --------------------------------------------------------------------------- //

class _ChannelCard extends ConsumerStatefulWidget {
  const _ChannelCard({required this.row, super.key});

  final AiAgentSetting row;

  @override
  ConsumerState<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<_ChannelCard> {
  bool _saving = false;
  bool _limitsOpen = false;

  /// Saves [changes] to this channel; true when the server accepted them.
  Future<bool> _update(Map<String, Object> changes, String done) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .updateSettings(widget.row.connectionId, changes);
      if (mounted) showKnowledgeSnack(context, done);
      return true;
    } on ApiException catch (error) {
      if (mounted) {
        showKnowledgeSnack(
          context,
          aiErrorMessage(context, error),
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseMode(String mode) async {
    if (_saving || mode == widget.row.mode) return;
    // Automatic replies reach customers with no human in between: confirm,
    // with what readiness says is worth knowing, before asking the server.
    if (mode == AiAssistMode.auto && !await _confirmAuto()) return;
    if (!mounted) return;
    await _update({'mode': mode}, context.l10n.aiModeSaved);
  }

  Future<bool> _confirmAuto() async {
    final warnings = widget.row.readiness?.warnings ?? const <String>[];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          title: Text(l10n.aiModeAuto),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aiModeAutoWarning),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text(
                  '${l10n.aiWorthKnowing}: '
                  '${warnings.map((c) => aiReadinessReason(dialogContext, c)).join(' · ')}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('ai-confirm-auto'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.aiModeAuto),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final row = widget.row;
    final provider = row.provider.toUpperCase();
    final status = aiConnectionStatus(context, row.status);
    final readiness = row.readiness;
    final repliesSupported = row.assistSupported && row.autoSupported;
    final showLimits =
        repliesSupported &&
        row.mode != AiAssistMode.off &&
        row.hasChannelConfig;

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );

    return Card(
      key: Key('assist-${row.connectionId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  ConversationBadges.providerIcon(provider),
                  size: 18,
                  color: ConversationBadges.providerGlyphColor(
                    context,
                    provider,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.connectionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionOf(row.connectionName),
                        textAlign: ambientStartAlign(context),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        ConversationBadges.providerLabel(context, provider),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (status case (final label, final tone))
                  StatusBadge(
                    key: Key('assist-${row.connectionId}-status'),
                    label: label,
                    tone: tone,
                    dense: true,
                  ),
                if (row.assistSupported && readiness != null)
                  switch (aiReadinessState(context, readiness.state)) {
                    (final label, final tone) => StatusBadge(
                      key: Key('assist-${row.connectionId}-readiness'),
                      label: label,
                      tone: tone,
                      dense: true,
                      subtle: tone == BadgeTone.neutral,
                    ),
                  },
              ],
            ),
            const SizedBox(height: Space.sm),
            if (!row.assistSupported)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(
                  key: Key('assist-${row.connectionId}-unsupported'),
                  label: l10n.aiAssistUnsupported,
                ),
              )
            else
              Semantics(
                label: l10n.aiAssistModeLabel(row.connectionName),
                child: SegmentedButton<String>(
                  key: Key('assist-${row.connectionId}-modes'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  segments: [
                    for (final mode in row.offeredModes)
                      ButtonSegment<String>(
                        value: mode,
                        label: Text(
                          aiModeLabel(context, mode),
                          key: Key('assist-${row.connectionId}-$mode'),
                        ),
                      ),
                  ],
                  selected: {row.mode},
                  onSelectionChanged: _saving
                      ? null
                      : (selection) => _chooseMode(selection.first),
                ),
              ),
            if (repliesSupported && row.autoReplyPolicy.isNotEmpty) ...[
              const Divider(height: Space.lg),
              sectionLabel(l10n.aiCardReplies),
              _ReplyPolicy(
                row: row,
                enabled: !_saving,
                onChanged: (v) =>
                    _update({'auto_reply_policy': v}, l10n.aiChannelSaved),
              ),
            ],
            if (row.assistSupported && readiness != null)
              _ReadinessDetails(readiness: readiness),
            if (showLimits) ...[
              const Divider(height: Space.lg),
              InkWell(
                key: Key('assist-${row.connectionId}-limits-toggle'),
                onTap: () => setState(() => _limitsOpen = !_limitsOpen),
                child: Row(
                  children: [
                    Icon(
                      _limitsOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: colors.mutedForeground,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(child: sectionLabel(l10n.aiCardAdvanced)),
                  ],
                ),
              ),
              if (_limitsOpen) ...[
                Text(
                  l10n.aiCardAdvancedHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: Space.md),
                _ChannelLimits(row: row, saving: _saving, update: _update),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// What this channel replies with: the organization default, or its own.
/// Only an automatic channel replies at all, so for the others it is shown
/// but cannot be changed.
class _ReplyPolicy extends StatelessWidget {
  const _ReplyPolicy({
    required this.row,
    required this.enabled,
    required this.onChanged,
  });

  final AiAgentSetting row;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final active = row.mode == AiAssistMode.auto;
    final effective = aiReplyPolicyLabel(context, row.effectiveAutoReplyPolicy);
    final values = [
      ...AiAutoReplyPolicy.channelValues,
      if (!AiAutoReplyPolicy.channelValues.contains(row.autoReplyPolicy))
        row.autoReplyPolicy,
    ];
    final String hint;
    if (!active) {
      hint = l10n.aiReplyPolicyInactive(aiModeLabel(context, row.mode));
    } else if (row.autoReplyPolicy == AiAutoReplyPolicy.inherit) {
      hint = l10n.aiReplyPolicyInheritedValue(effective);
    } else {
      hint = l10n.aiReplyPolicyOverridden;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.aiConnectionPolicyLabel,
              style: theme.textTheme.bodySmall,
            ),
            if (row.effectiveAutoReplyPolicy.isNotEmpty)
              StatusBadge(
                key: Key('assist-${row.connectionId}-effective'),
                label: l10n.aiCardEffective(effective),
                dense: true,
                subtle: true,
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        DropdownButtonFormField<String>(
          key: Key('assist-${row.connectionId}-reply-policy'),
          initialValue: row.autoReplyPolicy,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            for (final value in values)
              DropdownMenuItem(
                value: value,
                child: Text(aiReplyPolicyLabel(context, value)),
              ),
          ],
          onChanged: active && enabled
              ? (v) {
                  if (v != null && v != row.autoReplyPolicy) onChanged(v);
                }
              : null,
        ),
        const SizedBox(height: Space.xs),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// Why a mode is unavailable, in words: hard blocks, AUTO-only blocks, then
/// what is merely worth knowing — the web's three tiers.
class _ReadinessDetails extends StatelessWidget {
  const _ReadinessDetails({required this.readiness});

  final AiReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final autoBlocking = readiness.autoBlocking;
    final warnings = readiness.warnings
        .where((code) => !autoBlocking.contains(code))
        .toList();
    final ready = readiness.sourcesReady;
    final chunks = readiness.embeddedChunks;
    if (readiness.blocking.isEmpty &&
        autoBlocking.isEmpty &&
        warnings.isEmpty &&
        chunks == null) {
      return const SizedBox.shrink();
    }

    Widget line(
      String heading,
      List<String> codes,
      Color color,
      IconData icon,
    ) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                '$heading: ${codes.map((c) => aiReadinessReason(context, c)).join(' · ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        key: const Key('assist-readiness'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: Space.md),
          if (readiness.blocking.isNotEmpty)
            line(
              l10n.aiBlockedBy,
              readiness.blocking,
              colors.danger,
              Icons.block,
            ),
          if (autoBlocking.isNotEmpty)
            line(
              l10n.aiAutoBlockedBy,
              autoBlocking,
              colors.warning,
              Icons.warning_amber_rounded,
            ),
          if (warnings.isNotEmpty)
            line(
              l10n.aiWorthKnowing,
              warnings,
              colors.mutedForeground,
              Icons.info_outline,
            ),
          if (chunks != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                l10n.aiWhatIsIndexed(ready ?? 0, chunks),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Limits & safety
// --------------------------------------------------------------------------- //

typedef _Update =
    Future<bool> Function(Map<String, Object> changes, String done);

/// One channel's limits and safety rules, each saved as it is changed.
class _ChannelLimits extends StatefulWidget {
  const _ChannelLimits({
    required this.row,
    required this.saving,
    required this.update,
  });

  final AiAgentSetting row;
  final bool saving;
  final _Update update;

  @override
  State<_ChannelLimits> createState() => _ChannelLimitsState();
}

class _ChannelLimitsState extends State<_ChannelLimits> {
  late final _dailyCap = TextEditingController(
    text: '${widget.row.dailyAutoSendLimit}',
  );
  final _newTopic = TextEditingController();
  bool _showFloor = false;
  String? _topicError;

  @override
  void didUpdateWidget(covariant _ChannelLimits oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the saved cap unless someone is part-way through changing it.
    final saved = widget.row.dailyAutoSendLimit;
    if (saved != oldWidget.row.dailyAutoSendLimit &&
        _dailyCap.text == '${oldWidget.row.dailyAutoSendLimit}') {
      _dailyCap.text = '$saved';
    }
  }

  @override
  void dispose() {
    _dailyCap.dispose();
    _newTopic.dispose();
    super.dispose();
  }

  int? get _validCap {
    final range = AiAgentSetting.dailyAutoSendLimitRange;
    final value = int.tryParse(_dailyCap.text.trim());
    return value == null || value < range.min || value > range.max
        ? null
        : value;
  }

  Future<void> _addTopic() async {
    final l10n = context.l10n;
    final row = widget.row;
    final topic = _newTopic.text.trim();
    if (topic.isEmpty) return;
    String? error;
    if (topic.runes.length > AiAgentSetting.maxRestrictedTopicLength) {
      error = l10n.aiChannelTopicTooLong(
        AiAgentSetting.maxRestrictedTopicLength,
      );
    } else if ([
      ...row.extraRestrictedTopics,
      ...row.lockedRestrictedTopics,
    ].any((t) => t.toLowerCase() == topic.toLowerCase())) {
      error = l10n.aiChannelTopicDuplicate;
    } else if (row.extraRestrictedTopics.length >=
        AiAgentSetting.maxRestrictedTopics) {
      error = l10n.aiChannelTooManyTopics(AiAgentSetting.maxRestrictedTopics);
    }
    setState(() => _topicError = error);
    if (error != null) return;
    final saved = await widget.update({
      'extra_restricted_topics': [...row.extraRestrictedTopics, topic],
    }, l10n.aiChannelSaved);
    if (saved && mounted) _newTopic.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final row = widget.row;
    final enabled = !widget.saving;
    final range = AiAgentSetting.dailyAutoSendLimitRange;
    final cap = _validCap;
    const gap = SizedBox(height: Space.md);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Column(
      key: Key('assist-${row.connectionId}-limits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('ai-channel-daily-cap'),
                controller: _dailyCap,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.aiChannelDailyCap,
                  helperText: l10n.aiChannelDailyCapHint(range.min, range.max),
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                  errorText: cap == null
                      ? l10n.aiChannelNumberInvalid(range.min, range.max)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: TextButton(
                key: const Key('ai-channel-daily-cap-save'),
                onPressed:
                    enabled && cap != null && cap != row.dailyAutoSendLimit
                    ? () => widget.update({
                        'daily_auto_send_limit': cap,
                      }, l10n.aiChannelSaved)
                    : null,
                child: Text(l10n.saveAction),
              ),
            ),
          ],
        ),
        if (row.resumeBehaviour.isNotEmpty) ...[
          gap,
          label(l10n.aiChannelResume),
          AiChoiceCards(
            groupKey: 'resume',
            values: AiResumeBehaviour.values,
            current: row.resumeBehaviour,
            enabled: enabled,
            label: (v) => switch (v) {
              AiResumeBehaviour.ask => l10n.aiResumeAsk,
              AiResumeBehaviour.wait => l10n.aiResumeWait,
              _ => v,
            },
            onChanged: (v) =>
                widget.update({'resume_behaviour': v}, l10n.aiChannelSaved),
          ),
        ],
        if (row.groundingProfile.isNotEmpty) ...[
          gap,
          label(l10n.aiChannelGrounding),
          AiChoiceCards(
            groupKey: 'grounding',
            values: AiGroundingProfile.values,
            current: row.groundingProfile,
            enabled: enabled,
            label: (v) => aiGroundingLabel(context, v),
            hint: (v) => aiGroundingHint(context, v),
            badge: (v) => v == AiGroundingProfile.balanced
                ? l10n.aiGroundingRecommended
                : null,
            onChanged: (v) =>
                widget.update({'grounding_profile': v}, l10n.aiChannelSaved),
          ),
          if (row.groundingFloor != null) ...[
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
            if (_showFloor)
              Text(
                '${l10n.aiGroundingFloor('${row.groundingFloor}')} '
                '${l10n.aiGroundingNever}',
                key: const Key('ai-channel-floor'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
          ],
        ],
        gap,
        label(l10n.aiChannelTopics),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 14, color: colors.mutedForeground),
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
            for (final topic in row.extraRestrictedTopics)
              InputChip(
                key: Key('ai-topic-$topic'),
                label: Text(topic, textDirection: textDirectionOf(topic)),
                onDeleted: enabled
                    ? () => widget.update({
                        'extra_restricted_topics': [
                          for (final t in row.extraRestrictedTopics)
                            if (t != topic) t,
                        ],
                      }, l10n.aiChannelSaved)
                    : null,
                deleteButtonTooltipMessage: l10n.aiChannelRemoveTopic(topic),
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
                enabled: enabled,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTopic(),
                onChanged: (_) => setState(() => _topicError = null),
                textDirection: inputDirectionOf(_newTopic.text),
                decoration: InputDecoration(
                  hintText: l10n.aiChannelTopicPlaceholder,
                  errorText: _topicError,
                  errorMaxLines: 3,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            OutlinedButton.icon(
              key: const Key('ai-channel-add-topic'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: enabled ? _addTopic : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.aiChannelAddTopic),
            ),
          ],
        ),
        if (row.handoffRules.isNotEmpty) ...[
          gap,
          label(l10n.aiChannelHandoffRules),
          for (final rule in row.handoffRules)
            _HandoffRuleRow(
              rule: rule,
              onToggle: rule.locked || !enabled
                  ? null
                  : () => widget.update({
                      'handoff_on_restricted_topic': !rule.enabled,
                    }, l10n.aiChannelSaved),
            ),
        ],
      ],
    );
  }
}

class _HandoffRuleRow extends StatelessWidget {
  const _HandoffRuleRow({required this.rule, required this.onToggle});

  final AiHandoffRule rule;
  final VoidCallback? onToggle;

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
            TextButton(
              key: Key('ai-handoff-${rule.reason}-toggle'),
              onPressed: onToggle,
              child: Text(
                rule.enabled ? l10n.aiHandoffTurnOff : l10n.aiHandoffTurnOn,
              ),
            ),
        ],
      ),
    );
  }
}
