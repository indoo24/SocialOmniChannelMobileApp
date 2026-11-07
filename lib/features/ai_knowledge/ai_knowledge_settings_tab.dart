/// AI & Knowledge — the AI section of Settings, the same five tabs as the web:
/// Overview, Knowledge Base, AI Agent & Automatic Replies, AI Playground, and
/// Activity & Usage.
///
/// Shown only to holders of `ai_knowledge.manage` whose organization is in
/// the AI pilot (`ai_knowledge_enabled`) — the web's rule. That is
/// presentation: every request is re-checked server-side, and a 403/404 that
/// comes back anyway is shown for what it is.
///
/// Its tab bar moves between tabs by tapping only. This whole section is
/// itself a page of Settings' swipeable tabs, and a second swipe target inside
/// it would make the outer one unreachable from here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_activity_tab.dart';
import 'ai_agent_tab.dart';
import 'ai_knowledge_base_tab.dart';
import 'ai_knowledge_providers.dart';
import 'ai_metric_widgets.dart';
import 'ai_overview_tab.dart';
import 'ai_playground_tab.dart';

class AiKnowledgeSettingsTab extends ConsumerStatefulWidget {
  const AiKnowledgeSettingsTab({super.key});

  @override
  ConsumerState<AiKnowledgeSettingsTab> createState() =>
      _AiKnowledgeSettingsTabState();
}

class _AiKnowledgeSettingsTabState extends ConsumerState<AiKnowledgeSettingsTab>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabs;

  /// Tabs built so far. A tab is built the first time it opens and then kept,
  /// so what was typed on it (a question, a holding message) survives moving
  /// to another tab, and what it loaded is not asked for again.
  final _visited = <AiSection>{AiSection.overview};

  /// Swiping to another Settings tab should not lose any of that either.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Created here rather than lazily: a role without access never builds
    // the tab bar, and a controller first touched in dispose() would be
    // made from a deactivated element.
    _tabs = TabController(length: AiSection.values.length, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    ref.read(aiSectionProvider.notifier).select(AiSection.values[_tabs.index]);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  Widget _build(AiSection section) => switch (section) {
    AiSection.overview => const AiOverviewTab(),
    AiSection.knowledge => const AiKnowledgeBaseTab(),
    AiSection.agent => const AiAgentTab(),
    AiSection.playground => const AiPlaygroundTab(),
    AiSection.activity => const AiActivityTab(),
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!ref.watch(canManageAiKnowledgeProvider)) {
      return const AiNotAvailable();
    }

    // Outside the pilot every endpoint here is a 404; say so once instead of
    // showing five tabs of errors.
    final bases = ref.watch(knowledgeBasesProvider);
    if (bases.error case final ApiException error
        when error.isNotFound && !bases.isLoading) {
      return const AiNotAvailable();
    }

    final l10n = context.l10n;
    final current = ref.watch(aiSectionProvider);
    _visited.add(current);
    ref.listen(aiSectionProvider, (_, next) {
      if (_tabs.index != next.index) _tabs.animateTo(next.index);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          key: const Key('ai-section-tabs'),
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(key: const Key('ai-tab-overview'), text: l10n.aiTabOverview),
            Tab(key: const Key('ai-tab-knowledge'), text: l10n.aiTabKnowledge),
            Tab(key: const Key('ai-tab-agent'), text: l10n.aiTabAgent),
            Tab(
              key: const Key('ai-tab-playground'),
              text: l10n.aiTabPlayground,
            ),
            Tab(key: const Key('ai-tab-activity'), text: l10n.aiTabActivity),
          ],
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final section in AiSection.values)
                if (_visited.contains(section))
                  Offstage(
                    offstage: section != current,
                    child: TickerMode(
                      enabled: section == current,
                      child: _build(section),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
