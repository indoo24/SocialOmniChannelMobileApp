/// The inbox's page control: one page of conversations at a time, with a
/// compact bar fixed under the list.
///
/// * Narrow phones: `‹ Previous   Page 20 of 400 ▾   Next ›` — the page
///   indicator opens "Go to page", so no page is ever hundreds of taps away.
/// * Wider screens (or few pages): nearby page numbers with ellipses,
///   `‹  1 … 19 [20] 21 … 400  ›`; the current page and each ellipsis open
///   "Go to page" too.
///
/// Mirrors in RTL through the ambient [Directionality] (the chevrons are
/// direction-aware icons), and reads everything from [InboxState].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'inbox_controller.dart';

/// The page buttons to show around [current] out of [total]: page numbers,
/// with `null` for an ellipsis. Always the first and last page, [siblings]
/// pages either side of the current one, and an ellipsis only where it
/// stands for two or more pages (a single hidden page is shown instead).
/// Its length is fixed for a given [siblings] once [total] is large, so the
/// bar does not jump in width while paging.
List<int?> inboxPageWindow(int current, int total, {int siblings = 1}) {
  if (total <= 0) return const [];
  final page = current.clamp(1, total);
  // first + last + current + siblings + two ellipsis slots
  final slots = 2 * siblings + 5;
  if (total <= slots) return [for (var p = 1; p <= total; p++) p];

  final start = (page - siblings).clamp(3, total - 2 - 2 * siblings);
  final end = (page + siblings).clamp(3 + 2 * siblings, total - 2);
  return [
    1,
    if (start > 3) null else 2,
    for (var p = start; p <= end; p++) p,
    if (end < total - 2) null else total - 1,
    total,
  ];
}

const _slot = 44.0; // minimum touch target
const _gap = Space.xs;

class InboxPaginationBar extends ConsumerWidget {
  const InboxPaginationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inboxControllerProvider).value;
    if (state == null || state.totalPages <= 1) return const SizedBox.shrink();
    final inbox = ref.read(inboxControllerProvider.notifier);
    final theme = Theme.of(context);
    final busy = state.isNavigating;

    Future<void> jump() async {
      final page = await showGoToPageDialog(
        context,
        current: state.page,
        total: state.totalPages,
      );
      if (page != null && page != state.page) await inbox.goToPage(page);
    }

    return Material(
      key: const ValueKey('inboxPagination'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: Space.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.failedPage != null && !busy)
                  _PageError(page: state.failedPage!, onRetry: inbox.retryPage),
                LayoutBuilder(
                  builder: (context, constraints) => _controls(
                    context,
                    constraints.maxWidth,
                    state,
                    onPrevious: busy || !state.hasPrevious
                        ? null
                        : inbox.previousPage,
                    onNext: busy || !state.hasNext ? null : inbox.nextPage,
                    onPage: busy ? null : inbox.goToPage,
                    onJump: busy ? null : jump,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    double width,
    InboxState state, {
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
    required ValueChanged<int>? onPage,
    required VoidCallback? onJump,
  }) {
    // Page numbers when enough of them fit beside the arrows; otherwise the
    // compact "Page X of Y" indicator.
    final labelled = width >= 600;
    final arrows = labelled ? 2 * 120.0 : 2 * _slot;
    final room = width - arrows - Space.lg;
    List<int?>? numbers;
    for (final siblings in const [2, 1]) {
      final window = inboxPageWindow(
        state.page,
        state.totalPages,
        siblings: siblings,
      );
      if (window.length * (_slot + _gap) <= room) {
        numbers = window;
        break;
      }
    }

    final previous = _ArrowButton(
      key: const ValueKey('inboxPreviousPage'),
      next: false,
      showLabel: numbers == null ? width >= 340 : labelled,
      onPressed: onPrevious,
    );
    final next = _ArrowButton(
      key: const ValueKey('inboxNextPage'),
      next: true,
      showLabel: numbers == null ? width >= 340 : labelled,
      onPressed: onNext,
    );

    if (numbers == null) {
      return Row(
        children: [
          previous,
          Expanded(
            child: Center(
              child: _PageIndicator(
                page: state.page,
                total: state.totalPages,
                loading: state.isNavigating,
                onTap: onJump,
              ),
            ),
          ),
          next,
        ],
      );
    }

    return Row(
      children: [
        previous,
        Expanded(
          child: Row(
            key: const ValueKey('inboxPageNumbers'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final page in numbers)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                  child: page == null
                      ? _EllipsisButton(onPressed: onJump)
                      : _PageNumberButton(
                          page: page,
                          current: page == state.page,
                          loading:
                              state.isNavigating && page == state.loadingPage,
                          onPressed: onPage == null
                              ? null
                              : page == state.page
                              ? onJump
                              : () => onPage(page),
                        ),
                ),
            ],
          ),
        ),
        next,
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.next,
    required this.showLabel,
    required this.onPressed,
    super.key,
  });

  final bool next;
  final bool showLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = next
        ? context.l10n.inboxNextPage
        : context.l10n.inboxPreviousPage;
    // Direction-aware: they point the other way in RTL.
    final icon = Icon(next ? Icons.chevron_right : Icons.chevron_left);
    if (!showLabel) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: icon,
        constraints: const BoxConstraints(minWidth: _slot, minHeight: _slot),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
      iconAlignment: next ? IconAlignment.end : IconAlignment.start,
      style: TextButton.styleFrom(minimumSize: const Size(_slot, _slot)),
    );
  }
}

/// "Page 20 of 400" — tapping it opens "Go to page".
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.page,
    required this.total,
    required this.loading,
    required this.onTap,
  });

  final int page;
  final int total;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = context.l10n.inboxPageOf(page, total);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      hint: context.l10n.inboxGoToPage,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('inboxPageIndicator'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _slot),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Space.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.page,
    required this.current,
    required this.loading,
    required this.onPressed,
  });

  final int page;
  final bool current;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final foreground = current
        ? scheme.onPrimary
        : enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      selected: current,
      enabled: enabled,
      label: current
          ? context.l10n.inboxCurrentPage(page)
          : context.l10n.inboxPageNumber(page),
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('inboxPage_$page'),
        // Filled and bold when current — told apart by more than colour.
        color: current ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radii.md),
          child: SizedBox(
            width: _slot,
            height: _slot,
            child: Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  : Text(
                      '$page',
                      maxLines: 1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: current ? FontWeight.w700 : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EllipsisButton extends StatelessWidget {
  const _EllipsisButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _slot,
      height: _slot,
      child: IconButton(
        tooltip: context.l10n.inboxGoToPage,
        onPressed: onPressed,
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
      ),
    );
  }
}

/// "Couldn't load page 21 · Try again" — the agent is still on the page
/// they were on.
class _PageError extends StatelessWidget {
  const _PageError({required this.page, required this.onRetry});

  final int page;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('inboxPageError'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            context.l10n.inboxPageLoadFailed(page),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('inboxPageRetry'),
          onPressed: onRetry,
          child: Text(context.l10n.retryButton),
        ),
      ],
    );
  }
}

/// "Go to page": digits only, 1…[total]. Resolves to the page, or null when
/// cancelled (Cancel, Escape, tapping outside).
Future<int?> showGoToPageDialog(
  BuildContext context, {
  required int current,
  required int total,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _GoToPageDialog(current: current, total: total),
  );
}

class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.current}')
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: '${widget.current}'.length,
        );

  int? get _page {
    final page = int.tryParse(_controller.text);
    return page != null && page >= 1 && page <= widget.total ? page : null;
  }

  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = _page;
    if (page == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    final valid = _page != null;
    return AlertDialog(
      key: const ValueKey('inboxGoToPageDialog'),
      title: Text(context.l10n.inboxGoToPage),
      content: TextField(
        key: const ValueKey('inboxGoToPageField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter('${widget.total}'.length),
        ],
        decoration: InputDecoration(
          hintText: '1–${widget.total}',
          errorText: _showError && !valid
              ? context.l10n.inboxGoToPageInvalid(widget.total)
              : null,
        ),
        // Out of range as soon as it is typed; an empty field is only an
        // error once submitted.
        onChanged: (text) =>
            setState(() => _showError = text.isNotEmpty && _page == null),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('inboxGoToPageGo'),
          onPressed: valid ? _submit : null,
          child: Text(context.l10n.inboxGoToPageAction),
        ),
      ],
    );
  }
}
