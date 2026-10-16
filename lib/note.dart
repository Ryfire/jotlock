/// Note model. `pinned` notes sort before the rest (see [filterAndSort]).
class Note {
  final String id;
  final String text;
  final DateTime createdAt;
  final bool pinned;

  /// Index into the fixed priority palette in `note_colors.dart`
  /// (`0` = no color). Mirrors the native `color` field in NoteStore.
  final int colorIndex;

  /// Epoch millis of the one-shot reminder on this note, or 0 when none is
  /// set. Mirrors the native `reminderAt` field in NoteStore.
  final int reminderAt;

  /// True when the reminder should fire without sound (banner only).
  final bool reminderSilent;

  /// Recurrence interval in days: 0 = one-shot, 1 = daily, 7 = weekly,
  /// N = every N days (N % 7 == 0 came from an "every N weeks" pick).
  /// Mirrors the native `repeatDays` field in NoteStore.
  final int repeatDays;

  /// Marked-done flag (struck through in the list; mirrors the native
  /// `done` field in NoteStore). Independent of checklist item state.
  final bool done;

  const Note({
    required this.id,
    required this.text,
    required this.createdAt,
    this.pinned = false,
    this.colorIndex = 0,
    this.reminderAt = 0,
    this.reminderSilent = false,
    this.repeatDays = 0,
    this.done = false,
  });

  bool get hasReminder => reminderAt > 0;

  /// True when the reminder repeats (see [repeatDays]).
  bool get isRecurring => repeatDays > 0;

  /// The reminder target as a DateTime; only meaningful when [hasReminder].
  DateTime get reminderTime =>
      DateTime.fromMillisecondsSinceEpoch(reminderAt);

  /// A copy of this note with the given fields replaced. Used by the
  /// checklist toggle (new text) and tests.
  Note copyWith({String? text, bool? done}) => Note(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        pinned: pinned,
        colorIndex: colorIndex,
        reminderAt: reminderAt,
        reminderSilent: reminderSilent,
        repeatDays: repeatDays,
        done: done ?? this.done,
      );

  factory Note.fromMap(Map<dynamic, dynamic> map) => Note(
        id: map['id'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
        pinned: map['pinned'] as bool? ?? false,
        colorIndex: (map['color'] as num?)?.toInt() ?? 0,
        reminderAt: (map['reminderAt'] as num?)?.toInt() ?? 0,
        reminderSilent: map['reminderSilent'] as bool? ?? false,
        repeatDays: (map['repeatDays'] as num?)?.toInt() ?? 0,
        done: map['done'] as bool? ?? false,
      );

  /// Inverse of [fromMap], shaped for `NoteStore.importNotes` — the delete
  /// undo path round-trips a deleted note through it. Optional fields are
  /// omitted when absent/zero so a restored note looks native-made.
  Map<String, Object?> toMap() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'pinned': pinned,
        if (colorIndex > 0) 'color': colorIndex,
        if (hasReminder) ...{
          'reminderAt': reminderAt,
          'reminderSilent': reminderSilent,
          if (isRecurring) 'repeatDays': repeatDays,
        },
        if (done) 'done': true,
      };
}

/// A checklist item parsed from a note's text. Checklists are plain text:
/// a line starting with `[ ]` is an open item, `[x]`/`[X]` a done one —
/// nothing is stored outside the text, so capture screens, editors and
/// backups all keep working unchanged.
class ChecklistItem {
  /// Index of this line within `note.text.split('\n')`.
  final int lineIndex;
  final bool checked;
  final String label;

  const ChecklistItem({
    required this.lineIndex,
    required this.checked,
    required this.label,
  });
}

/// Matches an entire checklist line: optional leading whitespace, the
/// `[ ] / [x]` marker, an optional single space, then the label.
final RegExp _checklistLine = RegExp(
  r'^(?<indent>[ \t]*)\[(?<mark>[ xX])\](?<space> ?)(?<label>.*)$',
);

/// Parses [text] into its checklist items, in order.
List<ChecklistItem> checklistItems(String text) {
  final lines = text.split('\n');
  final result = <ChecklistItem>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _checklistLine.firstMatch(lines[i]);
    if (match == null) continue;
    result.add(ChecklistItem(
      lineIndex: i,
      checked: match.namedGroup('mark') != ' ',
      label: (match.namedGroup('label') ?? '').trim(),
    ));
  }
  return result;
}

/// The checklist item on line [lineIndex] of [text], or null when that
/// line is not a checklist item.
ChecklistItem? checklistItemAt(String text, int lineIndex) {
  final lines = text.split('\n');
  if (lineIndex < 0 || lineIndex >= lines.length) return null;
  final match = _checklistLine.firstMatch(lines[lineIndex]);
  if (match == null) return null;
  return ChecklistItem(
    lineIndex: lineIndex,
    checked: match.namedGroup('mark') != ' ',
    label: (match.namedGroup('label') ?? '').trim(),
  );
}

/// (checked, total) counts of the checklist items in [text].
(int, int) checklistProgress(String text) {
  final items = checklistItems(text);
  return (
    items.where((i) => i.checked).length,
    items.length,
  );
}

/// Returns [text] with the checklist marker on [lineIndex] flipped. Lines
/// that are not checklist items are returned untouched.
String toggleChecklistItem(String text, int lineIndex) {
  final lines = text.split('\n');
  if (lineIndex < 0 || lineIndex >= lines.length) return text;
  final match = _checklistLine.firstMatch(lines[lineIndex]);
  if (match == null) return text;
  final newMark = match.namedGroup('mark') == ' ' ? 'x' : ' ';
  lines[lineIndex] = '${match.namedGroup('indent')}[$newMark]'
      '${match.namedGroup('space')}${match.namedGroup('label')}';
  return lines.join('\n');
}

/// Human label for a repeat interval in days ('' when one-shot).
String repeatLabel(int repeatDays) {
  switch (repeatDays) {
    case 0:
      return '';
    case 1:
      return 'daily';
    case 7:
      return 'weekly';
    default:
      return 'every $repeatDays days';
  }
}

/// Display ordering helper: pinned notes first, then newest first, filtered
/// by a case-insensitive `contains` on the text when [query] is non-empty.
List<Note> filterAndSort(List<Note> notes, {String query = ''}) {
  final q = query.trim().toLowerCase();
  final result = (q.isEmpty)
      ? List<Note>.of(notes)
      : notes.where((n) => n.text.toLowerCase().contains(q)).toList();
  result.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return result;
}

/// Renders notes as a human-readable text export, in the same order as the
/// app list (pinned first, then newest first).
String notesToText(List<Note> notes, {DateTime? exportedAt}) {
  final sorted = filterAndSort(notes);
  final now = exportedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
  final buffer = StringBuffer()
    ..writeln('JotLock notes — ${sorted.length} notes — exported $stamp');
  for (final note in sorted) {
    final dt = note.createdAt;
    final created =
        '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    buffer
      ..writeln()
      ..writeln('${note.pinned ? '[pinned] ' : ''}$created')
      ..writeln(note.text);
  }
  return buffer.toString();
}
