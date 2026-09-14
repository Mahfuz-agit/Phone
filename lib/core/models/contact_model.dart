import 'dart:convert';

class PhoneEntry {
  final String label; // mobile, home, work, other
  final String number;

  const PhoneEntry({required this.label, required this.number});

  Map<String, dynamic> toMap() => {'label': label, 'number': number};

  factory PhoneEntry.fromMap(Map<String, dynamic> map) =>
      PhoneEntry(label: map['label'] ?? 'mobile', number: map['number'] ?? '');
}

class EmailEntry {
  final String label; // home, work, icloud, other
  final String email;

  const EmailEntry({required this.label, required this.email});

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

  // Added for issue #20 ("no address/birthday/organization/URL fields").
  final String? organization;
  final String? address;
  final DateTime? birthday;
  final String? website;

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
    this.organization,
    this.address,
    this.birthday,
    this.website,
  });

  String get fullName => '$firstName $lastName'.trim();

  /// NOTE: kept as plain A–Z/'#' bucketing. Full locale-aware
  /// (Unicode-script-aware) grouping was raised in review but agreed
  /// as out of scope for this pass — non-Latin names will currently
  /// bucket under '#'.
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
        'organization': organization,
        'address': address,
        'birthday': birthday?.toIso8601String(),
        'website': website,
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
      organization: map['organization'],
      address: map['address'],
      birthday: map['birthday'] != null ? DateTime.tryParse(map['birthday']) : null,
      website: map['website'],
    );
  }

  ContactModel copyWith({
    String? firstName,
    String? lastName,
    String? photoPath,
    bool clearPhoto = false,
    List<PhoneEntry>? phones,
    List<EmailEntry>? emails,
    String? note,
    bool? isFavorite,
    String? organization,
    String? address,
    DateTime? birthday,
    String? website,
  }) {
    return ContactModel(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      // `clearPhoto` lets the edit screen explicitly remove a photo —
      // without it there was no way to distinguish "leave unchanged"
      // from "set to null" (part of issue #19, photo remove).
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      phones: phones ?? this.phones,
      emails: emails ?? this.emails,
      note: note ?? this.note,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: DateTime.now(),
      organization: organization ?? this.organization,
      address: address ?? this.address,
      birthday: birthday ?? this.birthday,
      website: website ?? this.website,
    );
  }
}
