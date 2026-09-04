/// Templates repository.
///
/// Talks to the WhatsApp templates endpoints documented in
/// `apps.integrations.meta_views` and `apps.conversations.views`.
library;

import '../../core/api/api_client.dart';
import '../../core/models/template.dart';

class TemplatesRepository {
  const TemplatesRepository(this._api);

  final ApiClient _api;

  /// Fetches the message templates belonging to this channel's WABA.
  ///
  /// Live read from Meta Graph API via `GET /api/integrations/whatsapp/{id}/templates/`.
  Future<List<WhatsAppTemplate>> listTemplates(int channelId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/integrations/whatsapp/$channelId/templates/',
    );
    final raw = data['templates'] as List<dynamic>? ?? [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WhatsAppTemplate.fromJson)
        .toList(growable: false);
  }

  /// Submits a new BODY-only template to Meta for review.
  ///
  /// Calls `POST /api/integrations/whatsapp/{id}/templates/`.
  /// Requires `channel.manage` capability.
  Future<WhatsAppTemplate> createTemplate(
    int channelId, {
    required String name,
    required String category,
    required String language,
    required String body,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/$channelId/templates/',
      body: {
        'name': name.trim().toLowerCase(),
        'category': category.trim().toUpperCase(),
        'language': language.trim(),
        'body': body.trim(),
      },
    );
    return WhatsAppTemplate.fromJson(data);
  }

  /// Sends an approved template into an existing conversation.
  ///
  /// Calls `POST /api/conversations/{id}/send-template/`.
  /// Requires `conversation.reply` capability.
  Future<Map<String, dynamic>> sendConversationTemplate(
    int conversationId, {
    required String templateName,
    required String language,
    List<String> parameters = const [],
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/conversations/$conversationId/send-template/',
      body: {
        'template_name': templateName,
        'language': language,
        'parameters': parameters,
      },
    );
  }

  /// Sends an approved template outbound to a customer or phone number.
  ///
  /// Calls `POST /api/integrations/whatsapp/{id}/templates/send/`.
  /// Requires `channel.view` + `conversation.reply`.
  Future<Map<String, dynamic>> sendOutboundTemplate(
    int channelId, {
    int? customerId,
    String? phone,
    required String templateName,
    required String language,
    List<String> parameters = const [],
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/$channelId/templates/send/',
      body: {
        'customer_id': ?customerId,
        'phone': ?phone,
        'template_name': templateName,
        'language': language,
        'parameters': parameters,
      },
    );
  }
}
