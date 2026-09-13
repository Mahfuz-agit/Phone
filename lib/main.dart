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
  await _requestRuntimePermissions();

  runApp(const PhonebookApp());
}

/// Requests every runtime permission the app needs up front. Some of
/// these (READ_CALL_LOG + RECORD_AUDIO together) are sensitive — see
/// the note in android_manifest.md about default-dialer requirements
/// for Play Store distribution.
Future<void> _requestRuntimePermissions() async {
  await [
    Permission.microphone,
    Permission.phone,
    Permission.contacts,
    Permission.storage,
  ].request();
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
