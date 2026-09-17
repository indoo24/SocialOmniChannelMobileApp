import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/features/conversations/conversation_preview_formatter.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

void main() {
  late AppLocalizations l10nEn;
  late AppLocalizations l10nAr;

  setUpAll(() async {
    l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
    l10nAr = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  group('ConversationPreviewFormatter - Structured attachments', () {
    test('single image attachment formats to Photo / صورة', () {
      final attachments = [
        const MessageAttachment(type: 'IMAGE', fileName: 'pic.png'),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: attachments,
        ),
        'Photo',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          attachments: attachments,
        ),
        'صورة',
      );
    });

    test('single image attachment preserves accompanying text', () {
      final attachments = [
        const MessageAttachment(type: 'IMAGE', fileName: 'pic.png'),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: 'Check this design out',
          attachments: attachments,
        ),
        'Check this design out',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: 'انظر إلى هذا التصميم',
          attachments: attachments,
        ),
        'انظر إلى هذا التصميم',
      );
    });

    test(
      'single image attachment with marker stripped preserves accompanying text',
      () {
        final attachments = [
          const MessageAttachment(type: 'IMAGE', fileName: 'pic.png'),
        ];

        expect(
          ConversationPreviewFormatter.format(
            l10n: l10nEn,
            rawPreview: '[[media:IMAGE]] Check this design out',
            attachments: attachments,
          ),
          'Check this design out',
        );
      },
    );

    test('voice and audio messages format to Voice message / رسالة صوتية', () {
      final audioAttachment = [
        const MessageAttachment(type: 'AUDIO', durationMs: 5000),
      ];
      final voiceAttachment = [
        const MessageAttachment(type: 'VOICE', durationMs: 3200),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: audioAttachment,
        ),
        'Voice message',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          attachments: audioAttachment,
        ),
        'رسالة صوتية',
      );

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: voiceAttachment,
        ),
        'Voice message',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          attachments: voiceAttachment,
        ),
        'رسالة صوتية',
      );
    });

    test('video attachment formats to Video / فيديو', () {
      final videoAttachment = [
        const MessageAttachment(type: 'VIDEO', fileName: 'clip.mp4'),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: videoAttachment,
        ),
        'Video',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          attachments: videoAttachment,
        ),
        'فيديو',
      );
    });

    test('document attachment formats to actual filename when available', () {
      final docWithFilename = [
        const MessageAttachment(type: 'FILE', fileName: 'invoice_2026.pdf'),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: docWithFilename,
        ),
        'invoice_2026.pdf',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          attachments: docWithFilename,
        ),
        'invoice_2026.pdf',
      );
    });

    test(
      'document attachment formats to Document / مستند when filename is missing',
      () {
        final docWithoutFilename = [
          const MessageAttachment(type: 'FILE', fileName: ''),
        ];

        expect(
          ConversationPreviewFormatter.format(
            l10n: l10nEn,
            attachments: docWithoutFilename,
          ),
          'Document',
        );
        expect(
          ConversationPreviewFormatter.format(
            l10n: l10nAr,
            attachments: docWithoutFilename,
          ),
          'مستند',
        );
      },
    );

    test('multiple images format to Photos / صور', () {
      final images = [
        const MessageAttachment(type: 'IMAGE', fileName: '1.jpg'),
        const MessageAttachment(type: 'IMAGE', fileName: '2.jpg'),
      ];

      expect(
        ConversationPreviewFormatter.format(l10n: l10nEn, attachments: images),
        'Photos',
      );
      expect(
        ConversationPreviewFormatter.format(l10n: l10nAr, attachments: images),
        'صور',
      );
    });

    test(
      'multiple attachments of mixed types format to Attachments / مرفقات',
      () {
        final mixed = [
          const MessageAttachment(type: 'IMAGE', fileName: 'photo.jpg'),
          const MessageAttachment(type: 'FILE', fileName: 'doc.pdf'),
        ];

        expect(
          ConversationPreviewFormatter.format(l10n: l10nEn, attachments: mixed),
          'Attachments',
        );
        expect(
          ConversationPreviewFormatter.format(l10n: l10nAr, attachments: mixed),
          'مرفقات',
        );
      },
    );

    test('MIME types are correctly detected over generic types', () {
      final imageMime = [
        const MessageAttachment(type: 'FILE', mimeType: 'image/webp'),
      ];
      final videoMime = [
        const MessageAttachment(type: 'FILE', mimeType: 'video/quicktime'),
      ];
      final audioMime = [
        const MessageAttachment(type: 'FILE', mimeType: 'audio/mpeg'),
      ];

      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: imageMime,
        ),
        'Photo',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: videoMime,
        ),
        'Video',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          attachments: audioMime,
        ),
        'Voice message',
      );
    });
  });

  group('ConversationPreviewFormatter - String media marker fallbacks', () {
    test('parses [[media:IMAGE]] marker to Photo / صورة', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:IMAGE]]',
        ),
        'Photo',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:IMAGE]]',
        ),
        'صورة',
      );
    });

    test('preserves text when [[media:IMAGE]] has accompanying text', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:IMAGE]] Here is the receipt',
        ),
        'Here is the receipt',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: 'هذا هو الإيصال [[media:IMAGE]]',
        ),
        'هذا هو الإيصال',
      );
    });

    test(
      'parses [[media:VOICE]] and [[media:AUDIO]] to Voice message / رسالة صوتية',
      () {
        expect(
          ConversationPreviewFormatter.format(
            l10n: l10nEn,
            rawPreview: '[[media:VOICE]]',
          ),
          'Voice message',
        );
        expect(
          ConversationPreviewFormatter.format(
            l10n: l10nAr,
            rawPreview: '[[media:AUDIO]]',
          ),
          'رسالة صوتية',
        );
      },
    );

    test('parses [[media:VIDEO]] to Video / فيديو', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:VIDEO]]',
        ),
        'Video',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:VIDEO]]',
        ),
        'فيديو',
      );
    });

    test('parses [[media:FILE]] to Document / مستند', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:FILE]]',
        ),
        'Document',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:FILE]]',
        ),
        'مستند',
      );
    });

    test('extracts filename from [[media:FILE:filename]]', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:FILE:quarterly_report.pdf]]',
        ),
        'quarterly_report.pdf',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:FILE:contract.docx]]',
        ),
        'contract.docx',
      );
    });

    test('parses multiple image markers to Photos / صور', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:IMAGE]] [[media:IMAGE]]',
        ),
        'Photos',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:IMAGE]] [[media:IMAGE]]',
        ),
        'صور',
      );
    });

    test('parses multiple mixed markers to Attachments / مرفقات', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: '[[media:IMAGE]] [[media:FILE]]',
        ),
        'Attachments',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: '[[media:IMAGE]] [[media:FILE]]',
        ),
        'مرفقات',
      );
    });

    test('preserves plain text without markers unchanged', () {
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nEn,
          rawPreview: 'Can you help me with my order?',
        ),
        'Can you help me with my order?',
      );
      expect(
        ConversationPreviewFormatter.format(
          l10n: l10nAr,
          rawPreview: 'مرحبا، هل يمكنك مساعدتي؟',
        ),
        'مرحبا، هل يمكنك مساعدتي؟',
      );
    });

    test('returns empty string when raw preview is empty', () {
      expect(
        ConversationPreviewFormatter.format(l10n: l10nEn, rawPreview: ''),
        '',
      );
    });
  });

  group('Conversation and Group models integration', () {
    test('Conversation model parses last_message_attachments from JSON', () {
      final json = {
        'id': 10,
        'customer': {'id': 1, 'display_name': 'John'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'priority': 'NORMAL',
        'unread_count': 0,
        'message_count': 1,
        'last_message_preview': '[[media:IMAGE]]',
        'last_message_attachments': [
          {'type': 'IMAGE', 'file_name': 'photo.png', 'mime_type': 'image/png'},
        ],
      };

      final convo = Conversation.fromJson(json);
      expect(convo.lastMessageAttachments.length, 1);
      expect(convo.lastMessageAttachments.first.isImage, isTrue);
    });

    test(
      'CustomerConversationGroup inherits lastMessageAttachments from preview source',
      () {
        final convo1 = Conversation.fromJson({
          'id': 1,
          'customer': {'id': 100, 'display_name': 'Alice'},
          'provider': 'WHATSAPP',
          'status': 'OPEN',
          'priority': 'NORMAL',
          'unread_count': 0,
          'message_count': 0,
          'last_message_preview': '',
        });

        final convo2 = Conversation.fromJson({
          'id': 2,
          'customer': {'id': 100, 'display_name': 'Alice'},
          'provider': 'WHATSAPP',
          'status': 'OPEN',
          'priority': 'NORMAL',
          'unread_count': 1,
          'message_count': 1,
          'last_message_preview': '[[media:VOICE]]',
          'last_message_attachments': [
            {'type': 'VOICE', 'duration_ms': 4200, 'mime_type': 'audio/ogg'},
          ],
        });

        final group = CustomerConversationGroup(
          groupKey: 'WHATSAPP:100',
          customer: convo1.customer,
          provider: 'WHATSAPP',
          conversations: [convo1, convo2],
        );

        expect(group.lastMessageAttachments.length, 1);
        expect(group.lastMessageAttachments.first.isVoice, isTrue);
      },
    );
  });
}
