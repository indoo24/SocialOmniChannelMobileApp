/// Lead score, funnel stage, purchase status, sentiment, urgency and the
/// analyzer's summary — the panel the web app shows beside every
/// conversation, reached here the same way orders and customer details are:
/// a bottom sheet opened from the conversation AppBar, because a phone has
/// one column (see `customer_record_sheet.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/intelligence.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'customer_intelligence_section.dart';
import 'intelligence_providers.dart';

/// Opens the intelligence panel for a conversation.
Future<void> showIntelligencePanel(
  BuildContext context, {
  required int conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _IntelligencePanel(
        conversationId: conversationId,
        scrollController: controller,
      ),
    ),
  );
}

class _IntelligencePanel extends ConsumerStatefulWidget {
  const _IntelligencePanel({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_IntelligencePanel> createState() => _IntelligencePanelState();
}

class _IntelligencePanelState extends ConsumerState<_IntelligencePanel> {
  bool _analyzing = false;

  void _invalidateIntelligence() {
    // Called from child sections after an await (e.g. _setScore(),
    // _decide()) — ref.invalidate() throws "Using ref when a widget is
    // about to or has been unmounted" if this panel's sheet closed while
    // that request was in flight.
    if (!mounted) return;
    ref.invalidate(conversationIntelligenceProvider(widget.conversationId));
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _runAnalyzer() async {
    setState(() => _analyzing = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .refreshIntelligence(widget.conversationId);
      _invalidateIntelligence();
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(
      conversationIntelligenceProvider(widget.conversationId),
    );
    final canRefresh = ref.watch(
      canProvider(Perm.conversationRefreshIntelligence),
    );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                context.l10n.customerIntelligenceSectionTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (canRefresh)
              IconButton(
                tooltip: context.l10n.rerunAnalysisTooltip,
                onPressed: _analyzing ? null : _runAnalyzer,
                icon: _analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        async.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: LoadingState(label: context.l10n.loadingIntelligenceLabel),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: ErrorStateView(
              error: error,
              onRetry: _invalidateIntelligence,
            ),
          ),
          data: (intel) => intel == null
              ? _NotAnalyzedYet(
                  canRefresh: canRefresh,
                  busy: _analyzing,
                  onRun: _runAnalyzer,
                )
              : _IntelligenceContent(
                  conversationId: widget.conversationId,
                  intelligence: intel,
                  onChanged: _invalidateIntelligence,
                  onMessage: _showMessage,
                ),
        ),
      ],
    );
  }
}

class _NotAnalyzedYet extends StatelessWidget {
  const _NotAnalyzedYet({
    required this.canRefresh,
    required this.busy,
    required this.onRun,
  });

  final bool canRefresh;
  final bool busy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.psychology_outlined,
      title: context.l10n.notAnalyzedYetTitle,
      message: context.l10n.notAnalyzedYetMessage,
      action: canRefresh
          ? FilledButton.icon(
              onPressed: busy ? null : onRun,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(context.l10n.runAnalysisButton),
            )
          : null,
    );
  }
}

class _IntelligenceContent extends StatelessWidget {
  const _IntelligenceContent({
    required this.conversationId,
    required this.intelligence,
    required this.onChanged,
    required this.onMessage,
  });

  final int conversationId;
  final ConversationIntelligence intelligence;
  final VoidCallback onChanged;
  final void Function(String message, {bool isError}) onMessage;

  @override
  Widget build(BuildContext context) {
    return CustomerIntelligenceView(
      conversationId: conversationId,
      intelligence: intelligence,
      showHeader: false,
      onChanged: onChanged,
      onMessage: onMessage,
    );
  }
}
