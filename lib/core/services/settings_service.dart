import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SettingsService {
  static const _fileName = 'app_settings.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      // Corrupt or unreadable settings file — fall back to defaults
      // rather than crashing the app on startup.
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data));
  }

  /// Defaults to `true` — recording is opt-out, not opt-in, matching
  /// the app's original design intent. The toggle lets the user turn
  /// it off entirely (e.g. before a sensitive call) without touching
  /// permissions.
  Future<bool> isRecordingEnabled() async {
    final data = await _read();
    return data['recordingEnabled'] as bool? ?? true;
  }

  Future<void> setRecordingEnabled(bool value) async {
    final data = await _read();
    data['recordingEnabled'] = value;
    await _write(data);
  }
}
