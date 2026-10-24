import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thh_company_frontend/core/network/api_client.dart';
import 'package:thh_company_frontend/providers/auth_provider.dart';

import 'test_support.dart';

void main() {
  test('restricted tokens stay out of storage through verification and password change', () async {
    final storage = MemoryStorage();
    final api = ApiClient(storage);
    var personal = false;
    api.dio.httpClientAdapter = FakeAdapter((options) async {
      if (options.path.endsWith('/me')) return {'user': userFor('EMPLOYEE')};
      if (personal) return {'token': 'access', 'requiresPasswordChange': false};
      return {
        'requiresEmailVerification': true,
        'verificationToken': 'verification',
      };
    });
    final restricted = Dio();
    final adapter = FakeAdapter((options) async {
      if (options.path.endsWith('verify-email')) {
        expect(options.headers['Authorization'], 'Bearer verification');
        return {
          'requiresPasswordChange': true,
          'passwordChangeToken': 'password-change',
        };
      }
      if (options.path.endsWith('change-initial-password')) {
        expect(options.headers['Authorization'], 'Bearer password-change');
        personal = true;
      }
      return {'success': true};
    });
    restricted.httpClientAdapter = adapter;
    final auth = AuthProvider(
      api: api,
      storage: storage,
      verificationClient: restricted,
    );
    expect(
      await auth.login(
        email: 'kim@example.test',
        password: 'DefaultPassword@2026',
      ),
      false,
    );
    expect(auth.requiresEmailVerification, true);
    expect(storage.token, isNull);
    expect(await auth.sendVerificationOtp(), true);
    expect(await auth.verifyEmailOtp('123456'), true);
    expect(auth.requiresPasswordChange, true);
    expect(auth.requiresEmailVerification, false);
    expect(storage.token, isNull);
    expect(await auth.changeInitialPassword('PersonalPassword@2026'), true);
    expect(storage.token, isNull);
    expect(auth.requiresPasswordChange, false);
    expect(
      await auth.login(
        email: 'kim@example.test',
        password: 'PersonalPassword@2026',
      ),
      true,
    );
    expect(storage.token, 'access');
    expect(auth.isAuthenticated, true);
  });
  test(
    'verified account can resume password setup and recover from expired token',
    () async {
      final storage = MemoryStorage();
      final api = ApiClient(storage);
      api.dio.httpClientAdapter = FakeAdapter(
        (_) async => {
          'requiresPasswordChange': true,
          'passwordChangeToken': 'change',
        },
      );
      final restricted = Dio()
        ..httpClientAdapter = FakeAdapter(
          (_) async => {
            '_status': 401,
            'message': 'Invalid or expired password change token',
          },
        );
      final auth = AuthProvider(
        api: api,
        storage: storage,
        verificationClient: restricted,
      );
      await auth.login(
        email: 'kim@example.test',
        password: 'ResetPassword@2026',
      );
      expect(auth.requiresPasswordChange, true);
      expect(await auth.changeInitialPassword('PersonalPassword@2026'), false);
      expect(auth.errorMessage, contains('expired'));
      auth.cancelEmailVerification();
      expect(auth.requiresPasswordChange, false);
      expect(storage.token, isNull);
    },
  );
  test(
    'expired access sessions clear secure storage and signed-in state',
    () async {
      final auth = signedIn(
        'EMPLOYEE',
        adapter: FakeAdapter(
          (_) async => {
            '_status': 401,
            'message': 'Session expired or revoked',
          },
        ),
      );
      await expectLater(
        auth.api.dio.get('/api/tasks'),
        throwsA(isA<DioException>()),
      );
      expect(auth.isAuthenticated, false);
      expect(auth.user, isNull);
      expect(await auth.storage.readToken(), isNull);
      expect(auth.errorMessage, contains('expired'));
    },
  );
}
