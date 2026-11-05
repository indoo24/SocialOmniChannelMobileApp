/// Marking where a search's words appear in a piece of text.
///
/// Display only: what matched was decided by the server. This finds the
/// query's words in the text it sent back so the eye lands on them, and
/// marks nothing it cannot find — a server that matched `أحمد` for `احمد`, or
/// a phone number written with spaces, simply shows the snippet unmarked.
library;

import 'package:flutter/painting.dart';

/// The non-overlapping ranges of [text] where a word of [query] appears,
/// ignoring case, in order. Words shorter than two characters are skipped:
/// they would mark half of every snippet.
List<(int, int)> searchMatchRanges(String text, String query) {
  final haystack = text.toLowerCase();
  // Lower-casing can change a string's length (`İ`); offsets found in the
  // lowered text would then point at the wrong characters in [text].
  if (haystack.length != text.length) return const [];
  final terms = {
    for (final term in query.toLowerCase().split(RegExp(r'\s+')))
      if (term.length >= 2) term,
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  if (terms.isEmpty) return const [];

  final ranges = <(int, int)>[];
  for (final term in terms) {
    var from = 0;
    while (true) {
      final start = haystack.indexOf(term, from);
      if (start < 0) break;
      final end = start + term.length;
      // Longer terms went first, so a shorter one inside them is skipped.
      if (!ranges.any((r) => start < r.$2 && end > r.$1)) {
        ranges.add((start, end));
      }
      from = end;
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  return ranges;
}

/// [text] as spans, with [highlight] applied where [query]'s words appear.
List<TextSpan> highlightSearchMatches(
  String text,
  String query, {
  required TextStyle highlight,
}) {
  final ranges = searchMatchRanges(text, query);
  if (ranges.isEmpty) return [TextSpan(text: text)];
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final (start, end) in ranges) {
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start)));
    }
    spans.add(TextSpan(text: text.substring(start, end), style: highlight));
    cursor = end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
