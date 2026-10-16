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

  test('checklistItems: parses plain-text markers, skips other lines', () {
    const text = 'Shopping\n[ ] milk\n[x] eggs\n[X] SPAWN\n[ ]  zero label\n';
    final items = checklistItems(text);

    expect(items.length, 4);
    expect(items[0].lineIndex, 1);
    expect(items[0].checked, isFalse);
    expect(items[0].label, 'milk');
    expect(items[1].label, 'eggs');
    expect(items[1].checked, isTrue);
    // Uppercase X counts as done too.
    expect(items[2].checked, isTrue);
    expect(items[2].label, 'SPAWN');
    // Marker with no space before the label parses.
    expect(items[3].label, 'zero label');
    // The plain header line and the trailing blank are not items.
    expect(items.any((i) => i.lineIndex == 0), isFalse);
    expect(items.any((i) => i.lineIndex == 5), isFalse);
  });

  test('checklistItemAt: returns null for non-checklist lines', () {
    const text = 'plain\n[ ] item';
    expect(checklistItemAt(text, 0), isNull);
    expect(checklistItemAt(text, 1)?.label, 'item');
    expect(checklistItemAt(text, 2), isNull);
    expect(checklistItemAt(text, -1), isNull);
  });

  test('checklistProgress: counts checked and total', () {
    expect(checklistProgress('a\n[ ] x\n[x] y'), (1, 2));
    expect(checklistProgress('no checklist'), (0, 0));
    expect(checklistProgress('[x] only\n[x] both'), (2, 2));
  });

  test('toggleChecklistItem: flips the given line, preserves the rest', () {
    const text = '[ ] milk\n[x] eggs\n[ ] bread';

    final afterCheck = toggleChecklistItem(text, 0);
    expect(afterCheck, '[x] milk\n[x] eggs\n[ ] bread');

    final afterUncheck = toggleChecklistItem(afterCheck, 1);
    expect(afterUncheck, '[x] milk\n[ ] eggs\n[ ] bread');

    // Indicator text that merely contains brackets is untouched.
    const notAChecklist = 'see [note] for details';
    expect(toggleChecklistItem(notAChecklist, 0), notAChecklist);
    // Out-of-range lines are a no-op.
    expect(toggleChecklistItem(text, 99), text);
  });

  test('toggleChecklistItem: keeps indentation and separator spacing', () {
    expect(toggleChecklistItem('  [ ] indented', 0), '  [x] indented');
    expect(toggleChecklistItem('[x]no-space', 0), '[ ]no-space');
  });

  test('repeatLabel: presets and custom intervals', () {
    expect(repeatLabel(0), '');
    expect(repeatLabel(1), 'daily');
    expect(repeatLabel(7), 'weekly');
    expect(repeatLabel(3), 'every 3 days');
    expect(repeatLabel(14), 'every 14 days');
  });

  test('Note: repeatDays, reminder fields and toMap round-trip', () {
    final note = Note.fromMap({
      'id': '9',
      'text': 'recurring',
      'createdAt': 1700000000000,
      'pinned': true,
      'color': 2,
      'reminderAt': 1898841600000,
      'reminderSilent': true,
      'repeatDays': 3,
    });
    expect(note.hasReminder, isTrue);
    expect(note.isRecurring, isTrue);
    expect(note.reminderSilent, isTrue);

    final map = note.toMap();
    expect(map['id'], '9');
    expect(map['pinned'], isTrue);
    expect(map['color'], 2);
    expect(map['reminderAt'], 1898841600000);
    expect(map['reminderSilent'], isTrue);
    expect(map['repeatDays'], 3);

    // One-shot reminder: no repeatDays key.
    final oneShot = Note.fromMap({
      'id': '10',
      'text': 'once',
      'createdAt': 0,
      'reminderAt': 1898841600000,
    });
    expect(oneShot.isRecurring, isFalse);
    expect(oneShot.toMap().containsKey('repeatDays'), isFalse);
    expect(oneShot.toMap().containsKey('reminderSilent'), isTrue);

    // Plain note: no reminder or color keys.
    final plain = Note(id: '11', text: 'plain', createdAt: DateTime(2024));
    final plainMap = plain.toMap();
    expect(
      plainMap.keys.toSet(),
      {'id', 'text', 'createdAt', 'pinned'},
    );
  });

  test('copyWith: replaces text, keeps identity fields', () {
    final note = Note(
      id: '1',
      text: 'old',
      createdAt: DateTime(2024, 1, 1),
      pinned: true,
      reminderAt: 999,
      repeatDays: 7,
    );
    final edited = note.copyWith(text: 'new');
    expect(edited.text, 'new');
    expect(edited.id, '1');
    expect(edited.pinned, isTrue);
    expect(edited.reminderAt, 999);
    expect(edited.repeatDays, 7);
  });

  test('done: flag round-trips through fromMap/toMap, absent when false', () {
    final doneNote = Note.fromMap({
      'id': '1',
      'text': 'done deal',
      'createdAt': 0,
      'done': true,
    });
    expect(doneNote.done, isTrue);
    expect(doneNote.toMap()['done'], true);

    final undoneNote = Note.fromMap({
      'id': '2',
      'text': 'pending',
      'createdAt': 0,
    });
    expect(undoneNote.done, isFalse);
    // False/absent notes carry no done key.
    expect(undoneNote.toMap().containsKey('done'), isFalse);
    expect(
      Note.fromMap({'id': '3', 'text': 'x', 'createdAt': 0, 'done': false})
          .done,
      isFalse,
    );
  });
}
