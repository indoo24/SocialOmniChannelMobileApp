/// Helper utilities for downloading, saving, and opening attachments.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../logging/app_log.dart';
import '../models/message.dart';
import '../../l10n/l10n_extensions.dart';
import 'safe_url.dart';

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

  /// The MIME type to declare for a local file being uploaded, or null when
  /// nothing about it is recognisable (the transport then sends the honest
  /// `application/octet-stream`).
  ///
  /// The file's own leading bytes ([headerBytes]) win over its name: a
  /// renamed PNG is still a PNG. The extension — of the display [fileName]
  /// first, which is what the user saw and picked, then of the on-disk
  /// [filePath] — is only a fallback for formats with no signature (text,
  /// CSV, and ZIP-based Office files, which must not be reported as ZIP).
  /// This is a declaration, not a verdict: the backend re-derives the type
  /// from the bytes and decides what is accepted.
  static String? detectMimeType({
    required String fileName,
    String? filePath,
    List<int>? headerBytes,
  }) {
    final bytes = (headerBytes == null || headerBytes.isEmpty)
        ? null
        : headerBytes;
    if (bytes != null) {
      final sniffed = lookupMimeType('', headerBytes: bytes);
      if (sniffed != null) return sniffed;
    }
    return lookupMimeType(fileName) ??
        (filePath == null ? null : lookupMimeType(filePath));
  }

  /// The first bytes of [path] — enough for [detectMimeType]'s signature
  /// check — or null if the file cannot be read. Reads only that prefix,
  /// whatever the file's size.
  static Future<List<int>?> readHeaderBytes(String path) async {
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      return await handle.read(defaultMagicNumbersMaxLength);
    } on FileSystemException {
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// Longest filename, in UTF-8 bytes, this writes to disk: under the
  /// 255-byte limit of ext4/F2FS/APFS with room for a " (12)" collision
  /// suffix and a cache-key prefix. An Arabic name is two bytes a character,
  /// so a character count alone is not a safe measure.
  static const maxFileNameBytes = 180;

  /// [name] made safe to use as a single path segment: no separators or
  /// reserved/control characters, never `.`/`..`, never empty, and trimmed
  /// to [maxBytes] UTF-8 bytes with the extension kept.
  static String safeFileName(String name, {int maxBytes = maxFileNameBytes}) {
    var sanitized = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '_')
        .trim();
    if (sanitized.isEmpty || RegExp(r'^\.+$').hasMatch(sanitized)) {
      sanitized = 'file';
    }
    if (utf8.encode(sanitized).length <= maxBytes) return sanitized;

    final dot = sanitized.lastIndexOf('.');
    var ext = dot > 0 ? sanitized.substring(dot) : '';
    // An "extension" too long to be one is just part of the name.
    if (utf8.encode(ext).length > 16) ext = '';
    var stem = ext.isEmpty ? sanitized : sanitized.substring(0, dot);
    final budget = maxBytes - utf8.encode(ext).length;
    // Trim whole characters (runes), never a UTF-8 sequence in half.
    final runes = stem.runes.toList();
    var used = 0;
    var keep = 0;
    for (final rune in runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (used + size > budget) break;
      used += size;
      keep++;
    }
    stem = String.fromCharCodes(runes.take(keep)).trim();
    return '${stem.isEmpty ? 'file' : stem}$ext';
  }

  /// Sanitizes and ensures a unique filename in [directory].
  static String getUniqueFilePath(Directory directory, String baseName) {
    final sanitized = safeFileName(baseName);

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
    final rawName = attachment.fileName.trim();
    if (rawName.isNotEmpty) {
      if (rawName.contains('.')) {
        return rawName;
      }
      final ext = _extensionFromMime(attachment.mimeType);
      if (ext.isNotEmpty) {
        return '$rawName$ext';
      }
      return rawName;
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
      _ => attachment.hasImageFile ? 'image' : 'document',
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
    if (lower.contains('webp')) return '.webp';
    if (lower.contains('gif')) return '.gif';
    if (lower.contains('bmp')) return '.bmp';
    if (lower.contains('svg')) return '.svg';
    if (lower.contains('text') || lower.contains('txt')) return '.txt';
    if (lower.contains('csv')) return '.csv';
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
    if (lowerPath.endsWith('.webp')) return 'image/webp';
    if (lowerPath.endsWith('.gif')) return 'image/gif';
    if (lowerPath.endsWith('.bmp')) return 'image/bmp';
    if (lowerPath.endsWith('.svg')) return 'image/svg+xml';
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
    final key = safeFileName(
      attachment.attachmentId.isNotEmpty
          ? attachment.attachmentId
          : attachment.resolvedUrl.hashCode.abs().toString(),
      maxBytes: 64,
    );
    return File('${dir.path}/${key}_${safeFileName(fileName)}');
  }

  /// Downloads in progress, by cache path — a second tap on the same file
  /// joins the first transfer instead of starting a competing one that
  /// writes to the same place.
  static final Map<String, Future<File?>> _inFlight = {};

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

  /// Downloads the attachment using [api] (including authentication cookies)
  /// or returns existing local file if already downloaded and cached locally.
  ///
  /// The body is streamed to a `.part` file beside the cache entry and only
  /// renamed into place once complete, so the cache can never hold a
  /// truncated file that [findLocalAttachment] would then serve as whole —
  /// and a large document never passes through memory.
  static Future<File?> downloadAttachmentFile({
    required MessageAttachment attachment,
    required ApiClient api,
    int? messageId,
  }) async {
    // Return existing local or cached file immediately without re-downloading
    final local = await findLocalAttachment(attachment);
    if (local != null) return local;

    final target = await getCachedAttachmentFile(attachment);
    return _inFlight[target.path] ??= _download(
      attachment: attachment,
      api: api,
      target: target,
      messageId: messageId,
    ).whenComplete(() {
      // A block, not `=>`: remove() returns this very future, and
      // whenComplete would wait on it — waiting on itself forever.
      _inFlight.remove(target.path);
    });
  }

  static Future<File?> _download({
    required MessageAttachment attachment,
    required ApiClient api,
    required File target,
    int? messageId,
  }) async {
    // Same rule as every other server-supplied media URL: https (or the
    // configured dev host), never anything the session cookie should not
    // follow.
    final url = SafeUrl.forImage(attachment.resolvedUrl);
    if (url.isEmpty) {
      AppLog.debug(
        'AttachmentHelper',
        'Download aborted: no usable URL for attachmentId=${attachment.attachmentId}, '
        'messageId=$messageId',
      );
      return null;
    }

    final part = File('${target.path}.part');
    try {
      await api.downloadToFile(url, part.path);
      if (!part.existsSync() || part.lengthSync() == 0) {
        AppLog.debug(
          'AttachmentHelper',
          'Download returned empty payload: attachmentId=${attachment.attachmentId}, '
          'messageId=$messageId',
        );
        return null;
      }
      return await part.rename(target.path);
    } on ApiException catch (e) {
      AppLog.debug(
        'AttachmentHelper',
        'Download failed: status=${e.statusCode}, code=${e.code}, '
        'attachmentId=${attachment.attachmentId}, messageId=$messageId, '
        'mimeType=${attachment.mimeType}',
      );
      AppLog.warn(
        'AttachmentHelper',
        'Attachment download failed (HTTP status ${e.statusCode})',
      );
      return null;
    } catch (e) {
      AppLog.debug(
        'AttachmentHelper',
        'Download unexpected exception: ${e.runtimeType}, '
        'attachmentId=${attachment.attachmentId}, messageId=$messageId',
      );
      return null;
    } finally {
      try {
        if (part.existsSync()) part.deleteSync();
      } on FileSystemException {
        // A leftover .part is never read as a finished file.
      }
    }
  }

  /// Downloads [attachment] (if not already local) and immediately opens it
  /// with the default device application (e.g. default PDF viewer).
  static Future<void> openAttachment({
    required BuildContext context,
    required MessageAttachment attachment,
    required ApiClient api,
    int? messageId,
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
        messageId: messageId,
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
        AppLog.debug(
          'AttachmentHelper',
          'Open file error: resultType=${openResult.type}, message=${openResult.message}, '
          'filePath=${file.path}, mime=$mime, attachmentId=${attachment.attachmentId}, messageId=$messageId',
        );
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            // The plugin's own message is a diagnostic (paths, permission
            // names), not copy for the agent.
            content: Text(context.l10n.attachmentDownloadError),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else if (openResult.type == ResultType.done) {
        if (context.mounted) {
          messenger.hideCurrentSnackBar();
        }
      }
    } catch (e) {
      AppLog.debug(
        'AttachmentHelper',
        'openAttachment exception: $e, attachmentId=${attachment.attachmentId}, messageId=$messageId',
      );
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
    int? messageId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var source = await findLocalAttachment(attachment);
      if (source == null) {
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
          messageId: messageId,
        );

        if (downloaded == null || !downloaded.existsSync()) {
          throw StateError('Download failed');
        }
        source = downloaded;
      }

      final dir = await getAccessibleDirectory();
      final fileName = suggestFileName(attachment);
      final targetPath = getUniqueFilePath(dir, fileName);
      // A file-to-file copy: never the whole document in memory, never a
      // blocking write on the UI thread.
      final file = await source.copy(targetPath);

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
    } catch (e) {
      AppLog.debug(
        'AttachmentHelper',
        'saveAttachmentToDownloads exception: $e, attachmentId=${attachment.attachmentId}, messageId=$messageId',
      );
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
            // The plugin's own message is a diagnostic (paths, permission
            // names), not copy for the agent.
            content: Text(context.l10n.attachmentDownloadError),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (_) {}
  }
}
