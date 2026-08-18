/// Decides whether a URL the *server* supplied may be fetched by the app.
///
/// ## Why a server-supplied URL is untrusted
///
/// `avatarUrl` and `MessageAttachment.url` arrive in API responses and
/// WebSocket payloads and go straight into `CachedNetworkImage`, which fetches
/// them without further inspection. Several of them did not originate with
/// Scenario's backend at all: a customer's avatar on WhatsApp or Instagram is
/// whatever that platform reported, which is ultimately whatever the customer
/// set. So "the backend returned it" is not the same as "we produced it".
///
/// An unchecked URL there gives an attacker one useful primitive: cause the
/// agent's device to make a request they choose. That leaks the device's IP,
/// its User-Agent and the fact that an agent is currently reading this
/// conversation, to a host of the attacker's choosing — a read receipt the
/// product never agreed to send. A `http://` URL additionally downgrades the
/// fetch to plaintext, sidestepping the transport guarantees the rest of the
/// app is built on. `file://` and `data:` are refused for the same reason:
/// neither is ever a legitimate remote avatar.
///
/// ## What this is not
///
/// Not an allowlist of *hosts*. Avatars legitimately live on Meta and Twilio
/// CDNs and the set changes as channels are added, so pinning hosts would
/// break the product on the next integration. This narrows the *scheme* — the
/// part that is genuinely invariant — and leaves host policy to the backend,
/// which is where knowledge of the channel integrations actually lives.
library;

import '../config/environment.dart';

class SafeUrl {
  const SafeUrl._();

  /// Returns [url] when it is safe to hand to an image loader, else `''`.
  ///
  /// Callers already treat empty as "no image" and fall back to initials, so
  /// a rejected URL degrades to the same thing a missing one does — no new
  /// branch at any call site, and never a broken-image glyph.
  static String forImage(String? url, {Environment? environment}) {
    if (url == null) return '';

    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return '';

    if (uri.scheme == 'https') return trimmed;

    // Cleartext is allowed only where cleartext is already the configured
    // transport — a local dev backend serving media over http. A release
    // build can never satisfy this: Environment.useTls is forced true there.
    final env = environment ?? Environment.current;
    if (uri.scheme == 'http' && !env.useTls && uri.host == env.host.split(':').first) {
      return trimmed;
    }

    return '';
  }
}
