/// Re-paging an Android Ogg/Opus recording into a well-formed Ogg Opus file
/// before it is uploaded (`voice_note_ogg.dart`), and the file-level step
/// both recorders run (`prepareRecordedVoiceNote`).
///
/// The input fixture reproduces what Android's `MediaMuxer` OGG writer gives
/// the app — see `support/ogg_opus_fixtures.dart` for exactly which AOSP
/// behaviour it encodes. The output is checked with that file's own parser,
/// not the app's.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/features/messages/voice_note_ogg.dart';
import 'package:scenario_mobile/features/messages/voice_note_recording.dart';

import 'support/ogg_opus_fixtures.dart';

void main() {
  group('the Android recording as written', () {
    test('breaks the rules the re-paging exists for', () {
      final ogg = inspectOgg(androidOggOpus(packets: 5));
      final audio = ogg.pages.skip(2).toList();

      expect(
        ogg.pages.any((p) => p.flags & eosFlag != 0),
        isFalse,
        reason: 'no end-of-stream page',
      );
      expect(
        audio.first.granule,
        0,
        reason:
            'RFC 7845 §4: a first audio page claiming fewer samples '
            'than it holds (960) must be rejected',
      );
      expect(
        audio.last.granule,
        4 * 960,
        reason: 'one frame short, no pre-skip',
      );
    });
  });

  group('repageOggOpus', () {
    test('gives the layout the backend gives web recordings', () {
      final input = androidOggOpus(packets: 150);
      final note = repageOggOpus(input);
      final ogg = inspectOgg(note.bytes);

      expect(note.channels, 1);
      expect(note.preSkip, 104);
      expect(note.samples, 150 * 960);

      expect(ogg.pages, hasLength(152));
      expect(ogg.pages.every((p) => p.crcOk), isTrue);
      expect(ogg.pages.map((p) => p.serial).toSet(), {0x5EED});
      expect(ogg.pages.map((p) => p.sequence), List.generate(152, (i) => i));
      expect(
        ogg.pages.every((p) => p.packetCount == 1),
        isTrue,
        reason: 'one packet per page, as the backend writes them',
      );

      // Beginning- and end-of-stream exactly once, where they belong.
      expect(ogg.pages.first.flags, bosFlag);
      expect(ogg.pages.last.flags, eosFlag);
      expect(ogg.pages.skip(1).take(150).every((p) => p.flags == 0), isTrue);

      // Headers at granule 0; then pre-skip + the samples up to the end of
      // each packet (RFC 7845 §4).
      expect(ogg.pages[0].granule, 0);
      expect(ogg.pages[1].granule, 0);
      for (var i = 0; i < 150; i++) {
        expect(ogg.pages[2 + i].granule, 104 + (i + 1) * 960);
      }
    });

    test('copies every packet — headers and audio — byte for byte', () {
      final input = androidOggOpus(packets: 40);
      final before = inspectOgg(input).packets;
      final after = inspectOgg(repageOggOpus(input).bytes).packets;

      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        expect(after[i], before[i], reason: 'packet $i');
      }
    });

    test('is stable: a re-paged file re-pages to itself', () {
      final once = repageOggOpus(androidOggOpus(packets: 20)).bytes;
      expect(repageOggOpus(once).bytes, once);
    });

    test('reports a stereo stream rather than hiding it', () {
      final note = repageOggOpus(
        androidOggOpus(channels: 2, rate: 48000, packets: 3),
      );
      expect(note.channels, 2);
      expect(note.preSkip, 312);
    });

    test('reassembles a packet that spans two pages', () {
      final head = opusHead();
      final tags = opusTags();
      final big = Uint8List.fromList([9 << 3, ...List.filled(599, 3)]);
      final input = BytesBuilder()
        ..add(
          oggPage(
            head,
            segments: lacingFor(head.length),
            flags: bosFlag,
            granule: 0,
            sequence: 0,
          ),
        )
        ..add(
          oggPage(
            tags,
            segments: lacingFor(tags.length),
            flags: 0,
            granule: 0,
            sequence: 1,
          ),
        )
        // 600 bytes: 255 + 255 on this page (unfinished)…
        ..add(
          oggPage(
            big.sublist(0, 510),
            segments: [255, 255],
            flags: 0,
            granule: -1,
            sequence: 2,
          ),
        )
        // …and the last 90 on the next, flagged as a continuation.
        ..add(
          oggPage(
            big.sublist(510),
            segments: [90],
            flags: continuedFlag,
            granule: 960,
            sequence: 3,
          ),
        );

      final out = inspectOgg(repageOggOpus(input.toBytes()).bytes);
      expect(out.packets[2], big);
      expect(out.pages.last.granule, 104 + 960);
    });

    test('keeps the audio before a page cut short at the end of the file', () {
      final whole = androidOggOpus(packets: 10);
      final cut = Uint8List.sublistView(whole, 0, whole.length - 20);

      final note = repageOggOpus(cut);
      expect(note.samples, 9 * 960);
      expect(inspectOgg(note.bytes).pages.last.flags, eosFlag);
    });

    group('refuses', () {
      void refuses(Uint8List data, String why) => expect(
        () => repageOggOpus(data),
        throwsA(isA<VoiceNoteFormatException>()),
        reason: why,
      );

      test('a corrupt page', () {
        final data = androidOggOpus(packets: 5);
        data[data.length - 3] ^= 0xFF;
        refuses(data, 'CRC mismatch');
      });

      test('a missing page', () {
        final data = androidOggOpus(packets: 5);
        final pages = _splitPages(data)..removeAt(4);
        refuses(
          Uint8List.fromList(pages.expand((p) => p).toList()),
          'sequence gap',
        );
      });

      test('two interleaved streams', () {
        final a = _splitPages(androidOggOpus(packets: 3));
        final b = _splitPages(androidOggOpus(packets: 3, serial: 7));
        refuses(
          Uint8List.fromList([...a.take(4), b[2]].expand((p) => p).toList()),
          'second serial',
        );
      });

      test('another codec in an Ogg box', () {
        final vorbis = 'vorbis'.codeUnits;
        final data = BytesBuilder()
          ..add(
            oggPage(
              [1, ...vorbis, ...List.filled(23, 0)],
              segments: [30],
              flags: bosFlag,
              granule: 0,
              sequence: 0,
            ),
          )
          ..add(
            oggPage(
              [3, ...vorbis],
              segments: [7],
              flags: 0,
              granule: 0,
              sequence: 1,
            ),
          )
          ..add(
            oggPage(
              [0, 1, 2],
              segments: [3],
              flags: eosFlag,
              granule: 64,
              sequence: 2,
            ),
          );
        refuses(data.toBytes(), 'Vorbis is not Opus');
      });

      test('headers and no audio', () {
        final pages = _splitPages(androidOggOpus(packets: 1));
        refuses(
          Uint8List.fromList(pages.take(2).expand((p) => p).toList()),
          'nothing to play',
        );
      });

      test('a packet that declares no frames', () {
        final head = opusHead();
        final tags = opusTags();
        final data = BytesBuilder()
          ..add(
            oggPage(
              head,
              segments: lacingFor(head.length),
              flags: bosFlag,
              granule: 0,
              sequence: 0,
            ),
          )
          ..add(
            oggPage(
              tags,
              segments: lacingFor(tags.length),
              flags: 0,
              granule: 0,
              sequence: 1,
            ),
          )
          // TOC code 3 with a frame count of 0.
          ..add(
            oggPage(
              [(9 << 3) | 3, 0],
              segments: [2],
              flags: 0,
              granule: 0,
              sequence: 2,
            ),
          );
        refuses(data.toBytes(), 'zero frames');
      });

      test('bytes that are not Ogg at all', () {
        refuses(
          Uint8List.fromList('caff'.codeUnits + List.filled(40, 0)),
          'no capture pattern',
        );
      });
    });
  });

  group('prepareRecordedVoiceNote', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('voice_note_ogg'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(List<int> bytes) =>
        File('${dir.path}/voice.ogg')..writeAsBytesSync(bytes);

    test('re-pages an Android recording in place', () {
      final file = write(androidOggOpus(packets: 30));

      prepareRecordedVoiceNote(file.path);

      final ogg = inspectOgg(file.readAsBytesSync());
      expect(ogg.pages.last.flags, eosFlag);
      expect(ogg.pages[2].granule, 104 + 960);
    });

    test('refuses a recording whose own header says stereo', () {
      final file = write(androidOggOpus(channels: 2, rate: 48000, packets: 3));
      final original = file.readAsBytesSync();

      expect(
        () => prepareRecordedVoiceNote(file.path),
        throwsA(
          isA<VoiceNoteNotMonoException>().having(
            (e) => e.numChannels,
            'numChannels',
            2,
          ),
        ),
      );
      expect(file.readAsBytesSync(), original, reason: 'left for the caller');
    });

    test('refuses a broken Ogg recording', () {
      final data = androidOggOpus(packets: 5);
      data[60] ^= 0xFF;
      final file = write(data);

      expect(
        () => prepareRecordedVoiceNote(file.path),
        throwsA(isA<VoiceNoteFormatException>()),
      );
    });

    test('leaves a recording in another container exactly as it is', () {
      // iOS records through AVFoundation; that container is unconfirmed, so
      // nothing here touches it.
      final caf = [...'caff'.codeUnits, 0, 1, 0, 0, ...List.filled(60, 7)];
      final file = write(caf);

      prepareRecordedVoiceNote(file.path);

      expect(file.readAsBytesSync(), caf);
    });
  });
}

List<Uint8List> _splitPages(Uint8List data) {
  final pages = <Uint8List>[];
  var pos = 0;
  while (pos < data.length) {
    final segments = data[pos + 26];
    var end = pos + 27 + segments;
    for (var i = 0; i < segments; i++) {
      end += data[pos + 27 + i];
    }
    pages.add(Uint8List.sublistView(data, pos, end));
    pos = end;
  }
  return pages;
}
