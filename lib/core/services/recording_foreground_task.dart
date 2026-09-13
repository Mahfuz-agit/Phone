import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../database/db_helper.dart';
import '../repositories/call_repository.dart';
import '../repositories/contact_repository.dart';
import 'audio_recording_service.dart';
import 'call_detection_service.dart';

/// Entry point required by flutter_foreground_task — runs in the
/// same isolate as the foreground service notification, keeping the
/// process alive so [CallDetectionService] + [AudioRecordingService]
/// are not killed when the app is minimized during a call.
@pragma('vm:entry-point')
void startRecordingTaskHandler() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  CallDetectionService? _detectionService;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Repositories open their own DB connection lazily via DbHelper,
    // which is safe to reuse across isolates on the same process.
    await DbHelper.instance.database;

    _detectionService = CallDetectionService(
      audioService: AudioRecordingService(),
      callRepository: CallRepository(),
      contactRepository: ContactRepository(),
    );
    _detectionService!.start();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No periodic work needed — call state arrives via the
    // phone_state stream, not polling.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detectionService?.stop();
    _detectionService = null;
  }
}

/// Call once (e.g. from a settings toggle or app startup) to
/// initialize and launch the persistent foreground service.
class RecordingForegroundController {
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'call_recording_channel',
        channelName: 'Call Recording',
        channelDescription: 'Keeps auto call recording active in the background.',
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
}
