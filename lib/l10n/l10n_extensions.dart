/// `context.l10n.someString` instead of `AppLocalizations.of(context)` at
/// every call site.
library;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
