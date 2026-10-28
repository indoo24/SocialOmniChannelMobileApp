/// Voice-message playback, owned by the app rather than by a message bubble.
///
/// A bubble is the wrong owner for a player. The message list builds bubbles
/// lazily and disposes them as they leave the viewport (it has
/// `addAutomaticKeepAlives: false`), and leaving a conversation disposes all
/// of them, so a player living in a bubble stopped whenever the agent
/// scrolled or moved on. Here one [AudioPlayer] belongs to a keep-alive
/// provider instead, and a bubble only shows and drives the session for its
/// own recording: it can be disposed and rebuilt any number of times while
/// the audio carries on, and a rebuilt bubble picks the session up where it
/// is.
///
/// One session at a time, as before: playing a voice note stops whatever
/// else was playing and returns it to idle.
///
/// The player lives as long as the provider. That ends when the app's
/// provider container does, or at sign-out (`clearSessionScopedState`
/// invalidates this provider), because a customer's recording must not keep
/// playing for the next person to sign in. Backgrounding, locking and app
/// lifecycle are left to the platform and the audio plugin as they were.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a voice note's session stands.
enum VoicePlaybackStatus {
  /// Fetching the recording and preparing the player.
  loading,
  playing,
  paused,

  /// Played to the end. Shown as idle; playing again starts from `0:00`
  /// without fetching the file again.
  completed,

  /// The recording could not be fetched or played.
  error,
}

/// The one voice note the app is playing, or has just played.
@immutable
class VoicePlaybackSession {
  const VoicePlaybackSession({
    required this.key,
    required this.status,
    this.duration,
    this.rate = 1.0,
  });

  /// Which recording: see `VoiceNotePlayer`'s playback key.
  final String key;
  final VoicePlaybackStatus status;

  /// The length the player reports once the audio is loaded.
  final Duration? duration;

  /// Playback speed: 1, 1.5 or 2.
  final double rate;

  /// Playing or paused part-way: the bubble shows the elapsed position and
  /// the speed control.
  bool get inProgress =>
      status == VoicePlaybackStatus.playing ||
      status == VoicePlaybackStatus.paused;

  VoicePlaybackSession copyWith({
    VoicePlaybackStatus? status,
    Duration? duration,
    double? rate,
  }) => VoicePlaybackSession(
    key: key,
    status: status ?? this.status,
    duration: duration ?? this.duration,
    rate: rate ?? this.rate,
  );

  @override
  bool operator ==(Object other) =>
      other is VoicePlaybackSession &&
      other.key == key &&
      other.status == status &&
      other.duration == duration &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(key, status, duration, rate);
}

/// Fetches a recording's bytes. Called once, when its session starts.
typedef VoiceNoteBytesLoader = Future<Uint8List> Function();

class VoicePlaybackController extends Notifier<VoicePlaybackSession?> {
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  /// Bumped by every new session and at teardown: a load or a resume that
  /// finishes after something newer started must not take over.
  int _generation = 0;

  /// The speed last set on the player itself.
  double _playerRate = 1.0;

  /// The playing session's position. A listenable of its own, not session
  /// state: it ticks several times a second, and only the playing bubble's
  /// waveform and time label need it.
  ValueListenable<Duration> get position => _position;

  @override
  VoicePlaybackSession? build() {
    ref.onDispose(_tearDown);
    return null;
  }

  /// Plays the recording [key].
  ///
  /// Resumes it if it is the paused session, replays it from the start if it
  /// has just completed, and otherwise starts a new session — stopping any
  /// other recording — with the bytes [load] returns.
  Future<void> play(String key, VoiceNoteBytesLoader load) async {
    final current = state;
    final player = _player;
    if (current != null && current.key == key) {
      if (current.status == VoicePlaybackStatus.loading) return;
      if (player != null &&
          (current.status == VoicePlaybackStatus.paused ||
              current.status == VoicePlaybackStatus.completed)) {
        return _resume(current, player);
      }
    }

    final generation = ++_generation;
    // Started before anything is awaited, so that a bubble disposed while
    // this runs has already handed over everything the load needs.
    final bytes = load();
    _position.value = Duration.zero;
    state = VoicePlaybackSession(key: key, status: VoicePlaybackStatus.loading);
    if (current != null && current.status == VoicePlaybackStatus.playing) {
      await _quietly(() => player?.pause());
    }

    try {
      final data = await bytes;
      if (generation != _generation) return;
      final player = await _ensurePlayer();
      if (generation != _generation) return;
      if (_playerRate != 1.0) {
        _playerRate = 1.0;
        await player.setPlaybackRate(1.0);
      }
      await player.play(BytesSource(data));
      if (generation != _generation) return;
      state = state?.copyWith(status: VoicePlaybackStatus.playing);
    } catch (_) {
      if (generation != _generation) return;
      state = VoicePlaybackSession(key: key, status: VoicePlaybackStatus.error);
    }
  }

  Future<void> _resume(VoicePlaybackSession session, AudioPlayer player) async {
    final generation = ++_generation;
    if (session.status == VoicePlaybackStatus.completed) {
      _position.value = Duration.zero;
      await _quietly(
        () => player
            .seek(Duration.zero)
            .timeout(const Duration(milliseconds: 300)),
      );
    }
    try {
      await player.resume();
      if (generation != _generation) return;
      state = state?.copyWith(status: VoicePlaybackStatus.playing);
    } catch (_) {
      if (generation != _generation) return;
      state = session.copyWith(status: VoicePlaybackStatus.error);
    }
  }

  /// Pauses [key] if it is the one playing. Position and speed are kept for
  /// the resume.
  Future<void> pause(String key) async {
    final session = state;
    if (session == null ||
        session.key != key ||
        session.status != VoicePlaybackStatus.playing) {
      return;
    }
    state = session.copyWith(status: VoicePlaybackStatus.paused);
    await _quietly(() => _player?.pause());
  }

  /// Moves [key] to [position], if its audio is loaded. A completed note
  /// becomes a paused one at that point, as the bubble shows.
  Future<void> seek(String key, Duration position) async {
    final session = state;
    final player = _player;
    if (session == null ||
        session.key != key ||
        player == null ||
        session.status == VoicePlaybackStatus.loading ||
        session.status == VoicePlaybackStatus.error) {
      return;
    }
    if (session.status == VoicePlaybackStatus.completed) {
      state = session.copyWith(status: VoicePlaybackStatus.paused);
    }
    _position.value = position;
    await _quietly(() => player.seek(position));
  }

  /// Sets [key]'s speed while it is in progress. Neither restarts nor seeks,
  /// and a paused note stays paused.
  Future<void> setRate(String key, double rate) async {
    final session = state;
    if (session == null || session.key != key || !session.inProgress) return;
    state = session.copyWith(rate: rate);
    _playerRate = rate;
    await _quietly(() => _player?.setPlaybackRate(rate));
  }

  /// Ends the session, whichever it is. The player is kept for the next one.
  Future<void> stop() async {
    if (state == null) return;
    ++_generation;
    state = null;
    _position.value = Duration.zero;
    await _quietly(() => _player?.stop());
  }

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    await player.setReleaseMode(ReleaseMode.stop);
    _subscriptions.addAll([
      player.onPlayerStateChanged.listen(_onPlayerState, onError: _onError),
      player.onPositionChanged.listen(_onPosition, onError: _onError),
      player.onDurationChanged.listen(_onDuration, onError: _onError),
      player.onPlayerComplete.listen((_) => _onComplete(), onError: _onError),
    ]);
    return player;
  }

  /// Follows pauses and resumes the platform makes on its own (an audio
  /// interruption, say). Ignored outside a session in progress, so events
  /// from the previous recording cannot touch a new one while it loads.
  void _onPlayerState(PlayerState playerState) {
    final session = state;
    if (session == null || !session.inProgress) return;
    final status = switch (playerState) {
      PlayerState.playing => VoicePlaybackStatus.playing,
      PlayerState.paused => VoicePlaybackStatus.paused,
      _ => null,
    };
    if (status != null && status != session.status) {
      state = session.copyWith(status: status);
    }
  }

  /// The real position stream, never a timer. Ignored outside a session so a
  /// late tick after completion cannot show a stale position.
  void _onPosition(Duration position) {
    if (state?.inProgress ?? false) _position.value = position;
  }

  void _onDuration(Duration duration) {
    final session = state;
    if (session == null || duration <= Duration.zero) return;
    if (session.status == VoicePlaybackStatus.error) return;
    state = session.copyWith(duration: duration);
  }

  /// Back to idle for a fresh play: position rewound and speed back to 1x —
  /// on the player itself, so the next session really is at normal speed.
  void _onComplete() {
    final session = state;
    if (session == null || !session.inProgress) return;
    state = session.copyWith(status: VoicePlaybackStatus.completed, rate: 1.0);
    _position.value = Duration.zero;
    if (_playerRate != 1.0) {
      _playerRate = 1.0;
      unawaited(_quietly(() => _player?.setPlaybackRate(1.0)));
    }
  }

  void _onError(Object _) {
    final session = state;
    if (session == null || session.status == VoicePlaybackStatus.error) return;
    ++_generation;
    state = session.copyWith(status: VoicePlaybackStatus.error);
  }

  void _tearDown() {
    ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) unawaited(_quietly(player.dispose));
  }

  /// The player is a platform channel: a call into one already torn down
  /// throws, and nothing here depends on its answer.
  static Future<void> _quietly(Future<void>? Function() call) async {
    try {
      await call();
    } catch (_) {}
  }

  /// Stream subscriptions held for the current player — one per stream,
  /// however many bubbles show the session.
  @visibleForTesting
  int get debugSubscriptionCount => _subscriptions.length;
}

/// The app's voice-note player. Keep-alive like every provider here: it
/// survives every screen, and goes with the container or at sign-out.
final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackController, VoicePlaybackSession?>(
      VoicePlaybackController.new,
    );
