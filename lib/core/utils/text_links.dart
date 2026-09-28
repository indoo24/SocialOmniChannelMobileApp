/// Finds the web links inside a piece of message text.
///
/// Deliberately narrow: only `http://` and `https://` URLs written out in
/// full, each checked with [SafeUrl.forLink]. Nothing else in a message —
/// `javascript:`, `data:`, bare domains, e-mail addresses — ever becomes
/// tappable. The text itself is never interpreted as HTML or markup.
library;

import 'safe_url.dart';

/// One run of [splitTextLinks]'s result: plain text, or a link when [uri]
/// is set. [text] is always exactly the characters of the original message.
class TextLinkPart {
  const TextLinkPart(this.text, [this.uri]);

  final String text;

  /// What the link opens — the URL as written, minus any punctuation that
  /// only followed it.
  final Uri? uri;

  bool get isLink => uri != null;

  @override
  bool operator ==(Object other) =>
      other is TextLinkPart && other.text == text && other.uri == uri;

  @override
  int get hashCode => Object.hash(text, uri);

  @override
  String toString() => isLink ? 'link($text)' : 'text($text)';
}

/// A URL candidate: the scheme, then everything up to whitespace or a
/// character that cannot appear in a URL written in prose. Not preceded by a
/// letter or digit, so `xhttps://…` is left alone.
final _candidate = RegExp(
  r'(?<![A-Za-z0-9])https?://[^\s<>"]+',
  caseSensitive: false,
);

/// Punctuation that ends a sentence or clause rather than a URL, including
/// Arabic comma, semicolon and question mark.
const _trailing = '.,;:!?\'"*\u2026\u060C\u061B\u061F\u00BB\u201D\u2019';

/// Closing brackets are trimmed only when unbalanced inside the URL, so
/// `(https://example.com)` loses its `)` but
/// `https://en.wikipedia.org/wiki/Mercury_(planet)` keeps it.
const _brackets = {')': '(', ']': '[', '}': '{'};

/// [text] split into plain runs and links, in order. Concatenating every
/// part's [TextLinkPart.text] gives back [text] exactly.
List<TextLinkPart> splitTextLinks(String text) {
  if (text.isEmpty) return const [];
  // Fast path: most messages have no link at all.
  if (!text.toLowerCase().contains('http')) return [TextLinkPart(text)];

  final parts = <TextLinkPart>[];
  var plainStart = 0;
  for (final match in _candidate.allMatches(text)) {
    final link = _trim(match.group(0)!);
    final uri = SafeUrl.forLink(link);
    if (uri == null) continue;
    if (match.start > plainStart) {
      parts.add(TextLinkPart(text.substring(plainStart, match.start)));
    }
    parts.add(TextLinkPart(link, uri));
    plainStart = match.start + link.length;
  }
  if (parts.isEmpty) return [TextLinkPart(text)];
  if (plainStart < text.length) {
    parts.add(TextLinkPart(text.substring(plainStart)));
  }
  return parts;
}

String _trim(String candidate) {
  var link = _cutRtlAfterHost(candidate);
  while (link.isNotEmpty) {
    final last = link[link.length - 1];
    if (_trailing.contains(last)) {
      link = link.substring(0, link.length - 1);
      continue;
    }
    final open = _brackets[last];
    if (open != null && _count(link, last) > _count(link, open)) {
      link = link.substring(0, link.length - 1);
      continue;
    }
    break;
  }
  return link;
}

/// A URL written straight into Arabic text with no space after it
/// (`https://example.comللتفاصيل`) would otherwise swallow the next word into
/// its host. Right-to-left letters are kept in the path
/// (`https://ar.wikipedia.org/wiki/مصر`), never in the host.
String _cutRtlAfterHost(String candidate) {
  final hostStart = candidate.indexOf('://') + 3;
  var hostEnd = candidate.indexOf(RegExp('[/?#]'), hostStart);
  if (hostEnd < 0) hostEnd = candidate.length;
  final rtl = candidate.substring(hostStart, hostEnd).indexOf(_rtlLetter);
  return rtl < 0 ? candidate : candidate.substring(0, hostStart + rtl);
}

final _rtlLetter = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

/// Whether [text] contains any right-to-left letters (Arabic, Hebrew…).
bool containsRtl(String text) => _rtlLetter.hasMatch(text);

int _count(String text, String char) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == char) count++;
  }
  return count;
}
