import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/contact_model.dart';
import '../../core/repositories/contact_repository.dart';

// AddEditContactScreen is defined at the bottom of this same file —
// kept together with List/Detail so the whole Contacts feature lives
// in one file instead of three.

/// =====================================================================
/// SHARED HELPERS — alert / launch / multi-item picker
/// Top-level (not tied to one State) so both the list (swipe-to-call)
/// and the detail screen (quick actions) can reuse them.
/// =====================================================================

Future<void> _showAlert(BuildContext context, String title, String message) async {
  if (!context.mounted) return;
  await showCupertinoDialog(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(ctx))],
    ),
  );
}

/// Launches [uri] and — fix for issue #31 — actually checks the
/// return value of canLaunchUrl()/launchUrl() instead of assuming
/// success, surfacing a clear message when nothing can handle it
/// (e.g. manifest `<queries>` misconfigured, or emulator with no
/// dialer/mail app installed).
Future<void> _launchOrWarn(BuildContext context, Uri uri) async {
  bool launched = false;
  try {
    if (await canLaunchUrl(uri)) {
      launched = await launchUrl(uri);
    }
  } catch (_) {
    launched = false;
  }
  if (!launched) {
    await _showAlert(context, "Couldn't Open", 'No app available to handle this action.');
  }
}

/// Fix for issue #32: previously the first phone/email was always
/// used silently. Now, if there's more than one candidate, the user
/// picks which one via an action sheet.
Future<void> _pickAndLaunch<T>({
  required BuildContext context,
  required List<T> items,
  required String Function(T) labelOf,
  required Uri Function(T) uriOf,
  required String emptyMessage,
}) async {
  if (items.isEmpty) {
    await _showAlert(context, 'Not Available', emptyMessage);
    return;
  }
  if (items.length == 1) {
    await _launchOrWarn(context, uriOf(items.first));
    return;
  }
  final selected = await showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      actions: items
          .map((item) => CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, item),
                child: Text(labelOf(item)),
              ))
          .toList(),
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
  if (selected != null) {
    await _launchOrWarn(context, uriOf(selected));
  }
}

Future<bool> _confirmDialog(BuildContext context, {required String title, required String body}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx, false)),
        CupertinoDialogAction(
          isDestructiveAction: true,
          child: const Text('Delete'),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// =====================================================================
/// SHARED WIDGET: ContactAvatar
/// Fix for #35/#36: previously used a synchronous File.existsSync()
/// check on every build (blocks the UI thread) with no handling for a
/// corrupt/undecodable image file. Image.file's errorBuilder covers
/// both missing AND corrupt files in one place, with no sync I/O.
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

  Widget _initialsCircle() {
    final initials = (contact.firstName.isNotEmpty ? contact.firstName[0] : '') +
        (contact.lastName.isNotEmpty ? contact.lastName[0] : '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _colorForName(contact.fullName), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = contact.photoPath;
    if (path == null || path.isEmpty) return _initialsCircle();

    return ClipOval(
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initialsCircle(),
      ),
    );
  }
}

/// =====================================================================
/// SCREEN: ContactsListScreen
/// =====================================================================
class ContactsListScreen extends StatefulWidget {
  final VoidCallback? onMoreTap;
  const ContactsListScreen({super.key, this.onMoreTap});

  @override
  State<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends State<ContactsListScreen> {
  final _repo = ContactRepository();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, List<ContactModel>> _sections = {};
  Map<String, GlobalKey> _sectionKeys = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Fix for #44 — this controller was never disposed.
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _rebuildSections(List<ContactModel> contacts) {
    final map = <String, List<ContactModel>>{};
    for (final c in contacts) {
      map.putIfAbsent(c.sectionLetter, () => []).add(c);
    }
    _sections = map;
    // A fresh GlobalKey per letter each time the section list changes
    // (add/delete/search) — stale keys from a previous build would
    // point at widgets no longer in the tree.
    _sectionKeys = {for (final letter in map.keys) letter: GlobalKey()};
  }

  Future<void> _load() async {
    final contacts = await _repo.getAll();
    if (!mounted) return; // fix for #8
    setState(() {
      _rebuildSections(contacts);
      _loading = false;
    });
  }

  /// Delegates to ContactRepository.search(), which already handles
  /// name/email/note matching and phone-number-format normalization
  /// (#21, #22) — no need to duplicate that logic here.
  Future<void> _onSearchChanged(String query) async {
    final results = await _repo.search(query);
    if (!mounted) return;
    setState(() => _rebuildSections(results));
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
    // Fix for #3/#6/#47: ContactDetailScreen now reliably returns
    // `true` on every exit path (edit, favorite toggle, delete, and
    // both the custom back button and the system back gesture), so
    // this reload actually fires when something changed.
    if (changed == true) _load();
  }

  void _onLetterTap(String letter) {
    final ctx = _sectionKeys[letter]?.currentContext;
    if (ctx != null) {
      // Fix for #1/#2: previously this callback was empty. Because
      // the list below is built eagerly (not ListView.builder), every
      // section's GlobalKey already has a mounted context to scroll
      // to, even for sections currently off-screen.
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut, alignment: 0);
    }
  }

  Future<void> _swipeDelete(ContactModel contact) async {
    try {
      await _repo.delete(contact.id);
    } catch (e) {
      // Fix for #29 — delete failures were silently swallowed.
      if (mounted) await _showAlert(context, 'Delete Failed', e.toString());
    } finally {
      _load();
    }
  }

  Future<void> _swipeCall(ContactModel contact) async {
    await _pickAndLaunch<PhoneEntry>(
      context: context,
      items: contact.phones,
      labelOf: (p) => '${p.label}: ${p.number}',
      uriOf: (p) => Uri(scheme: 'tel', path: p.number),
      emptyMessage: 'This contact has no phone number saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fix for #26: full A-Z (+ '#') index is always shown; letters
    // with no contacts are dimmed and disabled rather than omitted.
    final letters = _sections.keys.toList()..sort();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contacts'),
        leading: widget.onMoreTap == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onMoreTap,
                child: const Icon(CupertinoIcons.gear_alt),
              ),
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
                    child: _sections.isEmpty
                        ? Center(child: Text('No contacts', style: AppTypography.subhead))
                        : Stack(
                            children: [
                              // Built eagerly (not .builder) so every
                              // section header has a real, mounted
                              // GlobalKey context to scroll to — see
                              // _onLetterTap. Fine for the scale of a
                              // personal phonebook (hundreds, not tens
                              // of thousands, of contacts).
                              ListView(
                                controller: _scrollController,
                                children: letters
                                    .map((letter) => _ContactSection(
                                          key: _sectionKeys[letter],
                                          letter: letter,
                                          contacts: _sections[letter]!,
                                          onTap: _openDetail,
                                          onSwipeCall: _swipeCall,
                                          onSwipeDelete: _swipeDelete,
                                        ))
                                    .toList(),
                              ),
                              Positioned(
                                right: 2,
                                top: 8,
                                bottom: 8,
                                child: _AlphabetIndex(
                                  activeLetters: _sections.keys.toSet(),
                                  onLetterTap: _onLetterTap,
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
  final Future<void> Function(ContactModel) onSwipeCall;
  final Future<void> Function(ContactModel) onSwipeDelete;

  const _ContactSection({
    super.key,
    required this.letter,
    required this.contacts,
    required this.onTap,
    required this.onSwipeCall,
    required this.onSwipeDelete,
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
          decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: contacts.asMap().entries.map((entry) {
              final isLast = entry.key == contacts.length - 1;
              final contact = entry.value;
              return Column(
                children: [
                  // Fix for #28/#29: swipe right to call, swipe left
                  // to delete (with confirmation + error handling).
                  Dismissible(
                    key: ValueKey(contact.id),
                    direction: DismissDirection.horizontal,
                    background: Container(
                      color: AppColors.systemGreen,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(CupertinoIcons.phone_fill, color: Colors.white),
                    ),
                    secondaryBackground: Container(
                      color: AppColors.systemRed,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(CupertinoIcons.delete_solid, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        await onSwipeCall(contact);
                        return false; // never actually remove the tile for "call"
                      }
                      return _confirmDialog(
                        context,
                        title: 'Delete Contact',
                        body: 'Delete ${contact.fullName}? This cannot be undone.',
                      );
                    },
                    onDismissed: (_) => onSwipeDelete(contact),
                    child: CupertinoListTile(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: ContactAvatar(contact: contact, size: 36),
                      title: Text(contact.fullName, style: AppTypography.body),
                      trailing: contact.isFavorite
                          ? const Icon(CupertinoIcons.star_fill, color: AppColors.systemYellow, size: 18)
                          : null,
                      onTap: () => onTap(contact),
                    ),
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

/// Fix for #26: shows the complete A-Z + '#' index (like stock iOS
/// Contacts), dimming letters with no contacts instead of hiding
/// them, so the index shape doesn't jump around as you filter/search.
class _AlphabetIndex extends StatelessWidget {
  final Set<String> activeLetters;
  final void Function(String) onLetterTap;

  const _AlphabetIndex({required this.activeLetters, required this.onLetterTap});

  static const _all = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: _all.map((letter) {
        final isActive = activeLetters.contains(letter);
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isActive ? () => onLetterTap(letter) : null,
            child: SizedBox(
              width: 18,
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.systemBlue : AppColors.systemGray4,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// =====================================================================
/// SCREEN: ContactDetailScreen
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
  bool _loadedOnce = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.getById(widget.contactId);
    if (!mounted) return; // fix for #7
    setState(() {
      _contact = c;
      _loadedOnce = true;
    });
  }

  Future<void> _toggleFavorite() async {
    try {
      await _repo.toggleFavorite(widget.contactId);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) await _showAlert(context, 'Failed', e.toString());
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Delete Contact',
      body: 'This cannot be undone.',
    );
    if (!confirmed) return;

    try {
      await _repo.delete(widget.contactId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Fix for #29 in the detail screen too.
      if (mounted) await _showAlert(context, 'Delete Failed', e.toString());
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => AddEditContactScreen(existing: _contact)),
    );
    if (result == true) {
      _changed = true;
      await _load();
    }
  }

  /// Centralizes "leave this screen" so every exit path — the custom
  /// back button below AND the system back gesture/button — reports
  /// `_changed` consistently. Fixes #3/#6.
  void _handleBack() {
    Navigator.pop(context, _changed);
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;

    return PopScope(
      // We take over back-button/gesture handling ourselves so the
      // pop always carries `_changed` — a bare PopScope(canPop: true)
      // would let the system pop with no result, which is exactly
      // how issues #3/#6 happened originally.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Contact'),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _handleBack,
            child: const Icon(CupertinoIcons.back),
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: contact == null ? null : _openEdit,
            child: const Text('Edit'),
          ),
        ),
        child: SafeArea(
          child: !_loadedOnce
              ? const Center(child: CupertinoActivityIndicator())
              : contact == null
                  // Fix for #33/#34: distinguishes "still loading"
                  // from "genuinely not found" (e.g. deleted from
                  // another screen while this one was open).
                  ? Center(
                      child: Text('Contact not found', style: AppTypography.subhead),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: Column(
                            children: [
                              ContactAvatar(contact: contact, size: 90),
                              const SizedBox(height: 12),
                              Text(contact.fullName, style: AppTypography.title1),
                              if (contact.organization != null && contact.organization!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(contact.organization!, style: AppTypography.subhead),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _QuickAction(
                              icon: CupertinoIcons.phone_fill,
                              label: 'Call',
                              onTap: () => _pickAndLaunch<PhoneEntry>(
                                context: context,
                                items: contact.phones,
                                labelOf: (p) => '${p.label}: ${p.number}',
                                uriOf: (p) => Uri(scheme: 'tel', path: p.number),
                                emptyMessage: 'This contact has no phone number saved.',
                              ),
                            ),
                            _QuickAction(
                              icon: CupertinoIcons.chat_bubble_fill,
                              label: 'Message',
                              onTap: () => _pickAndLaunch<PhoneEntry>(
                                context: context,
                                items: contact.phones,
                                labelOf: (p) => '${p.label}: ${p.number}',
                                uriOf: (p) => Uri(scheme: 'sms', path: p.number),
                                emptyMessage: 'This contact has no phone number saved.',
                              ),
                            ),
                            _QuickAction(
                              icon: CupertinoIcons.mail_solid,
                              label: 'Mail',
                              onTap: () => _pickAndLaunch<EmailEntry>(
                                context: context,
                                items: contact.emails,
                                labelOf: (e) => '${e.label}: ${e.email}',
                                uriOf: (e) => Uri(scheme: 'mailto', path: e.email),
                                emptyMessage: 'This contact has no email saved.',
                              ),
                            ),
                            _QuickAction(
                              icon: contact.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                              label: 'Favorite',
                              onTap: _toggleFavorite,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (contact.phones.isNotEmpty)
                          _InfoCard(rows: contact.phones.map((p) => _InfoRow(p.label, p.number)).toList()),
                        if (contact.emails.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _InfoCard(rows: contact.emails.map((e) => _InfoRow(e.label, e.email)).toList()),
                        ],
                        // Fix for #20 — organization/address/birthday/website display.
                        if (contact.address != null && contact.address!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _InfoCard(rows: [_InfoRow('Address', contact.address!)]),
                        ],
                        if (contact.birthday != null) ...[
                          const SizedBox(height: 16),
                          _InfoCard(rows: [_InfoRow('Birthday', DateFormat.yMMMd().format(contact.birthday!))]),
                        ],
                        if (contact.website != null && contact.website!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _InfoCard(
                            rows: [_InfoRow('Website', contact.website!)],
                            onRowTap: (index) {
                              final raw = contact.website!;
                              final url = raw.startsWith('http') ? raw : 'https://$raw';
                              _launchOrWarn(context, Uri.parse(url));
                            },
                          ),
                        ],
                        if (contact.note != null && contact.note!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _InfoCard(rows: [_InfoRow('Note', contact.note!)]),
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
            decoration: BoxDecoration(color: AppColors.systemGray6, borderRadius: BorderRadius.circular(14)),
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
  _InfoRow(this.label, this.value);
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  final void Function(int index)? onRowTap;
  const _InfoCard({required this.rows, this.onRowTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final isLast = entry.key == rows.length - 1;
          final row = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 70, child: Text(entry.value.label, style: AppTypography.footnote)),
                Expanded(
                  child: Text(
                    entry.value.value,
                    style: onRowTap != null
                        ? AppTypography.body.copyWith(color: AppColors.systemBlue)
                        : AppTypography.body,
                  ),
                ),
              ],
            ),
          );
          return Column(
            children: [
              onRowTap != null ? GestureDetector(onTap: () => onRowTap!(entry.key), child: row) : row,
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
  late final TextEditingController _organization;
  late final TextEditingController _address;
  late final TextEditingController _website;

  late List<PhoneEntry> _phones;
  late List<EmailEntry> _emails;
  late List<TextEditingController> _phoneControllers;
  late List<TextEditingController> _emailControllers;

  String? _photoPath;
  DateTime? _birthday;

  bool _saving = false;
  String? _firstNameError; // fix for #9

  static const _phoneLabels = ['mobile', 'home', 'work', 'other'];
  static const _emailLabels = ['home', 'work', 'icloud', 'other'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _firstName = TextEditingController(text: e?.firstName ?? '');
    _lastName = TextEditingController(text: e?.lastName ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _organization = TextEditingController(text: e?.organization ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _website = TextEditingController(text: e?.website ?? '');
    _photoPath = e?.photoPath;
    _birthday = e?.birthday;

    _phones = List.of(e?.phones ?? const [PhoneEntry(label: 'mobile', number: '')]);
    _emails = List.of(e?.emails ?? const []);
    _phoneControllers = _phones.map((p) => TextEditingController(text: p.number)).toList();
    _emailControllers = _emails.map((em) => TextEditingController(text: em.email)).toList();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _note.dispose();
    _organization.dispose();
    _address.dispose();
    _website.dispose();
    for (final c in _phoneControllers) {
      c.dispose();
    }
    for (final c in _emailControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPhoneField() {
    setState(() {
      _phones.add(const PhoneEntry(label: 'mobile', number: ''));
      _phoneControllers.add(TextEditingController());
    });
  }

  void _addEmailField() {
    setState(() {
      _emails.add(const EmailEntry(label: 'home', email: ''));
      _emailControllers.add(TextEditingController());
    });
  }

  // Fix for #17 — there was previously no way to remove a phone/email
  // row once added.
  void _removePhoneField(int index) {
    setState(() {
      _phones.removeAt(index);
      _phoneControllers.removeAt(index).dispose();
    });
  }

  void _removeEmailField(int index) {
    setState(() {
      _emails.removeAt(index);
      _emailControllers.removeAt(index).dispose();
    });
  }

  // Fix for #16 — labels were hardcoded to 'mobile'/'home' with no
  // way to change them.
  Future<void> _pickPhoneLabel(int index) async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Label'),
        actions: _phoneLabels
            .map((l) => CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, l), child: Text(l)))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _phones[index] = PhoneEntry(label: selected, number: _phones[index].number));
    }
  }

  Future<void> _pickEmailLabel(int index) async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Label'),
        actions: _emailLabels
            .map((l) => CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, l), child: Text(l)))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _emails[index] = EmailEntry(label: selected, email: _emails[index].email));
    }
  }

  // Fix for #19 — photo add/change/remove.
  Future<void> _changePhoto() async {
    final hasPhoto = _photoPath != null;
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'pick'), child: const Text('Choose Photo')),
          if (hasPhoto)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Remove Photo'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (action == 'remove') {
      setState(() => _photoPath = null);
      return;
    }
    if (action == 'pick') {
      try {
        final picked = await FilePicker.pickFile(type: FileType.image);
        if (picked == null || picked.path == null) return;

        final docsDir = await getApplicationDocumentsDirectory();
        final photosDir = Directory(p.join(docsDir.path, 'contact_photos'));
        if (!await photosDir.exists()) await photosDir.create(recursive: true);

        final ext = p.extension(picked.path!);
        final destPath = p.join(photosDir.path, '${DateTime.now().millisecondsSinceEpoch}$ext');
        await File(picked.path!).copy(destPath);

        if (mounted) setState(() => _photoPath = destPath);
      } catch (e) {
        if (mounted) await _showAlert(context, 'Photo Failed', e.toString());
      }
    }
  }

  Future<void> _pickBirthday() async {
    DateTime temp = _birthday ?? DateTime(2000, 1, 1);
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 260,
        color: AppColors.cardBackground,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () {
                    setState(() => _birthday = temp);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: temp,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    // Fix for #9/#49 — validation with a visible reason, instead of
    // silently doing nothing when first name is empty.
    if (_firstName.text.trim().isEmpty) {
      setState(() => _firstNameError = 'First name is required');
      return;
    }
    setState(() {
      _firstNameError = null;
      _saving = true;
    });

    try {
      for (int i = 0; i < _phones.length; i++) {
        _phones[i] = PhoneEntry(label: _phones[i].label, number: _phoneControllers[i].text.trim());
      }
      for (int i = 0; i < _emails.length; i++) {
        _emails[i] = EmailEntry(label: _emails[i].label, email: _emailControllers[i].text.trim());
      }

      final cleanPhones = _phones.where((p) => p.number.isNotEmpty).toList();
      final cleanEmails = _emails.where((e) => e.email.isNotEmpty).toList();

      if (widget.isEditing) {
        await _repo.update(widget.existing!.copyWith(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          phones: cleanPhones,
          emails: cleanEmails,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          organization: _organization.text.trim().isEmpty ? null : _organization.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          website: _website.text.trim().isEmpty ? null : _website.text.trim(),
          birthday: _birthday,
          photoPath: _photoPath,
          clearPhoto: _photoPath == null,
        ));
      } else {
        await _repo.create(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          phones: cleanPhones,
          emails: cleanEmails,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          organization: _organization.text.trim().isEmpty ? null : _organization.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          website: _website.text.trim().isEmpty ? null : _website.text.trim(),
          birthday: _birthday,
          photoPath: _photoPath,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Fix for #10/#11 — a failed save previously left `_saving`
      // stuck true forever with no feedback, since there was no
      // try/catch at all.
      if (mounted) await _showAlert(context, 'Save Failed', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            Center(
              child: GestureDetector(
                onTap: _changePhoto,
                child: Stack(
                  children: [
                    _PhotoPreview(path: _photoPath, name: _firstName.text),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppColors.systemBlue, shape: BoxShape.circle),
                        child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FormCard(
              children: [
                CupertinoTextField(
                  controller: _firstName,
                  placeholder: 'First name',
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onChanged: (_) {
                    if (_firstNameError != null) setState(() => _firstNameError = null);
                  },
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
            if (_firstNameError != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 6),
                child: Text(_firstNameError!, style: const TextStyle(color: AppColors.systemRed, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            _FormCard(
              children: [
                for (int i = 0; i < _phones.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickPhoneLabel(i),
                          child: SizedBox(
                            width: 70,
                            child: Text(_phones[i].label, style: AppTypography.footnote.copyWith(color: AppColors.systemBlue)),
                          ),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Phone number',
                            keyboardType: TextInputType.phone,
                            decoration: null,
                            controller: _phoneControllers[i],
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 32,
                          onPressed: () => _removePhoneField(i),
                          child: const Icon(CupertinoIcons.minus_circle, color: AppColors.systemRed, size: 20),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickEmailLabel(i),
                          child: SizedBox(
                            width: 70,
                            child: Text(_emails[i].label, style: AppTypography.footnote.copyWith(color: AppColors.systemBlue)),
                          ),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Email',
                            keyboardType: TextInputType.emailAddress,
                            decoration: null,
                            controller: _emailControllers[i],
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 32,
                          onPressed: () => _removeEmailField(i),
                          child: const Icon(CupertinoIcons.minus_circle, color: AppColors.systemRed, size: 20),
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
            // Fix for #20 — organization / address / birthday / website fields.
            _FormCard(
              children: [
                CupertinoTextField(
                  controller: _organization,
                  placeholder: 'Company / Organization',
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                const Divider(height: 1, indent: 16, color: AppColors.separator),
                CupertinoTextField(
                  controller: _address,
                  placeholder: 'Address',
                  maxLines: 2,
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                const Divider(height: 1, indent: 16, color: AppColors.separator),
                CupertinoTextField(
                  controller: _website,
                  placeholder: 'Website',
                  keyboardType: TextInputType.url,
                  decoration: null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                const Divider(height: 1, indent: 16, color: AppColors.separator),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onPressed: _pickBirthday,
                  child: Row(
                    children: [
                      const Text('Birthday', style: TextStyle(color: AppColors.label)),
                      const Spacer(),
                      Text(
                        _birthday == null ? 'Not set' : DateFormat.yMMMd().format(_birthday!),
                        style: AppTypography.subhead,
                      ),
                    ],
                  ),
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

class _PhotoPreview extends StatelessWidget {
  final String? path;
  final String name;
  const _PhotoPreview({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return Container(
        width: 90,
        height: 90,
        decoration: const BoxDecoration(color: AppColors.systemGray4, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(CupertinoIcons.person_fill, color: Colors.white, size: 40),
      );
    }
    return ClipOval(
      child: Image.file(
        File(path!),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 90,
          height: 90,
          decoration: const BoxDecoration(color: AppColors.systemGray4, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(CupertinoIcons.person_fill, color: Colors.white, size: 40),
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
      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
      child: Column(children: children),
    );
  }
}
