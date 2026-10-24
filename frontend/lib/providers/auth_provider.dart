import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  final TokenStorage storage;

  AuthProvider({
    required this.api,
    required this.storage,
    Dio? verificationClient,
  }) : _providedVerificationClient = verificationClient {
    api.onSessionExpired = () async {
      isAuthenticated = false;
      user = null;
      _clearVerification();
      errorMessage = 'Your session expired. Please sign in again.';
      notifyListeners();
    };
  }

  final Dio? _providedVerificationClient;
  bool isRestoringSession = false;

  bool isLoading = false;
  bool isOtpLoading = false;
  bool isAuthenticated = false;
  bool requiresEmailVerification = false;
  bool requiresPasswordChange = false;
  String? _passwordChangeToken;

  Map<String, dynamic>? user;
  String? errorMessage;
  String? otpMessage;

  String? _verificationToken;
  String? _verificationEmail;

  String? get verificationEmail => _verificationEmail;

  // Separate client: verification tokens must never be confused
  // with normal session tokens stored in secure storage.
  late final Dio _verificationDio =
      _providedVerificationClient ??
      Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

  String? _extractToken(dynamic response) {
    if (response is! Map) return null;

    final data = response['data'];

    final candidates = [
      response['token'],
      response['accessToken'],
      if (data is Map) data['token'],
      if (data is Map) data['accessToken'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.isNotEmpty) {
        return candidate;
      }
    }

    return null;
  }

  Map<String, dynamic> _extractUser(dynamic response) {
    if (response is! Map) {
      throw const FormatException('Invalid user response');
    }

    final data = response['data'];
    dynamic result = response['user'];

    if (result == null && data is Map) {
      result = data['user'] ?? data;
    }

    result ??= response;

    if (result is! Map) {
      throw const FormatException('User not found');
    }

    return Map<String, dynamic>.from(result);
  }

  void _clearVerification() {
    _verificationToken = null;
    _verificationEmail = null;
    requiresEmailVerification = false;
    requiresPasswordChange = false;
    _passwordChangeToken = null;
    otpMessage = null;
  }

  Future<void> refreshProfile() async {
    try {
      final response = await api.dio.get(ApiConfig.mePath);
      user = _extractUser(response.data);
      notifyListeners();
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        await storage.deleteToken();
        isAuthenticated = false;
        user = null;
        errorMessage = api.errorMessage(error);
        notifyListeners();
      }
      // An expired session is handled by ApiClient. Temporary network failures
      // leave the last known profile available; the destination offers retry.
    }
  }

  Future<void> restoreSession() async {
    isRestoringSession = true;
    isLoading = true;
    notifyListeners();

    try {
      final token = await storage.readToken();

      if (token == null || token.isEmpty) {
        user = null;
        isAuthenticated = false;
        return;
      }

      final response = await api.dio.get(ApiConfig.mePath);

      user = _extractUser(response.data);
      isAuthenticated = true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await storage.deleteToken();
      }

      user = null;
      isAuthenticated = false;
    } catch (_) {
      user = null;
      isAuthenticated = false;
    } finally {
      isLoading = false;
      isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    storage.persistSession = rememberMe;
    isLoading = true;
    errorMessage = null;
    _clearVerification();
    notifyListeners();

    try {
      await storage.deleteToken();
      final response = await api.dio.post(
        ApiConfig.loginPath,
        data: {'email': email.trim(), 'password': password},
      );

      final body = response.data;

      if (body is! Map) {
        throw const FormatException('Invalid login response');
      }

      if (body['requiresEmailVerification'] == true) {
        final token = body['verificationToken'];

        if (token is! String || token.isEmpty) {
          throw const FormatException(
            'Verification token missing from login response',
          );
        }

        _verificationToken = token;
        _verificationEmail = email.trim();
        requiresEmailVerification = true;
        isAuthenticated = false;
        user = null;

        return false;
      }

      if (body['requiresPasswordChange'] == true) {
        _setPasswordChange(body);
        return false;
      }

      final token = _extractToken(body);

      if (token == null) {
        throw const FormatException('Access token missing from login response');
      }

      await storage.saveToken(token);

      final profile = await api.dio.get(ApiConfig.mePath);

      user = _extractUser(profile.data);
      isAuthenticated = true;

      return true;
    } catch (error) {
      await storage.deleteToken();
      isAuthenticated = false;
      user = null;
      _clearVerification();

      errorMessage = error is FormatException
          ? error.message
          : api.errorMessage(error);

      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Options _verificationOptions() {
    final token = _verificationToken;

    if (token == null || token.isEmpty) {
      throw const FormatException(
        'Verification session expired. Please sign in again.',
      );
    }

    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<bool> sendVerificationOtp({bool resend = false}) async {
    if (isOtpLoading) return false;

    isOtpLoading = true;
    errorMessage = null;
    otpMessage = null;
    notifyListeners();

    try {
      final path = resend
          ? ApiConfig.resendVerificationOtpPath
          : ApiConfig.sendVerificationOtpPath;

      final response = await _verificationDio.post(
        path,
        options: _verificationOptions(),
      );

      final body = response.data;

      otpMessage = body is Map && body['message'] is String
          ? body['message'] as String
          : 'Verification code sent';

      return true;
    } catch (error) {
      errorMessage = error is FormatException
          ? error.message
          : api.errorMessage(error);

      return false;
    } finally {
      isOtpLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String code) async {
    if (isOtpLoading) return false;

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      errorMessage = 'Enter a valid 6-digit code';
      notifyListeners();
      return false;
    }

    isOtpLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _verificationDio.post(
        ApiConfig.verifyEmailPath,
        data: {'code': code},
        options: _verificationOptions(),
      );

      // The backend marks the email verified but does not
      // create a normal login session.
      _clearVerification();

      isAuthenticated = false;
      user = null;
      if (response.data is Map &&
          response.data['requiresPasswordChange'] == true) {
        _setPasswordChange(response.data as Map);
      } else {
        otpMessage = 'Email verified successfully. Please sign in.';
      }

      return true;
    } catch (error) {
      errorMessage = error is FormatException
          ? error.message
          : api.errorMessage(error);

      return false;
    } finally {
      isOtpLoading = false;
      notifyListeners();
    }
  }

  void _setPasswordChange(Map body) {
    final token = body['passwordChangeToken'];
    if (token is! String || token.isEmpty) {
      throw const FormatException(
        'Password change session missing. Sign in again.',
      );
    }
    _passwordChangeToken = token;
    requiresPasswordChange = true;
    requiresEmailVerification = false;
    isAuthenticated = false;
    user = null;
  }

  Future<bool> changeInitialPassword(String password) async {
    if (isOtpLoading) return false;
    isOtpLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (_passwordChangeToken == null) {
        throw const FormatException('Sign in again to choose your password.');
      }
      await _verificationDio.post(
        '/api/auth/change-initial-password',
        data: {'password': password},
        options: Options(
          headers: {'Authorization': 'Bearer $_passwordChangeToken'},
        ),
      );
      _clearVerification();
      otpMessage = 'Password saved. Sign in with your personal password.';
      return true;
    } catch (error) {
      errorMessage = error is FormatException
          ? error.message
          : api.errorMessage(error);
      return false;
    } finally {
      isOtpLoading = false;
      notifyListeners();
    }
  }

  void cancelEmailVerification() {
    if (isOtpLoading) return;

    _clearVerification();
    errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    isLoading = true;
    notifyListeners();

    try {
      await api.dio.post(ApiConfig.logoutPath);
    } catch (_) {
      // A failed request does not confirm server-side revocation.
    } finally {
      await storage.deleteToken();

      user = null;
      isAuthenticated = false;
      _clearVerification();

      isLoading = false;
      notifyListeners();
    }
  }
}
