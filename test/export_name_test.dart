import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/main.dart';

void main() {
  group('sanitizeExportFileName', () {
    test('keeps a clean name unchanged', () {
      expect(sanitizeExportFileName('my notes 2026', 'jotlock_backup'), 'my notes 2026');
    });

    test('replaces characters file systems reject with spaces', () {
      expect(sanitizeExportFileName(r'a\b/c:d*e?f"g<h>i|j', 'fallback'), 'a b c d e f g h i j');
    });

    test('collapses whitespace runs and trims', () {
      expect(sanitizeExportFileName('  spaced   out  ', 'fallback'), 'spaced out');
    });

    test('drops trailing dots and spaces', () {
      expect(sanitizeExportFileName('report.', 'fallback'), 'report');
      expect(sanitizeExportFileName('report . ', 'fallback'), 'report');
    });

    test('caps the length', () {
      final name = sanitizeExportFileName('a' * 120, 'fallback');
      expect(name.length, 100);
      expect(name, 'a' * 100);
    });

    test('a cap-cut name still loses its trailing dot', () {
      // 99 'a' plus a dot is exactly at the cap and ends in a dot.
      expect(sanitizeExportFileName('${'a' * 99}.', 'fallback'), 'a' * 99);
    });

    test('falls back when nothing usable remains', () {
      expect(sanitizeExportFileName('', 'jotlock_backup'), 'jotlock_backup');
      expect(sanitizeExportFileName('   ', 'jotlock_backup'), 'jotlock_backup');
      expect(sanitizeExportFileName('...', 'jotlock_backup'), 'jotlock_backup');
      expect(sanitizeExportFileName(r'\/:*?"<>|', 'jotlock_backup'), 'jotlock_backup');
    });
  });
}
