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
import 'package:jotlock/note_colors.dart';
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
      home: const _PinGate(child: NotesPage()),
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

  /// Applies (or clears, when 0) the priority color on a note.
  Future<void> _setNoteColor(Note note, int colorIndex) async {
    await _repo.setNoteColor(note.id, colorIndex);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Priority color',
                      style: Theme.of(sheetContext).textTheme.labelLarge,
                    ),
                  ),
                  Row(
                    children: [
                      _ColorSwatch(
                        selected: note.colorIndex == noColorIndex,
                        onTap: () => Navigator.pop(sheetContext, 'color:0'),
                      ),
                      for (var i = 0; i < noteColors.length; i++) ...[
                        const Spacer(),
                        _ColorSwatch(
                          color: noteColors[i],
                          selected: note.colorIndex == i + 1,
                          onTap: () =>
                              Navigator.pop(sheetContext, 'color:${i + 1}'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
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
    if (action.startsWith('color:')) {
      final index = int.tryParse(action.substring('color:'.length)) ?? 0;
      await _setNoteColor(note, index);
      return;
    }
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
                  tooltip: 'About & support',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                ),
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
    final tint = noteCardColor(note.colorIndex, Theme.of(context).colorScheme);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: tint,
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
            _BackgroundTile(repo: widget.repo),
            const Divider(),
            _PinTile(repo: widget.repo),
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

/// Optional app PIN: a 4-8 digit code asked when the app is opened,
/// guarding the Flutter management UI only. Lock-screen capture and the
/// shade Jot field stay instant — they are the app's core flow and the
/// device keyguard already protects what sits behind them. Only a salted
/// SHA-256 hash is stored natively (see AppSettings.kt).
class _PinGate extends StatefulWidget {
  const _PinGate({required this.child});
  final Widget child;

  @override
  State<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<_PinGate> with WidgetsBindingObserver {
  final NotesRepository _repo = NotesRepository();

  /// null = first check still running; otherwise whether a PIN is set.
  bool? _pinSet;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final set = await _isPinSet();
    if (!mounted) return;
    setState(() {
      _pinSet = set;
      _locked = set;
    });
  }

  Future<bool> _isPinSet() async {
    try {
      return await _repo.isPinSet();
    } catch (_) {
      // Native bridge unavailable (e.g. widget tests) — no gate.
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock on every return to the foreground. Full-screen system
    // activities (file/ringtone pickers, the device-admin screen) count;
    // in-app dialogs and bottom sheets only reach `inactive` and do not.
    if (state != AppLifecycleState.resumed || _locked) return;
    _recheckPin();
  }

  /// Re-queries instead of trusting the cached flag: a PIN may have been
  /// set or removed in settings during this session.
  Future<void> _recheckPin() async {
    final set = await _isPinSet();
    if (!mounted || !set || _locked) return;
    setState(() {
      _pinSet = true;
      _locked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Until the first check resolves, show a splash instead of the notes
    // list so a gated app never flashes its contents on open.
    if (_pinSet == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      children: [
        widget.child,
        if (_locked)
          _PinUnlockScreen(
            repo: _repo,
            onUnlocked: () => setState(() => _locked = false),
          ),
      ],
    );
  }
}

/// Full-screen unlock gate covering the notes UI while it is locked.
class _PinUnlockScreen extends StatefulWidget {
  const _PinUnlockScreen({required this.repo, required this.onUnlocked});
  final NotesRepository repo;
  final VoidCallback onUnlocked;

  @override
  State<_PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<_PinUnlockScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text;
    if (pin.isEmpty) return;
    var ok = false;
    try {
      ok = await widget.repo.verifyPin(pin);
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    // Best-effort: platform haptics can be unavailable (e.g. in tests).
    unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
    setState(() {
      _error = 'Wrong PIN — try again';
      _controller.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'JotLock is locked',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Enter your PIN',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: outline),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'PIN',
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog to set, change, or remove the app PIN. Pops `true` when the
/// stored PIN changed, so the settings tile can refresh.
enum _PinDialogPurpose { set, manage }

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.repo, required this.purpose});
  final NotesRepository repo;
  final _PinDialogPurpose purpose;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');

  static final List<TextInputFormatter> _pinFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(8),
  ];

  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _manage => widget.purpose == _PinDialogPurpose.manage;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _fail(String message) {
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _submit({required bool removing}) async {
    if (_busy) return;
    if (!removing) {
      if (!_pinPattern.hasMatch(_next.text)) {
        _fail('PIN must be 4-8 digits');
        return;
      }
      if (_next.text != _confirm.text) {
        _fail('PINs do not match');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      if (_manage) {
        final currentOk = removing
            ? await widget.repo.clearPin(_current.text)
            : await widget.repo.verifyPin(_current.text);
        if (!mounted) return;
        if (!currentOk) {
          _fail('Current PIN is incorrect');
          return;
        }
        if (!removing) await widget.repo.setPin(_next.text);
      } else {
        await widget.repo.setPin(_next.text);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      _fail('Something went wrong — try again');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_manage ? 'Change app PIN' : 'Set app PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Asked when you open JotLock. 4-8 digits.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_manage)
              TextField(
                controller: _current,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: _pinFormatters,
                decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
            TextField(
              controller: _next,
              autofocus: !_manage,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: _pinFormatters,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: _pinFormatters,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(removing: false),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_manage)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _submit(removing: true),
            child: const Text('Remove PIN'),
          ),
        FilledButton(
          onPressed: _busy ? null : () => _submit(removing: false),
          child: Text(_manage ? 'Save new PIN' : 'Save PIN'),
        ),
      ],
    );
  }
}

/// Settings row for the optional app PIN: shows On/Off and opens the
/// set/change dialog on tap.
class _PinTile extends StatefulWidget {
  const _PinTile({required this.repo});
  final NotesRepository repo;

  @override
  State<_PinTile> createState() => _PinTileState();
}

class _PinTileState extends State<_PinTile> {
  bool _set = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final set = await widget.repo.isPinSet();
      if (!mounted) return;
      setState(() => _set = set);
    } catch (_) {}
  }

  Future<void> _open() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _PinSetupDialog(
        repo: widget.repo,
        purpose: _set ? _PinDialogPurpose.manage : _PinDialogPurpose.set,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_outline),
      title: const Text('App PIN'),
      subtitle: Text(_set ? 'On — asked when the app opens' : 'Off'),
      onTap: _open,
      trailing: _set
          ? const Icon(Icons.check_circle_outline)
          : const Icon(Icons.chevron_right),
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

/// Settings row for background keep-alive: shows the battery-optimization
/// exemption state and opens the system allow-dialog when missing.
class _BackgroundTile extends StatefulWidget {
  const _BackgroundTile({required this.repo});
  final NotesRepository repo;

  @override
  State<_BackgroundTile> createState() => _BackgroundTileState();
}

class _BackgroundTileState extends State<_BackgroundTile> {
  bool _exempt = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exempt = await widget.repo.isBatteryExempt();
      if (!mounted) return;
      setState(() => _exempt = exempt);
    } catch (_) {}
  }

  Future<void> _request() async {
    try {
      await widget.repo.requestBatteryExempt();
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.battery_saver_outlined),
      title: const Text('Keep running in background'),
      subtitle: Text(
        _exempt
            ? 'Battery optimization is off — the lock screen card and '
                'reminders stay live.'
            : 'Tap to allow JotLock to keep running in the background.',
      ),
      onTap: _exempt ? null : _request,
      trailing: _exempt
          ? const Icon(Icons.check_circle_outline)
          : const Icon(Icons.chevron_right),
    );
  }
}

/// About page content — edit these three values to update what users see.
/// Links open in the browser; the app itself stays offline.
class _SupportLink {
  const _SupportLink(this.label, this.url, {required this.icon});
  final String label;
  final String url;
  final IconData icon;
}

const String _aboutMessage =
    'Hi — JotLock is made by one person who wanted a notes app that never '
    'gets in the way: jot a thought from the lock screen, lock the phone, '
    'move on. If it saves you time too, a small donation keeps it free, '
    'open source, and ad-free. Thank you!';

const List<_SupportLink> _supportLinks = [
  _SupportLink(
    'Donate',
    'https://example.com/jotlock-donate',
    icon: Icons.favorite_outline,
  ),
];

const String _sourceUrl = 'https://github.com/CornMuffinThePapaya/jotlock';

/// In-app About page: developer note, support links, source code, version.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await NotesRepository().getVersionName();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (_) {}
  }

  Future<void> _open(String url) async {
    try {
      await NotesRepository().openUrl(url);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About JotLock')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.edit_note,
                    size: 56,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text('JotLock', style: Theme.of(context).textTheme.titleLarge),
                if (_version.isNotEmpty)
                  Text(
                    'Version $_version',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(_aboutMessage, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          const Divider(),
          for (final link in _supportLinks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(link.icon),
              title: Text(link.label),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(link.url),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: const Text('Source code on GitHub'),
            subtitle: const Text('MIT licensed — inspect every line'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(_sourceUrl),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'No accounts, no cloud, no internet permission — '
            'notes never leave your device.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A single circular color choice in the long-press sheet. A null [color]
/// renders the "no color" swatch (outline circle with a slash).
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.onTap, this.color, this.selected = false});

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedRing = selected
        ? Border.all(color: scheme.primary, width: 2)
        : Border.all(color: Colors.transparent, width: 2);
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selectedRing,
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: color == null
                ? Border.all(color: scheme.outline, width: 1.5)
                : null,
          ),
          child: color == null
              ? Icon(Icons.block, size: 14, color: scheme.outline)
              : (selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null),
        ),
      ),
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
