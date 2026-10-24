import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thh_company_frontend/core/design/app_theme.dart';
import 'package:thh_company_frontend/core/network/api_client.dart';
import 'package:thh_company_frontend/core/network/workspace_api.dart';
import 'package:thh_company_frontend/features/workspace/access.dart';
import 'package:thh_company_frontend/features/auth/auth_screen.dart';
import 'package:thh_company_frontend/features/workspace/workspace_screen.dart';
import 'package:thh_company_frontend/providers/auth_provider.dart';

import 'test_support.dart';

Future<void> capture(WidgetTester tester, String name, {Finder? target}) async {
  final directory = Platform.environment['THH_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    for (final asset in [
      'assets/images/thh_workflow_logo.png',
      'assets/illustrations/security.png',
      'assets/illustrations/checklist.png',
      'assets/illustrations/inbox.png',
    ]) {
      await precacheImage(
        AssetImage(asset),
        tester.element(find.byType(MaterialApp)),
      );
    }
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      target ?? find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final poppins = FontLoader('Poppins');
    for (final name in [
      'Poppins-Regular.ttf',
      'Poppins-Medium.ttf',
      'Poppins-SemiBold.ttf',
      'Poppins-Bold.ttf',
      'Poppins-ExtraBold.ttf',
    ]) {
      poppins.addFont(rootBundle.load('assets/fonts/$name'));
    }
    await poppins.load();
    final fontDirectory = Platform.environment['THH_FONT_DIRECTORY'];
    if (fontDirectory == null) return;
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final name in entry.value) {
        loader.addFont(
          File('$fontDirectory/$name')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
    }
  });
  test('response parsing supports the backend collection envelopes', () {
    for (final body in <Record>[
      {
        'users': [
          {'id': 1},
        ],
      },
      {
        'departments': [
          {'id': 1},
        ],
      },
      {
        'data': [
          {'id': 1},
        ],
        'pagination': {'total': 21, 'totalPages': 2},
      },
      {
        'data': {
          'notifications': [
            {'id': 1},
          ],
          'pagination': {'total': 21, 'totalPages': 2},
        },
      },
      {
        'data': {
          'logs': [
            {'id': 1},
          ],
          'pagination': {'total': 21, 'totalPages': 2},
        },
      },
    ]) {
      expect(WorkspaceApi.parsePage(body).items.single['id'], 1);
    }
  });
  test(
    'role permissions preserve project leadership and independent reviews',
    () {
      final employee = Access(userFor('EMPLOYEE'));
      final manager = Access(userFor('MANAGER'));
      final admin = Access(userFor('ADMIN'));
      final task = <String, dynamic>{
        'createdById': 2,
        'project': {'leadManagerId': 1, 'ownerDepartmentId': 1},
        'assignments': [
          {'userId': 1},
        ],
      };
      expect(employee.destinations, isNot(contains('People')));
      expect(manager.destinations, contains('Approvals'));
      expect(employee.worksOn(task), true);
      expect(employee.managesTask(task), false);
      expect(manager.managesTask(task), true);
      expect(admin.reviews(task), false);
      task['assignments'] = [];
      expect(admin.reviews(task), true);
      expect(manager.reviews(task), true);
      task['createdById'] = 1;
      expect(manager.reviews(task), false);
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(412, 915),
    const Size(1280, 900),
  ]) {
    testWidgets('login layout fits ${size.width} with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage();
      final auth = AuthProvider(api: ApiClient(storage), storage: storage);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      if (size.width == 360) await capture(tester, 'login-android');
      expect(tester.takeException(), isNull);
    });
  }
  for (final role in ['ADMIN', 'MANAGER', 'EMPLOYEE']) {
    testWidgets('$role Android layout shows role-specific navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = signedIn(role);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const WorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Hello, Kim'), findsOneWidget);
      if (role == 'EMPLOYEE') await capture(tester, 'workspace-android');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(
        find.text('People'),
        role == 'EMPLOYEE' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Approvals'),
        role == 'EMPLOYEE' ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
