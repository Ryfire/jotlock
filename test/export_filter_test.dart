import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/main.dart';

void main() {
  group('filterExportJson', () {
    const backup = [
      {'id': 'a', 'text': 'first', 'createdAt': 1},
      {'id': 'b', 'text': 'second', 'createdAt': 2},
      {'id': 'c', 'text': 'third', 'createdAt': 3},
    ];

    test('keeps only the selected notes, in backup order', () {
      final out =
          jsonDecode(filterExportJson(jsonEncode(backup), {'c', 'a'})) as List;
      expect(out.map((m) => m['id']), ['a', 'c']);
    });

    test('exports nothing when the selection is empty', () {
      final out =
          jsonDecode(filterExportJson(jsonEncode(backup), <String>{})) as List;
      expect(out, isEmpty);
    });

    test('keeps every note when everything is selected', () {
      final out = jsonDecode(
        filterExportJson(jsonEncode(backup), {'a', 'b', 'c'}),
      ) as List;
      expect(out.length, 3);
    });

    test('ignores selected ids that no longer exist', () {
      final out = jsonDecode(
        filterExportJson(jsonEncode(backup), {'b', 'ghost'}),
      ) as List;
      expect(out.map((m) => m['id']), ['b']);
    });

    test('round-trips note fields untouched', () {
      final out =
          jsonDecode(filterExportJson(jsonEncode(backup), {'b'})) as List;
      expect(out.single, {'id': 'b', 'text': 'second', 'createdAt': 2});
    });
  });
}
