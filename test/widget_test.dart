import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockNotesChannels({bool pinSet = false, String? correctPin}) {
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
            return <Map<String, Object>>[
              {
                'id': '1',
                'text': 'Hello from the lock screen',
                'createdAt': 0,
              },
            ];
          case 'isNotificationEnabled':
            return true;
          case 'isPinSet':
            return pinSet;
          case 'verifyPin':
            final args = call.arguments as Map?;
            return correctPin != null && args?['pin'] == correctPin;
          default:
            return null;
        }
      },
    );
  }

  testWidgets('renders notes from the native store', (tester) async {
    mockNotesChannels();
    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('JotLock'), findsOneWidget);
    expect(find.text('Hello from the lock screen'), findsOneWidget);
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
}
