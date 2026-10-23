import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const primary = Color(0xFF6155FF);
  static const dark = Color(0xFF20243A);
  static const muted = Color(0xFF81879A);

  final _codeController = TextEditingController();

  Timer? _timer;
  int _resendSeconds = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendCode(resend: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();

    setState(() => _resendSeconds = 60);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode({required bool resend}) async {
    final auth = context.read<AuthProvider>();

    final success = await auth.sendVerificationOtp(resend: resend);

    if (!mounted) return;

    if (success) {
      _startCooldown();
    } else {
      _showMessage(auth.errorMessage ?? 'Unable to send verification code');
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showMessage('Please enter a valid 6-digit code');
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.verifyEmailOtp(code);

    if (!mounted) return;

    if (!success) {
      _showMessage(auth.errorMessage ?? 'Verification failed');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FD),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to login',
          onPressed: auth.isOtpLoading ? null : auth.cancelEmailVerification,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: dark),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: IgnorePointer(
              child: Container(
                width: 310,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.09),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            size: 56,
                            color: primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Verify your email',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w800,
                          color: dark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'We sent a verification code to',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        auth.verificationEmail ?? 'your email',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Enter the 6-digit code below. It expires in 5 minutes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 34),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 12,
                          color: dark,
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 22,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE8EAF2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE8EAF2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _verifyCode(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: auth.isOtpLoading ? null : _verifyCode,
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: auth.isOtpLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Verify Email',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        "Didn't receive the code?",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 5),
                      TextButton(
                        onPressed: auth.isOtpLoading || _resendSeconds > 0
                            ? null
                            : () => _sendCode(resend: true),
                        child: Text(
                          _resendSeconds > 0
                              ? 'Resend in $_resendSeconds seconds'
                              : 'Resend verification code',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (auth.otpMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          auth.otpMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: primary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
