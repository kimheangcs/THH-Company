import 'package:dio/dio.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thh_company_frontend/core/design/app_theme.dart';
import 'package:thh_company_frontend/core/network/api_client.dart';
import 'package:thh_company_frontend/core/storage/token_storage.dart';
import 'package:thh_company_frontend/features/auth/auth_screen.dart';
import 'package:thh_company_frontend/features/shared/editor.dart';
import 'package:thh_company_frontend/features/workspace/profile_sheet.dart';
import 'package:thh_company_frontend/providers/auth_provider.dart';

import 'test_support.dart';
import 'widget_test.dart' show capture;

void main() {
  setUpAll(() async {
    final font = FontLoader('Poppins');
    for (final name in [
      'Poppins-Regular.ttf',
      'Poppins-Medium.ttf',
      'Poppins-SemiBold.ttf',
      'Poppins-Bold.ttf',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/$name'));
    }
    await font.load();
    final directory = Platform.environment['THH_FONT_DIRECTORY'];
    if (directory != null) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('$directory/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    }
  });
  test('all primary text styles use the bundled Poppins family', () {
    for (final style in [
      AppTheme.light.textTheme.bodyMedium,
      AppTheme.light.textTheme.titleMedium,
      AppTheme.light.textTheme.headlineLarge,
    ]) {
      expect(style?.fontFamily, 'Poppins');
    }
  });
  test(
    'remember me persists only explicitly remembered access sessions',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final temporary = TokenStorage()..persistSession = false;
      await temporary.saveToken('temporary-test-token');
      expect(await temporary.readToken(), 'temporary-test-token');
      expect(await TokenStorage().readToken(), isNull);
      await temporary.deleteToken();
      expect(await temporary.readToken(), isNull);
      final remembered = TokenStorage();
      await remembered.saveToken('remembered-test-token');
      expect(await TokenStorage().readToken(), 'remembered-test-token');
      await remembered.deleteToken();
      expect(await TokenStorage().readToken(), isNull);
    },
  );
  for (final role in ['ADMIN', 'MANAGER', 'EMPLOYEE']) {
    testWidgets('$role profile card matches its role and fits a small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: RepaintBoundary(
                      key: const ValueKey('profile-preview'),
                      child: ProfileCard(user: userFor(role)),
                    ),
                  ),
                ),
                child: const Text('Open profile'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open profile'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          role == 'ADMIN'
              ? 'Admin'
              : role == 'MANAGER'
              ? 'Manager'
              : 'Employee',
        ),
        findsOneWidget,
      );
      expect(
        find.text(role == 'ADMIN' ? 'Edit profile' : 'Profile details'),
        findsOneWidget,
      );
      expect(
        find.text(role == 'ADMIN' ? 'Change password' : 'Password help'),
        findsOneWidget,
      );
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      await capture(
        tester,
        'profile-${role.toLowerCase()}',
        target: find.byKey(const ValueKey('profile-preview')),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'six-digit OTP accepts a pasted code and opens personal password setup',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage(), api = ApiClient(MemoryStorage());
      api.dio.httpClientAdapter = FakeAdapter(
        (_) async => {
          'requiresEmailVerification': true,
          'verificationToken': 'verify',
        },
      );
      final restricted = Dio()
        ..httpClientAdapter = FakeAdapter((options) async {
          expect(options.data['code'], '142869');
          return {
            'requiresPasswordChange': true,
            'passwordChangeToken': 'change',
          };
        });
      final auth = AuthProvider(
        api: api,
        storage: storage,
        verificationClient: restricted,
      );
      await tester.runAsync(
        () => auth.login(
          email: 'person@example.test',
          password: 'DefaultPassword@2026',
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verify OTP'), findsOneWidget);
      await capture(tester, 'otp-android');
      await tester.enterText(find.byKey(const ValueKey('otp-input')), '142869');
      await tester.ensureVisible(find.text('Verify code'));
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('Save new password'), findsOneWidget);
      await capture(tester, 'reset-password-android');
      expect(await storage.readToken(), isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mobile editors remain usable above the Android keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditor(
                context,
                title: 'New teammate',
                fields: const [
                  EditField('firstName', 'First name', required: true),
                  EditField('lastName', 'Last name', required: true),
                  EditField('email', 'Work email', required: true),
                ],
                save: (_) async {},
              ),
              child: const Text('Create'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('forgot password explains the supported admin reset flow', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final auth = AuthProvider(api: ApiClient(storage), storage: storage);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('company administrator to reset'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
