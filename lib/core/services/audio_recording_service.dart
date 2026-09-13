import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Native trim channel. ffmpeg_kit_flutter was retired in April 2025
/// (binaries pulled from every registry), so trimming is done with a
/// small native Android MediaExtractor/MediaMuxer implementation
/// instead of a third-party FFmpeg wrapper — see
/// android/app/src/main/kotlin/.../MainActivity.kt.
const MethodChannel _trimChannel = MethodChannel('phonebook/audio_trim');

/// Records microphone audio during a call. This is mic-only recording:
/// it relies on the other party's voice leaking into the mic through
/// the earpiece/speaker (works reliably only in speakerphone mode).
/// There is no supported public Android API to capture both call
/// legs separately in a non-root app.
class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  static const String _folderName = 'call_recordings';

  Future<Directory> _recordingsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording for a call. [callId] is used to build a
  /// predictable, unique file name.
  Future<String?> startRecording(String callId) async {
    if (!await hasPermission()) return null;

    final dir = await _recordingsDir();
    final fileName = 'call_${callId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = p.join(dir.path, fileName);

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        // MIC is the only source a non-root app can legally use here.
        // The Android VOICE_CALL/VOICE_DOWNLINK sources are restricted
        // to system-signed apps and will fail or return silence.
      ),
      path: path,
    );

    _currentPath = path;
    return path;
  }

  /// Stops the active recording and returns its final file path,
  /// or null if nothing was recording.
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _currentPath = null;
    return path;
  }

  Future<bool> isRecording() => _recorder.isRecording();

  String? get currentPath => _currentPath;

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// Renames a saved recording file on disk, returning the new path.
  Future<String> renameFile(String oldPath, String newBaseName) async {
    final file = File(oldPath);
    final ext = p.extension(oldPath);
    final newPath = p.join(p.dirname(oldPath), '$newBaseName$ext');
    final renamed = await file.rename(newPath);
    return renamed.path;
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Trims an m4a/AAC recording between [startMs] and [endMs] using
  /// native MediaExtractor/MediaMuxer (container-level cut, no
  /// re-encoding). Returns the new file's path.
  Future<String> trimRecording({
    required String sourcePath,
    required int startMs,
    required int endMs,
  }) async {
    final dir = p.dirname(sourcePath);
    final base = p.basenameWithoutExtension(sourcePath);
    final outputPath = p.join(dir, '${base}_trimmed_${DateTime.now().millisecondsSinceEpoch}.m4a');

    final result = await _trimChannel.invokeMethod<String>('trim', {
      'sourcePath': sourcePath,
      'outputPath': outputPath,
      'startMs': startMs,
      'endMs': endMs,
    });

    if (result == null) {
      throw StateError('Native trim returned no output path');
    }
    return result;
  }
}
