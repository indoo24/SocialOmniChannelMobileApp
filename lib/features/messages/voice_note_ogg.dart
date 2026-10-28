/// Re-pages a recorded Ogg/Opus voice note into a well-formed Ogg Opus
/// stream (RFC 3533 framing, RFC 7845 mapping) without touching the audio.
///
/// Android records Opus through the platform's own Ogg writer (`MediaMuxer`
/// → AOSP `OggWriter`, unchanged from Android 10 to current), and the file it
/// writes breaks two rules a strict player relies on:
///
///  * no page ever carries the end-of-stream flag — `OggWriter` sets
///    `e_o_s` from a flag it only raises after the file is closed;
///  * every granule position is the *start* time of its packet, without the
///    pre-skip, so the first audio page claims 0 samples while holding a whole
///    frame. RFC 7845 §4 says a decoder MUST reject such a stream.
///
/// The backend sends an Ogg upload to WhatsApp byte for byte, whereas the
/// web app's recordings are re-paged by the backend — one packet per page,
/// granule = pre-skip + samples so far, end-of-stream on the last page — and
/// those play. This writes exactly that layout. The Opus packets, the
/// `OpusHead` and the `OpusTags` are copied byte for byte: nothing is decoded
/// or re-encoded, so the sound is unchanged.
library;

import 'dart:typed_data';

/// The bytes are not an Ogg/Opus recording this can re-page.
class VoiceNoteFormatException implements Exception {
  const VoiceNoteFormatException(this.message);

  final String message;

  @override
  String toString() => 'VoiceNoteFormatException: $message';
}

/// A re-paged recording, and what its `OpusHead` says.
class OggOpusVoiceNote {
  const OggOpusVoiceNote({
    required this.bytes,
    required this.channels,
    required this.preSkip,
    required this.samples,
  });

  /// The well-formed file.
  final Uint8List bytes;

  /// The channel count the stream declares.
  final int channels;

  /// Samples (at 48 kHz) the decoder discards at the start.
  final int preSkip;

  /// Samples (at 48 kHz) in all audio packets, pre-skip included.
  final int samples;
}

/// Whether [bytes] begin with the Ogg capture pattern.
bool isOgg(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x4F && // O
    bytes[1] == 0x67 && // g
    bytes[2] == 0x67 && // g
    bytes[3] == 0x53; // S

/// Rewrites [data] — a single-stream Ogg/Opus file — with correct granule
/// positions, contiguous page numbers, one packet per page and the
/// end-of-stream flag on the last page.
///
/// Throws [VoiceNoteFormatException] for anything that is not such a file:
/// another codec, several interleaved streams, a corrupt page or no audio.
/// A page cut short at the very end — a recording interrupted mid-write — is
/// dropped rather than refused; everything before it is intact audio.
OggOpusVoiceNote repageOggOpus(Uint8List data) {
  final read = _readPackets(data);
  final packets = read.packets;
  if (packets.length < 3) {
    throw const VoiceNoteFormatException('no audio after the Opus headers');
  }

  final head = packets[0];
  if (!_startsWith(head, 'OpusHead') || head.length < 19) {
    throw const VoiceNoteFormatException('not an Opus stream');
  }
  // RFC 7845 §5.1: only major version 0 is defined.
  if (head[8] >> 4 != 0) {
    throw VoiceNoteFormatException('unsupported OpusHead version ${head[8]}');
  }
  final channels = head[9];
  final preSkip = head[10] | (head[11] << 8);
  final mapping = head[18];
  if (channels == 0 || (mapping == 0 && channels > 2)) {
    throw VoiceNoteFormatException(
      'invalid channel layout: $channels channels, family $mapping',
    );
  }

  final tags = packets[1];
  if (!_startsWith(tags, 'OpusTags')) {
    throw const VoiceNoteFormatException('missing OpusTags');
  }

  // Zero-length packets carry no audio and no duration; drop them.
  final audio = [
    for (final p in packets.skip(2))
      if (p.isNotEmpty) p,
  ];
  if (audio.isEmpty) {
    throw const VoiceNoteFormatException('no audio after the Opus headers');
  }

  final out = BytesBuilder(copy: false);
  var sequence = 0;
  void page(Uint8List packet, {required int granule, required int flags}) {
    out.add(
      _page(
        packet,
        serial: read.serial,
        sequence: sequence++,
        granule: granule,
        flags: flags,
      ),
    );
  }

  page(head, granule: 0, flags: _bos);
  page(tags, granule: 0, flags: 0);
  var granule = preSkip;
  for (var i = 0; i < audio.length; i++) {
    granule += opusPacketSamples(audio[i]);
    page(audio[i], granule: granule, flags: i == audio.length - 1 ? _eos : 0);
  }

  return OggOpusVoiceNote(
    bytes: out.takeBytes(),
    channels: channels,
    preSkip: preSkip,
    samples: granule - preSkip,
  );
}

/// Length of one Opus packet in 48 kHz samples, from its TOC byte
/// (RFC 6716 §3.1). Throws [VoiceNoteFormatException] for a packet that
/// declares no frames.
int opusPacketSamples(Uint8List packet) {
  final toc = packet[0];
  final frames = switch (toc & 0x03) {
    0 => 1,
    1 || 2 => 2,
    _ => packet.length > 1 ? packet[1] & 0x3F : 0,
  };
  if (frames == 0) {
    throw const VoiceNoteFormatException('Opus packet with no frames');
  }
  return _frameMicros[toc >> 3] * frames * 48 ~/ 1000;
}

const _bos = 0x02;
const _eos = 0x04;
const _continued = 0x01;

/// Frame duration in microseconds by TOC `config` (RFC 6716 §3.1).
const _frameMicros = [
  10000, 20000, 40000, 60000, 10000, 20000, 40000, 60000, // SILK NB/MB/WB
  10000, 20000, 40000, 60000, 10000, 20000, 10000, 20000, // SILK WB, hybrid
  2500, 5000, 10000, 20000, 2500, 5000, 10000, 20000, // CELT NB/WB
  2500, 5000, 10000, 20000, 2500, 5000, 10000, 20000, // CELT SWB/FB
];

class _Read {
  _Read(this.serial, this.packets);

  final int serial;
  final List<Uint8List> packets;
}

_Read _readPackets(Uint8List data) {
  final view = ByteData.sublistView(data);
  final packets = <Uint8List>[];
  final partial = BytesBuilder(copy: false);
  int? serial;
  int? lastSequence;
  var pos = 0;

  while (pos < data.length) {
    if (data.length - pos < 27) break; // cut short at the end
    if (!isOgg(Uint8List.sublistView(data, pos, pos + 4))) {
      throw VoiceNoteFormatException('no Ogg page at byte $pos');
    }
    if (data[pos + 4] != 0) {
      throw VoiceNoteFormatException('unknown Ogg version ${data[pos + 4]}');
    }
    final flags = data[pos + 5];
    final pageSerial = view.getUint32(pos + 14, Endian.little);
    final pageSequence = view.getUint32(pos + 18, Endian.little);
    final crc = view.getUint32(pos + 22, Endian.little);
    final segments = data[pos + 26];
    final bodyStart = pos + 27 + segments;
    if (bodyStart > data.length) break;
    var bodyLength = 0;
    for (var i = 0; i < segments; i++) {
      bodyLength += data[pos + 27 + i];
    }
    final end = bodyStart + bodyLength;
    if (end > data.length) break;

    if (_crc(data, pos, end) != crc) {
      throw VoiceNoteFormatException('corrupt Ogg page at byte $pos');
    }
    if (serial == null) {
      serial = pageSerial;
    } else if (pageSerial != serial) {
      throw const VoiceNoteFormatException('more than one Ogg stream');
    }
    if (lastSequence != null && pageSequence != lastSequence + 1) {
      throw VoiceNoteFormatException('Ogg page missing before byte $pos');
    }
    lastSequence = pageSequence;
    if (flags & _continued == 0 && partial.length > 0) {
      throw VoiceNoteFormatException('unfinished packet before byte $pos');
    }

    var offset = bodyStart;
    for (var i = 0; i < segments; i++) {
      final lace = data[pos + 27 + i];
      partial.add(Uint8List.sublistView(data, offset, offset + lace));
      offset += lace;
      if (lace < 255) packets.add(partial.takeBytes());
    }
    pos = end;
  }

  if (serial == null) {
    throw const VoiceNoteFormatException('no Ogg pages');
  }
  // A packet still open here was cut off with the file; it is dropped.
  return _Read(serial, packets);
}

Uint8List _page(
  Uint8List packet, {
  required int serial,
  required int sequence,
  required int granule,
  required int flags,
}) {
  final lacing = <int>[
    for (var n = packet.length; n >= 255; n -= 255) 255,
    packet.length % 255,
  ];
  if (lacing.length > 255) {
    throw const VoiceNoteFormatException('Opus packet too large for a page');
  }
  final page = Uint8List(27 + lacing.length + packet.length);
  final view = ByteData.sublistView(page);
  page.setRange(0, 4, const [0x4F, 0x67, 0x67, 0x53]);
  page[4] = 0;
  page[5] = flags;
  view.setInt64(6, granule, Endian.little);
  view.setUint32(14, serial, Endian.little);
  view.setUint32(18, sequence, Endian.little);
  page[26] = lacing.length;
  page.setRange(27, 27 + lacing.length, lacing);
  page.setRange(27 + lacing.length, page.length, packet);
  view.setUint32(22, _crc(page, 0, page.length), Endian.little);
  return page;
}

bool _startsWith(Uint8List bytes, String ascii) {
  if (bytes.length < ascii.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

final _crcTable = List<int>.generate(256, (i) {
  var v = i << 24;
  for (var k = 0; k < 8; k++) {
    v = (v & 0x80000000) != 0
        ? ((v << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
        : (v << 1) & 0xFFFFFFFF;
  }
  return v;
}, growable: false);

/// Ogg's CRC-32 (polynomial 0x04C11DB7, no reflection, no final xor) over
/// one page, with its own checksum field read as zero.
int _crc(Uint8List page, int start, int end) {
  var crc = 0;
  for (var i = start; i < end; i++) {
    final b = (i - start >= 22 && i - start < 26) ? 0 : page[i];
    crc = ((crc << 8) & 0xFFFFFFFF) ^ _crcTable[((crc >> 24) & 0xFF) ^ b];
  }
  return crc;
}
