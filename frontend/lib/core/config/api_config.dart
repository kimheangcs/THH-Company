class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String loginPath = '/api/auth/login';
  static const String mePath = '/api/auth/me';
  static const String logoutPath = '/api/auth/logout';

  static const String sendVerificationOtpPath =
      '/api/auth/send-verification-otp';

  static const String resendVerificationOtpPath =
      '/api/auth/resend-verification-otp';

  static const String verifyEmailPath = '/api/auth/verify-email';
}
