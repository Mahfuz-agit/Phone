import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process alive during calls so the main-isolate
/// CallDetectionService + AudioRecordingService are not killed.
///
/// IMPORTANT: Do NOT start CallDetectionService here.
/// phone_state only delivers events reliably on the main isolate.
@pragma('vm:entry-point')
void startRecordingTaskHandler() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Intentionally empty — process keep-alive only.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No periodic work.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Nothing to clean up.
  }
}

class RecordingForegroundController {
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'call_recording_channel',
        channelName: 'Call Recording',
        channelDescription:
            'Keeps auto call recording active in the background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<ServiceRequestResult> start() {
    return FlutterForegroundTask.startService(
      notificationTitle: 'Phonebook',
      notificationText: 'Call recording is active',
      callback: startRecordingTaskHandler,
    );
  }

  static Future<ServiceRequestResult> stop() {
    return FlutterForegroundTask.stopService();
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
