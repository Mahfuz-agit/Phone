import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/call_record_model.dart';
import '../../core/repositories/call_repository.dart';
import '../../core/services/audio_recording_service.dart';
import '../../core/services/refresh_bus.dart';
import '../contacts/contacts_screens.dart';

class CallsListScreen extends StatefulWidget {
  const CallsListScreen({super.key});

  @override
  State<CallsListScreen> createState() => _CallsListScreenState();
}

class _CallsListScreenState extends State<CallsListScreen> {
  final _repo = CallRepository();
  final _searchController = TextEditingController();

  List<CallRecordModel> _calls = [];
  bool _loading = true;
  bool _searchingRecordings = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Fix: live-refresh when the background isolate logs a new call
    // — see main.dart's FlutterForegroundTask.addTaskDataCallback.
    RefreshBus.tick.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.tick.removeListener(_onRefreshSignal);
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    // Don't clobber an active recording search with a background
    // refresh — only auto-reload the plain list view.
    if (mounted && !_searchingRecordings) _load();
  }

  Future<void> _load() async {
    final calls = await _repo.getAll();
    if (!mounted) return;
    setState(() {
      _calls = calls;
      _loading = false;
    });
  }

  Future<void> _onRecordingSearch(String query) async {
    if (query.trim().isEmpty) {
      _load();
      return;
    }
    final results = await _repo.searchRecordings(query.trim());
    if (!mounted) return;
    setState(() => _calls = results);
  }

  Future<bool> _confirmDelete(CallRecordModel call) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Call'),
        content: Text('Delete this entry for ${call.displayName}?'),
        actions: [
          CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx, false)),
          CupertinoDialogAction(isDestructiveAction: true, child: const Text('Delete'), onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteCall(CallRecordModel call) async {
    try {
      await _repo.delete(call.id);
    } catch (e) {
      if (mounted) {
        await showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(e.toString()),
            actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(ctx))],
          ),
        );
      }
    } finally {
      _load();
    }
  }

  IconData _iconFor(CallType type) {
    switch (type) {
      case CallType.missed:
        return CupertinoIcons.phone_down_fill;
      case CallType.incoming:
        return CupertinoIcons.arrow_down_left;
      case CallType.outgoing:
        return CupertinoIcons.arrow_up_right;
    }
  }

  Color _colorFor(CallType type) => type == CallType.missed ? AppColors.systemRed : AppColors.systemGreen;

  Future<void> _openDetail(CallRecordModel call) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => CallDetailScreen(callId: call.id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Calls'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => setState(() => _searchingRecordings = !_searchingRecordings),
          child: Icon(_searchingRecordings ? CupertinoIcons.xmark : CupertinoIcons.search),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_searchingRecordings)
              Padding(
                padding: const EdgeInsets.all(8),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Search recordings by name or date',
                  onChanged: _onRecordingSearch,
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _calls.isEmpty
                      ? Center(
                          child: Text(
                            _searchingRecordings ? 'No matching recordings' : 'No calls yet',
                            style: AppTypography.subhead,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _calls.length,
                          separatorBuilder: (_, __) => const Padding(
                            padding: EdgeInsets.only(left: 60),
                            child: Divider(height: 1, color: AppColors.separator),
                          ),
                          itemBuilder: (context, index) {
                            final call = _calls[index];
                            return Dismissible(
                              key: ValueKey(call.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: AppColors.systemRed,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(CupertinoIcons.delete_solid, color: Colors.white),
                              ),
                              confirmDismiss: (_) => _confirmDelete(call),
                              onDismissed: (_) => _deleteCall(call),
                              child: CupertinoListTile(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Icon(_iconFor(call.type), color: _colorFor(call.type), size: 20),
                                title: Text(
                                  call.displayName,
                                  style: call.type == CallType.missed
                                      ? AppTypography.body.copyWith(color: AppColors.systemRed)
                                      : AppTypography.body,
                                ),
                                subtitle: Text(
                                  DateFormat('MMM d, h:mm a').format(call.timestamp),
                                  style: AppTypography.footnote,
                                ),
                                trailing: call.hasRecording
                                    ? const Icon(CupertinoIcons.mic_fill, color: AppColors.systemBlue, size: 18)
                                    : Text(
                                        call.durationSeconds > 0
                                            ? '${call.durationSeconds ~/ 60}:${(call.durationSeconds % 60).toString().padLeft(2, '0')}'
                                            : '',
                                        style: AppTypography.footnote,
                                      ),
                                onTap: () => _openDetail(call),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class CallDetailScreen extends StatefulWidget {
  final String callId;
  const CallDetailScreen({super.key, required this.callId});

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  final _repo = CallRepository();
  final _audioService = AudioRecordingService();
  final _player = AudioPlayer();

  CallRecordModel? _call;
  Duration _playerDuration = Duration.zero;
  Duration _playerPosition = Duration.zero;
  bool _isPlaying = false;

  RangeValues? _trimRange;
  bool _trimming = false;

  @override
  void initState() {
    super.initState();
    _load();

    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() {
        _playerDuration = d;
        _trimRange ??= RangeValues(0, d.inSeconds.toDouble());
      });
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _playerPosition = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    });
  }

  Future<void> _load() async {
    final calls = await _repo.getAll();
    if (!mounted) return;
    final call = calls.firstWhere((c) => c.id == widget.callId);
    setState(() => _call = call);
    if (call.recordingPath != null) {
      await _player.setSource(DeviceFileSource(call.recordingPath!));
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _showAlert(String title, String message) async {
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

  Future<void> _launchOrWarn(Uri uri) async {
    bool launched = false;
    try {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri);
      }
    } catch (_) {
      launched = false;
    }
    if (!launched) await _showAlert("Couldn't Open", 'No app available to handle this action.');
  }

  Future<void> _openContact() async {
    final call = _call;
    if (call == null) return;

    if (call.contactId != null) {
      await Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => ContactDetailScreen(contactId: call.contactId!)),
      );
    } else {
      final created = await Navigator.of(context).push<bool>(
        CupertinoPageRoute(builder: (_) => AddEditContactScreen(prefillPhoneNumber: call.phoneNumber)),
      );
      if (created == true) _load();
    }
  }

  Future<void> _applyTrim() async {
    final call = _call;
    final range = _trimRange;
    if (call?.recordingPath == null || range == null) return;

    setState(() => _trimming = true);
    try {
      final newPath = await _audioService.trimRecording(
        sourcePath: call!.recordingPath!,
        startMs: (range.start * 1000).round(),
        endMs: (range.end * 1000).round(),
      );
      final newDuration = (range.end - range.start).round();

      await _repo.renameRecording(call.id, newPath);
      await _repo.markTrimmed(call.id, newDuration);
      await _audioService.deleteFile(call.recordingPath!);

      await _load();
    } catch (e) {
      await _showAlert('Trim Failed', e.toString());
    } finally {
      if (mounted) setState(() => _trimming = false);
    }
  }

  Future<void> _renamePrompt() async {
    final call = _call;
    if (call?.recordingPath == null) return;

    final controller = TextEditingController();
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename Recording'),
        content: CupertinoTextField(controller: controller, placeholder: 'New file name'),
        actions: [
          CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(child: const Text('Rename'), onPressed: () => Navigator.pop(ctx, controller.text.trim())),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        final newPath = await _audioService.renameFile(call!.recordingPath!, newName);
        await _repo.renameRecording(call.id, newPath);
        await _load();
      } catch (e) {
        await _showAlert('Rename Failed', e.toString());
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.groupedBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('Call')),
      child: SafeArea(
        child: call == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Text(call.displayName, style: AppTypography.title1),
                        const SizedBox(height: 4),
                        Text(call.phoneNumber, style: AppTypography.subhead),
                        const SizedBox(height: 8),
                        Text(DateFormat('MMM d, yyyy • h:mm a').format(call.timestamp), style: AppTypography.footnote),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _QuickAction(icon: CupertinoIcons.phone_fill, label: 'Call', onTap: () => _launchOrWarn(Uri(scheme: 'tel', path: call.phoneNumber))),
                      _QuickAction(icon: CupertinoIcons.chat_bubble_fill, label: 'Message', onTap: () => _launchOrWarn(Uri(scheme: 'sms', path: call.phoneNumber))),
                      _QuickAction(
                        icon: call.contactId != null ? CupertinoIcons.person_crop_circle : CupertinoIcons.person_add,
                        label: call.contactId != null ? 'Contact' : 'Add',
                        onTap: _openContact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (call.recordingPath == null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
                      child: const Text('No recording for this call', style: AppTypography.subhead),
                    )
                  else
                    _RecordingCard(
                      isPlaying: _isPlaying,
                      duration: _playerDuration,
                      position: _playerPosition,
                      trimRange: _trimRange,
                      trimming: _trimming,
                      onTogglePlay: _togglePlay,
                      onSeek: (v) => _player.seek(Duration(seconds: v.round())),
                      onTrimRangeChanged: (r) => setState(() => _trimRange = r),
                      onApplyTrim: _applyTrim,
                      onRename: _renamePrompt,
                    ),
                ],
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

class _RecordingCard extends StatelessWidget {
  final bool isPlaying;
  final Duration duration;
  final Duration position;
  final RangeValues? trimRange;
  final bool trimming;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeek;
  final ValueChanged<RangeValues> onTrimRangeChanged;
  final VoidCallback onApplyTrim;
  final VoidCallback onRename;

  const _RecordingCard({
    required this.isPlaying,
    required this.duration,
    required this.position,
    required this.trimRange,
    required this.trimming,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onTrimRangeChanged,
    required this.onApplyTrim,
    required this.onRename,
  });

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final double maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final double positionSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recording', style: AppTypography.headline),
          const SizedBox(height: 12),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onTogglePlay,
                child: Icon(isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill, size: 40, color: AppColors.systemBlue),
              ),
              Expanded(child: Slider(value: positionSeconds, max: maxSeconds, onChanged: onSeek, activeColor: AppColors.systemBlue)),
              Text('${_fmt(position)} / ${_fmt(duration)}', style: AppTypography.footnote),
            ],
          ),
          const SizedBox(height: 16),
          Text('Trim', style: AppTypography.headline),
          const SizedBox(height: 8),
          if (trimRange != null)
            RangeSlider(
              values: trimRange!,
              max: maxSeconds,
              activeColor: AppColors.systemOrange,
              labels: RangeLabels(_fmt(Duration(seconds: trimRange!.start.round())), _fmt(Duration(seconds: trimRange!.end.round()))),
              onChanged: onTrimRangeChanged,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              onPressed: trimming ? null : onApplyTrim,
              child: trimming ? const CupertinoActivityIndicator() : const Text('Apply Trim'),
            ),
          ),
          const Divider(height: 1, color: AppColors.separator),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 8),
            onPressed: onRename,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.pencil, size: 18), SizedBox(width: 6), Text('Rename Recording')]),
          ),
        ],
      ),
    );
  }
}
