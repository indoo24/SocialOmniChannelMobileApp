/// A recording stand-in for the audioplayers platform, for tests that need to
/// see what happens to real `AudioPlayer` instances — how many are created and
/// disposed, what each is asked to do, and who listens to them — rather than
/// mocking the player away.
///
/// The `AudioPlayer` objects under test are the package's own; only the
/// platform channel beneath them is replaced.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';

class FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  final _events = StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _events.stream;
}

class FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final List<String> created = [];
  final List<String> disposed = [];

  /// `AudioPlayer.dispose()` releases the native player first, then
  /// disposes it once its own streams have closed.
  final List<String> released = [];
  final Map<String, int> pauses = {};
  final Map<String, int> resumes = {};
  final Map<String, int> stops = {};
  final Map<String, int> sourcesSet = {};
  final Map<String, List<Duration>> seeks = {};
  final Map<String, double> rates = {};
  final Map<String, StreamController<AudioEvent>> _events = {};

  /// Listeners currently attached to each player's platform event stream.
  final Map<String, int> listeners = {};

  /// What `getCurrentPosition` answers, per player.
  final Map<String, Duration> positions = {};

  /// When set, loading a source fails the way a decoder rejecting the file
  /// does.
  bool failNextSource = false;

  /// Players created and not yet disposed.
  List<String> get live =>
      created.where((id) => !disposed.contains(id)).toList();

  @override
  Future<void> create(String playerId) async {
    created.add(playerId);
    listeners[playerId] = 0;
    _events[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    disposed.add(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> pause(String playerId) async =>
      pauses[playerId] = (pauses[playerId] ?? 0) + 1;

  @override
  Future<void> stop(String playerId) async =>
      stops[playerId] = (stops[playerId] ?? 0) + 1;

  @override
  Future<void> resume(String playerId) async =>
      resumes[playerId] = (resumes[playerId] ?? 0) + 1;

  @override
  Future<void> release(String playerId) async => released.add(playerId);

  @override
  Future<void> seek(String playerId, Duration position) async {
    (seeks[playerId] ??= []).add(position);
    positions[playerId] = position;
    _events[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.seekComplete),
    );
  }

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async =>
      rates[playerId] = playbackRate;

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async => _load(playerId);

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async => _load(playerId);

  void _load(String playerId) {
    sourcesSet[playerId] = (sourcesSet[playerId] ?? 0) + 1;
    if (failNextSource) {
      failNextSource = false;
      // As a platform does: the error is reported on the player's event
      // stream as well as by the call.
      final error = Exception('decoder rejected the file');
      _events[playerId]?.addError(error);
      throw error;
    }
    positions[playerId] = Duration.zero;
    _events[playerId]
      ?..add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      )
      ..add(
        const AudioEvent(
          eventType: AudioEventType.duration,
          duration: Duration(seconds: 7),
        ),
      );
  }

  /// The platform reports the end of the file.
  void complete(String playerId) => _events[playerId]?.add(
    const AudioEvent(eventType: AudioEventType.complete),
  );

  @override
  Future<void> setAudioContext(String playerId, AudioContext ctx) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => 7000;

  @override
  Future<int?> getCurrentPosition(String playerId) async =>
      positions[playerId]?.inMilliseconds ?? 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  /// Every subscription is counted while it lasts, so a test can see whether
  /// listeners pile up.
  @override
  Stream<AudioEvent> getEventStream(String playerId) {
    final source = _events[playerId];
    if (source == null) return const Stream.empty();
    return Stream.multi((controller) {
      listeners[playerId] = (listeners[playerId] ?? 0) + 1;
      final sub = source.stream.listen(
        controller.addSync,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller.onCancel = () {
        listeners[playerId] = (listeners[playerId] ?? 1) - 1;
        return sub.cancel();
      };
    }, isBroadcast: true);
  }
}
