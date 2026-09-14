import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';

import '../models/call_record_model.dart';
import '../repositories/call_repository.dart';
import '../repositories/contact_repository.dart';
import 'audio_recording_service.dart';

/// Listens to system phone call state on the **main isolate** and
/// drives auto-recording + call logging.
///
/// Must NOT be started inside a flutter_foreground_task isolate —
/// phone_state requires the main Flutter engine to deliver events
/// reliably.
class CallDetectionService {
  final AudioRecordingService _audio;
  final CallRepository _callRepo;
  final ContactRepository _contactRepo;

  StreamSubscription<PhoneState>? _sub;

  DateTime? _callStartedAt;
  String? _activeNumber;
  String? _activeCallId;
  CallType? _activeType;
  bool _isFinishing = false;

  CallDetectionService({
    required AudioRecordingService audioService,
    required CallRepository callRepository,
    required ContactRepository contactRepository,
  })  : _audio = audioService,
        _callRepo = callRepository,
        _contactRepo = contactRepository;

  bool get isListening => _sub != null;

  void start() {
    if (_sub != null) return;

    debugPrint('[CallDetection] Starting PhoneState listener (main isolate)');
    _sub = PhoneState.stream.listen(
      _onStateChanged,
      onError: (Object e, StackTrace st) {
        debugPrint('[CallDetection] Stream error: $e\n$st');
      },
      cancelOnError: false,
    );
  }

  void stop() {
    debugPrint('[CallDetection] Stopping PhoneState listener');
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onStateChanged(PhoneState state) async {
    try {
      debugPrint(
        '[CallDetection] status=\( {state.status} number= \){state.number}',
      );

      switch (state.status) {
        case PhoneStateStatus.CALL_INCOMING:
          _activeNumber = _normalizeNumber(state.number);
          _activeType = CallType.incoming;
          break;

        case PhoneStateStatus.CALL_OUTGOING:
          _activeNumber = _normalizeNumber(state.number);
          _activeType = CallType.outgoing;
          break;

        case PhoneStateStatus.CALL_STARTED:
          _callStartedAt = DateTime.now();
          _activeNumber ??= _normalizeNumber(state.number);
          _activeType ??= CallType.outgoing;
          _activeCallId = DateTime.now().millisecondsSinceEpoch.toString();

          try {
            await _audio.startRecording(_activeCallId!);
            debugPrint('[CallDetection] Recording started for $_activeCallId');
          } catch (e, st) {
            debugPrint('[CallDetection] startRecording failed: $e\n$st');
          }
          break;

        case PhoneStateStatus.CALL_ENDED:
          await _finishCall();
          break;

        case PhoneStateStatus.NOTHING:
          break;
      }
    } catch (e, st) {
      debugPrint('[CallDetection] _onStateChanged error: $e\n$st');
    }
  }

  Future<void> _finishCall() async {
    if (_isFinishing) return;
    _isFinishing = true;

    try {
      String? recordingPath;
      try {
        recordingPath = await _audio.stopRecording();
        debugPrint('[CallDetection] Recording stopped → $recordingPath');
      } catch (e, st) {
        debugPrint('[CallDetection] stopRecording failed: $e\n$st');
      }

      final number = _activeNumber?.isNotEmpty == true ? _activeNumber! : 'Unknown';
      final start = _callStartedAt;
      final duration =
          start == null ? 0 : DateTime.now().difference(start).inSeconds;

      String? contactId;
      String displayName = number;

      try {
        final matches = await _contactRepo.search(number);
        if (matches.isNotEmpty) {
          contactId = matches.first.id;
          displayName = matches.first.fullName;
        }
      } catch (e, st) {
        debugPrint('[CallDetection] contact search failed: $e\n$st');
      }

      final type = (duration == 0 && _activeType == CallType.incoming)
          ? CallType.missed
          : (_activeType ?? CallType.incoming);

      await _callRepo.logCall(
        contactId: contactId,
        phoneNumber: number,
        displayName: displayName,
        type: type,
        durationSeconds: duration,
        recordingPath: recordingPath,
      );

      debugPrint(
        '[CallDetection] Logged $type call with $displayName '
        '(\( {duration}s, recording= \){recordingPath != null})',
      );
    } catch (e, st) {
      debugPrint('[CallDetection] _finishCall error: $e\n$st');
    } finally {
      _callStartedAt = null;
      _activeNumber = null;
      _activeCallId = null;
      _activeType = null;
      _isFinishing = false;
    }
  }

  String? _normalizeNumber(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
