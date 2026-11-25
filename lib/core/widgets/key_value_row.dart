/// A label and its value, side by side — the details tables in the
/// conversation sheet and the customer profile.
///
/// Built so nothing is cut: the label column takes a share of the row
/// rather than a fixed width (so a large system text size or a long label
/// still leaves the value room), both sides wrap instead of ellipsizing, and
/// on a very narrow row the label goes above its value instead.
///
/// A left-to-right value that is one unbroken token — an e-mail address, a
/// number — has nowhere sensible to wrap, so one that is only slightly too
/// long is shrunk a little to stay on its line instead of losing its last
/// letters to the next; a longer one still wraps.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/text_direction.dart';

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    required this.label,
    required this.value,
    this.ltr = false,
    this.valueStyle,
    super.key,
  });

  final String label;
  final String value;

  /// For phone numbers and e-mail addresses: always left-to-right, so in
  /// Arabic a leading `+` stays in front of the number.
  final bool ltr;

  /// Overrides the value's style (merged over the default).
  final TextStyle? valueStyle;

  /// Below this width the label is stacked above the value.
  static const stackBelow = 250.0;

  /// The smallest a one-token value is shrunk to before it wraps instead.
  static const minTokenScale = 0.8;

  /// The label column's share of the row, and its bounds.
  static const labelShare = 0.38;
  static const minLabelWidth = 88.0;
  static const maxLabelWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      height: 1.35,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final baseValueStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    final shown = value.isEmpty ? '—' : value;

    final effectiveValueStyle = baseValueStyle?.merge(valueStyle) ?? valueStyle;
    Widget plainValue() => Text(
      shown,
      key: const ValueKey('keyValueRowValue'),
      softWrap: true,
      textDirection: ltr && value.isNotEmpty ? TextDirection.ltr : null,
      textAlign: ltr ? ambientStartAlign(context) : null,
      style: effectiveValueStyle,
    );
    Widget valueText() {
      final oneToken = ltr && value.isNotEmpty && !value.contains(' ');
      if (!oneToken) return plainValue();
      return LayoutBuilder(
        builder: (context, box) {
          final painter = TextPainter(
            text: TextSpan(text: shown, style: effectiveValueStyle),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          if (width <= box.maxWidth || width * minTokenScale > box.maxWidth) {
            return plainValue();
          }
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: plainValue(),
            ),
          );
        },
      );
    }

    final labelText = Text(
      label,
      key: const ValueKey('keyValueRowLabel'),
      softWrap: true,
      style: labelStyle,
    );

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < stackBelow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labelText,
                  const SizedBox(height: Space.xxs),
                  valueText(),
                ],
              );
            }
            final labelWidth = (constraints.maxWidth * labelShare).clamp(
              minLabelWidth,
              maxLabelWidth,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: labelWidth, child: labelText),
                const SizedBox(width: Space.md),
                Expanded(child: valueText()),
              ],
            );
          },
        ),
      ),
    );
  }
}
