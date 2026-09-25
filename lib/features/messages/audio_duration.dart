/// Reads a recording's length from its container headers, without decoding
/// or playing it.
///
/// A voice note's bubble shows its full length before it is ever played, the
/// way WhatsApp does. The backend's `duration_ms` covers notes recorded in
/// this app; notes that arrive from a platform (a customer's WhatsApp voice
/// note) often carry none, and the player only reports a duration once it is
/// playing. This fills that gap from the file itself: the same bytes the
/// player would load, parsed for the one number every container already
/// stores.
///
/// Covers the formats voice notes actually arrive in — Ogg Opus (WhatsApp and
/// this app's own recorder), Ogg Vorbis, MP4/M4A (AAC) and WAV. Anything else
/// returns null, and the bubble falls back to the player's duration once
/// playback starts.
library;

import 'dart:typed_data';

/// The duration stored in [bytes]' container, or null when the format is not
/// one of those above or the header is missing or implausible.
Duration? audioDurationFromBytes(Uint8List bytes) {
  try {
    final duration =
        _oggDuration(bytes) ?? _mp4Duration(bytes) ?? _wavDuration(bytes);
    // A voice note is seconds to minutes long; anything outside a day is a
    // misread header, not a recording.
    if (duration == null ||
        duration <= Duration.zero ||
        duration > const Duration(hours: 24)) {
      return null;
    }
    return duration;
  } on RangeError {
    return null;
  }
}

bool _matches(Uint8List b, int at, List<int> ascii) {
  if (at < 0 || at + ascii.length > b.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (b[at + i] != ascii[i]) return false;
  }
  return true;
}

int _indexOf(Uint8List b, List<int> ascii, [int from = 0]) {
  for (var i = from; i <= b.length - ascii.length; i++) {
    if (_matches(b, i, ascii)) return i;
  }
  return -1;
}

const _oggS = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
const _opusHead = [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64];
const _vorbisId = [0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]; // \x01vorbis

/// Ogg: the last page's granule position is the total sample count. Opus
/// counts at 48 kHz and prepends `pre_skip` priming samples that are never
/// played; Vorbis counts at the rate in its identification header.
Duration? _oggDuration(Uint8List b) {
  if (!_matches(b, 0, _oggS)) return null;
  final view = ByteData.sublistView(b);

  int rate;
  var preSkip = 0;
  final opus = _indexOf(b, _opusHead);
  if (opus >= 0 && opus + 12 <= b.length) {
    rate = 48000;
    preSkip = view.getUint16(opus + 10, Endian.little);
  } else {
    final vorbis = _indexOf(b, _vorbisId);
    if (vorbis < 0 || vorbis + 16 > b.length) return null;
    rate = view.getUint32(vorbis + 12, Endian.little);
    if (rate == 0) return null;
  }

  // Walk back from the end to the last page that carries a real granule
  // position (-1 marks a page on which no packet ends).
  for (var i = b.length - 27; i >= 0; i--) {
    if (!_matches(b, i, _oggS) || b[i + 4] != 0) continue;
    final granule = view.getInt64(i + 6, Endian.little);
    if (granule <= 0) continue;
    final samples = granule - preSkip;
    if (samples <= 0) return null;
    return Duration(microseconds: (samples * 1000000) ~/ rate);
  }
  return null;
}

const _ftyp = [0x66, 0x74, 0x79, 0x70];
const _mvhd = [0x6D, 0x76, 0x68, 0x64];

/// MP4/M4A: the movie header (`mvhd`) stores the duration in its own
/// timescale. Version 0 uses 32-bit fields, version 1 64-bit ones. `moov` may
/// sit at either end of the file, so the box is searched for, not walked to.
Duration? _mp4Duration(Uint8List b) {
  if (!_matches(b, 4, _ftyp)) return null;
  final at = _indexOf(b, _mvhd);
  if (at < 0) return null;
  final data = at + 4;
  final view = ByteData.sublistView(b);
  final version = b[data];
  final int timescale;
  final int units;
  if (version == 1) {
    timescale = view.getUint32(data + 20);
    units = view.getUint64(data + 24);
  } else {
    timescale = view.getUint32(data + 12);
    units = view.getUint32(data + 16);
  }
  if (timescale == 0) return null;
  return Duration(microseconds: (units * 1000000) ~/ timescale);
}

const _riff = [0x52, 0x49, 0x46, 0x46];
const _wave = [0x57, 0x41, 0x56, 0x45];
const _fmt = [0x66, 0x6D, 0x74, 0x20];
const _data = [0x64, 0x61, 0x74, 0x61];

/// WAV: the `data` chunk's size over the `fmt ` chunk's byte rate.
Duration? _wavDuration(Uint8List b) {
  if (!_matches(b, 0, _riff) || !_matches(b, 8, _wave)) return null;
  final view = ByteData.sublistView(b);
  final fmt = _indexOf(b, _fmt, 12);
  final data = _indexOf(b, _data, 12);
  if (fmt < 0 || data < 0) return null;
  final byteRate = view.getUint32(fmt + 16, Endian.little);
  final size = view.getUint32(data + 4, Endian.little);
  if (byteRate == 0) return null;
  return Duration(microseconds: (size * 1000000) ~/ byteRate);
}
