import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thh_company_frontend/core/design/app_theme.dart';
import 'package:thh_company_frontend/core/network/workspace_api.dart';
import 'package:thh_company_frontend/features/shared/editor.dart';
import 'package:thh_company_frontend/features/workspace/access.dart';
import 'package:thh_company_frontend/features/workspace/resource_forms.dart';

import 'test_support.dart';

const departmentData = [
  {'id': 1, 'name': 'IT Department', 'isActive': true, 'managerId': 11},
  {'id': 2, 'name': 'Marketing Department', 'isActive': true, 'managerId': 22},
  {'id': 3, 'name': 'No manager', 'isActive': true, 'managerId': null},
  {'id': 4, 'name': 'Inactive manager', 'isActive': true, 'managerId': 44},
  {'id': 5, 'name': 'Unverified manager', 'isActive': true, 'managerId': 55},
];
final peopleData = [
  userFor('ADMIN'),
  for (final item in [
    (12, 'Other', 'IT Manager', 1, 'ACTIVE', true),
    (11, 'Chan', 'Sophea', 1, 'ACTIVE', true),
    (22, 'Sok', 'Dara', 2, 'ACTIVE', true),
    (44, 'Inactive', 'Manager', 4, 'INACTIVE', true),
    (55, 'Unverified', 'Manager', 5, 'ACTIVE', false),
  ])
    {
      'id': item.$1,
      'firstName': item.$2,
      'lastName': item.$3,
      'departmentId': item.$4,
      'status': item.$5,
      'emailVerifiedAt': item.$6 ? '2026-10-01T00:00:00Z' : null,
      'role': 'MANAGER',
    },
];

WorkspaceApi demoApi({bool manager = false}) {
  final auth = signedIn(
    manager ? 'MANAGER' : 'ADMIN',
    adapter: FakeAdapter(
      (options) async => options.path == '/api/departments'
          ? {'departments': departmentData}
          : {'users': manager ? [] : peopleData},
    ),
  );
  return WorkspaceApi(auth.api);
}

Finder dropdown(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byType(DropdownButtonFormField<String>),
    )
    .first;
Future<void> choose(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(dropdown(label));
  await tester.tap(dropdown(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> openProject(
  WidgetTester tester, {
  Record initial = const {},
  Record? existing,
  required Future<void> Function(Record) save,
}) async {
  final fields = await tester.runAsync(
    () => resourceFields(
      'Projects',
      demoApi(),
      Access(userFor('ADMIN')),
      existing: existing,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEditor(
              context,
              title: 'Project',
              fields: fields!,
              initial: initial,
              save: save,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

String? leadValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<String>>(dropdown('Project lead'))
    .initialValue;

void main() {
  testWidgets(
    'owning department loads its assigned manager and submits numeric IDs',
    (tester) async {
      Record? saved;
      await openProject(
        tester,
        save: (body) async {
          saved = body;
        },
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Team portal');
      await tester.enterText(find.byType(TextFormField).at(1), 'PORTAL');
      await choose(tester, 'Owning department', 'IT Department');
      expect(leadValue(tester), '11');
      expect(find.text('Chan Sophea · Manager'), findsOneWidget);
      await choose(tester, 'Owning department', 'Marketing Department');
      expect(leadValue(tester), '22');
      expect(find.text('Sok Dara · Manager'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved?['ownerDepartmentId'], 2);
      expect(saved?['leadManagerId'], 22);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing, inactive and unverified managers clear the previous lead',
    (tester) async {
      Record? saved;
      await openProject(
        tester,
        save: (body) async {
          saved = body;
        },
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Team portal');
      await tester.enterText(find.byType(TextFormField).at(1), 'PORTAL');
      for (final department in [
        'No manager',
        'Inactive manager',
        'Unverified manager',
      ]) {
        await choose(tester, 'Owning department', 'IT Department');
        expect(leadValue(tester), '11');
        await choose(tester, 'Owning department', department);
        expect(leadValue(tester), isNull);
        expect(
          find.textContaining('No active, verified manager assigned'),
          findsOneWidget,
        );
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(find.text('Choose project lead'), findsOneWidget);
        expect(saved, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editing preserves a current lead until the department changes', (
    tester,
  ) async {
    final existing = <String, dynamic>{
      'name': 'Existing project',
      'code': 'EXISTING',
      'ownerDepartmentId': 1,
      'leadManagerId': 1,
    };
    await openProject(
      tester,
      initial: existing,
      existing: existing,
      save: (_) async {},
    );
    expect(leadValue(tester), '1');
    await choose(tester, 'Owning department', 'IT Department');
    expect(leadValue(tester), '1');
    await choose(tester, 'Owning department', 'Marketing Department');
    expect(leadValue(tester), '22');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a preset department loads its manager when no lead is supplied',
    (tester) async {
      await openProject(
        tester,
        initial: {'ownerDepartmentId': 1},
        save: (_) async {},
      );
      expect(leadValue(tester), '11');
      expect(tester.takeException(), isNull);
    },
  );
  test('manager defaults use the authenticated manager when users API hides managers', () async {
    final actor = {
      ...userFor('MANAGER'),
      'id': 11,
      'departmentId': 1,
      'firstName': 'Chan',
      'lastName': 'Sophea',
    };
    final fields = await resourceFields(
      'Projects',
      demoApi(manager: true),
      Access(actor),
    );
    final owner = fields.singleWhere((f) => f.keyName == 'ownerDepartmentId');
    final lead = fields.singleWhere((f) => f.keyName == 'leadManagerId');
    expect(owner.choices?.keys, ['1']);
    expect(owner.selectionDefaults?['1']?['leadManagerId'], '11');
    expect(lead.choices?.keys, ['11']);
  });
}
