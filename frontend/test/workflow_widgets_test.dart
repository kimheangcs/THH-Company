import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thh_company_frontend/core/design/app_theme.dart';
import 'package:thh_company_frontend/core/network/workspace_api.dart';
import 'package:thh_company_frontend/features/workspace/access.dart';
import 'package:thh_company_frontend/features/workspace/record_screen.dart';

import 'test_support.dart';

import 'package:thh_company_frontend/features/shared/editor.dart';

void main() {
  testWidgets(
    'assigned employee submits a task and loses progress controls during review',
    (tester) async {
      final task = <String, dynamic>{
        'id': 7,
        'title': 'Prepare the launch',
        'status': 'IN_PROGRESS',
        'progress': 80,
        'createdById': 2,
        'project': {
          'id': 1,
          'name': 'Launch',
          'status': 'IN_PROGRESS',
          'leadManagerId': 2,
          'ownerDepartmentId': 1,
        },
        'assignments': [
          {'userId': 1, 'user': userFor('EMPLOYEE')},
        ],
      };
      final adapter = FakeAdapter((options) async {
        if (options.path == '/api/tasks/7/submit-review') {
          task['status'] = 'IN_REVIEW';
          return {'data': task};
        }
        if (options.path == '/api/tasks/7') return {'data': task};
        return {'data': []};
      });
      final auth = signedIn('EMPLOYEE', adapter: adapter);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecordScreen(
            kind: 'Tasks',
            id: 7,
            api: WorkspaceApi(auth.api),
            access: Access(auth.user!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approve task'), findsNothing);
      await tester.ensureVisible(find.text('Submit for review'));
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        adapter.calls.where((c) => c.path.endsWith('submit-review')).length,
        1,
      );
      expect(find.text('Update progress'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.text('In Review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('assigned manager rejects a request with a required reason', (
    tester,
  ) async {
    final request = <String, dynamic>{
      'id': 7,
      'title': 'Purchase request',
      'type': 'PURCHASE',
      'status': 'PENDING',
      'submittedById': 2,
      'assignedApproverId': 1,
    };
    final adapter = FakeAdapter((options) async {
      if (options.path == '/api/requests/7/reject') {
        expect(options.data['comment'], 'Budget needs revision');
        request['status'] = 'REJECTED';
        return {'data': request};
      }
      if (options.path == '/api/requests/7/history') {
        return {
          'data': {'approvalSteps': [], 'approvalActions': []},
        };
      }
      if (options.path == '/api/requests/7') return {'data': request};
      return {'data': []};
    });
    final auth = signedIn('MANAGER', adapter: adapter);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RecordScreen(
          kind: 'Requests',
          id: 7,
          api: WorkspaceApi(auth.api),
          access: Access(auth.user!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Reason for rejection is required'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Budget needs revision');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'notification uses its list data and never calls a nonexistent detail endpoint',
    (tester) async {
      final adapter = FakeAdapter((_) async => {'data': []});
      final auth = signedIn('EMPLOYEE', adapter: adapter);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecordScreen(
            kind: 'Inbox',
            id: 7,
            api: WorkspaceApi(auth.api),
            access: Access(auth.user!),
            initial: {
              'id': 7,
              'title': 'Task updated',
              'message': 'Your team shared an update.',
              'isRead': false,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your team shared an update.'), findsOneWidget);
      expect(adapter.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'forms keep text booleans as text and preserve password whitespace',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEditor(
                  context,
                  title: 'Edit record',
                  fields: const [
                    EditField('title', 'Title', required: true),
                    EditField(
                      'password',
                      'Password',
                      secret: true,
                      required: true,
                    ),
                  ],
                  save: (body) async {
                    saved = body;
                  },
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'true');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  Password@2026  ',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved?['title'], 'true');
      expect(saved?['password'], '  Password@2026  ');
    },
  );
}
