/// Model for WhatsApp message templates.
///
/// Mirrors the backend's `TemplateSummary` schema from
/// `apps.integrations.services.whatsapp_templates`.
library;

import '../utils/json_safe.dart';
import '../widgets/badges.dart';

class WhatsAppTemplate {
  const WhatsAppTemplate({
    required this.id,
    required this.name,
    required this.language,
    required this.category,
    required this.status,
    this.body = '',
    this.rejectedReason = '',
    this.variables = 0,
    this.canSend = false,
    this.unsupported = const [],
  });

  final String id;
  final String name;
  final String language;
  final String category;
  final String status;
  final String body;
  final String rejectedReason;
  final int variables;
  final bool canSend;
  final List<String> unsupported;

  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isRejected => status.toUpperCase() == 'REJECTED';

  BadgeTone get statusTone => switch (status.toUpperCase()) {
    'APPROVED' => BadgeTone.success,
    'PENDING' => BadgeTone.warning,
    'REJECTED' => BadgeTone.danger,
    _ => BadgeTone.neutral,
  };

  factory WhatsAppTemplate.fromJson(Map<String, dynamic> json) =>
      WhatsAppTemplate(
        id: JsonSafe.asString(json['id']),
        name: JsonSafe.asString(json['name']),
        language: JsonSafe.asString(json['language']),
        category: JsonSafe.asString(json['category']),
        status: JsonSafe.asString(json['status'], fallback: 'PENDING'),
        body: JsonSafe.asString(json['body']),
        rejectedReason: JsonSafe.asString(json['rejected_reason']),
        variables: JsonSafe.asInt(json['variables']),
        canSend: JsonSafe.asBool(json['can_send']),
        unsupported:
            (json['unsupported'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'language': language,
    'category': category,
    'status': status,
    'body': body,
    'rejected_reason': rejectedReason,
    'variables': variables,
    'can_send': canSend,
    'unsupported': unsupported,
  };
}
