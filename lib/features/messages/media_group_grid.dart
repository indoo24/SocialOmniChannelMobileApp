import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/safe_url.dart';

/// A WhatsApp-style responsive collage grid for multiple image attachments
/// sent together in the same media batch.
///
/// Supports:
/// - 2 images: 2 equal-width side-by-side columns.
/// - 3 images: 1 prominent start-side tile (flex: 3), 2 stacked end-side tiles (flex: 2).
/// - 4 images: 2x2 grid.
/// - >4 images: 2x2 grid showing the first 3 images, with a `+N` count overlay
///   on the 4th tile. Tapping opens the gallery viewer allowing the user to
///   browse all images in the group.
class MediaGroupGrid extends ConsumerWidget {
  const MediaGroupGrid({
    required this.attachments,
    this.messageId,
    this.isOutbound = false,
    this.onTapImage,
    super.key,
  });

  final List<MessageAttachment> attachments;
  final int? messageId;
  final bool isOutbound;
  final void Function(int index)? onTapImage;

  static const double maxGridWidth = 240.0;
  static const double gap = 3.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final count = attachments.length;
    final totalHeight = count == 2 ? 150.0 : 180.0;

    return FutureBuilder<Map<String, String>>(
      future: ref.read(apiClientProvider).mediaAuthHeaders(),
      builder: (context, snapshot) {
        final headers = snapshot.data ?? const {};

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxGridWidth),
          child: SizedBox(
            height: totalHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: _buildLayout(context, headers),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayout(BuildContext context, Map<String, String> headers) {
    final count = attachments.length;

    if (count == 2) {
      return _buildTwoImageLayout(headers);
    } else if (count == 3) {
      return _buildThreeImageLayout(context, headers);
    } else {
      return _buildFourOrMoreLayout(context, headers);
    }
  }

  /// 2 images side-by-side.
  Widget _buildTwoImageLayout(Map<String, String> headers) {
    const tileHeight = 150.0;

    return SizedBox(
      height: tileHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildTile(0, headers)),
          const SizedBox(width: gap),
          Expanded(child: _buildTile(1, headers)),
        ],
      ),
    );
  }

  /// 3 images: 1 large tile at start (flex 3), 2 stacked tiles at end (flex 2).
  /// Respects Directionality so in RTL, the large tile is on the start (right).
  Widget _buildThreeImageLayout(
    BuildContext context,
    Map<String, String> headers,
  ) {
    const totalHeight = 180.0;

    return SizedBox(
      height: totalHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _buildTile(0, headers),
          ),
          const SizedBox(width: gap),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTile(1, headers)),
                const SizedBox(height: gap),
                Expanded(child: _buildTile(2, headers)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4 or more images: 2x2 grid.
  /// If > 4, shows a `+N` badge on the 4th visible tile.
  Widget _buildFourOrMoreLayout(
    BuildContext context,
    Map<String, String> headers,
  ) {
    const totalHeight = 180.0;
    final overflowCount = attachments.length - 3;

    return SizedBox(
      height: totalHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTile(0, headers)),
                const SizedBox(width: gap),
                Expanded(child: _buildTile(1, headers)),
              ],
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTile(2, headers)),
                const SizedBox(width: gap),
                Expanded(
                  child: _buildTile(
                    3,
                    headers,
                    overlayText:
                        attachments.length > 4 ? '+$overflowCount' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    int index,
    Map<String, String> headers, {
    String? overlayText,
  }) {
    if (index >= attachments.length) return const SizedBox.shrink();
    final attachment = attachments[index];

    return GestureDetector(
      onTap: () => onTapImage?.call(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImageContent(attachment, headers),
          if (overlayText != null)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              alignment: Alignment.center,
              child: Text(
                overlayText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageContent(
    MessageAttachment attachment,
    Map<String, String> headers,
  ) {
    final localPath = attachment.localFilePath;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildErrorTile(),
      );
    }

    final safeUrl = SafeUrl.forImage(attachment.resolvedUrl);
    if (safeUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: safeUrl,
        httpHeaders: headers,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: Colors.black.withValues(alpha: 0.05),
          child: const Center(
            child: Icon(
              Icons.image_outlined,
              color: Colors.black26,
              size: 24,
            ),
          ),
        ),
        errorWidget: (_, _, _) => _buildErrorTile(),
      );
    }

    return _buildErrorTile();
  }

  Widget _buildErrorTile() {
    return Container(
      color: Colors.black.withValues(alpha: 0.05),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.black38,
          size: 28,
        ),
      ),
    );
  }
}

/// Groups contiguous messages that belong to the same outgoing/incoming media batch
/// into a single composite [Message] for collage rendering.
///
/// Only messages sharing the same non-empty [Message.baseClientMessageId] and containing
/// only image attachments are grouped together.
List<Message> groupMediaBatchMessages(List<Message> messages) {
  if (messages.isEmpty) return messages;
  final result = <Message>[];
  var i = 0;
  while (i < messages.length) {
    final current = messages[i];
    final batchKey = current.baseClientMessageId;
    if (batchKey == null || !current.hasOnlyImages) {
      result.add(current);
      i++;
      continue;
    }
    final batch = <Message>[current];
    var j = i + 1;
    while (j < messages.length) {
      final next = messages[j];
      if (next.baseClientMessageId == batchKey &&
          next.direction == current.direction &&
          next.hasOnlyImages) {
        batch.add(next);
        j++;
      } else {
        break;
      }
    }
    if (batch.length == 1) {
      result.add(current);
      i++;
    } else {
      final primary = batch.first;
      final allAttachments = <MessageAttachment>[
        for (final m in batch) ...m.attachments,
      ];
      final caption = batch
          .map((m) => m.text.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');

      final hasFailed = batch.any((m) => m.hasFailed || m.isDeliveryFailure);
      final isPending = batch.any((m) => m.isPending);
      final latest = batch.last;
      final failedMsg = batch.firstWhere(
        (m) => m.hasFailed || m.isDeliveryFailure,
        orElse: () => latest,
      );

      final status = hasFailed
          ? 'FAILED'
          : (isPending ? 'PENDING' : latest.deliveryStatus);
      final sendState = hasFailed
          ? SendState.failed
          : (isPending ? SendState.sending : latest.sendState);
      final error = hasFailed ? failedMsg.deliveryError : '';
      final errorCode = hasFailed ? failedMsg.deliveryErrorCode : '';

      final deliveredAt =
          batch.map((m) => m.deliveredAt).whereType<DateTime>().lastOrNull;
      final readAt =
          batch.map((m) => m.readAt).whereType<DateTime>().lastOrNull;

      final allMemberIds =
          batch.map((m) => m.id).where((id) => id > 0).toList();

      result.add(
        primary.copyWith(
          text: caption,
          attachments: allAttachments,
          deliveryStatus: status,
          sendState: sendState,
          deliveryError: error,
          deliveryErrorCode: errorCode,
          deliveredAt: deliveredAt,
          readAt: readAt,
          memberMessageIds: allMemberIds,
        ),
      );
      i = j;
    }
  }
  return result;
}

