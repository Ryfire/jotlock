import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mutable in-memory mock of the native [NoteStore] channel so delete /
  /// update / import / done flows can be observed end-to-end.
  ({
    List<String> updatedTexts,
    List<dynamic> imports,
    List<String> cancels,
    List<bool> dones,
  }) mockNotesChannels({
    bool pinSet = false,
    String? correctPin,
    List<Map<String, Object>>? initialNotes,
    bool relockOnResume = true,
  }) {
    final notes = initialNotes == null
        ? <Map<String, Object>>[
            {'id': '1', 'text': 'Hello from the lock screen', 'createdAt': 0},
          ]
        : List<Map<String, Object>>.of(initialNotes);
    final updatedTexts = <String>[];
    final imports = <dynamic>[];
    final cancels = <String>[];
    final dones = <bool>[];

    const permissionsChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('jotlock/notes'),
      (call) async {
        switch (call.method) {
          case 'getNotes':
            return List<Map<String, Object>>.of(notes);
          case 'isNotificationEnabled':
            return true;
          case 'isPinSet':
            return pinSet;
          case 'getRelockOnResume':
            return relockOnResume;
          case 'setRelockOnResume':
            return true;
          case 'verifyPin':
            final args = call.arguments as Map?;
            return correctPin != null && args?['pin'] == correctPin;
          case 'deleteNote':
            final id = (call.arguments as Map)['id'] as String;
            notes.removeWhere((n) => n['id'] == id);
            return true;
          case 'updateNote':
            final args = call.arguments as Map;
            final note = notes.firstWhere(
              (n) => n['id'] == args['id'],
            );
            notes[notes.indexOf(note)] = {
              ...note,
              'text': args['text'] as String,
            };
            updatedTexts.add(args['text'] as String);
            return true;
          case 'importNotes':
            imports.add(call.arguments);
            // Mirror the native merge: add notes whose id is not present.
            for (final raw
                in jsonDecode((call.arguments as Map)['json'] as String)
                    as List<dynamic>) {
              final map = Map<String, Object>.from(raw as Map);
              if (!notes.any((n) => n['id'] == map['id'])) {
                notes.add(map);
              }
            }
            return 1;
          case 'cancelReminder':
            cancels.add((call.arguments as Map)['id'] as String);
            return true;
          case 'setDone':
            final args = call.arguments as Map;
            final id = args['id'] as String;
            final done = args['done'] == true;
            final note = notes.firstWhere((n) => n['id'] == id);
            final updated = Map<String, Object>.from(note);
            if (done) {
              updated['done'] = true;
            } else {
              updated.remove('done');
            }
            notes[notes.indexOf(note)] = updated;
            dones.add(done);
            return true;
          default:
            return null;
        }
      },
    );
    return (
      updatedTexts: updatedTexts,
      imports: imports,
      cancels: cancels,
      dones: dones,
    );
  }

  testWidgets('renders notes from the native store', (tester) async {
    mockNotesChannels();
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('JotLock (1)'), findsOneWidget);
    expect(find.text('Hello from the lock screen'), findsOneWidget);
  });

  testWidgets('title drops the count when there are no notes',
      (tester) async {
    mockNotesChannels(initialNotes: []);
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('JotLock'), findsOneWidget);
  });

  testWidgets('delete shows an undo snackbar; undo restores the note',
      (tester) async {
    final captured = mockNotesChannels();
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsOneWidget);
    expect(find.text('Hello from the lock screen'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Note restored'), findsOneWidget);
    expect(find.text('Hello from the lock screen'), findsOneWidget);

    // The restore went through the import path with the original note.
    expect(captured.imports, hasLength(1));
    final restored =
        (jsonDecode(((captured.imports.single as Map)['json']) as String)
                as List<dynamic>)
            .single as Map<String, dynamic>;
    expect(restored['id'], '1');
    expect(restored['text'], 'Hello from the lock screen');
  });

  testWidgets('trailing checkbox marks done, strikes text, clears reminder',
      (tester) async {
    final captured = mockNotesChannels(
      initialNotes: [
        {
          'id': '5',
          'text': 'Buy oat milk',
          'createdAt': 0,
          'reminderAt': DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
          'repeatDays': 7,
        },
      ],
    );
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    // Plain note: the only checkbox is the trailing done toggle.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('Marked done — reminder cleared'), findsOneWidget);
    expect(captured.dones, [true]);
    expect(captured.cancels, ['5']);

    final text = tester.widget<Text>(find.text('Buy oat milk'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('unchecking done is a plain state change (no re-arm)',
      (tester) async {
    final captured = mockNotesChannels(
      initialNotes: [
        {'id': '6', 'text': 'Done deed', 'createdAt': 0, 'done': true},
      ],
    );
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(captured.dones, [false]);
    expect(captured.cancels, isEmpty);
    expect(find.textContaining('reminder cleared'), findsNothing);
  });

  testWidgets('done survives delete + undo restore', (tester) async {
    final captured = mockNotesChannels(
      initialNotes: [
        {'id': '12', 'text': 'Keep me', 'createdAt': 0},
      ],
    );
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox)); // mark done
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline)); // delete
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo')); // restore
    await tester.pumpAndSettle();

    expect(find.text('Keep me'), findsOneWidget);
    final restored =
        (jsonDecode(((captured.imports.single as Map)['json']) as String)
                as List<dynamic>)
            .single as Map<String, dynamic>;
    expect(restored['done'], true);
    // And the restored card shows the trailing checkbox checked.
    final box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.value ?? false, isTrue);
  });

  testWidgets('checklist note renders checkbox rows and toggle saves',
      (tester) async {
    final captured = mockNotesChannels(
      initialNotes: [
        {
          'id': '7',
          'text': '[ ] milk\n[x] eggs',
          'createdAt': 0,
        },
      ],
    );
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('1/2'), findsOneWidget);
    // Two body checkbox rows plus the trailing done toggle.
    expect(find.byType(Checkbox), findsNWidgets(3));

    // Checking the first item saves the flipped plain text.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(captured.updatedTexts, ['[x] milk\n[x] eggs']);
    // Body toggles never touch the note-level done flag (independent).
    expect(captured.dones, isEmpty);
  });

  testWidgets('checking the last item clears the reminder automatically',
      (tester) async {
    final captured = mockNotesChannels(
      initialNotes: [
        {
          'id': '8',
          'text': '[x] milk\n[ ] bread',
          'createdAt': 0,
          'reminderAt': DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
          'reminderSilent': false,
          'repeatDays': 7,
        },
      ],
    );
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    // Subtitle shows progress and the weekly recurrence.
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.textContaining('reminds'), findsOneWidget);
    final subtitleText =
        (find.textContaining('reminds').evaluate().single.widget as Text)
            .data!;
    expect(subtitleText, contains('weekly'));

    // One body checkbox remains unchecked (index 1; index 2 is the
    // trailing done toggle); the note has a recurring reminder.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();

    expect(find.text('All items done — reminder cleared'), findsOneWidget);
    expect(captured.cancels, ['8']);
    expect(captured.updatedTexts.single, '[x] milk\n[x] bread');
    // Body completion clears the reminder but does NOT set done.
    expect(captured.dones, isEmpty);
  });

  testWidgets('plain note keeps its text rendering (no checkbox rows)',
      (tester) async {
    mockNotesChannels();
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('Hello from the lock screen'), findsOneWidget);
    // Only the trailing done toggle renders — no checklist rows.
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('pin gate blocks the notes list and re-locks on resume',
      (tester) async {
    mockNotesChannels(pinSet: true, correctPin: '1234');
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    // The gate covers the list; the notes page stays mounted beneath it
    // (by design, so state survives unlock), which finders see through.
    expect(find.text('JotLock is locked'), findsOneWidget);

    // Wrong PIN: error shown, gate stays up.
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN — try again'), findsOneWidget);
    expect(find.text('JotLock is locked'), findsOneWidget);

    // Correct PIN: notes revealed.
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsNothing);
    expect(find.text('Hello from the lock screen'), findsOneWidget);

    // Every return to the foreground re-locks.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsOneWidget);
  });

  testWidgets('keyboard-style focus bounce does not re-lock', (tester) async {
    mockNotesChannels(pinSet: true, correctPin: '1234');
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsNothing);

    // Dismissing the soft keyboard can emit inactive -> resumed without
    // the app ever leaving the foreground (OEM focus bounce) — the gate
    // must stay down.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsNothing);
  });

  testWidgets('re-lock toggle off keeps the gate down across backgrounding',
      (tester) async {
    mockNotesChannels(pinSet: true, correctPin: '1234', relockOnResume: false);
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    // A true backgrounding would normally re-lock, but the setting is off.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsNothing);
  });

  testWidgets('home-button round trip re-locks despite replayed states',
      (tester) async {
    // The real Android sequence: backgrounding emits inactive -> hidden ->
    // paused, and the return replays hidden -> inactive before resumed.
    // The gate must still re-lock on such a return.
    mockNotesChannels(pinSet: true, correctPin: '1234');
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('JotLock is locked'), findsOneWidget);
  });

  testWidgets('about page shows the next-gen mark and the updated message',
      (tester) async {
    mockNotesChannels();
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-next-mark')), findsOneWidget);
    expect(find.textContaining('feature-packed note suite'), findsOneWidget);
    expect(find.textContaining('all-around organizer'), findsOneWidget);
    expect(find.textContaining('If it saves you time too'), findsOneWidget);
    // The old opening line is gone.
    expect(find.textContaining('made by one person'), findsNothing);
  });
}
