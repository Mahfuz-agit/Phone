import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/activity_log_model.dart';
import '../../core/repositories/activity_log_repository.dart';

/// =====================================================================
/// SCREEN: ActivityLogScreen
/// Shows every logged action (call, contact add/edit/delete, recording
/// rename/trim, backup/restore) with type/date filtering and CSV/PDF
/// export — all in one file per the "fewer files" instruction.
/// =====================================================================
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _repo = ActivityLogRepository();

  List<ActivityLogModel> _logs = [];
  bool _loading = true;

  ActivityType? _typeFilter;
  DateTimeRange? _dateFilter;
  String? _contactIdFilter;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await _repo.filter(
      contactId: _contactIdFilter,
      type: _typeFilter,
      from: _dateFilter?.start,
      to: _dateFilter?.end,
    );
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  String _labelFor(ActivityType type) {
    switch (type) {
      case ActivityType.call:
        return 'Call';
      case ActivityType.contactAdded:
        return 'Contact added';
      case ActivityType.contactEdited:
        return 'Contact edited';
      case ActivityType.contactDeleted:
        return 'Contact deleted';
      case ActivityType.recordingRenamed:
        return 'Recording renamed';
      case ActivityType.recordingTrimmed:
        return 'Recording trimmed';
      case ActivityType.backup:
        return 'Backup';
      case ActivityType.restore:
        return 'Restore';
    }
  }

  IconData _iconFor(ActivityType type) {
    switch (type) {
      case ActivityType.call:
        return CupertinoIcons.phone;
      case ActivityType.contactAdded:
        return CupertinoIcons.person_add;
      case ActivityType.contactEdited:
        return CupertinoIcons.pencil;
      case ActivityType.contactDeleted:
        return CupertinoIcons.trash;
      case ActivityType.recordingRenamed:
        return CupertinoIcons.tag;
      case ActivityType.recordingTrimmed:
        return CupertinoIcons.scissors;
      case ActivityType.backup:
        return CupertinoIcons.cloud_upload;
      case ActivityType.restore:
        return CupertinoIcons.cloud_download;
    }
  }

  Future<void> _openFilterSheet() async {
    ActivityType? tempType = _typeFilter;
    DateTimeRange? tempRange = _dateFilter;

    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter Activity', style: AppTypography.headline),
              const SizedBox(height: 12),
              Text('Type', style: AppTypography.footnote),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: tempType == null,
                    onTap: () => setSheetState(() => tempType = null),
                  ),
                  ...ActivityType.values.map((t) => _FilterChip(
                        label: _labelFor(t),
                        selected: tempType == t,
                        onTap: () => setSheetState(() => tempType = t),
                      )),
                ],
              ),
              const SizedBox(height: 16),
              Text('Date range', style: AppTypography.footnote),
              const SizedBox(height: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final now = DateTime.now();
                  final range = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(now.year - 3),
                    lastDate: now,
                    initialDateRange: tempRange,
                  );
                  if (range != null) setSheetState(() => tempRange = range);
                },
                child: Text(
                  tempRange == null
                      ? 'Any date'
                      : '${DateFormat.yMd().format(tempRange!.start)} - ${DateFormat.yMd().format(tempRange!.end)}',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: AppColors.systemGray5,
                      onPressed: () {
                        setSheetState(() {
                          tempType = null;
                          tempRange = null;
                        });
                      },
                      child: const Text('Clear', style: TextStyle(color: AppColors.label)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: () {
                        setState(() {
                          _typeFilter = tempType;
                          _dateFilter = tempRange;
                        });
                        Navigator.pop(ctx);
                        _load();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Directory> _exportDir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'PhoneBookApp'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final rows = <List<dynamic>>[
        ['timestamp', 'type', 'contact_id', 'description'],
        ..._logs.map((l) => [
              l.timestamp.toIso8601String(),
              _labelFor(l.type),
              l.contactId ?? '',
              l.description,
            ]),
      ];
      final csvString = const ListToCsvConverter().convert(rows);
      final dir = await _exportDir();
      final file = File(p.join(dir.path, 'activity_log_${DateTime.now().millisecondsSinceEpoch}.csv'));
      await file.writeAsString(csvString);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Activity log export'));
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, text: 'Activity Log'),
            pw.Table.fromTextArray(
              headers: ['Date', 'Type', 'Description'],
              data: _logs
                  .map((l) => [
                        DateFormat('yyyy-MM-dd HH:mm').format(l.timestamp),
                        _labelFor(l.type),
                        l.description,
                      ])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

      final dir = await _exportDir();
      final file = File(p.join(dir.path, 'activity_log_${DateTime.now().millisecondsSinceEpoch}.pdf'));
      await file.writeAsBytes(await doc.save());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Activity log export'));
    } finally {
      setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = _typeFilter != null || _dateFilter != null;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Activity Log'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openFilterSheet,
          child: Icon(
            hasFilter ? CupertinoIcons.line_horizontal_3_decrease_circle_fill : CupertinoIcons.line_horizontal_3_decrease_circle,
            color: AppColors.systemBlue,
          ),
        ),
        trailing: _exporting
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => showCupertinoModalPopup(
                  context: context,
                  builder: (ctx) => CupertinoActionSheet(
                    title: const Text('Export Activity Log'),
                    actions: [
                      CupertinoActionSheetAction(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _exportCsv();
                        },
                        child: const Text('Export as CSV'),
                      ),
                      CupertinoActionSheetAction(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _exportPdf();
                        },
                        child: const Text('Export as PDF'),
                      ),
                    ],
                    cancelButton: CupertinoActionSheetAction(
                      isDefaultAction: true,
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                child: const Icon(CupertinoIcons.square_arrow_up),
              ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _logs.isEmpty
                ? Center(child: Text('No activity recorded', style: AppTypography.subhead))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(left: 56),
                      child: Divider(height: 1, color: AppColors.separator),
                    ),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return CupertinoListTile(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Icon(_iconFor(log.type), color: AppColors.systemBlue, size: 20),
                        title: Text(log.description, style: AppTypography.body),
                        subtitle: Text(
                          DateFormat('MMM d, yyyy • h:mm a').format(log.timestamp),
                          style: AppTypography.footnote,
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.systemBlue : AppColors.systemGray6,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.label,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
