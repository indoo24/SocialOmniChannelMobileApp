/// Design tokens, ported verbatim from the web client.
///
/// The web app defines these as HSL custom properties in `frontend/src/index.css`
/// and consumes them through Tailwind. They are converted to Color here rather
/// than re-picked by eye, so "the same product" is a fact about the values and
/// not a judgement about the screenshots.
///
/// When the web palette changes, change it here — these are the only colour
/// literals in the app.
library;

import 'package:flutter/material.dart';

/// Converts the CSS `hsl(H S% L%)` triples used by the web client.
Color _hsl(double h, double s, double l) =>
    HSLColor.fromAHSL(1.0, h, s / 100, l / 100).toColor();

class ScenarioColors {
  const ScenarioColors._();

  // --- light (:root) ------------------------------------------------------
  static final background = _hsl(210, 20, 98);
  static final foreground = _hsl(222, 47, 11);
  static final card = _hsl(0, 0, 100);
  static final cardForeground = _hsl(222, 47, 11);
  static final primary = _hsl(243, 75, 59);
  static final primaryForeground = _hsl(0, 0, 100);
  static final secondary = _hsl(210, 40, 96);
  static final secondaryForeground = _hsl(222, 47, 11);
  static final muted = _hsl(210, 40, 96);
  static final mutedForeground = _hsl(215, 16, 47);
  static final accent = _hsl(210, 40, 94);
  static final destructive = _hsl(0, 72, 51);
  static final destructiveForeground = _hsl(0, 0, 100);
  static final border = _hsl(214, 32, 91);
  static final ring = _hsl(243, 75, 59);

  /// The web sidebar is a dark slab against a light app. On mobile there is no
  /// sidebar, but the same colour anchors the app bar so the two clients read
  /// as one product.
  static final sidebar = _hsl(222, 47, 11);
  static final sidebarForeground = _hsl(213, 27, 84);
  static final sidebarAccent = _hsl(217, 33, 20);

  // --- dark (.dark) -------------------------------------------------------
  static final darkBackground = _hsl(222, 47, 8);
  static final darkForeground = _hsl(210, 40, 96);
  static final darkCard = _hsl(222, 47, 11);
  static final darkPrimary = _hsl(243, 75, 66);
  static final darkPrimaryForeground = _hsl(222, 47, 11);
  static final darkSecondary = _hsl(217, 33, 17);
  static final darkMuted = _hsl(217, 33, 17);
  static final darkMutedForeground = _hsl(215, 20, 65);
  static final darkAccent = _hsl(217, 33, 20);
  static final darkDestructive = _hsl(0, 63, 51);
  static final darkBorder = _hsl(217, 33, 20);

  /// The agent's own message bubble in dark mode. The lighter dark-mode
  /// primary only gives white text about 3.6:1 contrast; the light-mode
  /// indigo keeps the brand colour at better than 6:1.
  static final darkOutgoingBubble = _hsl(243, 75, 59);

  // --- semantic status colours -------------------------------------------
  // Mirrors the web Badge variants (success / warning / danger / muted).
  static final success = _hsl(142, 71, 45);
  static final successSurface = _hsl(142, 76, 96);
  static final warning = _hsl(38, 92, 50);
  static final warningSurface = _hsl(48, 96, 94);
  static final danger = _hsl(0, 72, 51);
  static final dangerSurface = _hsl(0, 86, 97);
  static final info = _hsl(243, 75, 59);
  static final infoSurface = _hsl(226, 100, 97);
}

/// Spacing scale. Tailwind's 4px rhythm, which the web app uses throughout.
class Space {
  const Space._();
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// `--radius: 0.625rem` = 10px, with the same −2/−4 derivations Tailwind makes.
class Radii {
  const Radii._();

  /// Message bubbles and the composer's input field.
  static const xl = 18.0;
  static const lg = 10.0;
  static const md = 8.0;
  static const sm = 6.0;
  static const pill = 999.0;
}

/// Component dimensions shared by the inbox and the conversation, so their
/// controls line up and stay comfortably tappable.
class Sizes {
  const Sizes._();

  /// Minimum side of anything tappable (Material's 48 minus the visual
  /// density the dense headers already use).
  static const touchTarget = 44.0;

  /// Height of the inbox filter pills and account selectors.
  static const pill = 36.0;

  static const iconSm = 16.0;
  static const iconMd = 20.0;
  static const iconLg = 24.0;

  /// Customer avatar in an inbox row.
  static const rowAvatar = 44.0;

  /// Start inset of the divider between inbox rows: row padding + avatar +
  /// gap, so separators line up with the text, not the avatar.
  static const rowDividerIndent = Space.lg + rowAvatar + Space.md;

  /// Widest a message bubble gets, however wide the screen.
  static const bubbleMaxWidth = 520.0;

  /// Fraction of the screen width a message bubble may take.
  static const bubbleWidthFactor = 0.78;

  /// Width of a single inline image in a bubble.
  static const inlineImageWidth = 240.0;
}
