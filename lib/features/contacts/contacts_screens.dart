import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/contact_model.dart';
import '../../core/repositories/contact_repository.dart';

// AddEditContactScreen is defined at the bottom of this same file —
// kept together with List/Detail so the whole Contacts feature lives
// in one file instead of three.

/// =====================================================================
/// SHARED WIDGET: ContactAvatar
/// Used by the list, detail, and search results so avatar rendering
/// logic lives in exactly one place.
/// =====================================================================
class ContactAvatar extends StatelessWidget {
  final ContactModel contact;
  final double size;

  const ContactAvatar({super.key, required this.contact, this.size = 40});

  Color _colorForName(String name) {
    final palette = [
      AppColors.systemBlue,
      AppColors.systemGreen,
      AppColors.systemOrange,
      AppColors.systemRed,
      AppColors.systemYellow,
    ];
    if (name.isEmpty) return AppColors.systemGray;
    return palette[name.codeUnitAt(0) % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (contact.photoPath != null && File(contact.photoPath!).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(contact.photoPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final initials = (contact.firstName.isNotEmpty ? contact.firstName[0] : '') +
        (contact.lastName.isNotEmpty ? contact.lastName[0] : '');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorForName(contact.fullName),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// =====================================================================
/// SCREEN: ContactsListScreen
/// Alphabet-sectioned list with a right-side A-Z index, search bar,
/// and a floating add button — mirrors the stock iOS Contacts app.
/// =====================================================================
class ContactsListScreen extends StatefulWidget {
  const ContactsListScreen({super.key});

  @override
  State<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends State<ContactsListScreen> {
  final _repo = ContactRepository();
  final _searchController = TextEditingController();

  List<ContactModel> _allContacts = [];
  List<ContactModel> _visibleContacts = [];
  Map<String, List<ContactModel>> _sections = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await _repo.getAll();
    setState(() {
      _allContacts = contacts;
      _visibleContacts = contacts;
      _sections = _groupBySection(contacts);
      _loading = false;
    });
  }

  Map<String, List<ContactModel>> _groupBySection(List<ContactModel> contacts) {
    final map = <String, List<ContactModel>>{};
    for (final c in contacts) {
      map.putIfAbsent(c.sectionLetter, () => []).add(c);
    }
    return map;
  }

  void _onSearchChanged(String query) {
    final filtered = query.isEmpty
        ? _allContacts
        : _allContacts
            .where((c) =>
                c.fullName.toLowerCase().contains(query.toLowerCase()) ||
                c.phones.any((p) => p.number.contains(query)))
            .toList();
    setState(() {
      _visibleContacts = filtered;
      _sections = _groupBySection(filtered);
    });
  }

  Future<void> _openAddContact() async {
    final created = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => const AddEditContactScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openDetail(ContactModel contact) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => ContactDetailScreen(contactId: contact.id)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final letters = _sections.keys.toList()..sort();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contacts'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openAddContact,
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: CupertinoSearchTextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        ListView.builder(
                          itemCount: letters.length,
                          itemBuilder: (context, index) {
                            final letter = letters[index];
                            final contacts = _sections[letter]!;
                            return _ContactSection(
                              letter: letter,
                              contacts: contacts,
                              onTap: _openDetail,
                            );
                          },
                        ),
                        if (letters.length > 3)
                          Positioned(
                            right: 2,
                            top: 8,
                            bottom: 8,
                            child: _AlphabetIndex(
                              letters: letters,
                              onLetterTap: (letter) {
                                // Simple jump: rebuild list scrolled to
                                // section start. For a production app,
                                // wire this to a ScrollController with
                                // section offsets.
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  final String letter;
  final List<ContactModel> contacts;
  final void Function(ContactModel) onTap;

  const _ContactSection({
    required this.letter,
    required this.contacts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(letter, style: AppTypography.footnote.copyWith(fontWeight: FontWeight.w600)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: contacts.asMap().entries.map((entry) {
              final isLast = entry.key == contacts.length - 1;
              final contact = entry.value;
              return Column(
                children: [
                  CupertinoListTile(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: ContactAvatar(contact: contact, size: 36),
                    title: Text(contact.fullName, style: AppTypography.body),
                    trailing: contact.isFavorite
                        ? const Icon(CupertinoIcons.star_fill, color: AppColors.systemYellow, size: 18)
                        : null,
                    onTap: () => onTap(contact),
                  ),
                  if (!isLast)
                    const Padding(
                      padding: EdgeInsets.only(left: 60),
                      child: Divider(height: 1, color: AppColors.separator),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _AlphabetIndex extends StatelessWidget {
  final List<String> letters;
  final void Function(String) onLetterTap;

  const _AlphabetIndex({required this.letters, required this.onLetterTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters
          .map((l) => GestureDetector(
                onTap: () => onLetterTap(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text(
                    l,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.systemBlue,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

/// =====================================================================
/// SCREEN: ContactDetailScreen
/// Large avatar, quick-action row (Call/Message/Mail), grouped info
/// sections — mirrors the stock iOS Contacts detail page.
/// =====================================================================
class ContactDetailScreen extends StatefulWidget {
  final String contactId;
  const ContactDetailScreen({super.key, required this.contactId});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  final _repo = ContactRepository();
  ContactModel? _contact;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.getById(widget.contactId);
    setState(() => _contact = c);
  }

  Future<void> _toggleFavorite() async {
    await _repo.toggleFavorite(widget.contactId);
    _changed = true;
    _load();
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Contact'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.delete(widget.contactId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (_) => AddEditContactScreen(existing: _contact),
      ),
    );
    if (result == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contact'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: contact == null ? null : _openEdit,
          child: const Text('Edit'),
        ),
      ),
      child: SafeArea(
        child: contact == null
            ? const Center(child: CupertinoActivityIndicator())
            : PopScope(
                onPopInvoked: (didPop) {
                  if (didPop) {
                    // Let caller know if we should refresh the list.
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          ContactAvatar(contact: contact, size: 90),
                          const SizedBox(height: 12),
                          Text(contact.fullName, style: AppTypography.title1),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _QuickAction(icon: CupertinoIcons.phone_fill, label: 'Call', onTap: () {}),
                        _QuickAction(icon: CupertinoIcons.chat_bubble_fill, label: 'Message', onTap: () {}),
                        _QuickAction(icon: CupertinoIcons.mail_solid, label: 'Mail', onTap: () {}),
                        _QuickAction(
                          icon: contact.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                          label: 'Favorite',
                          onTap: _toggleFavorite,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (contact.phones.isNotEmpty)
                      _InfoCard(
                        rows: contact.phones
                            .map((p) => _InfoRow(label: p.label, value: p.number))
                            .toList(),
                      ),
                    if (contact.emails.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        rows: contact.emails
                            .map((e) => _InfoRow(label: e.label, value: e.email))
                            .toList(),
                      ),
                    ],
                    if (contact.note != null && contact.note!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(rows: [_InfoRow(label: 'Note', value: contact.note!)]),
                    ],
                    const SizedBox(height: 24),
                    CupertinoButton(
                      color: AppColors.systemRed.withOpacity(0.1),
                      onPressed: _delete,
                      child: const Text('Delete Contact', style: TextStyle(color: AppColors.systemRed)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.systemGray6,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.systemBlue, size: 22),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTypography.caption1),
      ],
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  _InfoRow({required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final isLast = entry.key == rows.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(entry.value.label, style: AppTypography.footnote),
                    ),
                    Expanded(
                      child: Text(entry.value.value, style: AppTypography.body),
                    ),
                  ],
                ),
              ),
              if (!isLast) const Divider(height: 1, indent: 16, color: AppColors.separator),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// =====================================================================
/// SCREEN: AddEditContactScreen
/// Modal-sheet style form (Cancel / Save) for creating or editing a
/// contact. Kept in this file alongside List/Detail per the
/// "fewer files" instruction — all three Contacts screens live here.
/// =====================================================================
class AddEditContactScreen extends StatefulWidget {
  final ContactModel? existing;
  const AddEditContactScreen({super.key, this.existing});

  bool get isEditing => existing != null;

  @override
  State<AddEditContactScreen> createState() => _AddEditContactScreenState();
}

class _AddEditContactScreenState extends State<AddEditContactScreen> {
  final _repo = ContactRepository();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _note;
  late List<PhoneEntry> _phones;
  late List<EmailEntry> _emails;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _firstName = TextEditingController(text: e?.firstName ?? '');
    _lastName = TextEditingController(text: e?.lastName ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _phones = List.of(e?.phones ?? const [PhoneEntry(label: 'mobile', number: '')]);
    _emails = List.of(e?.emails ?? const []);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _note.dispose();
    super.dispose();
  }

  void _addPhoneField() {
    setState(() => _phones.add(const PhoneEntry(label: 'mobile', number: '')));
  }

  void _addEmailField() {
    setState(() => _emails.add(const EmailEntry(label: 'home', email: '')));
  }

  Future<void> _save() async {
    if (_firstName.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final cleanPhones = _phones.where((p) => p.number.trim().isNotEmpty).toList();
    final cleanEmails = _emails.where((e) => e.email.trim().isNotEmpty).toList();

    if (widget.isEditing) {
      await _repo.update(widget.existing!.copyWith(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phones: cleanPhones,
        emails: cleanEmails,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ));
    } else {
      await _repo.create(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phones: cleanPhones,
        emails: cleanEmails,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        middle: Text(widget.isEditing ? 'Edit Contact' : 'New Contact'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FormCard(
              children: [
                CupertinoTextField(
                  controller: _firstName,
                  placeholder: 'First name',
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                const Divider(height: 1, indent: 16, color: AppColors.separator),
                CupertinoTextField(
                  controller: _lastName,
                  placeholder: 'Last name',
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FormCard(
              children: [
                for (int i = 0; i < _phones.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(_phones[i].label, style: AppTypography.footnote),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Phone number',
                            keyboardType: TextInputType.phone,
                            decoration: null,
                            controller: TextEditingController(text: _phones[i].number)
                              ..selection = TextSelection.collapsed(offset: _phones[i].number.length),
                            onChanged: (v) => _phones[i] = PhoneEntry(label: _phones[i].label, number: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onPressed: _addPhoneField,
                  child: const Text('+ Add phone'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FormCard(
              children: [
                for (int i = 0; i < _emails.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(_emails[i].label, style: AppTypography.footnote),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Email',
                            keyboardType: TextInputType.emailAddress,
                            decoration: null,
                            controller: TextEditingController(text: _emails[i].email)
                              ..selection = TextSelection.collapsed(offset: _emails[i].email.length),
                            onChanged: (v) => _emails[i] = EmailEntry(label: _emails[i].label, email: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onPressed: _addEmailField,
                  child: const Text('+ Add email'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FormCard(
              children: [
                CupertinoTextField(
                  controller: _note,
                  placeholder: 'Note',
                  maxLines: 3,
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;
  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: children),
    );
  }
}
