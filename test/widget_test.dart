import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jotlock/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders notes from the native store', (tester) async {
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
          default:
            return null;
        }
      },
    );

    await tester.pumpWidget(const LockNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('JotLock'), findsOneWidget);
    expect(find.text('Hello from the lock screen'), findsOneWidget);
  });
}
