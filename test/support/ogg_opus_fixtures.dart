/// Ogg/Opus files for the voice-note tests, and an independent reader for
/// checking what the app produced.
///
/// [androidOggOpus] reproduces the layout Android's `MediaMuxer` OGG writer
/// (AOSP `OggWriter`, with `C2SoftOpusEnc` feeding it) gives a recording:
/// `OpusHead` and `OpusTags` on pages of their own, then one Opus packet per
/// page whose granule position is 48 kHz × the packet's *start* time (no
/// pre-skip), and no page flagged end-of-stream. The Opus packets themselves
/// are synthetic — valid TOC bytes and filler — which a remux must not care
/// about.
///
/// Nothing here shares code with `lib/`: the CRC and the page parser are
/// written out again so that a mistake in the app's version cannot hide
/// itself.
library;

import 'dart:typed_data';

const bosFlag = 0x02;
const eosFlag = 0x04;
const continuedFlag = 0x01;

/// One Opus packet: SILK wideband 20 ms (config 9), or CELT fullband 20 ms
/// (config 31) for 48 kHz; stereo sets the TOC's `s` bit. 960 samples at
/// 48 kHz either way.
Uint8List opusPacket(int index, {int channels = 1, int rate = 16000}) {
  final config = rate <= 16000 ? 9 : 31;
  final toc = (config << 3) | (channels == 2 ? 0x04 : 0);
  return Uint8List.fromList([toc, ...List.filled(58, (index * 7) & 0xFF)]);
}

Uint8List opusHead({int channels = 1, int preSkip = 104, int rate = 16000}) {
  final b = BytesBuilder()
    ..add('OpusHead'.codeUnits)
    ..add([1, channels, preSkip & 0xFF, preSkip >> 8])
    ..add(_le32(rate))
    ..add([0, 0, 0]);
  return b.toBytes();
}

Uint8List opusTags([String vendor = 'libopus']) {
  final b = BytesBuilder()
    ..add('OpusTags'.codeUnits)
    ..add(_le32(vendor.length))
    ..add(vendor.codeUnits)
    ..add(_le32(0));
  return b.toBytes();
}

/// An Ogg page holding [body] with the given lacing [segments].
Uint8List oggPage(
  List<int> body, {
  required List<int> segments,
  required int flags,
  required int granule,
  int serial = 0x5EED,
  required int sequence,
}) {
  final page = Uint8List(27 + segments.length + body.length);
  final view = ByteData.sublistView(page);
  page.setAll(0, 'OggS'.codeUnits);
  page[5] = flags;
  view.setInt64(6, granule, Endian.little);
  view.setUint32(14, serial, Endian.little);
  view.setUint32(18, sequence, Endian.little);
  page[26] = segments.length;
  page.setAll(27, segments);
  page.setAll(27 + segments.length, body);
  view.setUint32(22, oggCrc(page), Endian.little);
  return page;
}

/// Lacing values for one whole packet of [length] bytes.
List<int> lacingFor(int length) => [
  for (var n = length; n >= 255; n -= 255) 255,
  length % 255,
];

/// A recording as Android writes it: see the library comment.
Uint8List androidOggOpus({
  int channels = 1,
  int packets = 150,
  int rate = 16000,
  int serial = 0x5EED,
}) {
  final preSkip = const {16000: 104, 48000: 312}[rate]!;
  final head = opusHead(channels: channels, preSkip: preSkip, rate: rate);
  final tags = opusTags();
  final out = BytesBuilder()
    ..add(
      oggPage(
        head,
        segments: lacingFor(head.length),
        flags: bosFlag,
        granule: 0,
        serial: serial,
        sequence: 0,
      ),
    )
    ..add(
      oggPage(
        tags,
        segments: lacingFor(tags.length),
        flags: 0,
        granule: 0,
        serial: serial,
        sequence: 1,
      ),
    );
  for (var i = 0; i < packets; i++) {
    final packet = opusPacket(i, channels: channels, rate: rate);
    final startUs = i * 20000;
    out.add(
      oggPage(
        packet,
        segments: lacingFor(packet.length),
        flags: 0, // OggWriter never sets e_o_s
        granule: 48000 * startUs ~/ 1000000, // start, not end; no pre-skip
        serial: serial,
        sequence: 2 + i,
      ),
    );
  }
  return out.toBytes();
}

class InspectedPage {
  InspectedPage(
    this.flags,
    this.granule,
    this.serial,
    this.sequence,
    this.crcOk,
    this.packetCount,
  );

  final int flags;
  final int granule;
  final int serial;
  final int sequence;
  final bool crcOk;

  /// Packets that complete on this page.
  final int packetCount;
}

class InspectedOgg {
  InspectedOgg(this.pages, this.packets);

  final List<InspectedPage> pages;
  final List<Uint8List> packets;
}

/// Parses [data] page by page, independently of the app's reader.
InspectedOgg inspectOgg(Uint8List data) {
  final pages = <InspectedPage>[];
  final packets = <Uint8List>[];
  var partial = <int>[];
  var pos = 0;
  final view = ByteData.sublistView(data);
  while (pos < data.length) {
    final segments = data[pos + 26];
    final lacing = data.sublist(pos + 27, pos + 27 + segments);
    final bodyStart = pos + 27 + segments;
    final end = bodyStart + lacing.fold<int>(0, (a, b) => a + b);
    final page = Uint8List.fromList(data.sublist(pos, end));
    final stored = ByteData.sublistView(page).getUint32(22, Endian.little);
    page.setAll(22, [0, 0, 0, 0]);
    var completed = 0;
    var offset = bodyStart;
    for (final lace in lacing) {
      partial.addAll(data.sublist(offset, offset + lace));
      offset += lace;
      if (lace < 255) {
        packets.add(Uint8List.fromList(partial));
        partial = <int>[];
        completed++;
      }
    }
    pages.add(
      InspectedPage(
        data[pos + 5],
        view.getInt64(pos + 6, Endian.little),
        view.getUint32(pos + 14, Endian.little),
        view.getUint32(pos + 18, Endian.little),
        oggCrc(page) == stored,
        completed,
      ),
    );
    pos = end;
  }
  return InspectedOgg(pages, packets);
}

/// Ogg's CRC-32 over a page whose checksum field is zero.
int oggCrc(Uint8List page) {
  var crc = 0;
  for (final byte in page) {
    crc ^= byte << 24;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x80000000) != 0
          ? ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
          : (crc << 1) & 0xFFFFFFFF;
    }
  }
  return crc;
}

List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  v >> 24,
];
