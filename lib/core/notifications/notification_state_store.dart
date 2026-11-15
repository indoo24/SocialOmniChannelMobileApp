/// Persists the grouping state ([NotificationGroupState]) between pushes.
///
/// Why a file and not memory: on Android each background push runs in a
/// background isolate that shares no Dart memory with the app's UI isolate,
/// and a killed app gets a fresh process per push. The only thing two pushes
/// — or a push and the app opening — reliably share is disk.
///
/// The file lives in the app-private support directory (not backed up:
/// `allowBackup="false"`), holds at most a handful of short previews per
/// conversation, and is deleted on sign-out.
///
/// Concurrency: [locked] serialises read-modify-write within an isolate (two
/// pushes handled back to back by the same background isolate). Writes are
/// atomic (temp file + rename), so a reader never sees a half-written file.
/// The UI isolate only ever *clears* the state (app opened / signed out), so
/// the remaining cross-isolate race is a reset landing at the same instant
/// as a push — at worst one notification survives the reset, and the next
/// app open clears it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../logging/app_log.dart';
import 'notification_grouping.dart';

class NotificationStateStore {
  NotificationStateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'notification_groups.json';

  /// One chain per isolate — static, because every store instance in an
  /// isolate points at the same file.
  static Future<void> _tail = Future.value();

  static void _log(String message) =>
      AppLog.debug('NotificationStateStore', message);

  /// Runs [body] after every earlier [locked] body in this isolate has
  /// finished, and before any later one starts.
  Future<T> locked<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// The stored state, or an empty one if there is none or it is unreadable.
  Future<NotificationGroupState> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return NotificationGroupState.empty;
      return NotificationGroupState.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (error) {
      _log('read() failed, starting from an empty state: $error');
      return NotificationGroupState.empty;
    }
  }

  Future<void> write(NotificationGroupState state) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (error) {
      // Losing the state only costs grouping accuracy for the next push,
      // never the notification itself.
      _log('write() failed: $error');
    }
  }

  /// Removes everything, including de-duplication memory. Sign-out only.
  Future<void> delete() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (error) {
      _log('delete() failed: $error');
    }
  }
}
