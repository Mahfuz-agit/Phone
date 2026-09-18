import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

import '../models/activity_log_model.dart';
import '../models/call_record_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/call_repository.dart';
import '../repositories/contact_repository.dart';
import 'audio_recording_service.dart';
import 'settings_service.dart';

class CallDetectionService {
  final AudioRecordingService _audio;
  final CallRepository _callRepo;
  final ContactRepository _contactRepo;
  final _activityLog = ActivityLogRepository();
  final _settings = SettingsService();

  StreamSubscription<PhoneState>? _sub;
  Future<void> _chain = Future.value();

  DateTime? _callStartedAt;
  String? _activeNumber;
  String? _activeCallId;
  CallType? _activeType;
  bool _isRecording = false;

  CallDetectionService({
    required AudioRecordingService audioService,
    required CallRepository callRepository,
    required ContactRepository contactRepository,
  })  : _audio = audioService,
        _callRepo = callRepository,
        _contactRepo = contactRepository;

  void start() {
    _sub = PhoneState.stream.listen(
      (state) {
        _chain = _chain.then((_) => _handleStateChanged(state)).catchError((e) {
          _activityLog.log(type: ActivityType.call, description: '[DEBUG] Handler error: $e');
        });
      },
      onError: (Object e, StackTrace st) {
        _activityLog.log(type: ActivityType.call, description: '[DEBUG] Stream error: $e');
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _handleStateChanged(PhoneState state) async {
    await _activityLog.log(
      type: ActivityType.call,
      description: '[DEBUG] phone_state: ${state.status.name}, number: ${state.number ?? "null"}',
    );

    switch (state.status) {
      case PhoneStateStatus.CALL_INCOMING:
        _activeNumber = state.number;
        _activeType = CallType.incoming;
        break;

      case PhoneStateStatus.CALL_OUTGOING:
        _activeNumber = state.number;
        _activeType = CallType.outgoing;
        if (_callStartedAt == null) {
          _callStartedAt = DateTime.now();
          _activeCallId = DateTime.now().millisecondsSinceEpoch.toString();
          await _startRecordingSafely(_activeCallId!);
        }
        break;

      case PhoneStateStatus.CALL_STARTED:
        _activeNumber ??= state.number;
        _activeType ??= CallType.outgoing;
        if (_callStartedAt == null) {
          _callStartedAt = DateTime.now();
          _activeCallId = DateTime.now().millisecondsSinceEpoch.toString();
          await _startRecordingSafely(_activeCallId!);
        }
        break;

      case PhoneStateStatus.CALL_ENDED:
        await _finishCall();
        break;

      case PhoneStateStatus.NOTHING:
        break;
    }
  }

  Future<void> _startRecordingSafely(String callId) async {
    try {
      final enabled = await _settings.isRecordingEnabled();
      if (!enabled) {
        await _activityLog.log(type: ActivityType.call, description: 'Recording skipped: disabled in Settings.');
        return;
      }

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        await _activityLog.log(
          type: ActivityType.call,
          description: 'Recording skipped: microphone permission not granted (status: ${micStatus.name}).',
        );
        return;
      }

      final path = await _audio.startRecording(callId);
      if (path == null) {
        await _activityLog.log(type: ActivityType.call, description: 'Recording did not start for call $callId.');
      } else {
        _isRecording = true;
        await _activityLog.log(type: ActivityType.call, description: '[DEBUG] Recording started: $path');
      }
    } catch (e) {
      await _activityLog.log(type: ActivityType.call, description: 'Recording failed to start for call $callId: $e');
    }
  }

  Future<String?> _stopRecordingSafely() async {
    if (!_isRecording) return null;
    try {
      final path = await _audio.stopRecording();
      _isRecording = false;
      return path;
    } catch (e) {
      await _activityLog.log(type: ActivityType.call, description: 'Recording failed to stop cleanly: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> _finishCall() async {
    // Fix: this is the "Unknown call" bug. If we never received a
    // CALL_INCOMING/CALL_OUTGOING/CALL_STARTED before this CALL_ENDED
    // — i.e. we have neither a number nor a type — this is almost
    // certainly a spurious state event (e.g. fired once when the
    // foreground service's listener first attaches), not a real
    // call. Log it for visibility and skip creating a call record.
    if (_activeType == null && _activeNumber == null) {
      await _activityLog.log(
        type: ActivityType.call,
        description: '[DEBUG] Ignored CALL_ENDED with no prior number/type (likely a spurious event, not a real call).',
      );
      _callStartedAt = null;
      _activeCallId = null;
      return;
    }

    final recordingPath = await _stopRecordingSafely();

    final number = _activeNumber ?? 'Unknown';
    final start = _callStartedAt;
    final duration = start == null ? 0 : DateTime.now().difference(start).inSeconds;

    await _activityLog.log(
      type: ActivityType.call,
      description: '[DEBUG] Call ended. started=${start != null}, duration=${duration}s, '
          'recording=${recordingPath != null}',
    );

    final contact = await _contactRepo.search(number);
    final matched = contact.isNotEmpty ? contact.first : null;

    await _callRepo.logCall(
      contactId: matched?.id,
      phoneNumber: number,
      displayName: matched?.fullName ?? number,
      type: duration == 0 && _activeType == CallType.incoming
          ? CallType.missed
          : (_activeType ?? CallType.incoming),
      durationSeconds: duration,
      recordingPath: recordingPath,
    );

    // Fix: signals the main UI isolate that data changed, since this
    // whole service runs inside flutter_foreground_task's separate
    // background isolate — without this, CallsListScreen had no way
    // to know new data existed until the app was fully restarted.
    try {
      FlutterForegroundTask.sendDataToMain('call_logged');
    } catch (_) {
      // Best-effort — if the main isolate isn't listening yet (e.g.
      // very early in startup), the call is still safely in the DB
      // and will show up on next natural reload.
    }

    _callStartedAt = null;
    _activeNumber = null;
    _activeCallId = null;
    _activeType = null;
  }
}
