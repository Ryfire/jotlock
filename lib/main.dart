import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:jotlock/note.dart';
import 'package:jotlock/notes_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LockNotesApp());
}

class LockNotesApp extends StatelessWidget {
  const LockNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JotLock',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const NotesPage(),
    );
  }
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with WidgetsBindingObserver {
  final NotesRepository _repo = NotesRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Note> _notes = const [];
  bool _loading = true;
  bool _notificationEnabled = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Notes may have been saved from the lock screen while we were away,
    // share-sheet / text-selection launches may be waiting for us, and a
    // fired reminder notification may have asked us to open a note.
    if (state == AppLifecycleState.resumed) {
      _reload();
      _consumeIncomingText();
      _consumeOpenNoteRequest();
    }
  }

  Future<void> _bootstrap() async {
    unawaited(_setupNotification());
    await _reload();
    await _consumeIncomingText();
    await _consumeOpenNoteRequest();
  }

  /// Opens the note whose reminder notification the user tapped, if any.
  Future<void> _consumeOpenNoteRequest() async {
    try {
      final id = await _repo.takePendingOpenNoteId();
      if (id == null || !mounted) return;
      Note? target;
      for (final n in _notes) {
        if (n.id == id) target = n;
      }
      if (target != null) await _edit(target);
    } catch (_) {
      // Native bridge unavailable (e.g. widget tests).
    }
  }

  Future<void> _setupNotification() async {
    try {
      await _requestNotificationPermission();
      await _repo.refreshNotification();
    } catch (_) {
      // Native bridge unavailable (e.g. widget tests); UI still loads.
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _reload() async {
    List<Note> notes;
    var enabled = _notificationEnabled;
    try {
      notes = await _repo.getNotes();
      enabled = await _repo.isNotificationEnabled();
    } catch (_) {
      notes = _notes; // Keep old notes on transient errors.
    }
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _notificationEnabled = enabled;
      _loading = false;
    });
  }

  /// Opens the editor pre-filled with text sent into the app from the share
  /// sheet or the text-selection "JotLock" entry point, if any.
  Future<void> _consumeIncomingText() async {
    try {
      final text = await _repo.takePendingIncomingText();
      if (text == null || !mounted) return;
      await _add(initial: text);
    } catch (_) {}
  }

  List<Note> get _displayNotes =>
      filterAndSort(_notes, query: _searching ? _searchController.text : '');

  Future<void> _add({String? initial}) async {
    final text = await _showEditor(context, initial: initial);
    if (text == null) return;
    await _repo.saveNote(text);
    await _reload();
  }

  Future<void> _edit(Note note) async {
    final text = await _showEditor(context, initial: note.text);
    if (text == null) return;
    await _repo.updateNote(note.id, text);
    await _reload();
  }

  Future<void> _togglePin(Note note) async {
    await _repo.setPinned(note.id, !note.pinned);
    await _reload();
  }

  Future<void> _delete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteNote(note.id);
    await _reload();
  }

  Future<void> _copy(Note note) async {
    await Clipboard.setData(ClipboardData(text: note.text));
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _showNoteActions(Note note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: Icon(
                note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(note.pinned ? 'Unpin' : 'Pin'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              leading: Icon(
                note.hasReminder ? Icons.alarm_on_outlined : Icons.alarm_add,
              ),
              title: Text(note.hasReminder ? 'Edit reminder' : 'Remind me…'),
              onTap: () => Navigator.pop(sheetContext, 'remind'),
            ),
            if (note.hasReminder)
              ListTile(
                leading: const Icon(Icons.alarm_off),
                title: const Text('Cancel reminder'),
                onTap: () => Navigator.pop(sheetContext, 'cancel_reminder'),
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () => Navigator.pop(sheetContext, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              iconColor: Theme.of(context).colorScheme.error,
              title: const Text('Delete'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _edit(note);
      case 'pin':
        await _togglePin(note);
      case 'copy':
        await _copy(note);
      case 'remind':
        await _pickReminder(note);
      case 'cancel_reminder':
        await _cancelReminder(note);
      case 'share':
        await SharePlus.instance.share(ShareParams(text: note.text));
      case 'delete':
        await _delete(note);
    }
  }

  /// Opens the reminder picker; on a result, schedules or clears.
  Future<void> _pickReminder(Note note) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => _ReminderPickerDialog(
        initial: note.hasReminder ? note.reminderTime : null,
        initialSilent: note.reminderSilent,
      ),
    );
    if (!mounted) return;
    if (result is (DateTime, bool)) {
      final (at, sound) = result;
      try {
        await _repo.setReminder(note.id, at, silent: !sound);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not set reminder — the time may have passed'),
          ),
        );
        return;
      }
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder set for '
            '${MaterialLocalizations.of(context).formatShortDate(at)} · '
            '${TimeOfDay.fromDateTime(at).format(context)}'
            '${sound ? '' : ' (silent)'}',
          ),
        ),
      );
    } else if (result == _ReminderPickerDialog.remove) {
      await _cancelReminder(note);
    }
  }

  Future<void> _cancelReminder(Note note) async {
    await _repo.cancelReminder(note.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder canceled')),
    );
  }

  Future<void> _toggleNotification() async {
    if (_notificationEnabled) {
      await _repo.dismissNotification();
    } else {
      await _repo.refreshNotification();
    }
    await _reload();
  }

  Future<void> _openSettings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // The sheet content can be tall (radios + admin notice + backup
      // actions); allow it to take more of the screen and scroll instead of
      // clipping the bottom.
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(repo: _repo, onChanged: _reload),
    );
    if (action == 'export' && mounted) await _exportNotes();
    if (action == 'export_text' && mounted) await _exportNotesText();
    if (action == 'import' && mounted) await _importNotes();
    if (action == 'clear' && mounted) await _confirmClearAll();
    if (mounted) await _reload();
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all notes?'),
        content: Text(
          'Are you sure? This will permanently delete all ${_notes.length} '
          'note${_notes.length == 1 ? '' : 's'}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.clearNotes();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notes deleted')),
    );
  }

  Future<void> _exportNotes() async {
    try {
      final json = await _repo.getExportJson();
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File(
        '${dir.path}${Platform.pathSeparator}jotlock_backup_$stamp.json',
      );
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: 'JotLock backup ($stamp)',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed')),
      );
    }
  }

  Future<void> _exportNotesText() async {
    try {
      final json = await _repo.getExportJson();
      final notes =
          (jsonDecode(json) as List<dynamic>).whereType<Map>().map(Note.fromMap).toList();
      final text = notesToText(notes);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File(
        '${dir.path}${Platform.pathSeparator}jotlock_notes_$stamp.txt',
      );
      await file.writeAsString(text);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          text: 'JotLock notes export ($stamp)',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed')),
      );
    }
  }

  Future<void> _importNotes() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = files.isEmpty ? null : files.single.path;
    if (path == null) return;
    try {
      final json = await File(path).readAsString();
      final added = await _repo.importNotes(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? 'Imported $added note${added == 1 ? '' : 's'}'
                : 'No new notes to import',
          ),
        ),
      );
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import failed — invalid file')),
      );
    }
  }

  void _exitSearch() {
    _searchController.clear();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('JotLock'),
        actions: _searching
            ? [
                IconButton(
                  tooltip: 'Close search',
                  onPressed: _exitSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Search',
                  onPressed: () => setState(() => _searching = true),
                  icon: const Icon(Icons.search_outlined),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  tooltip: _notificationEnabled
                      ? 'Hide lock screen notification'
                      : 'Show lock screen notification',
                  onPressed: _toggleNotification,
                  icon: Icon(
                    _notificationEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                  ),
                ),
              ],
      ),
      body: _buildBody(context),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(),
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notes.isEmpty) return const _EmptyState();
    final notes = _displayNotes;
    if (notes.isEmpty) {
      return const Center(child: Text('No matching notes'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: notes.length,
      itemBuilder: (context, index) => _buildNoteTile(context, notes[index]),
    );
  }

  Widget _buildNoteTile(BuildContext context, Note note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: note.pinned ? const Icon(Icons.push_pin, size: 20) : null,
        title: Text(
          note.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: note.hasReminder
            ? Row(
                children: [
                  Icon(
                    Icons.alarm,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_formatDate(context, note.createdAt)} · reminds '
                      '${_formatReminder(context, note.reminderTime)}',
                    ),
                  ),
                ],
              )
            : Text(_formatDate(context, note.createdAt)),
        onTap: () => _edit(note),
        onLongPress: () => _showNoteActions(note),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => _copy(note),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(note),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(dt)} · ${TimeOfDay.fromDateTime(dt).format(context)}';
  }

  /// Compact reminder display: omits the date when it is today.
  String _formatReminder(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final time = TimeOfDay.fromDateTime(dt).format(context);
    return sameDay ? time : '${loc.formatShortDate(dt)} · $time';
  }
}

Future<String?> _showEditor(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NoteEditorDialog(initialText: initial),
  );
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.initialText});
  final String? initialText;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialText == null ? 'New note' : 'Edit note'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        maxLength: 4000,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Note text',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Reminder picker: quick presets plus a custom date & time selection.
/// Pops with a [DateTime] to set the reminder, [_ReminderPickerDialog.remove]
/// to clear an existing one, or null to dismiss.
class _ReminderPickerDialog extends StatefulWidget {
  const _ReminderPickerDialog({this.initial, this.initialSilent = false});
  final DateTime? initial;
  final bool initialSilent;

  /// Sentinel returned to clear the reminder.
  static const String remove = 'remove';

  @override
  State<_ReminderPickerDialog> createState() => _ReminderPickerDialogState();
}

class _ReminderPickerDialogState extends State<_ReminderPickerDialog> {
  DateTime? _selected;
  bool _playSound = true;

  // Computed once at open time so "10 minutes" is measured from then, and
  // so groupValue comparisons stay stable across rebuilds.
  late final Map<String, DateTime> _presets = {
    'In 10 minutes': _withSecondsZeroed(
      DateTime.now().add(const Duration(minutes: 10)),
    ),
    'In 1 hour': _withSecondsZeroed(
      DateTime.now().add(const Duration(hours: 1)),
    ),
    'Tomorrow 9 AM': _tomorrowNine(),
  };

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _playSound = !(widget.initialSilent);
  }

  DateTime _tomorrowNine() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selected ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _selected != null && _isSameDay(_selected!, date)
          ? TimeOfDay.fromDateTime(_selected!)
          : TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Remind me' : 'Edit reminder'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<DateTime>(
              groupValue: _selected,
              onChanged: (dt) {
                if (dt == null) return;
                setState(() => _selected = _withSecondsZeroed(dt));
              },
              child: Column(
                children: [
                  for (final entry in _presets.entries)
                    RadioListTile<DateTime>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(entry.key),
                      subtitle: Text(_describe(entry.value)),
                      value: entry.value,
                    ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Play sound'),
              subtitle: const Text('Ring when it fires — turn off for a quiet banner'),
              value: _playSound,
              onChanged: (v) => setState(() => _playSound = v),
            ),
            OutlinedButton.icon(
              onPressed: _pickCustom,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _selected == null
                    ? 'Pick date & time…'
                    : 'Custom: ${_describe(_selected!)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, _ReminderPickerDialog.remove),
            child: const Text('Remove reminder'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                    context,
                    (_selected!, _playSound),
                  ),
          child: const Text('Set reminder'),
        ),
      ],
    );
  }

  DateTime _withSecondsZeroed(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  String _describe(DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(dt).format(context);
    return '${loc.formatShortDate(dt)} · $time';
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.repo, required this.onChanged});
  final NotesRepository repo;
  final VoidCallback onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  String _afterSave = 'wait';
  bool _adminActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final afterSave = await widget.repo.getAfterSaveAction();
      final admin = await widget.repo.isDeviceAdminActive();
      if (!mounted) return;
      setState(() {
        _afterSave = afterSave;
        _adminActive = admin;
      });
    } catch (_) {}
  }

  Future<void> _selectMode(String mode) async {
    if (mode == 'lock' && !_adminActive) {
      await widget.repo.setAfterSaveAction(mode);
      await widget.repo.requestDeviceAdmin();
      final active = await widget.repo.isDeviceAdminActive();
      if (!active) {
        // Activation declined — lock mode can't work without it.
        await widget.repo.setAfterSaveAction('wait');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device admin not activated — lock mode disabled.'),
            ),
          );
        }
      }
    } else {
      await widget.repo.setAfterSaveAction(mode);
    }
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            Text(
              'After saving a note from the lock screen:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            RadioGroup<String>(
              groupValue: _afterSave,
              onChanged: (mode) => _selectMode(mode!),
              child: Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lock the phone'),
                    subtitle: const Text(
                      'Locks and turns the screen off right after saving — '
                      'one-time device admin activation required.',
                    ),
                    value: 'lock',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show the home screen'),
                    subtitle: const Text('Closes the note screen and goes home.'),
                    value: 'home',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stay on the confirmation'),
                    subtitle: const Text(
                      'Keeps "✓ Note saved" on screen — tap Lock to return '
                      'to the lock screen or Go home to head home.',
                    ),
                    value: 'wait',
                  ),
                ],
              ),
            ),
            if (_afterSave == 'lock' && !_adminActive)
              TextButton.icon(
                onPressed: () => widget.repo.requestDeviceAdmin(),
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Activate device admin'),
              ),
            const Divider(),
            _ReminderSoundTile(repo: widget.repo),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export notes (JSON)'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Export notes (text)'),
              onTap: () => Navigator.pop(context, 'export_text'),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Import notes (JSON)'),
              onTap: () => Navigator.pop(context, 'import'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              iconColor: Theme.of(context).colorScheme.error,
              textColor: Theme.of(context).colorScheme.error,
              title: const Text('Clear all notes'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
            if (_adminActive)
              Text(
                'Device admin is active. It is only used to lock the screen '
                'after saving. While active, Android requires you to '
                'deactivate it before uninstalling the app '
                '(Settings → Security → Device admin apps).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings row for the reminder sound: shows the current sound's name,
/// opens the system notification-sound picker on tap.
class _ReminderSoundTile extends StatefulWidget {
  const _ReminderSoundTile({required this.repo});
  final NotesRepository repo;

  @override
  State<_ReminderSoundTile> createState() => _ReminderSoundTileState();
}

class _ReminderSoundTileState extends State<_ReminderSoundTile> {
  String _title = 'System default';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.repo.getReminderSoundTitle();
      if (!mounted) return;
      setState(() => _title = t);
    } catch (_) {}
  }

  Future<void> _pick() async {
    try {
      final t = await widget.repo.pickReminderSound();
      if (!mounted) return;
      setState(() => _title = t);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('Reminder sound'),
      subtitle: Text(_title),
      onTap: _pick,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 56, color: outline),
            const SizedBox(height: 16),
            Text(
              'Looks kind of empty in here…',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: outline),
            ),
            const SizedBox(height: 8),
            Text(
              'The ＋ button below is feeling ignored.\n'
              'Lock-screen notes show up here too.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: outline),
            ),
          ],
        ),
      ),
    );
  }
}
