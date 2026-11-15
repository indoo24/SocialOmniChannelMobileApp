/// The large icon of a conversation notification: the customer's initials
/// on a coloured disc, with a small dot in the channel's brand colour —
/// the same initials-avatar the inbox shows when a customer has no photo.
///
/// Drawn locally rather than downloading `avatar_url`: a background push
/// has seconds to finish, platform avatar URLs (Meta's CDN) expire and
/// would leak the device's IP to a third party on every message, and the
/// payload carries no avatar field today anyway.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

class NotificationAvatar {
  const NotificationAvatar._();

  /// Pixel size. Android scales the large icon to ~48dp; 192px is 48dp at
  /// xxxhdpi, so it stays sharp on every density.
  static const size = 192;

  /// Calm, readable-with-white-text colours; one is picked per conversation
  /// so the same customer keeps the same colour across notifications.
  static const _palette = <int>[
    0xFF3A2CF0, // Scenario blue
    0xFF0F766E,
    0xFF7C3AED,
    0xFFB45309,
    0xFF0369A1,
    0xFFBE185D,
    0xFF4D7C0F,
    0xFF9333EA,
  ];

  /// The channel colours from `ConversationBadges.providerColor`.
  static int? providerColor(String provider) => switch (provider) {
    'WHATSAPP' => 0xFF25D366,
    'FACEBOOK' => 0xFF0866FF,
    'INSTAGRAM' => 0xFFE1306C,
    'TIKTOK' => 0xFF010101,
    _ => null,
  };

  static int backgroundFor(int conversationId) =>
      _palette[conversationId.abs() % _palette.length];

  /// PNG bytes, or null if drawing is unavailable or slow — the notification
  /// is then posted without a large icon rather than not at all.
  static Future<Uint8List?> render({
    required String initials,
    required int conversationId,
    required String provider,
  }) async {
    if (initials.isEmpty) return null;
    try {
      return await _draw(
        initials,
        conversationId,
        provider,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _draw(
    String initials,
    int conversationId,
    String provider,
  ) async {
    const s = size * 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, s, s));

    canvas.drawCircle(
      const ui.Offset(s / 2, s / 2),
      s / 2,
      ui.Paint()..color = ui.Color(backgroundFor(conversationId)),
    );

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: ui.TextAlign.center,
              fontSize: initials.length > 1 ? s * 0.36 : s * 0.42,
              fontWeight: ui.FontWeight.w600,
              maxLines: 1,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
          ..addText(initials);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: s));
    canvas.drawParagraph(paragraph, ui.Offset(0, (s - paragraph.height) / 2));

    final dot = providerColor(provider);
    if (dot != null) {
      // Bottom-end corner, ringed in white so it reads on any background.
      const r = s * 0.15;
      const centre = ui.Offset(s - r - s * 0.02, s - r - s * 0.02);
      canvas.drawCircle(
        centre,
        r + s * 0.03,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.drawCircle(centre, r, ui.Paint()..color = ui.Color(dot));
    }

    final image = await recorder.endRecording().toImage(size, size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
