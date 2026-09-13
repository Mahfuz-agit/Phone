enum ActivityType {
  call,
  contactAdded,
  contactEdited,
  contactDeleted,
  recordingRenamed,
  recordingTrimmed,
  backup,
  restore,
}

class ActivityLogModel {
  final String id;
  final ActivityType type;
  final String? contactId;
  final String description;
  final DateTime timestamp;

  ActivityLogModel({
    required this.id,
    required this.type,
    this.contactId,
    required this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'type': type.name,
        'contact_id': contactId,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ActivityLogModel.fromDbMap(Map<String, dynamic> map) {
    return ActivityLogModel(
      id: map['id'],
      type: ActivityType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ActivityType.call,
      ),
      contactId: map['contact_id'],
      description: map['description'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}
