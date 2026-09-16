import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app_shell.dart';
import 'app/splash_screen.dart';
import 'app/theme/app_theme.dart';
import 'core/database/db_helper.dart';
import 'core/services/recording_foreground_task.dart';
import 'core/services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fix: previously all of this ran with `await` BEFORE runApp(),
  // meaning the very first frame the user saw was whatever blank
  // frame the OS shows while Dart is still busy — on a slow phone
  // that reads as a frozen/janky launch. Now the splash renders on
  // the first frame, and initialization happens underneath it.
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

/// Shows SplashScreen immediately, runs all startup work in the
/// background, then cross-fades into AppShell once ready. This is
/// the piece that actually fixes "slow phone feels janky on open" —
/// there's always something visible and animating from frame one.
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

    final granted = await _requestRuntimePermissions();
    if (granted) {
      final recordingEnabled = await SettingsService().isRecordingEnabled();
      if (recordingEnabled) {
        await RecordingForegroundController.start();
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
