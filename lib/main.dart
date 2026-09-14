import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app_shell.dart';
import 'app/theme/app_theme.dart';
import 'core/database/db_helper.dart';
import 'core/repositories/call_repository.dart';
import 'core/repositories/contact_repository.dart';
import 'core/services/audio_recording_service.dart';
import 'core/services/call_detection_service.dart';
import 'core/services/recording_foreground_task.dart';

/// Global instance — lives on the main isolate for the whole app lifetime.
late final CallDetectionService callDetectionService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DbHelper.instance.database;
  await RecordingForegroundController.init();

  callDetectionService = CallDetectionService(
    audioService: AudioRecordingService(),
    callRepository: CallRepository(),
    contactRepository: ContactRepository(),
  );

  final granted = await _requestRuntimePermissions();

  if (granted) {
    await _startCallPipeline();
  } else {
    debugPrint(
      '[main] Mic/Phone permission missing — call detection not started',
    );
  }

  runApp(const PhonebookApp());
}

/// Starts both the keep-alive foreground service and the main-isolate
/// phone state listener.
Future<void> _startCallPipeline() async {
  try {
    final result = await RecordingForegroundController.start();
    debugPrint('[main] Foreground service start → $result');
  } catch (e, st) {
    debugPrint('[main] Foreground service failed: $e\n$st');
  }

  callDetectionService.start();
  debugPrint('[main] CallDetectionService started on main isolate');
}

/// Returns true only when microphone + phone state are granted.
/// Notification is requested but not required to start detection.
Future<bool> _requestRuntimePermissions() async {
  final statuses = await [
    Permission.microphone,
    Permission.phone,
    Permission.notification,
    Permission.storage,
  ].request();

  // READ_CALL_LOG helps phone_state return the caller number on some OEMs.
  // Permission.phone already covers it on most Android versions; this is a
  // best-effort extra request where the OS exposes it separately.
  try {
    await Permission.phone.request();
  } catch (_) {}

  final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
  final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;

  debugPrint(
    '[main] permissions → mic=$micGranted phone=$phoneGranted '
    'notification=${statuses[Permission.notification]?.isGranted}',
  );

  return micGranted && phoneGranted;
}

class PhonebookApp extends StatelessWidget {
  const PhonebookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Phonebook',
      debugShowCheckedModeBanner: false,
      theme: cupertinoAppTheme,
      home: const AppShell(),
    );
  }
}
