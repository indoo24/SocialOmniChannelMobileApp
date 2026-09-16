/// Formatter for conversation previews in the Inbox list.
///
/// Converts internal media markers (e.g. `[[media:IMAGE]]`, `[[media:FILE]]`)
/// and structured attachment metadata into human-friendly, localized labels:
/// - Photo / Photos
/// - Voice message
/// - Video
/// - Document (or actual filename if available)
/// - Attachments
library;

import 'package:flutter/widgets.dart';

import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/models/message.dart';
import '../../l10n/generated/app_localizations.dart';

/// Utilities for formatting the latest message preview shown in Inbox conversation rows.
class ConversationPreviewFormatter {
  const ConversationPreviewFormatter._();

  /// Matches internal media markers like `[[media:IMAGE]]`, `[[media:FILE:spec.pdf]]`,
  /// `[media:AUDIO]`, etc.
  static final RegExp _mediaMarkerRegex = RegExp(
    r'\[{1,2}\s*media:\s*([A-Za-z0-9_-]+)(?:[:,\s]([^\]]+))?\s*\]{1,2}',
    caseSensitive: false,
  );

  /// Strips all media markers from [text] and trims whitespace.
  static String stripMediaMarkers(String text) {
    if (text.isEmpty) return '';
    return text.replaceAll(_mediaMarkerRegex, '').trim();
  }

  /// Formats the conversation preview text using either structured [attachments]
  /// or by parsing [rawPreview] for media markers.
  ///
  /// Returns an empty string if [rawPreview] is empty and no attachments exist.
  static String format({
    required AppLocalizations l10n,
    String rawPreview = '',
    List<MessageAttachment> attachments = const [],
  }) {
    final cleanText = stripMediaMarkers(rawPreview);

    // 1. If structured attachment metadata is present, prioritize it.
    if (attachments.isNotEmpty) {
      // If there is accompanying text, preserve it per UI rules.
      if (cleanText.isNotEmpty) {
        return cleanText;
      }

      if (attachments.length > 1) {
        final allImages = attachments.every((a) => a.isImage);
        return allImages
            ? l10n.photosMessageLabel
            : l10n.attachmentsMessageLabel;
      }

      final attachment = attachments.first;
      if (attachment.isImage) {
        return l10n.photoMessageLabel;
      }
      if (attachment.isVoice) {
        return l10n.voiceMessageLabel;
      }
      if (attachment.isVideo) {
        return l10n.videoMessageLabel;
      }
      if (attachment.isDocument) {
        if (attachment.fileName.trim().isNotEmpty) {
          return attachment.fileName.trim();
        }
        return l10n.documentMessageLabel;
      }

      return l10n.attachmentsMessageLabel;
    }

    // 2. Fallback: Parse raw preview string for media markers.
    final matches = _mediaMarkerRegex.allMatches(rawPreview).toList();
    if (matches.isEmpty) {
      return rawPreview.trim();
    }

    // If there is accompanying text alongside the media markers, show it.
    if (cleanText.isNotEmpty) {
      return cleanText;
    }

    // When there is no accompanying text, translate the marker(s).
    if (matches.length > 1) {
      final allImages = matches.every((m) {
        final type = (m.group(1) ?? '').toUpperCase();
        return type == 'IMAGE' || type == 'PHOTO';
      });
      return allImages ? l10n.photosMessageLabel : l10n.attachmentsMessageLabel;
    }

    final match = matches.first;
    final type = (match.group(1) ?? '').toUpperCase();
    final param = _extractParam(match.group(2));

    switch (type) {
      case 'IMAGE':
      case 'PHOTO':
        return l10n.photoMessageLabel;
      case 'AUDIO':
      case 'VOICE':
        return l10n.voiceMessageLabel;
      case 'VIDEO':
        return l10n.videoMessageLabel;
      case 'FILE':
      case 'DOCUMENT':
      case 'DOC':
        if (param.isNotEmpty) {
          return param;
        }
        return l10n.documentMessageLabel;
      default:
        return l10n.attachmentsMessageLabel;
    }
  }

  /// Extracts and cleans filename or parameter string from marker groups.
  static String _extractParam(String? raw) {
    if (raw == null) return '';
    var cleaned = raw.trim();
    if (cleaned.toLowerCase().startsWith('name=')) {
      cleaned = cleaned.substring(5).trim();
    } else if (cleaned.toLowerCase().startsWith('filename=')) {
      cleaned = cleaned.substring(9).trim();
    }
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  /// Formats the preview for a standalone [Conversation].
  static String formatConversation({
    required BuildContext context,
    required Conversation conversation,
  }) {
    final l10n = AppLocalizations.of(context);
    final formatted = format(
      l10n: l10n,
      rawPreview: conversation.lastMessagePreview,
      attachments: conversation.lastMessageAttachments,
    );
    return formatted.isEmpty ? l10n.noMessagesYetPreview : formatted;
  }

  /// Formats the preview for a [CustomerConversationGroup].
  static String formatGroup({
    required BuildContext context,
    required CustomerConversationGroup group,
  }) {
    final l10n = AppLocalizations.of(context);
    final formatted = format(
      l10n: l10n,
      rawPreview: group.lastMessagePreview,
      attachments: group.lastMessageAttachments,
    );
    return formatted.isEmpty ? l10n.noMessagesYetPreview : formatted;
  }
}

/// Convenience top-level helper for formatting inbox previews in widgets.
String formatConversationPreview(
  BuildContext context, {
  Conversation? conversation,
  CustomerConversationGroup? group,
  String? preview,
  List<MessageAttachment>? attachments,
}) {
  if (group != null) {
    return ConversationPreviewFormatter.formatGroup(
      context: context,
      group: group,
    );
  }
  if (conversation != null) {
    return ConversationPreviewFormatter.formatConversation(
      context: context,
      conversation: conversation,
    );
  }
  final l10n = AppLocalizations.of(context);
  final formatted = ConversationPreviewFormatter.format(
    l10n: l10n,
    rawPreview: preview ?? '',
    attachments: attachments ?? const [],
  );
  return formatted.isEmpty ? l10n.noMessagesYetPreview : formatted;
}
