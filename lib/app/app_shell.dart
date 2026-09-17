import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/repositories/activity_log_repository.dart';
import '../core/repositories/call_repository.dart';
import '../core/services/data_management_service.dart';
import '../core/services/public_mirror_service.dart';
import '../core/services/recording_foreground_task.dart';
import '../core/services/settings_service.dart';
import '../features/activity_log/activity_log_screen.dart';
import '../features/calls/calls_screens.dart';
import '../features/contacts/contacts_screens.dart';
import 'theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: cupertinoAppTheme.barBackgroundColor,
        activeColor: AppColors.systemBlue,
        inactiveColor: AppColors.systemGray,
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.phone), label: 'Calls'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.person_2), label: 'Contacts'),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return CupertinoTabView(builder: (_) => const CallsListScreen());
          case 1:
          default:
            return CupertinoTabView(
              builder: (innerContext) => ContactsListScreen(
                onMoreTap: () => Navigator.of(innerContext).push(
                  CupertinoPageRoute(builder: (_) => const MoreScreen()),
                ),
              ),
            );
        }
      },
    );
  }
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _dataService = DataManagementService();
  final _callRepo = CallRepository();
  final _activityLogRepo = ActivityLogRepository();
  final _settings = SettingsService();
  final _publicMirror = PublicMirrorService();

  bool _busy = false;
  bool _recordingEnabled = true;
  bool _settingsLoaded = false;
  String? _mirrorPath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMirrorPath();
  }

  Future<void> _loadSettings() async {
    final enabled = await _settings.isRecordingEnabled();
    if (!mounted) return;
    setState(() {
      _recordingEnabled = enabled;
      _settingsLoaded = true;
    });
  }

  Future<void> _loadMirrorPath() async {
    final path = await _publicMirror.mirrorFolderPath();
    if (!mounted) return;
    setState(() => _mirrorPath = path);
  }

  Future<void> _onRecordingToggle(bool value) async {
    setState(() => _recordingEnabled = value);
    await _settings.setRecordingEnabled(value);

    if (!value) {
      await RecordingForegroundController.stop();
      return;
    }

    final micGranted = await Permission.microphone.isGranted;
    final phoneGranted = await Permission.phone.isGranted;
    if (!micGranted || !phoneGranted) {
      final results = await [Permission.microphone, Permission.phone].request();
      final ok = (results[Permission.microphone]?.isGranted ?? false) &&
          (results[Permission.phone]?.isGranted ?? false);
      if (!ok) {
        setState(() => _recordingEnabled = false);
        await _settings.setRecordingEnabled(false);
        await _showResult('Permission Needed', 'Microphone and Phone permissions are required to enable recording.');
        return;
      }
    }
    await RecordingForegroundController.start();
  }

  Future<void> _showResult(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(ctx))],
      ),
    );
  }

  Future<void> _run(
    Future<String> Function() action, {
    String? confirmTitle,
    String? confirmBody,
  }) async {
    if (confirmTitle != null) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmBody ?? ''),
          actions: [
            CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx, false)),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Continue'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final message = await action();
      await _showResult('Success', message);
    } catch (e) {
      await _showResult('Failed', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareDebugLog() async {
    await _run(() async {
      final logs = await _activityLogRepo.getAll();
      if (logs.isEmpty) return 'Activity log is empty — nothing to share.';

      final buffer = StringBuffer();
      final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
      for (final log in logs) {
        buffer.writeln('[${fmt.format(log.timestamp)}] ${log.type.name}: ${log.description}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'debug_log_${DateTime.now().millisecondsSinceEpoch}.txt'));
      await file.writeAsString(buffer.toString());

      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Phonebook app debug log'));
      return 'Debug log ready to share (${logs.length} entries).';
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('More')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MoreCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.mic_fill, color: AppColors.systemBlue, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Auto Call Recording', style: AppTypography.body)),
                      _settingsLoaded
                          ? CupertinoSwitch(value: _recordingEnabled, onChanged: _onRecordingToggle)
                          : const CupertinoActivityIndicator(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MoreCard(
              children: [
                _MoreRow(
                  icon: CupertinoIcons.doc_text,
                  label: 'Activity Log',
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const ActivityLogScreen())),
                ),
                _MoreRow(icon: CupertinoIcons.square_arrow_up_on_square, label: 'Share Debug Log', onTap: _shareDebugLog),
                _MoreRow(
                  icon: CupertinoIcons.arrow_down_doc,
                  label: 'Sync System Call History',
                  onTap: () => _run(() async {
                    final count = await _callRepo.importSystemCallLog();
                    return count == 0
                        ? 'Already up to date — no new calls found.'
                        : 'Imported $count call(s) from your phone\'s call history.\n\n'
                            'Note: only number, name, time, and duration could be '
                            'imported — audio recordings of past calls are not '
                            'accessible to any app on Android.';
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MoreCard(
              children: [
                _MoreRow(
                  icon: CupertinoIcons.folder,
                  label: 'Restore from Local Backup Files',
                  onTap: () => _run(() async {
                    final result = await _publicMirror.restoreFromMirror();
                    if (result.contacts == 0 && result.calls == 0 && result.logs == 0) {
                      return 'No new data found in the backup files — everything is already here (or no backup exists yet).';
                    }
                    return 'Restored ${result.contacts} contact(s), ${result.calls} call(s), '
                        'and ${result.logs} activity log entr${result.logs == 1 ? 'y' : 'ies'} '
                        'from the local backup files.';
                  }),
                ),
              ],
            ),
            if (_mirrorPath != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: Text(
                  'Your data is auto-backed up as plain files here, and survives '
                  'uninstalling the app:\n$_mirrorPath',
                  style: AppTypography.caption1,
                ),
              ),
            const SizedBox(height: 16),
            _MoreCard(
              children: [
                _MoreRow(
                  icon: CupertinoIcons.square_arrow_up,
                  label: 'Export Contacts (.vcf)',
                  onTap: () => _run(() async {
                    await _dataService.exportVCard();
                    return 'Contacts exported and ready to share.';
                  }),
                ),
                _MoreRow(
                  icon: CupertinoIcons.square_arrow_down,
                  label: 'Import Contacts (.vcf)',
                  onTap: () => _run(() async {
                    final result = await _dataService.importVCardFromFile();
                    if (result.imported == 0 && result.skippedDuplicates == 0) {
                      return 'No file selected.';
                    }
                    return 'Imported ${result.imported} contact(s). Skipped ${result.skippedDuplicates} duplicate(s).';
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MoreCard(
              children: [
                _MoreRow(
                  icon: CupertinoIcons.cloud_upload,
                  label: 'Backup App Data (.zip)',
                  onTap: () => _run(() async {
                    await _dataService.createBackup();
                    return 'Backup created and ready to share.';
                  }),
                ),
                _MoreRow(
                  icon: CupertinoIcons.cloud_download,
                  label: 'Restore from .zip Backup',
                  onTap: () => _run(
                    () async {
                      final ok = await _dataService.restoreBackup();
                      return ok ? 'Restore complete.' : 'No file selected.';
                    },
                    confirmTitle: 'Restore Backup?',
                    confirmBody: 'This replaces all current contacts and recordings.',
                  ),
                ),
              ],
            ),
            if (_busy)
              const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CupertinoActivityIndicator())),
          ],
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final List<Widget> children;
  const _MoreCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
      child: Column(children: children),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, color: AppColors.systemBlue, size: 20),
      title: Text(label, style: AppTypography.body),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.systemGray3),
      onTap: onTap,
    );
  }
}
