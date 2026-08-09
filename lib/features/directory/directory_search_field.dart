/// App-bar search field shared by the directory screens.
///
/// Submit-to-search rather than search-as-you-type: on a phone every keystroke
/// is a request over mobile data, and the backend's `search` filter scans
/// several columns. The web client debounces instead because a keyboard is
/// faster than a thumb and the connection is usually not the constraint.
library;

import 'package:flutter/material.dart';

class DirectorySearchField extends StatefulWidget {
  const DirectorySearchField({
    required this.hint,
    required this.onSubmitted,
    super.key,
  });

  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  State<DirectorySearchField> createState() => _DirectorySearchFieldState();
}

class _DirectorySearchFieldState extends State<DirectorySearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
    );
  }
}
