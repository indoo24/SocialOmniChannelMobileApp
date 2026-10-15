/// WhatsApp's own bold markup: `*like this*`.
///
/// WhatsApp shows text between single asterisks in bold on the customer's
/// phone, so a WhatsApp thread shows it the same way here. The message text
/// itself is never changed — what is stored, sent and copied keeps its
/// asterisks; only the way it is drawn differs. Other channels do not use this
/// markup, and their messages are drawn exactly as written.
library;

/// A bold run found in a message: [start] and [end] are the positions of the
/// opening and closing asterisks; the bold text lies strictly between them.
class BoldSpan {
  const BoldSpan(this.start, this.end);

  final int start;
  final int end;

  int get contentStart => start + 1;
  int get contentEnd => end;

  @override
  bool operator ==(Object other) =>
      other is BoldSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'BoldSpan($start, $end)';
}

/// Follows WhatsApp's rules closely enough for display: the opening `*` does
/// not follow a letter or digit and is followed by a non-space; the closing
/// `*` follows a non-space and is not followed by a letter or digit; the run
/// stays on one line and is not empty. So `2*3*4` and `* not bold *` stay as
/// written.
final _bold = RegExp(
  r'(?<![\p{L}\p{N}_*])\*(?=[^\s*])[^*\n]*?(?<=[^\s*])\*(?![\p{L}\p{N}_*])',
  unicode: true,
);

/// The bold runs in [text], in order and never overlapping.
List<BoldSpan> whatsappBoldSpans(String text) {
  if (!text.contains('*')) return const [];
  return [
    for (final match in _bold.allMatches(text))
      BoldSpan(match.start, match.end - 1),
  ];
}
