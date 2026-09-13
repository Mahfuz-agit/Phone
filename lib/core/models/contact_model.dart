import 'dart:convert';

class PhoneEntry {
  final String label; // mobile, home, work
  final String number;

  PhoneEntry({required this.label, required this.number});

  Map<String, dynamic> toMap() => {'label': label, 'number': number};

  factory PhoneEntry.fromMap(Map<String, dynamic> map) =>
      PhoneEntry(label: map['label'] ?? 'mobile', number: map['number'] ?? '');
}

class EmailEntry {
  final String label;
  final String email;

  EmailEntry({required this.label, required this.email});

  Map<String, dynamic> toMap() => {'label': label, 'email': email};

  factory EmailEntry.fromMap(Map<String, dynamic> map) =>
      EmailEntry(label: map['label'] ?? 'home', email: map['email'] ?? '');
}

class ContactModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? photoPath;
  final List<PhoneEntry> phones;
  final List<EmailEntry> emails;
  final String? note;
  final bool isFavorite;
  final DateTime updatedAt;

  ContactModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.photoPath,
    this.phones = const [],
    this.emails = const [],
    this.note,
    this.isFavorite = false,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get sectionLetter {
    if (firstName.isEmpty) return '#';
    final c = firstName[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'photo_path': photoPath,
        'phones': jsonEncode(phones.map((p) => p.toMap()).toList()),
        'emails': jsonEncode(emails.map((e) => e.toMap()).toList()),
        'note': note,
        'is_favorite': isFavorite ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ContactModel.fromDbMap(Map<String, dynamic> map) {
    final phonesRaw = jsonDecode(map['phones'] ?? '[]') as List;
    final emailsRaw = jsonDecode(map['emails'] ?? '[]') as List;
    return ContactModel(
      id: map['id'],
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      photoPath: map['photo_path'],
      phones: phonesRaw.map((p) => PhoneEntry.fromMap(p)).toList(),
      emails: emailsRaw.map((e) => EmailEntry.fromMap(e)).toList(),
      note: map['note'],
      isFavorite: (map['is_favorite'] ?? 0) == 1,
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  ContactModel copyWith({
    String? firstName,
    String? lastName,
    String? photoPath,
    List<PhoneEntry>? phones,
    List<EmailEntry>? emails,
    String? note,
    bool? isFavorite,
  }) {
    return ContactModel(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      photoPath: photoPath ?? this.photoPath,
      phones: phones ?? this.phones,
      emails: emails ?? this.emails,
      note: note ?? this.note,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: DateTime.now(),
    );
  }
}
