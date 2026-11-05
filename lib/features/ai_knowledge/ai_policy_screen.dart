/// AI policy — the organization's AI switches, daily budgets and rollout
/// state (`GET/PUT /ai/policy/`), and the way into each channel's own
/// limits (`ai_channel_settings_screen.dart`).
///
/// Edits are held in the form until Save, which sends only what changed
/// (every field of the PUT is optional, and each change is audited on its
/// own). Leaving with unsaved changes asks first.
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
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_activity_screen.dart' show AiNotAvailable;
import 'ai_knowledge_labels.dart';
import 'ai_knowledge_providers.dart';
import 'ai_knowledge_settings_tab.dart' show canManageAiKnowledgeProvider;
import 'ai_metric_widgets.dart';
import 'knowledge_forms.dart';

class AiPolicyScreen extends ConsumerStatefulWidget {
  const AiPolicyScreen({super.key});

  @override
  ConsumerState<AiPolicyScreen> createState() => _AiPolicyScreenState();
}

class _AiPolicyScreenState extends ConsumerState<AiPolicyScreen> {
  /// The policy the form was filled from — what "unchanged" means.
  AiOrganizationPolicy? _baseline;

  bool _aiEnabled = false;
  bool _autoSend = false;
  String _rollout = AiRolloutState.pilot;
  final _requestLimit = TextEditingController();
  final _tokenLimit = TextEditingController();

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _requestLimit.dispose();
    _tokenLimit.dispose();
    super.dispose();
  }

  void _fill(AiOrganizationPolicy policy) {
    _baseline = policy;
    _aiEnabled = policy.isAiEnabled;
    _autoSend = policy.isAutoSendEnabled;
    _rollout = policy.rolloutState;
    _requestLimit.text = '${policy.dailyRequestLimit}';
    _tokenLimit.text = '${policy.dailyTokenLimit}';
    _fieldErrors = const {};
    _error = null;
  }

  static int? _limit(String text, int max) {
    final value = int.tryParse(text.trim());
    return value == null || value < 0 || value > max ? null : value;
  }

  /// The form as a policy, or null while a limit is not a valid number.
  AiOrganizationPolicy? get _edited {
    final requests = _limit(
      _requestLimit.text,
      AiOrganizationPolicy.maxDailyRequestLimit,
    );
    final tokens = _limit(
      _tokenLimit.text,
      AiOrganizationPolicy.maxDailyTokenLimit,
    );
    if (requests == null || tokens == null) return null;
    return AiOrganizationPolicy(
      isAiEnabled: _aiEnabled,
      isAutoSendEnabled: _autoSend,
      dailyRequestLimit: requests,
      dailyTokenLimit: tokens,
      rolloutState: _rollout,
    );
  }

  bool get _dirty {
    final baseline = _baseline;
    if (baseline == null) return false;
    final edited = _edited;
    // An invalid number is still an edit nobody saved.
    return edited == null || baseline.changesTo(edited).isNotEmpty;
  }

  Future<void> _save() async {
    final baseline = _baseline;
    final edited = _edited;
    if (_saving || baseline == null || edited == null) return;
    final changes = baseline.changesTo(edited);
    if (changes.isEmpty) return;
    final l10n = context.l10n;
    setState(() {
      _saving = true;
      _fieldErrors = const {};
      _error = null;
    });
    try {
      await ref.read(aiPolicyProvider.notifier).save(changes);
      if (!mounted) return;
      final saved = ref.read(aiPolicyProvider).value;
      setState(() {
        if (saved != null) _fill(saved);
        _saving = false;
      });
      showKnowledgeSnack(context, l10n.aiPolicySaved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = error.fieldErrors();
        _error = aiErrorMessage(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!ref.watch(canManageAiKnowledgeProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiPolicyTitle)),
        body: const AiNotAvailable(),
      );
    }

    final policy = ref.watch(aiPolicyProvider);
    // The form fills once, from the first policy the server sends; after
    // that only a save or a refresh with nothing unsaved replaces it.
    if (_baseline == null && policy.value != null) _fill(policy.value!);

    if (policy.error case final ApiException error
        when error.isNotFound && !policy.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiPolicyTitle)),
        body: const AiNotAvailable(),
      );
    }

    final dirty = _dirty;
    final canSave = dirty && _edited != null && !_saving;

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
        appBar: AppBar(title: Text(l10n.aiPolicyTitle)),
        bottomNavigationBar: _baseline == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(Space.md),
                child: FilledButton(
                  key: const Key('ai-policy-save'),
                  onPressed: canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.saveAction),
                ),
              ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(agentSettingsProvider);
            if (dirty) return;
            ref.invalidate(aiPolicyProvider);
            final fresh = await ref
                .read(aiPolicyProvider.future)
                .then<AiOrganizationPolicy?>((p) => p, onError: (_) => null);
            if (fresh != null && mounted) setState(() => _fill(fresh));
          },
          child: ListView(
            key: const Key('ai-policy'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.md),
            children: [
              if (_baseline == null)
                policy.when(
                  loading: () =>
                      const SizedBox(height: 240, child: LoadingState()),
                  error: (error, _) => ErrorStateView(
                    error: error,
                    onRetry: () => ref.invalidate(aiPolicyProvider),
                  ),
                  data: (_) => const SizedBox.shrink(),
                )
              else
                _organizationForm(context),
              const SizedBox(height: Space.lg),
              const _ChannelLimitsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _organizationForm(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rollouts = [
      ...AiRolloutState.values,
      // A state this app does not know is still shown as the server has it.
      if (!AiRolloutState.values.contains(_rollout)) _rollout,
    ];

    String? limitError(String field, TextEditingController c, int max) {
      if (_fieldErrors[field] case final server?) return server;
      return _limit(c.text, max) == null
          ? l10n.aiPolicyLimitInvalid(max)
          : null;
    }

    return AiSectionCard(
      key: const Key('ai-policy-organization'),
      title: l10n.aiPolicyOrganizationTitle,
      icon: Icons.policy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('ai-policy-ai-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.aiPolicyAiEnabled),
            subtitle: Text(l10n.aiPolicyAiEnabledHint),
            value: _aiEnabled,
            onChanged: _saving ? null : (v) => setState(() => _aiEnabled = v),
          ),
          SwitchListTile(
            key: const Key('ai-policy-auto-send'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.aiPolicyAutoSendEnabled),
            subtitle: Text(l10n.aiPolicyAutoSendEnabledHint),
            value: _autoSend,
            onChanged: _saving ? null : (v) => setState(() => _autoSend = v),
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: const Key('ai-policy-request-limit'),
            controller: _requestLimit,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.aiPolicyDailyRequestLimit,
              helperText: l10n.aiPolicyLimitHint(
                AiOrganizationPolicy.maxDailyRequestLimit,
              ),
              helperMaxLines: 2,
              errorText: limitError(
                'daily_request_limit',
                _requestLimit,
                AiOrganizationPolicy.maxDailyRequestLimit,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: const Key('ai-policy-token-limit'),
            controller: _tokenLimit,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.aiPolicyDailyTokenLimit,
              helperText: l10n.aiPolicyLimitHint(
                AiOrganizationPolicy.maxDailyTokenLimit,
              ),
              helperMaxLines: 2,
              errorText: limitError(
                'daily_token_limit',
                _tokenLimit,
                AiOrganizationPolicy.maxDailyTokenLimit,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          DropdownButtonFormField<String>(
            key: const Key('ai-policy-rollout'),
            initialValue: _rollout,
            decoration: InputDecoration(
              labelText: l10n.aiPolicyRollout,
              helperText: l10n.aiPolicyRolloutHint,
              helperMaxLines: 3,
              errorText: _fieldErrors['rollout_state'],
            ),
            items: [
              for (final state in rollouts)
                DropdownMenuItem(
                  value: state,
                  child: Text(aiRolloutLabel(context, state)),
                ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _rollout = v ?? _rollout),
          ),
          if (_error != null &&
              !_fieldErrors.keys.any(
                {
                  'daily_request_limit',
                  'daily_token_limit',
                  'rollout_state',
                }.contains,
              )) ...[
            const SizedBox(height: Space.md),
            InlineError(message: _error!),
          ],
          if (_dirty) ...[
            const SizedBox(height: Space.sm),
            Text(
              l10n.aiUnsavedBody,
              key: const Key('ai-policy-unsaved'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every channel that can use AI, each opening its own limits.
class _ChannelLimitsSection extends ConsumerWidget {
  const _ChannelLimitsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(agentSettingsProvider);
    return AiSectionCard(
      key: const Key('ai-policy-channels'),
      title: l10n.aiPolicyChannelsTitle,
      subtitle: l10n.aiPolicyChannelsHint,
      icon: Icons.tune,
      child: settings.when(
        loading: () => const SizedBox(height: 120, child: LoadingState()),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(agentSettingsProvider),
        ),
        data: (rows) {
          final supported = [
            for (final row in rows)
              if (row.assistSupported) row,
          ];
          if (supported.isEmpty) {
            return Text(
              l10n.aiPolicyChannelsNone,
              style: Theme.of(context).textTheme.bodySmall,
            );
          }
          return Column(
            children: [for (final row in supported) _ChannelTile(row: row)],
          );
        },
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.row});

  final AiAgentSetting row;

  @override
  Widget build(BuildContext context) {
    final provider = row.provider.toUpperCase();
    return ListTile(
      key: Key('ai-policy-channel-${row.connectionId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ConversationBadges.providerIcon(provider),
        color: ConversationBadges.providerGlyphColor(context, provider),
      ),
      title: Text(
        row.connectionName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(ConversationBadges.providerLabel(context, provider)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            label: aiModeLabel(context, row.mode),
            tone: row.mode == AiAssistMode.auto
                ? BadgeTone.warning
                : BadgeTone.neutral,
            dense: true,
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => context.push(Routes.aiChannelSettings(row.connectionId)),
    );
  }
}
