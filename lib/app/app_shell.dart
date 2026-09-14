import 'package:flutter/cupertino.dart';

import '../core/services/data_management_service.dart';
import '../features/activity_log/activity_log_screen.dart';
import '../features/calls/calls_screens.dart';
import '../features/contacts/contacts_screens.dart';
import 'theme/app_theme.dart';

/// =====================================================================
/// ROOT SHELL
/// Exactly two bottom tabs — Calls and Contacts — per spec. Activity
/// Log, Backup/Restore, and vCard import/export live one level deeper,
/// behind the gear icon on the Contacts tab (see MoreScreen below).
/// =====================================================================
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

/// =====================================================================
/// SCREEN: MoreScreen
/// =====================================================================
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _dataService = DataManagementService();
  bool _busy = false;

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

  /// [action] now returns the success message to show — fix for
  /// #12/#13, which previously ran these operations with no feedback
  /// at all, success or failure. Exceptions thrown by the service
  /// layer (see data_management_service.dart's new validity checks)
  /// are now caught here and shown instead of crashing or vanishing.
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
                _MoreRow(
                  icon: CupertinoIcons.doc_text,
                  label: 'Activity Log',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(builder: (_) => const ActivityLogScreen()),
                  ),
                ),
              ],
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
                    return 'Imported ${result.imported} contact(s). '
                        'Skipped ${result.skippedDuplicates} duplicate(s).';
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MoreCard(
              children: [
                _MoreRow(
                  icon: CupertinoIcons.cloud_upload,
                  label: 'Backup App Data',
                  onTap: () => _run(() async {
                    await _dataService.createBackup();
                    return 'Backup created and ready to share.';
                  }),
                ),
                _MoreRow(
                  icon: CupertinoIcons.cloud_download,
                  label: 'Restore from Backup',
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
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CupertinoActivityIndicator()),
              ),
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
