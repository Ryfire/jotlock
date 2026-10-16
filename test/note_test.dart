import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/note.dart';

void main() {
  test('filterAndSort: pinned first, then newest first', () {
    final notes = [
      Note(id: '1', text: 'old', createdAt: DateTime(2024, 1, 1)),
      Note(
        id: '2',
        text: 'pinned but oldest',
        createdAt: DateTime(2024, 1, 3),
        pinned: true,
      ),
      Note(id: '3', text: 'newest', createdAt: DateTime(2024, 1, 2)),
    ];

    final sorted = filterAndSort(notes);

    expect(sorted.map((n) => n.id).toList(), ['2', '3', '1']);
  });

  test('filterAndSort: filters case-insensitively by text', () {
    final notes = [
      Note(id: '1', text: 'Groceries list', createdAt: DateTime(2024, 1, 1)),
      Note(id: '2', text: 'Password reset', createdAt: DateTime(2024, 1, 2)),
    ];

    expect(
      filterAndSort(notes, query: '  GROC ').map((n) => n.id).toList(),
      ['1'],
    );
    expect(
      filterAndSort(notes, query: 'xyz').map((n) => n.id).toList(),
      isEmpty,
    );
    // Original list is not mutated.
    expect(notes.length, 2);
  });

  test('notesToText renders a readable export, display order preserved', () {
    final notes = [
      Note(id: '1', text: 'Second note', createdAt: DateTime(2024, 1, 1, 23, 45)),
      Note(
        id: '2',
        text: 'Pinned note',
        createdAt: DateTime(2024, 1, 2, 9, 5),
        pinned: true,
      ),
    ];

    final text = notesToText(notes, exportedAt: DateTime(2026, 10, 14, 8, 1));

    expect(text, contains('JotLock notes — 2 notes'));
    expect(text, contains('[pinned] 2024-01-02 09:05'));
    expect(text, contains('Pinned note'));
    expect(text, contains('2024-01-01 23:45'));
    expect(text, contains('Second note'));
    // Pinned note appears before the unpinned one.
    expect(text.indexOf('Pinned note'), lessThan(text.indexOf('Second note')));
  });

  test('fromMap: color index round-trips and defaults to none', () {
    final colored = Note.fromMap({
      'id': '1',
      'text': 'colored',
      'createdAt': 1700000000000,
      'color': 3,
    });
    expect(colored.colorIndex, 3);

    // Legacy notes (and zeroed values) map to "no color".
    for (final map in [
      <dynamic, dynamic>{'id': '2', 'text': 'legacy'},
      <dynamic, dynamic>{'id': '3', 'text': 'explicit zero', 'color': 0},
    ]) {
      expect(Note.fromMap(map).colorIndex, 0);
    }
  });
}
