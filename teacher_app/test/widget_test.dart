import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_app/main.dart';

void main() {
  testWidgets('TeacherApp initial render smoke test', (WidgetTester tester) async {
    // Build TeacherApp and trigger a frame.
    await tester.pumpWidget(const TeacherApp());

    // Verify TeacherApp loads with title or login / dashboard screen
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Attendio'), findsWidgets);
  });
}
