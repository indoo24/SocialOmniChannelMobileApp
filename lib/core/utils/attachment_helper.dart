/// Helper utilities for downloading, saving, and opening attachments.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/message.dart';
import '../../l10n/l10n_extensions.dart';

class AttachmentHelper {
  const AttachmentHelper._();

  /// Pluggable runner for opening files via OpenFilex, overridable in tests.
  @visibleForTesting
  static Future<OpenResult> Function(String filePath, {String? type})
  openFileRunner = OpenFilex.open;

  /// Resolves the best directory for saving user-accessible files on the platform.
  /// Follows modern Android Scoped Storage requirements without using deprecated
  /// unrestricted external-storage paths.
  static Future<Directory> getAccessibleDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null && downloads.existsSync()) return downloads;
    } catch (_) {}

    try {
      final external = await getExternalStorageDirectory();
      if (external != null && external.existsSync()) return external;
    } catch (_) {}

    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {}

    try {
      return await getTemporaryDirectory();
    } catch (_) {}

    return Directory.systemTemp;
  }

  /// Sanitizes and ensures a unique filename in [directory].
  static String getUniqueFilePath(Directory directory, String baseName) {
    var sanitized = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty) sanitized = 'file';

    final dotIndex = sanitized.lastIndexOf('.');
    final name = dotIndex != -1 ? sanitized.substring(0, dotIndex) : sanitized;
    final ext = dotIndex != -1 ? sanitized.substring(dotIndex) : '';

    var targetPath = '${directory.path}/$sanitized';
    var file = File(targetPath);
    var counter = 1;

    while (file.existsSync()) {
      targetPath = '${directory.path}/$name ($counter)$ext';
      file = File(targetPath);
      counter++;
    }

    return targetPath;
  }

  /// Suggests a filename for [attachment] based on its name, type, and MIME.
  static String suggestFileName(MessageAttachment attachment) {
    if (attachment.fileName.trim().isNotEmpty) {
      return attachment.fileName.trim();
    }

    final ext = switch (attachment.type.toUpperCase()) {
      'IMAGE' => '.jpg',
      'AUDIO' || 'VOICE' => '.m4a',
      'VIDEO' => '.mp4',
      _ => _extensionFromMime(attachment.mimeType),
    };

    final prefix = switch (attachment.type.toUpperCase()) {
      'IMAGE' => 'photo',
      'AUDIO' || 'VOICE' => 'voice_note',
      'VIDEO' => 'video',
      _ => 'document',
    };

    final id = attachment.attachmentId.isNotEmpty
        ? attachment.attachmentId
        : DateTime.now().millisecondsSinceEpoch.toString();

    return '$prefix$id$ext';
  }

  static String _extensionFromMime(String mime) {
    final lower = mime.toLowerCase();
    if (lower.contains('pdf')) return '.pdf';
    if (lower.contains('word') || lower.contains('docx')) return '.docx';
    if (lower.contains('excel') ||
        lower.contains('sheet') ||
        lower.contains('xlsx')) {
      return '.xlsx';
    }
    if (lower.contains('presentation') || lower.contains('pptx')) {
      return '.pptx';
    }
    if (lower.contains('zip')) return '.zip';
    if (lower.contains('jpeg') || lower.contains('jpg')) return '.jpg';
    if (lower.contains('png')) return '.png';
    if (lower.contains('text') || lower.contains('txt')) return '.txt';
    return '';
  }

  /// Resolves the proper MIME type for opening [attachment] at [filePath].
  static String resolveMimeType(MessageAttachment attachment, String filePath) {
    if (attachment.mimeType.isNotEmpty &&
        attachment.mimeType != 'application/octet-stream') {
      return attachment.mimeType.trim();
    }
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.pdf')) return 'application/pdf';
    if (lowerPath.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lowerPath.endsWith('.doc')) return 'application/msword';
    if (lowerPath.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lowerPath.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lowerPath.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lowerPath.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lowerPath.endsWith('.zip')) return 'application/zip';
    if (lowerPath.endsWith('.txt')) return 'text/plain';
    if (lowerPath.endsWith('.csv')) return 'text/csv';
    if (lowerPath.endsWith('.png')) return 'image/png';
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerPath.endsWith('.mp4')) return 'video/mp4';
    if (lowerPath.endsWith('.mp3')) return 'audio/mpeg';
    if (lowerPath.endsWith('.m4a')) return 'audio/mp4';
    if (lowerPath.endsWith('.ogg')) return 'audio/ogg';
    return attachment.mimeType.isNotEmpty ? attachment.mimeType : '';
  }

  /// Returns the dedicated local caching directory for downloaded attachments.
  static Future<Directory> getAttachmentsDirectory() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      try {
        base = await getTemporaryDirectory();
      } catch (_) {
        base = Directory.systemTemp;
      }
    }
    final dir = Directory('${base.path}/attachments');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Generates a deterministic cache file path for [attachment].
  static Future<File> getCachedAttachmentFile(
    MessageAttachment attachment,
  ) async {
    final dir = await getAttachmentsDirectory();
    final fileName = suggestFileName(attachment);
    final key = attachment.attachmentId.isNotEmpty
        ? attachment.attachmentId
        : attachment.resolvedUrl.hashCode.abs().toString();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/${key}_$safeName');
  }

  /// Checks if [attachment] is already downloaded and available locally.
  static Future<File?> findLocalAttachment(MessageAttachment attachment) async {
    final localPath = attachment.localFilePath;
    if (localPath != null && localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (localFile.existsSync() && localFile.lengthSync() > 0) {
        return localFile;
      }
    }

    final cachedFile = await getCachedAttachmentFile(attachment);
    if (cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
      return cachedFile;
    }

    return null;
  }

  /// Downloads the attachment bytes using [api] (including authentication cookies)
  /// or returns existing local file if already downloaded and cached locally.
  static Future<File?> downloadAttachmentFile({
    required MessageAttachment attachment,
    required ApiClient api,
  }) async {
    // Return existing local or cached file immediately without re-downloading
    final local = await findLocalAttachment(attachment);
    if (local != null) return local;

    final url = attachment.resolvedUrl;
    if (url.isEmpty) return null;

    final response = await api.raw.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (response.statusCode != 200 && response.statusCode != 206) return null;
    if (bytes == null || bytes.isEmpty) return null;

    final targetFile = await getCachedAttachmentFile(attachment);
    targetFile.writeAsBytesSync(bytes, flush: true);
    return targetFile;
  }

  /// Downloads [attachment] (if not already local) and immediately opens it
  /// with the default device application (e.g. default PDF viewer).
  static Future<void> openAttachment({
    required BuildContext context,
    required MessageAttachment attachment,
    required ApiClient api,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final alreadyDownloaded = await findLocalAttachment(attachment) != null;
      if (!alreadyDownloaded && context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.downloadingAttachmentMessage),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      final file = await downloadAttachmentFile(
        attachment: attachment,
        api: api,
      );

      if (file == null || !file.existsSync() || file.lengthSync() == 0) {
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.attachmentDownloadError),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final mime = resolveMimeType(attachment, file.path);
      final openResult = await openFileRunner(
        file.path,
        type: mime.isNotEmpty ? mime : null,
      );

      if (openResult.type == ResultType.noAppToOpen) {
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.noAppToOpenFileError),
            action: SnackBarAction(
              label: context.l10n.openFileAction,
              onPressed: () => openFileRunner(
                file.path,
                type: mime.isNotEmpty ? mime : null,
              ),
            ),
          ),
        );
      } else if (openResult.type == ResultType.error ||
          openResult.type == ResultType.permissionDenied) {
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              openResult.message.isNotEmpty
                  ? openResult.message
                  : context.l10n.attachmentDownloadError,
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else if (openResult.type == ResultType.done) {
        if (context.mounted) {
          messenger.hideCurrentSnackBar();
        }
      }
    } catch (_) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.attachmentDownloadError),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Saves [attachment] directly to user-accessible Downloads and notifies the user.
  static Future<void> saveAttachmentToDownloads({
    required BuildContext context,
    required MessageAttachment attachment,
    required ApiClient api,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final local = await findLocalAttachment(attachment);
      Uint8List bytes;
      if (local != null) {
        bytes = await local.readAsBytes();
      } else {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(context.l10n.downloadingAttachmentMessage),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        final downloaded = await downloadAttachmentFile(
          attachment: attachment,
          api: api,
        );

        if (downloaded == null || !downloaded.existsSync()) {
          throw StateError('Download failed');
        }
        bytes = await downloaded.readAsBytes();
      }

      final dir = await getAccessibleDirectory();
      final fileName = suggestFileName(attachment);
      final targetPath = getUniqueFilePath(dir, fileName);
      final file = File(targetPath);
      file.writeAsBytesSync(bytes, flush: true);

      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.attachmentDownloadSuccess(file.path)),
          action: SnackBarAction(
            label: context.l10n.openFileAction,
            onPressed: () {
              final mime = resolveMimeType(attachment, file.path);
              openFileRunner(file.path, type: mime.isNotEmpty ? mime : null);
            },
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.attachmentDownloadError),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Opens a local file path using native apps and handles errors gracefully.
  static Future<void> openFile(
    String filePath, {
    BuildContext? context,
    String? mimeType,
  }) async {
    try {
      final openResult = await openFileRunner(filePath, type: mimeType);
      if (openResult.type == ResultType.noAppToOpen &&
          context != null &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noAppToOpenFileError)),
        );
      } else if ((openResult.type == ResultType.error ||
              openResult.type == ResultType.permissionDenied) &&
          context != null &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              openResult.message.isNotEmpty
                  ? openResult.message
                  : context.l10n.attachmentDownloadError,
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (_) {}
  }
}
