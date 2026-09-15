import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app_shell.dart';
import 'app/theme/app_theme.dart';
import 'core/database/db_helper.dart';
import 'core/services/recording_foreground_task.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DbHelper.instance.database;
  await RecordingForegroundController.init();

  final granted = await _requestRuntimePermissions();

  // This was missing before: init() only registers the notification
  // channel/config, it does not start the service. Without calling
  // start(), CallDetectionService never subscribes to the phone_state
  // stream, so calls were never detected, recorded, or logged —
  // which is why Recents stayed empty.
  if (granted) {
    await RecordingForegroundController.start();
  }

  runApp(const PhonebookApp());
}

/// Requests every runtime permission the app needs up front. Some of
/// these (READ_CALL_LOG + RECORD_AUDIO together) are sensitive — see
/// the note in android_manifest.md about default-dialer requirements
/// for Play Store distribution.
///
/// Returns true only if the two permissions the foreground service
/// actually needs (microphone + phone state) were granted — POST_
/// NOTIFICATIONS is required on Android 13+ for the persistent
/// "Call recording active" notification to show, but its absence
/// shouldn't block starting the service.
Future<bool> _requestRuntimePermissions() async {
  final statuses = await [
    Permission.microphone,
    Permission.phone,
    Permission.notification,
    Permission.storage,
  ].request();

  final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
  final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;
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
