// ignore_for_file: depend_on_referenced_packages

// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_classroom/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: '1:1234567890:android:test',
          messagingSenderId: '1234567890',
          projectId: 'smart-classroom-test',
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  testWidgets('App launches and shows role select screen', (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    
    await tester.pumpWidget(const SmartClassroomApp());
    await tester.pumpAndSettle();

    // Role select screen should show both role options
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
