import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('THH Workflow basic widget test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('THH Workflow'))),
    );

    expect(find.text('THH Workflow'), findsOneWidget);
  });
}
