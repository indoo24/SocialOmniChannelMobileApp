/// The one recorder setup every voice note in the app is made with — the
/// conversation composer's and the saved-reply form's.
///
/// WhatsApp plays a voice note only when it is mono Opus; `record`'s own
/// default is two channels, which Meta accepts and delivers but recipients
/// cannot play. So the channel count is stated here rather than left to
/// the package, and a recording the platform could not make in mono is
/// thrown away rather than sent.
library;

import 'dart:io';

import 'package:record/record.dart';

import 'voice_note_ogg.dart';

/// Mono Opus for speech. 16 kHz is one of Opus's own rates (Android's
/// encoder takes 8/12/16/24/48 kHz) and 24 kbps sits well inside its
/// range; both platforms may still nudge those two to the nearest value
/// the device supports, which is harmless. The channel count is not
/// allowed to move: see [startVoiceNote].
const voiceNoteRecordConfig = RecordConfig(
  encoder: AudioEncoder.opus,
  numChannels: 1,
  sampleRate: 16000,
  bitRate: 24000,
);

/// The platform moved a voice note off mono before it was sent.
class VoiceNoteNotMonoException implements Exception {
  const VoiceNoteNotMonoException(this.numChannels);

  final int numChannels;

  @override
  String toString() =>
      'VoiceNoteNotMonoException: recording has $numChannels channels';
}

/// Starts [recorder] on [voiceNoteRecordConfig], writing to [path].
///
/// Both platforms may fit a requested config to the device and say so
/// only afterwards, through `setOnConfigChanged`. When that report puts
/// the channel count anywhere but 1: if it arrives while `start()` is
/// still finishing, the recording is cancelled and this throws
/// [VoiceNoteNotMonoException]; if it arrives later, [onNotMono] is
/// called for the caller to discard the recording in progress.
Future<void> startVoiceNote(
  AudioRecorder recorder, {
  required String path,
  required void Function() onNotMono,
}) async {
  var started = false;
  int? earlyChannels;
  await recorder.setOnConfigChanged((actual) {
    if (actual.numChannels == voiceNoteRecordConfig.numChannels) return;
    if (started) {
      onNotMono();
    } else {
      earlyChannels = actual.numChannels;
    }
  });
  await recorder.start(voiceNoteRecordConfig, path: path);
  started = true;
  final channels = earlyChannels;
  if (channels != null) {
    try {
      await recorder.cancel();
    } catch (_) {}
    throw VoiceNoteNotMonoException(channels);
  }
}

/// Turns the finished recording at [path] into the file that is uploaded,
/// in place.
///
/// An Ogg recording — Android's — is re-paged into a well-formed Ogg Opus
/// stream ([repageOggOpus]: same audio, correct granule positions and an
/// end-of-stream page), and its own header is the final word on the channel
/// count: anything but mono throws [VoiceNoteNotMonoException], whatever the
/// recorder reported. A file that is Ogg but not usable Opus throws
/// [VoiceNoteFormatException]. Either way the caller discards it.
///
/// A recording in any other container is left exactly as recorded. iOS
/// writes Opus through AVFoundation, whose container is not established yet,
/// and guessing at it here would be worse than sending it unchanged.
void prepareRecordedVoiceNote(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  if (!isOgg(bytes)) return;
  final note = repageOggOpus(bytes);
  if (note.channels != voiceNoteRecordConfig.numChannels) {
    throw VoiceNoteNotMonoException(note.channels);
  }
  file.writeAsBytesSync(note.bytes, flush: true);
}
