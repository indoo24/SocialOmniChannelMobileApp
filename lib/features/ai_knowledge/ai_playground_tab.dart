/// AI Playground — the AI section's fourth tab: pick a knowledge base and ask
/// it what a customer might. The asking and the answer are
/// `playground_section.dart`.
///
/// The base chosen here is the same selection the Knowledge Base tab shows, so
/// a base being worked on there is the one being tested here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'ai_knowledge_providers.dart';
import 'ai_metric_widgets.dart';
import 'playground_section.dart';

class AiPlaygroundTab extends ConsumerWidget {
  const AiPlaygroundTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final bases = ref.watch(knowledgeBasesProvider);
    final selected = ref.watch(selectedKnowledgeBaseProvider);

    return ListView(
      key: const Key('ai-playground'),
      primary: false,
      padding: const EdgeInsets.all(Space.md),
      children: [
        AiTabHint(l10n.aiPlaygroundTabHint),
        bases.when(
          loading: () => const SizedBox(height: 160, child: LoadingState()),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(knowledgeBasesProvider),
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected != null) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('ai-playground-base-${selected.id}'),
                  initialValue: selected.id,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.aiPlaygroundBase),
                  items: [
                    for (final base in list)
                      DropdownMenuItem(
                        value: base.id,
                        child: Text(base.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      ref
                          .read(selectedKnowledgeBaseIdProvider.notifier)
                          .select(id);
                    }
                  },
                ),
                const SizedBox(height: Space.md),
              ],
              Container(
                key: const Key('ai-section-playground'),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(color: colors.border),
                ),
                child: PlaygroundSection(knowledgeBase: selected),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
