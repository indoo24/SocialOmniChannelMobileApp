/// Heading row for a settings section: the title on one side, the section's
/// primary action on the other.
///
/// The action used to sit on its own row under the heading, stretched edge to
/// edge, which read as a second heavier heading and pushed the section's real
/// content down. Keeping it beside the title matches the web layout and costs
/// no vertical space.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Height of a section action. Shorter than the app-wide 48px button so the
/// action reads as secondary to the heading it sits on, and short enough not
/// to set the height of the whole header row.
const double _kActionHeight = 38;

/// Content width below which the title and the action cannot share a line
/// without squeezing one of them, so the action wraps underneath. Measured
/// against *available* width, not screen width: these sections are nested in
/// cards whose padding has already been taken off.
const double _kStackActionBelowWidth = 320;

/// Makes a [FilledButton] in a section header size itself to its label.
///
/// The app theme sets `minimumSize: Size.fromHeight(48)`, and `fromHeight`
/// leaves the *width* at `double.infinity` — so every themed FilledButton
/// expands to fill whatever constraints it is handed. That is what turned
/// these actions into full-width bars; it was never the surrounding layout.
/// Releasing the minimum width here (rather than in the theme) keeps every
/// other button in the app exactly as it is.
///
/// Pair it with [sectionActionLabel] so a long or translated label ellipsizes
/// on one line instead of wrapping and growing the button taller.
ButtonStyle sectionActionStyle(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, _kActionHeight),
    padding: const EdgeInsets.symmetric(horizontal: Space.md),
    // Without this the button keeps the 48px tap-target box around its 38px
    // self, so it still occupies a 48px row.
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

/// One-line label for a section action — see [sectionActionStyle].
Widget sectionActionLabel(String text) {
  return Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({required this.title, this.action, super.key});

  final String title;

  /// Content-sized, built with [sectionActionStyle]. Null when the viewer
  /// lacks permission to act on the section.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleText = Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    if (action == null) return titleText;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Unbounded width (a horizontal scrollable, a test pumping the section
        // bare) has no right-hand side to align against, so stack instead of
        // letting Expanded throw.
        final stack =
            !constraints.hasBoundedWidth ||
            constraints.maxWidth < _kStackActionBelowWidth;

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleText,
              const SizedBox(height: Space.md),
              // The action is already content-sized by sectionActionStyle, so
              // Align only decides where it sits, never how wide it is.
              Align(alignment: AlignmentDirectional.centerStart, child: action),
            ],
          );
        }

        return Row(
          // Centered, not top-aligned: with the description gone the title is
          // a single line, and the two should share one baseline band.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleText),
            const SizedBox(width: Space.md),
            // Flexible, not a bare child: a Row lays non-flex children out
            // against an unbounded main axis, and a FilledButton.icon asserts
            // on infinite width. Loose fit leaves it at its natural width and
            // only narrows it if a long label would otherwise not fit.
            Flexible(child: action!),
          ],
        );
      },
    );
  }
}
