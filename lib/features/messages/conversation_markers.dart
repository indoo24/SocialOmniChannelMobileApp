/// Conversation markers on mobile, after the web's thread header.
///
/// The organization's switch is `/auth/me/`'s `conversation_markers_enabled`
/// (`Employee.conversationMarkersEnabled`); without it none of this shows.
/// With it, three pieces, all reading the server's own fields:
///
///  * [ConversationPrimaryMarkerButton] — the header's prominent button: the
///    detail's `primary_marker`, a toggle that puts it on or takes it off. It
///    takes the place of "Sold" (purchase confirmation) in the header, as on
///    the web; confirming a purchase moves into the conversation's actions.
///  * [MarkerMetaChip] — what the conversation wears (`markers`), in the
///    header's details row.
///  * [ConversationMarkersSection] — the conversation sheet's Markers group:
///    every marker on it, each removable, and "Add marker" for the ones this
///    employee may apply (`GET /conversations/{id}/markers/`).
///
/// A marker is an annotation and nothing more. Applying one sends
/// `POST /conversations/{id}/markers/` and nothing else — no purchase, status,
/// priority, pin or assignment request — and every change is shown from the
/// conversation as the server reads it afterwards, never assumed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_marker.dart';
import '../../core/models/employee.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import 'conversation_controller.dart';

/// `GET /conversations/{id}/markers/` — what the conversation wears and what
/// this employee may add. Auto-disposed: read fresh whenever the sheet that
/// shows it opens, and never kept past it.
final conversationMarkersProvider = FutureProvider.autoDispose
    .family<ConversationMarkers, int>((ref, conversationId) {
      return ref
          .watch(conversationRepositoryProvider)
          .conversationMarkers(conversationId);
    });

/// A marker's own colour (`#RRGGBB`), or [fallback] when it is not one.
Color markerColor(String hex, Color fallback) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 3) value = value.split('').map((c) => '$c$c').join();
  if (value.length != 6) return fallback;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? fallback : Color(0xFF000000 | parsed);
}

/// The marker's colour as text on [background]: taken toward [foreground]
/// only as far as it needs to read (4.5:1), so a pale yellow or a dark navy
/// marker stays legible in either theme while keeping its hue.
Color markerInk(Color color, Color background, Color foreground) {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  for (var t = 0.0; t <= 0.8; t += 0.1) {
    final ink = Color.lerp(color, foreground, t)!;
    if (contrast(ink, background) >= 4.5) return ink;
  }
  return Color.lerp(color, foreground, 0.8)!;
}

/// Who may use a marker: its team's name, or "Everyone".
String markerScopeLabel(BuildContext context, {
  required bool teamScoped,
  required String teamName,
}) => teamScoped && teamName.trim().isNotEmpty
    ? teamName.trim()
    : context.l10n.markersEveryone;

/// Shows why a marker request was refused.
void _sayMarkerError(
  ScaffoldMessengerState messenger,
  BuildContext context,
  ApiException error,
) {
  final l10n = context.l10n;
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (error) {
        _ when error.isForbidden => l10n.markersForbidden,
        _ when error.message.trim().isNotEmpty => error.message,
        _ => l10n.markersFailed,
      }),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

// ---------------------------------------------------------------------------
// Header: the primary marker
// ---------------------------------------------------------------------------

/// The conversation header's prominent button: the detail's `primary_marker`
/// as a toggle, in the marker's own colour — on (✓) when the conversation
/// wears it, off (+) when it does not.
///
/// * Tapping puts it on or takes it off, and shows what the server then
///   holds. While the request is out the button spins and ignores taps.
/// * Without `conversation.apply_marker` it is not a button: an applied
///   marker still shows (it is a fact about the conversation), an unapplied
///   one is not offered.
/// * Nothing at all when the server names no primary marker.
///
/// [maxWidth] is the room the header's first row leaves it. With too little
/// for a label, only the coloured toggle shows; the label is still its
/// tooltip and what a screen reader says.
class ConversationPrimaryMarkerButton extends ConsumerStatefulWidget {
  const ConversationPrimaryMarkerButton({
    required this.conversation,
    this.maxWidth = 160,
    super.key,
  });

  final Conversation conversation;
  final double maxWidth;

  /// Below this, the button shows no label.
  static const labelledMinWidth = 72.0;

  @override
  ConsumerState<ConversationPrimaryMarkerButton> createState() =>
      _ConversationPrimaryMarkerButtonState();
}

class _ConversationPrimaryMarkerButtonState
    extends ConsumerState<ConversationPrimaryMarkerButton> {
  bool _busy = false;

  Future<void> _toggle(PrimaryMarker marker) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final id = widget.conversation.id;
    setState(() => _busy = true);
    try {
      final controller = ref.read(conversationControllerProvider(id).notifier);
      if (marker.isApplied) {
        await controller.removeMarker(marker.id);
      } else {
        await controller.applyMarker(marker.id);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            marker.isApplied ? l10n.markersRemoved : l10n.markersApplied,
          ),
        ),
      );
    } on SessionExpiredException {
      // On its way back to sign-in already.
    } on RequestCancelledException {
      // Abandoned on purpose.
    } on ApiException catch (error) {
      if (mounted) _sayMarkerError(messenger, context, error);
    } finally {
      if (mounted) {
        ref.invalidate(conversationMarkersProvider(id));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final marker = widget.conversation.primaryMarker;
    if (marker == null) return const SizedBox.shrink();
    final canApply = ref.watch(canProvider(Perm.conversationApplyMarker));
    if (!canApply && !marker.isApplied) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;
    final base = markerColor(marker.color, colors.primary);
    final applied = marker.isApplied;
    final fill = base.withValues(
      alpha: applied ? (isDark ? 0.34 : 0.2) : (isDark ? 0.14 : 0.07),
    );
    final surface = theme.appBarTheme.backgroundColor ?? colors.surface;
    final ink = markerInk(
      base,
      Color.alphaBlend(fill, surface),
      colors.foreground,
    );
    final labelled =
        widget.maxWidth >= ConversationPrimaryMarkerButton.labelledMinWidth;

    final icon = _busy
        ? SizedBox(
            key: const ValueKey('conversationPrimaryMarkerBusy'),
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          )
        : Icon(
            applied ? Icons.check_circle_rounded : Icons.add_circle_outline,
            size: 17,
            color: ink,
          );

    final body = labelled
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 38,
              maxWidth: widget.maxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: Space.xs + 2),
                  Flexible(
                    child: Text(
                      marker.label,
                      key: const ValueKey('conversationPrimaryMarkerLabel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : SizedBox(width: 38, height: 38, child: Center(child: icon));

    return Tooltip(
      message: labelled
          ? markerScopeLabel(
              context,
              teamScoped: marker.isTeamScoped,
              teamName: marker.teamName,
            )
          : marker.label,
      child: Semantics(
        button: canApply,
        toggled: applied,
        label: applied
            ? l10n.primaryMarkerApplied(marker.label)
            : l10n.primaryMarkerNotApplied(marker.label),
        excludeSemantics: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              key: const ValueKey('conversationPrimaryMarker'),
              color: fill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
                side: BorderSide(
                  color: base.withValues(alpha: applied ? 0.7 : 0.4),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: canApply && !_busy ? () => _toggle(marker) : null,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header details row: what the conversation wears
// ---------------------------------------------------------------------------

/// One marker the conversation wears, as a compact chip in the header's
/// details row — the same size as the team and assignee chips beside it.
class MarkerMetaChip extends StatelessWidget {
  const MarkerMetaChip({required this.marker, super.key});

  final ConversationMarker marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = markerColor(marker.color, colors.primary);
    final fill = base.withValues(alpha: isDark ? 0.18 : 0.1);
    final surface = theme.appBarTheme.backgroundColor ?? colors.surface;
    final ink = markerInk(
      base,
      Color.alphaBlend(fill, surface),
      colors.foreground,
    );
    return Semantics(
      label: context.l10n.markerChipSemantics(marker.label),
      excludeSemantics: true,
      child: Opacity(
        opacity: marker.isActive ? 1 : 0.6,
        child: Container(
          key: ValueKey('conversationHeaderMarker_${marker.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: base.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sell_outlined, size: 11, color: ink),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  marker.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The markers to show as chips in the header: what the conversation wears,
/// less the primary marker when its button already says it is on.
List<ConversationMarker> headerMarkers(Conversation conversation) {
  final primary = conversation.primaryMarker;
  return [
    for (final m in conversation.markers)
      if (!(primary != null && primary.isApplied && primary.id == m.id)) m,
  ];
}

// ---------------------------------------------------------------------------
// Conversation sheet: the Markers group
// ---------------------------------------------------------------------------

/// The conversation sheet's Markers group, as the web's markers row: every
/// marker the conversation wears (removable with `conversation.apply_marker`)
/// and "Add marker" for the ones this employee may apply.
///
/// Like the web, it is not there at all when the conversation wears nothing
/// and there is nothing this employee could add.
class ConversationMarkersSection extends ConsumerStatefulWidget {
  const ConversationMarkersSection({
    required this.conversation,
    this.frame,
    super.key,
  });

  final Conversation conversation;

  /// Wraps the group when it shows — the sheet's own section card, which
  /// then carries the title. Without it the group titles itself.
  final Widget Function(Widget child)? frame;

  @override
  ConsumerState<ConversationMarkersSection> createState() =>
      _ConversationMarkersSectionState();
}

class _ConversationMarkersSectionState
    extends ConsumerState<ConversationMarkersSection> {
  /// The marker a request is out for; every chip waits until it answers.
  int? _pending;

  int get _id => widget.conversation.id;

  Future<void> _change(ConversationMarker marker, {required bool add}) async {
    if (_pending != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _pending = marker.id);
    try {
      final controller = ref.read(conversationControllerProvider(_id).notifier);
      if (add) {
        await controller.applyMarker(marker.id);
      } else {
        await controller.removeMarker(marker.id);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(add ? l10n.markersApplied : l10n.markersRemoved)),
      );
    } on SessionExpiredException {
      // On its way back to sign-in already.
    } on RequestCancelledException {
      // Abandoned on purpose.
    } on ApiException catch (error) {
      if (mounted) _sayMarkerError(messenger, context, error);
    } finally {
      if (mounted) {
        ref.invalidate(conversationMarkersProvider(_id));
        setState(() => _pending = null);
      }
    }
  }

  Future<void> _openPicker(List<ConversationMarker> addable) async {
    final chosen = await showAddMarkerSheet(context, addable: addable);
    if (chosen != null && mounted) await _change(chosen, add: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final canApply = ref.watch(canProvider(Perm.conversationApplyMarker));
    final async = ref.watch(conversationMarkersProvider(_id));

    // Whenever the conversation is read again with other markers on it — a
    // change made here, on the header's button, or by somebody else (a
    // realtime refresh) — the list is read again too.
    ref.listen(
      conversationControllerProvider(_id).select(
        (s) => s.value?.conversation.markers.map((m) => m.id).join(','),
      ),
      (previous, next) {
        if (previous != null && previous != next) {
          ref.invalidate(conversationMarkersProvider(_id));
        }
      },
    );

    final data = async.value;
    final current = data?.current ?? widget.conversation.markers;
    final addable = data?.addable ?? const <ConversationMarker>[];
    final failed = async.hasError && data == null;

    if (current.isEmpty) {
      if (!canApply) return const SizedBox.shrink();
      if (data == null && !failed) return const SizedBox.shrink();
      if (data != null && addable.isEmpty) return const SizedBox.shrink();
    }

    final busy = _pending != null;
    final content = KeyedSubtree(
      key: const ValueKey('conversationMarkersSection'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.frame == null) ...[
            Text(
              l10n.markersSectionTitle.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xxs),
          ],
          Text(
            l10n.markersSectionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final marker in current)
                _MarkerChip(
                  marker: marker,
                  busy: _pending == marker.id,
                  onRemove: canApply && !busy
                      ? () => _change(marker, add: false)
                      : null,
                ),
              if (canApply && addable.isNotEmpty)
                ActionChip(
                  key: const ValueKey('conversationMarkersAdd'),
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text(l10n.markersAdd),
                  onPressed: busy ? null : () => _openPicker(addable),
                ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.markersLoadFailed,
                    key: const ValueKey('conversationMarkersLoadFailed'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(conversationMarkersProvider(_id)),
                  child: Text(l10n.retryButton),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return widget.frame?.call(content) ?? content;
  }
}

/// A marker the conversation wears, in its colour, with × to take it off
/// when [onRemove] is given.
class _MarkerChip extends StatelessWidget {
  const _MarkerChip({required this.marker, required this.busy, this.onRemove});

  final ConversationMarker marker;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final base = markerColor(marker.color, colors.primary);
    final fill = base.withValues(alpha: isDark ? 0.2 : 0.1);
    final ink = markerInk(
      base,
      Color.alphaBlend(fill, colors.surface),
      colors.foreground,
    );
    final details = [
      markerScopeLabel(
        context,
        teamScoped: marker.isTeamScoped,
        teamName: marker.teamName,
      ),
      if (marker.appliedByName.trim().isNotEmpty) marker.appliedByName.trim(),
      if (!marker.isActive) l10n.markersArchived,
    ].join(' · ');

    return Tooltip(
      message: details,
      child: Chip(
        key: ValueKey('conversationMarkerChip_${marker.id}'),
        avatar: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              )
            : Icon(Icons.sell_outlined, size: 15, color: ink),
        label: Text(
          marker.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: ink,
            fontWeight: FontWeight.w600,
            fontStyle: marker.isActive ? null : FontStyle.italic,
          ),
        ),
        backgroundColor: fill,
        side: BorderSide(color: base.withValues(alpha: 0.4)),
        shape: const StadiumBorder(),
        deleteIcon: Icon(Icons.close_rounded, size: 16, color: ink),
        deleteButtonTooltipMessage: l10n.markersRemoveOne(marker.label),
        onDeleted: onRemove,
      ),
    );
  }
}

/// The markers this employee may add, grouped as the web groups them —
/// Everyone's first, then one group per team. Resolves to the one chosen, or
/// null when dismissed.
Future<ConversationMarker?> showAddMarkerSheet(
  BuildContext context, {
  required List<ConversationMarker> addable,
}) {
  final global = [
    for (final m in addable)
      if (m.scope == markerScopeOrganization) m,
  ];
  final teams = <int, List<ConversationMarker>>{};
  for (final m in addable) {
    if (m.scope != markerScopeTeam || m.teamId == null) continue;
    teams.putIfAbsent(m.teamId!, () => []).add(m);
  }

  return showModalBottomSheet<ConversationMarker>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = AppColors.of(sheetContext);
      final l10n = sheetContext.l10n;

      Widget group(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xs,
        ),
        child: Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: colors.mutedForeground,
          ),
        ),
      );

      Widget option(ConversationMarker m) => ListTile(
        key: ValueKey('addMarkerOption_${m.id}'),
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: markerColor(m.color, colors.primary),
            shape: BoxShape.circle,
          ),
        ),
        title: Text(m.label),
        onTap: () => Navigator.of(sheetContext).pop(m),
      );

      final empty = global.isEmpty && teams.isEmpty;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: ListView(
          key: const ValueKey('addMarkerSheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(
                l10n.markersPickerTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (empty)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  l10n.markersPickerEmpty,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (global.isNotEmpty) ...[
              group(l10n.markersEveryone),
              for (final m in global) option(m),
            ],
            for (final entry in teams.entries) ...[
              group(
                entry.value.first.teamName.trim().isEmpty
                    ? '#${entry.key}'
                    : entry.value.first.teamName,
              ),
              for (final m in entry.value) option(m),
            ],
          ],
        ),
      );
    },
  );
}
