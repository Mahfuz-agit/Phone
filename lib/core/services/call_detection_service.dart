import 'dart:async';
import 'package:phone_state/phone_state.dart';

import '../models/call_record_model.dart';
import '../repositories/call_repository.dart';
import '../repositories/contact_repository.dart';
import 'audio_recording_service.dart';

/// Listens to phone call state (idle / ringing / offhook) and drives
/// auto-recording start/stop. This must run inside a foreground
/// service to survive the app being backgrounded on Android 10+ —
/// see NOTE at the bottom of this file.
class CallDetectionService {
  final AudioRecordingService _audio;
  final CallRepository _callRepo;
  final ContactRepository _contactRepo;

  StreamSubscription<PhoneState>? _sub;

  DateTime? _callStartedAt;
  String? _activeNumber;
  String? _activeCallId;
  CallType? _activeType;

  CallDetectionService({
    required AudioRecordingService audioService,
    required CallRepository callRepository,
    required ContactRepository contactRepository,
  })  : _audio = audioService,
        _callRepo = callRepository,
        _contactRepo = contactRepository;

  void start() {
    _sub = PhoneState.stream.listen(_onStateChanged);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onStateChanged(PhoneState state) async {
    switch (state.status) {
      case PhoneStateStatus.CALL_INCOMING:
        _activeNumber = state.number;
        _activeType = CallType.incoming;
        break;

      case PhoneStateStatus.CALL_OUTGOING:
        // Fired the moment the user dials, before the other party
        // has picked up. Recording still only starts at CALL_STARTED
        // (i.e. once the call is actually connected).
        _activeNumber = state.number;
        _activeType = CallType.outgoing;
        break;

      case PhoneStateStatus.CALL_STARTED:
        _callStartedAt = DateTime.now();
        _activeNumber ??= state.number;
        _activeType ??= CallType.outgoing;
        _activeCallId = DateTime.now().millisecondsSinceEpoch.toString();
        await _audio.startRecording(_activeCallId!);
        break;

      case PhoneStateStatus.CALL_ENDED:
        await _finishCall();
        break;

      case PhoneStateStatus.NOTHING:
        // No-op: fires on app start / no active call.
        break;
    }
  }

  Future<void> _finishCall() async {
    final recordingPath = await _audio.stopRecording();

    final number = _activeNumber ?? 'Unknown';
    final start = _callStartedAt;
    final duration = start == null ? 0 : DateTime.now().difference(start).inSeconds;

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

// NOTE — Foreground service requirement:
// Android 10+ restricts starting microphone recording from a
// background process. To keep this listener + recorder alive while
// the app is minimized during a call, wrap this service inside a
// foreground service (e.g. via the `flutter_foreground_task` package)
// with a persistent notification such as "Call recording active".
// See recording_foreground_task.dart, which already does this.
