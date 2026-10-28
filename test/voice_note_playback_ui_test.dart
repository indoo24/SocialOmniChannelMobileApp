/// WhatsApp-style voice-note playback: full length before playback, elapsed
/// position while playing, a `1x / 1.5x / 2x` speed control during a
/// playback session, and a clean reset on completion or when another note
/// starts.
///
/// Runs the real `AudioPlayer` against a fake audioplayers platform (the same
/// technique as `voice_message_playback_test.dart`): position comes from the
/// player's own position stream, which polls the platform's current position
/// every frame — so these tests drive "the audio is at 0:17" exactly the way
/// the device does, and every speed change is checked on the platform call
/// the player actually makes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/messages/audio_duration.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake audioplayers platform
// ---------------------------------------------------------------------------

class _FakeGlobalPlatform extends GlobalAudioplayersPlatformInterface {
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

class _FakePlatform extends AudioplayersPlatformInterface {
  // Tolerant of player ids it never created: a failing test can leave a
  // player's async work running into the next test, which must not turn
  // one failure into a cascade.
  /// What the player reports once the audio is loaded.
  final Duration duration = const Duration(seconds: 42);
  final Map<String, StreamController<AudioEvent>> _events = {};
  final List<String> players = [];
  final Map<String, Duration> position = {};
  final Map<String, List<double>> rates = {};
  final Map<String, List<Duration>> seeks = {};
  final Map<String, int> resumes = {};
  final Map<String, int> pauses = {};

  @override
  Future<void> create(String playerId) async {
    players.add(playerId);
    _events[playerId] = StreamController<AudioEvent>.broadcast();
    position[playerId] = Duration.zero;
    rates[playerId] = [];
    seeks[playerId] = [];
    resumes[playerId] = 0;
    pauses[playerId] = 0;
  }

  @override
  Future<void> dispose(String playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> resume(String playerId) async =>
      resumes[playerId] = (resumes[playerId] ?? 0) + 1;

  @override
  Future<void> pause(String playerId) async =>
      pauses[playerId] = (pauses[playerId] ?? 0) + 1;

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration to) async {
    (seeks[playerId] ??= []).add(to);
    position[playerId] = to;
    _events[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.seekComplete),
    );
  }

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async =>
      (rates[playerId] ??= []).add(playbackRate);

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    // A new source starts at the beginning, as on a real platform.
    position[playerId] = Duration.zero;
    _events[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    _events[playerId]?.add(
      AudioEvent(eventType: AudioEventType.duration, duration: duration),
    );
  }

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {}

  void complete(String playerId) {
    position[playerId] = duration;
    _events[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.complete),
    );
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async =>
      position[playerId]?.inMilliseconds;

  @override
  Future<int?> getDuration(String playerId) async => duration.inMilliseconds;

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext ctx) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _events[playerId]?.stream ?? const Stream.empty();
}

// ---------------------------------------------------------------------------
// Recordings, server, harness
// ---------------------------------------------------------------------------

/// A minimal but well-formed Ogg Opus stream of [seconds] seconds: the
/// OpusHead page (with a 312-sample pre-skip, as encoders write) and a final
/// page whose granule position is the total sample count at 48 kHz.
Uint8List _oggOpus(double seconds, {int preSkip = 312}) {
  List<int> page(int granule, List<int> body) {
    final header = ByteData(27)
      ..setUint32(0, 0x5367674F, Endian.little) // "OggS"
      ..setUint8(4, 0)
      ..setInt64(6, granule, Endian.little);
    return [...header.buffer.asUint8List(), ...body];
  }

  final head = ByteData(19);
  final ascii = 'OpusHead'.codeUnits;
  for (var i = 0; i < 8; i++) {
    head.setUint8(i, ascii[i]);
  }
  head
    ..setUint8(8, 1)
    ..setUint8(9, 1)
    ..setUint16(10, preSkip, Endian.little)
    ..setUint32(12, 48000, Endian.little);
  final samples = (seconds * 48000).round() + preSkip;
  return Uint8List.fromList([
    ...page(0, head.buffer.asUint8List()),
    ...List.filled(200, 0x55),
    ...page(samples, List.filled(40, 0x66)),
  ]);
}

class _AudioServer implements HttpClientAdapter {
  _AudioServer(this.files);

  final Map<String, Uint8List> files;
  final List<String> fetched = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    fetched.add(options.path);
    final bytes = files[options.path];
    if (bytes == null) {
      return ResponseBody.fromString(jsonEncode({}), 404);
    }
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

Message _voiceMessage(
  int id, {
  required String url,
  int? durationMs = 42000,
  bool outbound = false,
}) => Message(
  id: id,
  direction: outbound ? 'OUTBOUND' : 'INBOUND',
  senderType: outbound ? 'AGENT' : 'CUSTOMER',
  senderName: outbound ? 'Sam Agent' : 'Sarah',
  messageType: 'AUDIO',
  deliveryStatus: 'DELIVERED',
  text: '',
  sentAt: DateTime.parse('2026-09-25T10:00:00Z'),
  attachments: [
    MessageAttachment(
      type: 'AUDIO',
      attachmentId: 'voice-$id',
      url: url,
      mimeType: 'audio/ogg',
      durationMs: durationMs,
    ),
  ],
);

Future<_AudioServer> _pump(
  WidgetTester tester,
  List<Message> messages, {
  Map<String, Uint8List>? files,
  Locale? locale,
}) async {
  final server = _AudioServer(
    files ?? {for (final m in messages) m.attachments.single.url: _oggOpus(42)},
  );
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  // Unmount (disposing every AudioPlayer) even when the test fails half-way
  // through playback, so a player's per-frame position polling cannot spill
  // into the next test and turn one failure into many.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _frames(tester);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              for (final m in messages)
                KeyedSubtree(
                  key: ValueKey('bubble-${m.id}'),
                  child: MessageBubble(message: m),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
  return server;
}

Future<void> _frames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _in(int id, Finder finder) =>
    find.descendant(of: find.byKey(ValueKey('bubble-$id')), matching: finder);

String _time(WidgetTester tester, int id) => tester
    .widget<Text>(_in(id, find.byKey(const ValueKey('voiceNoteTime'))))
    .data!;

Finder _speed(int id) => _in(id, find.byKey(const ValueKey('voiceNoteSpeed')));

String _speedLabel(WidgetTester tester, int id) => tester
    .widget<Text>(find.descendant(of: _speed(id), matching: find.byType(Text)))
    .data!;

Future<void> _tapPlayPause(WidgetTester tester, int id) async {
  final button = _in(
    id,
    find.byWidgetPredicate(
      (w) => w is Icon && (w.icon == Icons.play_arrow || w.icon == Icons.pause),
    ),
  );
  await tester.tap(button);
  await _frames(tester);
}

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance = _FakeGlobalPlatform();
  });

  /// The player behind the only (or the first-created) voice note.
  String player([int index = 0]) => platform.players[index];

  for (final outbound in [false, true]) {
    final side = outbound ? 'outgoing' : 'incoming';

    group('$side voice note', () {
      testWidgets('1 + 6. idle shows the full duration and no speed control', (
        tester,
      ) async {
        await _pump(tester, [
          _voiceMessage(1, url: 'https://a/1.ogg', outbound: outbound),
        ]);

        expect(_time(tester, 1), '0:42');
        expect(_speed(1), findsNothing);
        expect(_in(1, find.byIcon(Icons.play_arrow)), findsOneWidget);
      });

      testWidgets('2 + 3 + 7. playing shows the real, advancing position and '
          'the speed control', (tester) async {
        await _pump(tester, [
          _voiceMessage(1, url: 'https://a/1.ogg', outbound: outbound),
        ]);

        await _tapPlayPause(tester, 1);
        expect(_in(1, find.byIcon(Icons.pause)), findsOneWidget);
        expect(_time(tester, 1), '0:00');
        expect(_speedLabel(tester, 1), '1x');

        for (final second in [1, 2, 17]) {
          platform.position[player()] = Duration(seconds: second);
          await _frames(tester);
          expect(_time(tester, 1), '0:${second.toString().padLeft(2, '0')}');
        }
      });

      testWidgets('4 + 5. pause keeps the position; resume continues from it', (
        tester,
      ) async {
        await _pump(tester, [
          _voiceMessage(1, url: 'https://a/1.ogg', outbound: outbound),
        ]);
        await _tapPlayPause(tester, 1);
        platform.position[player()] = const Duration(seconds: 17);
        await _frames(tester);

        await _tapPlayPause(tester, 1); // pause
        expect(_in(1, find.byIcon(Icons.play_arrow)), findsOneWidget);
        expect(_time(tester, 1), '0:17');
        expect(_speed(1), findsOneWidget, reason: 'session still open');
        expect(platform.pauses[player()], 1);

        await _tapPlayPause(tester, 1); // resume
        expect(_in(1, find.byIcon(Icons.pause)), findsOneWidget);
        expect(platform.seeks[player()], isEmpty, reason: 'no rewind');
        expect(_time(tester, 1), '0:17');
        platform.position[player()] = const Duration(seconds: 18);
        await _frames(tester);
        expect(_time(tester, 1), '0:18');
      });

      testWidgets('8 + 9. 1x → 1.5x → 2x → 1x changes the real player speed '
          'without moving the position', (tester) async {
        await _pump(tester, [
          _voiceMessage(1, url: 'https://a/1.ogg', outbound: outbound),
        ]);
        await _tapPlayPause(tester, 1);
        platform.position[player()] = const Duration(seconds: 17);
        await _frames(tester);
        final resumesBefore = platform.resumes[player()];

        for (final (label, rate) in [('1.5x', 1.5), ('2x', 2.0), ('1x', 1.0)]) {
          await tester.tap(_speed(1));
          await _frames(tester);
          expect(_speedLabel(tester, 1), label);
          expect(platform.rates[player()]!.last, rate);
          expect(_time(tester, 1), '0:17');
        }
        expect(platform.rates[player()], [1.5, 2.0, 1.0]);
        expect(platform.seeks[player()], isEmpty);
        expect(platform.resumes[player()], resumesBefore);
        expect(_in(1, find.byIcon(Icons.pause)), findsOneWidget);
      });

      testWidgets('10 + 11 + 12. completion shows the full duration, hides the '
          'speed control, and the next play starts at 0:00 and 1x', (
        tester,
      ) async {
        await _pump(tester, [
          _voiceMessage(1, url: 'https://a/1.ogg', outbound: outbound),
        ]);
        await _tapPlayPause(tester, 1);
        await tester.tap(_speed(1)); // 1.5x
        await tester.tap(_speed(1)); // 2x
        await _frames(tester);
        platform.position[player()] = const Duration(seconds: 40);
        await _frames(tester);

        platform.complete(player());
        await _frames(tester);

        expect(_time(tester, 1), '0:42');
        expect(_speed(1), findsNothing);
        expect(_in(1, find.byIcon(Icons.play_arrow)), findsOneWidget);
        expect(platform.rates[player()]!.last, 1.0, reason: 'player reset');

        await _tapPlayPause(tester, 1);
        expect(platform.seeks[player()]!.last, Duration.zero);
        expect(_time(tester, 1), '0:00');
        expect(_speedLabel(tester, 1), '1x');
        expect(platform.players, hasLength(1), reason: 'same player reused');
      });
    });
  }

  testWidgets('13. starting another voice note stops and resets the first', (
    tester,
  ) async {
    await _pump(tester, [
      _voiceMessage(1, url: 'https://a/1.ogg'),
      _voiceMessage(2, url: 'https://a/2.ogg', outbound: true),
    ]);
    await _tapPlayPause(tester, 1);
    platform.position[player(0)] = const Duration(seconds: 17);
    await tester.tap(_speed(1)); // 1.5x
    await _frames(tester);

    await _tapPlayPause(tester, 2);

    // The first is back to idle, at 1x on the player.
    expect(_in(1, find.byIcon(Icons.play_arrow)), findsOneWidget);
    expect(_time(tester, 1), '0:42');
    expect(_speed(1), findsNothing);
    expect(platform.pauses[player(0)], greaterThanOrEqualTo(1));
    expect(platform.rates[player(0)]!.last, 1.0);
    // The second is the one playing.
    expect(_in(2, find.byIcon(Icons.pause)), findsOneWidget);
    expect(_speedLabel(tester, 2), '1x');

    // Playing the first again starts it from the top. Voice notes share the
    // app's one player, so that is the first recording loaded afresh rather
    // than a seek on a player of its own.
    await _tapPlayPause(tester, 1);
    expect(platform.players, hasLength(1));
    expect(platform.position[player(0)], Duration.zero);
    expect(_time(tester, 1), '0:00');
    expect(_in(2, find.byIcon(Icons.play_arrow)), findsOneWidget);
  });

  group('full duration without backend metadata', () {
    testWidgets('is read from the recording itself before playback, and the '
        'same download is reused to play it', (tester) async {
      final server = await _pump(
        tester,
        [_voiceMessage(1, url: 'https://a/1.ogg', durationMs: null)],
        files: {'https://a/1.ogg': _oggOpus(65)},
      );

      expect(_time(tester, 1), '1:05');
      expect(server.fetched, ['https://a/1.ogg']);

      await _tapPlayPause(tester, 1);
      expect(_time(tester, 1), '0:00');
      expect(server.fetched, hasLength(1), reason: 'fetched once');
    });

    testWidgets('an unreadable file keeps the existing 0:00 until the player '
        'reports a duration', (tester) async {
      await _pump(
        tester,
        [_voiceMessage(1, url: 'https://a/1.ogg', durationMs: null)],
        files: {'https://a/1.ogg': Uint8List.fromList(List.filled(64, 1))},
      );

      expect(_time(tester, 1), '0:00');

      await _tapPlayPause(tester, 1);
      platform.complete(player());
      await _frames(tester);
      expect(_time(tester, 1), '0:42', reason: "the player's own duration");
    });
  });

  testWidgets('RTL: the speed label is not reordered', (tester) async {
    await _pump(tester, [
      _voiceMessage(1, url: 'https://a/1.ogg'),
    ], locale: const Locale('ar'));
    await _tapPlayPause(tester, 1);
    await tester.tap(_speed(1));
    await _frames(tester);

    final label = tester.widget<Text>(
      find.descendant(of: _speed(1), matching: find.byType(Text)),
    );
    expect(label.data, '1.5x');
    expect(label.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  group('audioDurationFromBytes', () {
    test('Ogg Opus: granule position minus pre-skip at 48 kHz', () {
      expect(audioDurationFromBytes(_oggOpus(42)), const Duration(seconds: 42));
      expect(
        audioDurationFromBytes(_oggOpus(3.5)),
        const Duration(milliseconds: 3500),
      );
    });

    test('MP4 / M4A: mvhd duration over its timescale (v0 and v1)', () {
      Uint8List mp4({required int version}) {
        final mvhd = ByteData(version == 1 ? 36 : 24)..setUint8(0, version);
        if (version == 1) {
          mvhd
            ..setUint32(20, 44100)
            ..setUint64(24, 44100 * 61);
        } else {
          mvhd
            ..setUint32(12, 1000)
            ..setUint32(16, 61000);
        }
        return Uint8List.fromList([
          0,
          0,
          0,
          20,
          ...'ftypM4A '.codeUnits,
          0,
          0,
          0,
          0,
          ...'M4A '.codeUnits,
          0,
          0,
          0,
          0,
          ...'moov'.codeUnits,
          0,
          0,
          0,
          0,
          ...'mvhd'.codeUnits,
          ...mvhd.buffer.asUint8List(),
        ]);
      }

      expect(
        audioDurationFromBytes(mp4(version: 0)),
        const Duration(seconds: 61),
      );
      expect(
        audioDurationFromBytes(mp4(version: 1)),
        const Duration(seconds: 61),
      );
    });

    test('WAV: data size over byte rate', () {
      final header = ByteData(44)
        ..setUint32(0, 0x46464952, Endian.little) // RIFF
        ..setUint32(8, 0x45564157, Endian.little) // WAVE
        ..setUint32(12, 0x20746D66, Endian.little) // "fmt "
        ..setUint32(28, 16000, Endian.little) // byte rate
        ..setUint32(36, 0x61746164, Endian.little) // data
        ..setUint32(40, 16000 * 9, Endian.little);
      expect(
        audioDurationFromBytes(header.buffer.asUint8List()),
        const Duration(seconds: 9),
      );
    });

    test('anything unrecognised is null, never a guess', () {
      expect(audioDurationFromBytes(Uint8List(0)), isNull);
      expect(
        audioDurationFromBytes(Uint8List.fromList(List.filled(64, 1))),
        isNull,
      );
      expect(
        audioDurationFromBytes(Uint8List.fromList('OggS'.codeUnits)),
        isNull,
      );
    });
  });
}
