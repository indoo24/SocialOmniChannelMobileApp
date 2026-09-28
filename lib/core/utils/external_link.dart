/// The one way the app opens a web link outside itself — a link in a
/// message, a conversation's ad/post source, a shared TikTok post.
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';
import 'safe_url.dart';

/// Hands a link to the platform. Replaceable in tests.
@visibleForTesting
Future<bool> Function(Uri uri) launchExternalUrl = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [uri] in the browser, or in the app that owns the link (Instagram,
/// Facebook…), as the platform decides.
///
/// Re-checks [uri] with [SafeUrl.forLink] whatever the caller already
/// checked, and never throws: a refused link, no app to open it, or a
/// platform error is logged and reported as false — nothing raw reaches the
/// agent.
Future<bool> openExternalLink(Uri uri) async {
  if (SafeUrl.forLink(uri.toString()) == null) {
    AppLog.debug('ExternalLink', 'refused a ${uri.scheme}: link');
    return false;
  }
  try {
    final opened = await launchExternalUrl(uri);
    if (!opened) AppLog.debug('ExternalLink', 'no app to open ${uri.host}');
    return opened;
  } catch (error) {
    AppLog.debug('ExternalLink', 'opening ${uri.host} failed: $error');
    return false;
  }
}
