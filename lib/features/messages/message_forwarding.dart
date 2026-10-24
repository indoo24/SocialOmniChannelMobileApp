/// Forwarding a message into another conversation.
///
/// ## What this is, and is not
///
/// The backend has **no forward endpoint** (`API.md`, the live OpenAPI, and
/// `docs/MOBILE_BACKEND_SYNC.md` R6). So a forward here is what an agent could
/// do by hand with the documented send flow, done for them:
///
///  1. each attachment of the original is downloaded
///     (`GET /attachments/{public_id}/content/`) and staged as a draft in the
///     *destination* conversation (`POST /conversations/{id}/attachments/`);
///  2. one ordinary reply is sent there (`POST /conversations/{id}/reply/`)
///     with the original's text and the draft ids.
///
/// It is therefore a **new message from the signed-in employee**, delivered
/// to the destination customer through the backend's own provider pipeline —
/// so the destination's permissions, its channel's attachment rules and the
/// WhatsApp 24-hour window are all enforced by the server, and a refusal comes
/// back as an error here. What it is *not*: the server does not record that it
/// was forwarded, who wrote the original, or which message it came from, and
/// the recipient sees no "forwarded" label. The app does not pretend
/// otherwise.
///
/// Nothing reaches the customer until the final reply: drafts are invisible,
/// so a failure while staging sends nothing. The reply carries a stable
/// `client_message_id`, so retrying a request whose answer was lost cannot
/// store the message twice.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/utils/attachment_helper.dart';
import '../../l10n/generated/app_localizations.dart';

/// Why a message cannot be forwarded at all.
enum ForwardBlock {
  /// A system line ("assigned to …"), not something anyone wrote.
  system,

  /// Still sending, failed, or otherwise not a stored message yet.
  notSent,

  /// A kind of content this cannot carry (a template, a sticker, a shared
  /// post).
  unsupported,

  /// No text and no attachment: nothing to send.
  nothingToSend,

  /// An attachment the server does not have ready to download.
  attachmentUnavailable,
}

/// The attachment kinds that are sent on: pictures, video, audio and voice
/// notes, and documents. An explicit list because the model's own
/// `isDocument` is true of *anything* that is not a picture, audio or video —
/// a sticker, a location, a contact card — which this must not pass as a file.
const _carriedTypes = {'IMAGE', 'VIDEO', 'AUDIO', 'VOICE', 'FILE', 'DOCUMENT'};

/// Whether [attachment] is a recorded voice note, as opposed to an audio
/// file. The model's own `isVoice` is true of *every* audio attachment, which
/// would send a song as a voice note, so this asks for what says so: the
/// `VOICE` type, or the platform's own `whatsapp_type: voice`. A voice note
/// the server describes in neither way goes on as the audio file it is
/// described as — the sound is the same, but the recipient's app shows it as
/// a file, not a voice note.
bool isVoiceNote(MessageAttachment attachment) =>
    attachment.type.toUpperCase() == 'VOICE' ||
    attachment.whatsappType.toLowerCase() == 'voice' ||
    attachment.metadata?['is_voice'] == true;

/// The reason [message] cannot be forwarded, or null when it can.
///
/// Decided from the message alone, before anything is asked of the server —
/// and refused rather than sent incomplete: a message with one good and one
/// unsupported attachment is not forwarded as half of itself.
ForwardBlock? forwardBlockOf(Message message) {
  if (message.isSystem) return ForwardBlock.system;
  if (message.isPending || message.hasFailed || message.id < 0) {
    return ForwardBlock.notSent;
  }
  if (message.messageType.toUpperCase() == 'TEMPLATE') {
    return ForwardBlock.unsupported;
  }
  for (final attachment in message.attachments) {
    if (!_carriedTypes.contains(attachment.type.toUpperCase())) {
      return ForwardBlock.unsupported;
    }
    if (!attachment.isReady) return ForwardBlock.attachmentUnavailable;
  }
  if (message.text.trim().isEmpty && message.attachments.isEmpty) {
    return ForwardBlock.nothingToSend;
  }
  return null;
}

/// What was said to the agent for a message that cannot be forwarded.
String forwardBlockMessage(AppLocalizations l10n, ForwardBlock block) =>
    switch (block) {
      ForwardBlock.system => l10n.forwardBlockedSystem,
      ForwardBlock.notSent => l10n.forwardBlockedNotSent,
      ForwardBlock.unsupported => l10n.forwardBlockedUnsupported,
      ForwardBlock.nothingToSend => l10n.forwardBlockedNothing,
      ForwardBlock.attachmentUnavailable => l10n.forwardAttachmentUnavailable,
    };

/// A forward that could not be carried out for a reason of its own, as
/// opposed to the server refusing a request ([ApiException]).
class ForwardException implements Exception {
  const ForwardException(this.block);

  final ForwardBlock block;

  @override
  String toString() => 'ForwardException(${block.name})';
}

/// What to tell the agent after a failed forward. Never the raw exception.
///
/// A `400` is the server's refusal of *this message to this conversation* —
/// a closed WhatsApp 24-hour window, an expired token, a file the channel
/// cannot carry — and its message is written to be shown, so it is. The other
/// statuses are named in the app's own words.
String forwardErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ForwardException) return forwardBlockMessage(l10n, error.block);
  if (error is ApiException) {
    if (error is NetworkException || error.statusCode >= 500) {
      return l10n.forwardFailedMessage;
    }
    return switch (error.statusCode) {
      400 =>
        error.message.trim().isNotEmpty
            ? error.message.trim()
            : l10n.forwardDestinationRefusedMessage,
      403 => l10n.forwardPermissionDeniedMessage,
      404 => l10n.forwardDestinationGoneMessage,
      429 => l10n.forwardTooManyMessage,
      _ => l10n.forwardFailedMessage,
    };
  }
  return l10n.forwardFailedMessage;
}

/// Fetches an attachment's bytes onto the device (the cache, when it is
/// already there). Null when it cannot be had. Replaceable in tests.
typedef ForwardAttachmentFetcher =
    Future<File?> Function(MessageAttachment attachment, int messageId);

final forwardAttachmentFetcherProvider = Provider<ForwardAttachmentFetcher>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return (attachment, messageId) => AttachmentHelper.downloadAttachmentFile(
    attachment: attachment,
    api: api,
    messageId: messageId,
  );
});

class MessageForwarder {
  MessageForwarder(this._ref);

  final Ref _ref;

  /// Sends [message]'s text and attachments to [destinationConversationId] as
  /// a new message, and returns what the server stored.
  ///
  /// [clientMessageId] is the idempotency key for the final send: the same
  /// key on a retry returns the already-stored message instead of a second
  /// one. Throws [ForwardException] for a message that cannot be forwarded,
  /// and the server's [ApiException] for a refusal — in both cases after
  /// discarding whatever drafts were staged, with nothing sent.
  Future<Message> forward({
    required Message message,
    required int destinationConversationId,
    required String clientMessageId,
  }) async {
    final block = forwardBlockOf(message);
    if (block != null) throw ForwardException(block);

    final repository = _ref.read(conversationRepositoryProvider);
    final fetch = _ref.read(forwardAttachmentFetcherProvider);
    final staged = <String>[];

    try {
      for (final attachment in message.attachments) {
        final file = await fetch(attachment, message.id);
        if (file == null) {
          throw const ForwardException(ForwardBlock.attachmentUnavailable);
        }
        final name = attachment.fileName.isNotEmpty
            ? attachment.fileName
            : AttachmentHelper.suggestFileName(attachment);
        final draft = await repository.stageAttachment(
          destinationConversationId,
          filePath: file.path,
          fileName: name,
          // A voice note stays one: the server repackages it as the channel's
          // voice container only when told.
          isVoice: isVoiceNote(attachment),
          durationMs: isVoiceNote(attachment) ? attachment.durationMs : null,
          mimeType: AttachmentHelper.resolveMimeType(attachment, file.path),
        );
        staged.add(draft.id);
      }

      return await repository.reply(
        destinationConversationId,
        message.text.trim(),
        attachmentIds: staged,
        clientMessageId: clientMessageId,
      );
    } catch (_) {
      // Drafts are invisible to the customer, but they hold bytes on the
      // server until they expire: put them away. Best effort — a failure to
      // discard must not hide why the forward failed.
      for (final id in staged) {
        try {
          await repository.discardAttachment(destinationConversationId, id);
        } on Object {
          // It expires on its own.
        }
      }
      rethrow;
    }
  }
}

final messageForwarderProvider = Provider<MessageForwarder>(
  MessageForwarder.new,
);
