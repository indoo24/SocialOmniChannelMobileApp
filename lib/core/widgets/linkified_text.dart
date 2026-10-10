/// Message text with its web links tappable — the one URL-aware text
/// renderer, used for every message bubble (incoming, outgoing, templates).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/external_link.dart';
import '../utils/text_links.dart';

class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    required this.linkColor,
    this.style,
    this.textDirection,
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

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  // Parsed when the text changes, not on every rebuild of a long thread.
  late List<TextLinkPart> _parts;
  late bool _rtl;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
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

  @override
  Widget build(BuildContext context) {
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
}
