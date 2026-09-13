enum CallType { incoming, outgoing, missed }

class CallRecordModel {
  final String id;
  final String? contactId;
  final String phoneNumber;
  final String displayName;
  final CallType type;
  final DateTime timestamp;
  final int durationSeconds;
  final String? recordingPath; // null if not recorded

  CallRecordModel({
    required this.id,
    this.contactId,
    required this.phoneNumber,
    required this.displayName,
    required this.type,
    required this.timestamp,
    required this.durationSeconds,
    this.recordingPath,
  });

  bool get hasRecording => recordingPath != null;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'contact_id': contactId,
        'phone_number': phoneNumber,
        'display_name': displayName,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'duration_seconds': durationSeconds,
        'recording_path': recordingPath,
      };

  factory CallRecordModel.fromDbMap(Map<String, dynamic> map) {
    return CallRecordModel(
      id: map['id'],
      contactId: map['contact_id'],
      phoneNumber: map['phone_number'] ?? '',
      displayName: map['display_name'] ?? '',
      type: CallType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => CallType.incoming,
      ),
      timestamp: DateTime.parse(map['timestamp']),
      durationSeconds: map['duration_seconds'] ?? 0,
      recordingPath: map['recording_path'],
    );
  }

  CallRecordModel copyWith({int? durationSeconds, String? recordingPath}) {
    return CallRecordModel(
      id: id,
      contactId: contactId,
      phoneNumber: phoneNumber,
      displayName: displayName,
      type: type,
      timestamp: timestamp,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      recordingPath: recordingPath ?? this.recordingPath,
    );
  }
}
