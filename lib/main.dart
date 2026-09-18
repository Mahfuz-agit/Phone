import 'package:flutter/cupertino.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app_shell.dart';
import 'app/splash_screen.dart';
import 'app/theme/app_theme.dart';
import 'core/database/db_helper.dart';
import 'core/repositories/call_repository.dart';
import 'core/services/public_mirror_service.dart';
import 'core/services/recording_foreground_task.dart';
import 'core/services/refresh_bus.dart';
import 'core/services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhonebookApp());
}

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
      home: const AppStartup(),
    );
  }
}

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await DbHelper.instance.database;
    await RecordingForegroundController.init();

    // Fix: bridges the background foreground-service isolate (where
    // CallDetectionService actually runs) back to this, the main UI
    // isolate. Every time the background side logs a call, it calls
    // FlutterForegroundTask.sendDataToMain(...), which arrives here
    // and bumps RefreshBus so any listening screen reloads instantly
    // — this is what makes Calls update live instead of only after
    // an app restart.
    FlutterForegroundTask.addTaskDataCallback((data) {
      RefreshBus.notify();
    });

    // Fix: two-way sync with the public mirror files, fully
    // automatic — no manual "Restore" tap needed. Runs first so any
    // edits made directly to the JSON files (or data recovered after
    // a reinstall) are merged in before the UI loads.
    try {
      await PublicMirrorService().restoreFromMirror();
    } catch (_) {
      // Best-effort — a missing/corrupt mirror file shouldn't block
      // startup; the app just proceeds with whatever's in the DB.
    }

    final granted = await _requestRuntimePermissions();
    if (granted) {
      final recordingEnabled = await SettingsService().isRecordingEnabled();
      if (recordingEnabled) {
        await RecordingForegroundController.start();
      }

      // Fix: system call history sync is now automatic on every
      // launch — the manual "Sync System Call History" button was
      // removed from Settings.
      try {
        await CallRepository().importSystemCallLog();
      } catch (_) {
        // Best-effort — shouldn't block startup either.
      }
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _ready ? const AppShell(key: ValueKey('shell')) : const SplashScreen(key: ValueKey('splash')),
    );
  }
}
