import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the currently active voice message player so that playing one voice
/// message automatically pauses any previously playing voice message.
class ActiveVoicePlaybackCoordinator extends Notifier<String?> {
  VoidCallback? _activePauseCallback;

  @override
  String? build() => null;

  /// Registers [id] as the currently playing voice note.
  /// If a different player was active, its pause callback is invoked immediately.
  void setActive(String id, {VoidCallback? onPause}) {
    if (state != null && state != id) {
      final prevPause = _activePauseCallback;
      _activePauseCallback = null;
      prevPause?.call();
    }
    state = id;
    _activePauseCallback = onPause;
  }

  /// Clears active status if [id] matches the currently active player.
  void clear(String id) {
    if (state == id) {
      state = null;
      _activePauseCallback = null;
    }
  }

  /// Stops any currently playing player and resets active playback state.
  void stopAll() {
    final prevPause = _activePauseCallback;
    _activePauseCallback = null;
    state = null;
    prevPause?.call();
  }
}

final activeVoicePlaybackProvider =
    NotifierProvider<ActiveVoicePlaybackCoordinator, String?>(
      ActiveVoicePlaybackCoordinator.new,
    );
