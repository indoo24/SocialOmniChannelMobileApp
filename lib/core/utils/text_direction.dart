/// The direction a piece of user-written text runs in, judged from its own
/// words rather than the app's language — an Arabic message in the English
/// app, or an English one in the Arabic app.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

TextDirection textDirectionOf(String text) =>
    intl.Bidi.detectRtlDirectionality(text)
    ? TextDirection.rtl
    : TextDirection.ltr;

/// Aligns text laid out in its own direction ([textDirectionOf]) to the start
/// of the surrounding layout, so it lines up with its neighbours whichever
/// language it is in.
TextAlign ambientStartAlign(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? TextAlign.right
    : TextAlign.left;
