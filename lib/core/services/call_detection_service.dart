import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

import '../models/activity_log_model.dart';
import '../models/call_record_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/call_repository.dart';
import '../repositories/contact_repository.dart';
import 'audio_recording_service.dart';

class CallDetectionService {
  final AudioRecordingService _audio;
  final CallRepository _callRepo;
  final ContactRepository _contactRepo;
  final _activityLog = ActivityLogRepository();

  StreamSubscription<PhoneState>? _sub;

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
      _onStateChanged,
      onError: (Object e, StackTrace st) {
        _activityLog.log(type: ActivityType.call, description: '[DEBUG] Stream error: $e');
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onStateChanged(PhoneState state) async {
    // TEMPORARY DIAGNOSTIC — logs every single state transition this
    // device sends, with the exact enum name and number. Once we
    // confirm CALL_STARTED does or doesn't fire, this block should be
    // removed (it will otherwise clutter the Activity Log over time).
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
        // Some devices/Android versions fire CALL_OUTGOING for a
        // dialed call but never a separate CALL_STARTED once it
        // connects — start the clock and recording here too, as a
        // fallback. If CALL_STARTED also fires later, the guard
        // below (`if (_callStartedAt == null)`) prevents double work.
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
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        await _activityLog.log(
          type: ActivityType.call,
          description: 'Recording skipped: microphone permission not granted '
              '(status: ${micStatus.name}).',
        );
        return;
      }

      final path = await _audio.startRecording(callId);
      if (path == null) {
        await _activityLog.log(
          type: ActivityType.call,
          description: 'Recording did not start for call $callId '
              '(startRecording returned null despite granted permission).',
        );
      } else {
        _isRecording = true;
        await _activityLog.log(
          type: ActivityType.call,
          description: '[DEBUG] Recording started: $path',
        );
      }
    } catch (e) {
      await _activityLog.log(
        type: ActivityType.call,
        description: 'Recording failed to start for call $callId: $e',
      );
    }
  }

  Future<String?> _stopRecordingSafely() async {
    if (!_isRecording) return null;
    try {
      final path = await _audio.stopRecording();
      _isRecording = false;
      return path;
    } catch (e) {
      await _activityLog.log(
        type: ActivityType.call,
        description: 'Recording failed to stop cleanly: $e',
      );
      _isRecording = false;
      return null;
    }
  }

  Future<void> _finishCall() async {
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

    _callStartedAt = null;
    _activeNumber = null;
    _activeCallId = null;
    _activeType = null;
  }
}
