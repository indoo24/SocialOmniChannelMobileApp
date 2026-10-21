/// Message text with its web links tappable — the one URL-aware text
/// renderer, used for every message bubble (incoming, outgoing, templates) —
/// and, in WhatsApp threads, WhatsApp's `*bold*` drawn in bold.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/external_link.dart';
import '../utils/text_links.dart';
import '../utils/whatsapp_format.dart';

class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    required this.linkColor,
    this.style,
    this.textDirection,
    this.whatsappBold = false,
    super.key,
  });

  /// Shown exactly as given — links are styled, never rewritten.
  final String text;
  final TextStyle? style;

  /// Links keep the text's font and size; only colour and underline change.
  final Color linkColor;

  /// Overrides the ambient direction, for text whose language need not be
  /// the app's.
  final TextDirection? textDirection;

  /// Draws WhatsApp's `*bold*` markup in bold, without its asterisks. Only for
  /// WhatsApp messages: other channels do not treat asterisks as markup, so
  /// there they are shown as written. The [text] itself is never altered.
  final bool whatsappBold;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  // Parsed when the text changes, not on every rebuild of a long thread.
  late List<TextLinkPart> _parts;
  late bool _rtl;
  late List<BoldSpan> _bold;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.whatsappBold != widget.whatsappBold) {
      _disposeRecognizers();
      _parse();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parse() {
    _parts = splitTextLinks(widget.text);
    _rtl = containsRtl(widget.text);
    _bold = widget.whatsappBold
        ? _boldOutsideLinks(widget.text, _parts)
        : const [];
    for (final part in _parts) {
      if (!part.isLink) continue;
      final uri = part.uri!;
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => openExternalLink(uri),
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// Bold runs whose asterisks are not part of a link, and that do not cut a
  /// link in two: a link is either wholly bold or not bold at all.
  static List<BoldSpan> _boldOutsideLinks(
    String text,
    List<TextLinkPart> parts,
  ) {
    final spans = whatsappBoldSpans(text);
    if (spans.isEmpty) return spans;
    final links = <(int, int)>[];
    var offset = 0;
    for (final part in parts) {
      if (part.isLink) links.add((offset, offset + part.text.length));
      offset += part.text.length;
    }
    bool inside(int i, (int, int) link) => i >= link.$1 && i < link.$2;
    return [
      for (final span in spans)
        if (!links.any(
          (link) =>
              inside(span.start, link) ||
              inside(span.end, link) ||
              // Straddles the start or the end of the bold text.
              (link.$1 < span.contentStart && link.$2 > span.contentStart) ||
              (link.$1 < span.contentEnd && link.$2 > span.contentEnd),
        ))
          span,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_bold.isNotEmpty) return _buildWithBold();
    if (_recognizers.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        textDirection: widget.textDirection,
      );
    }

    final linkStyle = TextStyle(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    var link = 0;
    return Text.rich(
      TextSpan(
        children: [
          for (final part in _parts)
            if (part.isLink)
              TextSpan(
                // In right-to-left text the link is isolated as a
                // left-to-right run, so its trailing `/` or `?x=1` is not
                // reordered to the wrong end by the surrounding Arabic.
                text: _rtl ? '\u2066${part.text}\u2069' : part.text,
                semanticsLabel: part.text,
                style: linkStyle,
                mouseCursor: SystemMouseCursors.click,
                recognizer: _recognizers[link++],
              )
            else
              TextSpan(text: part.text),
        ],
      ),
      style: widget.style,
      textDirection: widget.textDirection,
    );
  }

  /// The same text, links and isolation as [build], with the bold runs in
  /// bold and their asterisks left out of what is drawn.
  Widget _buildWithBold() {
    final text = widget.text;
    final linkStyle = TextStyle(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );

    // Per character: hidden marker, bold, or which link it belongs to.
    final hidden = List<bool>.filled(text.length, false);
    final bold = List<bool>.filled(text.length, false);
    final linkOf = List<int>.filled(text.length, -1);
    for (final span in _bold) {
      hidden[span.start] = true;
      hidden[span.end] = true;
      for (var i = span.contentStart; i < span.contentEnd; i++) {
        bold[i] = true;
      }
    }
    var offset = 0;
    var link = 0;
    for (final part in _parts) {
      if (part.isLink) {
        for (var i = offset; i < offset + part.text.length; i++) {
          linkOf[i] = link;
        }
        link++;
      }
      offset += part.text.length;
    }

    final children = <InlineSpan>[];
    var i = 0;
    while (i < text.length) {
      if (hidden[i]) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < text.length &&
          !hidden[j] &&
          bold[j] == bold[i] &&
          linkOf[j] == linkOf[i]) {
        j++;
      }
      final run = text.substring(i, j);
      final weight = bold[i]
          ? const TextStyle(fontWeight: FontWeight.w700)
          : null;
      final linkIndex = linkOf[i];
      children.add(
        linkIndex < 0
            ? TextSpan(text: run, style: weight)
            : TextSpan(
                // Isolated in right-to-left text, as in [build].
                text: _rtl ? '\u2066$run\u2069' : run,
                semanticsLabel: run,
                style: weight == null ? linkStyle : linkStyle.merge(weight),
                mouseCursor: SystemMouseCursors.click,
                recognizer: _recognizers[linkIndex],
              ),
      );
      i = j;
    }

    return Text.rich(
      TextSpan(children: children),
      style: widget.style,
      textDirection: widget.textDirection,
    );
  }
}
