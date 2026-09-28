/// Where a conversation came from: the Meta ad or post the customer clicked
/// before writing (Click-to-WhatsApp and its Messenger/Instagram
/// equivalents).
///
/// ## Contract
///
/// `GET /api/conversations/{id}/` returns it as `attribution` — "the first
/// and latest referral observed on this conversation", null when Meta
/// reported no click. The OpenAPI schema types the object as untyped
/// (`additionalProperties: {}`), so the keys below are the ones the shipped
/// web app reads (its conversation-source card), taken as the working
/// contract until the backend documents them:
///
/// * `attribution`: `first`, `latest`, `has_multiple`
/// * each referral: `id`, `source`, `platform_hint`, `source_url`,
///   `headline`, `summary`, `summary_truncated`, `observed_at`
///
/// Nothing else is read. Every key is optional and type-checked: a missing or
/// malformed value hides only its own piece of the card, and a malformed
/// attribution as a whole is simply no attribution — it can never stop a
/// conversation from loading.
library;

/// What kind of Meta source a referral was (`source`).
enum ReferralSource {
  /// `META_PAID_AD` — a paid ad.
  metaPaidAd,

  /// `META_ORGANIC_POST` — an organic post.
  metaOrganicPost,

  /// Anything else, or nothing: shown as "Source not reported".
  unknown,
}

/// One observed referral.
class ConversationReferral {
  const ConversationReferral({
    this.id,
    this.source = ReferralSource.unknown,
    this.platformHint = '',
    this.sourceUrl = '',
    this.headline = '',
    this.summary = '',
    this.summaryTruncated = false,
    this.observedAt,
  });

  /// Compared only to tell `first` and `latest` apart. Kept as text so a
  /// numeric and a string id from different payload versions still compare.
  final String? id;
  final ReferralSource source;

  /// `FACEBOOK` | `INSTAGRAM` | `WHATSAPP` as sent; anything else is kept
  /// but has no display name, so no "on …" suffix is shown for it.
  final String platformHint;
  final String sourceUrl;
  final String headline;
  final String summary;

  /// The backend cut [summary] short — shown with a trailing "…".
  final bool summaryTruncated;
  final DateTime? observedAt;

  /// A referral object, or null for anything that is not one.
  static ConversationReferral? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawId = json['id'];
    return ConversationReferral(
      id: rawId is String || rawId is num ? rawId.toString() : null,
      source: switch (json['source']) {
        'META_PAID_AD' => ReferralSource.metaPaidAd,
        'META_ORGANIC_POST' => ReferralSource.metaOrganicPost,
        _ => ReferralSource.unknown,
      },
      platformHint: _text(json['platform_hint']),
      sourceUrl: _text(json['source_url']),
      headline: _text(json['headline']),
      summary: _text(json['summary']),
      summaryTruncated: json['summary_truncated'] == true,
      observedAt: json['observed_at'] is String
          ? DateTime.tryParse(json['observed_at'] as String)?.toLocal()
          : null,
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  /// The platform's display name for [platformHint], or null when it is
  /// missing or not one the web app names.
  String? get platformName => switch (platformHint.toUpperCase()) {
    'FACEBOOK' => 'Facebook',
    'INSTAGRAM' => 'Instagram',
    'WHATSAPP' => 'WhatsApp',
    _ => null,
  };

  /// [sourceUrl] when it is safe to hand to the system browser — an `https`
  /// URL with a host, the same rule the TikTok shared-post link uses —
  /// otherwise null, and the card stays non-clickable.
  Uri? get openableUrl {
    if (sourceUrl.isEmpty) return null;
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}

/// `ConversationDetail.attribution`.
class ConversationAttribution {
  const ConversationAttribution({
    this.first,
    this.latest,
    this.hasMultiple = false,
  });

  final ConversationReferral? first;
  final ConversationReferral? latest;
  final bool hasMultiple;

  /// The attribution, or null when there is nothing to show — absent,
  /// malformed, or with neither `first` nor `latest` a referral.
  static ConversationAttribution? fromJson(Object? json) {
    if (json is! Map) return null;
    final first = ConversationReferral.fromJson(json['first']);
    final latest = ConversationReferral.fromJson(json['latest']);
    if (first == null && latest == null) return null;
    return ConversationAttribution(
      first: first,
      latest: latest,
      hasMultiple: json['has_multiple'] == true,
    );
  }

  /// What the card shows: `first ?? latest`, as the web app does.
  ConversationReferral get primary => (first ?? latest)!;

  /// The later referral, shown as "Most recent" under the card — only when
  /// the backend says there were several (`has_multiple`) and `latest` is a
  /// different referral from the one the card already shows. Mirrors the
  /// web's `has_multiple && latest && latest.id !== primary.id`.
  ConversationReferral? get mostRecent {
    final l = latest;
    if (!hasMultiple || l == null) return null;
    return l.id != primary.id ? l : null;
  }
}
