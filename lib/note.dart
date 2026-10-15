/// Note model. `pinned` notes sort before the rest (see [filterAndSort]).
class Note {
  final String id;
  final String text;
  final DateTime createdAt;
  final bool pinned;

  const Note({
    required this.id,
    required this.text,
    required this.createdAt,
    this.pinned = false,
  });

  factory Note.fromMap(Map<dynamic, dynamic> map) => Note(
        id: map['id'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
        pinned: map['pinned'] as bool? ?? false,
      );
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
