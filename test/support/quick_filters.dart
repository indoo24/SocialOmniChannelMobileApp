/// Reading the inbox's quick filter pills in widget tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the quick filter pill keyed [key] (`quick_filter_<name>`) is the
/// selected one — what it reports to assistive technology, which is how the
/// state is carried now that the pill has no check glyph: the pill's own
/// `Semantics(selected: …)`, its first `Semantics` descendant.
bool isQuickFilterSelected(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(
    find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Semantics))
        .first,
  );
  return semantics.properties.selected ?? false;
}
