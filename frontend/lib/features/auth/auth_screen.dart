import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  DateTime? _resendAt;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final verify = auth.requiresEmailVerification;
    final change = auth.requiresPasswordChange;
    final busy = auth.isLoading || auth.isOtpLoading;
    final heading = change
        ? 'Make it yours.'
        : verify
        ? 'Check your inbox.'
        : 'Welcome back.';
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          return Row(
            children: [
              if (wide)
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF20213F), Color(0xFF3D2D72)],
                      ),
                    ),
                    padding: const EdgeInsets.all(64),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Brand(light: true),
                          const SizedBox(height: 48),
                          const Text(
                            'Great work.\nOne shared space.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 54,
                              height: 1.1,
                              letterSpacing: -2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Bring your people, projects, and decisions together.\nA little less busywork. A lot more momentum.',
                            style: TextStyle(
                              color: Color(0xFFCEC7E7),
                              height: 1.8,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Surface(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome,
                                      color: AppTheme.teal,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Built around your team',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'A focused workspace for every role, from your first task to your next big milestone.',
                                ),
                                const SizedBox(height: 18),
                                const Wrap(
                                  spacing: 8,
                                  children: [
                                    StatusPill('PROJECTS'),
                                    StatusPill('TEAMWORK'),
                                    StatusPill('PROGRESS'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 48),
                          const Text(
                            'THH COMPANY  /  WORK BETTER, TOGETHER',
                            style: TextStyle(
                              color: Color(0xFFB2A9CC),
                              fontSize: 11,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 56 : 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!wide) ...[
                              const _Brand(),
                              const SizedBox(height: 56),
                            ],
                            const Text(
                              'YOUR WORKSPACE, CONNECTED',
                              style: TextStyle(
                                color: AppTheme.teal,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              heading,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              change
                                  ? 'Choose a personal password to finish setting up your account.'
                                  : verify
                                  ? 'Send a verification code to ${auth.verificationEmail ?? 'your email'}, then enter it below.'
                                  : 'Sign in to pick up where your team left off.',
                              style: const TextStyle(color: AppTheme.muted),
                            ),
                            const SizedBox(height: 32),
                            if (!verify && !change) ...[
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: 'Work email',
                                  prefixIcon: Icon(Icons.alternate_email),
                                ),
                                validator: (v) =>
                                    v != null &&
                                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                            .hasMatch(v.trim())
                                    ? null
                                    : 'Enter your work email',
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!verify) ...[
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                autofillHints: [
                                  change
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: change
                                      ? 'Personal password'
                                      : 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Enter your password';
                                  }
                                  if (change &&
                                      (v.length < 12 ||
                                          utf8.encode(v).length > 72 ||
                                          !RegExp(r'[A-Z]').hasMatch(v) ||
                                          !RegExp(r'[a-z]').hasMatch(v) ||
                                          !RegExp(r'[0-9]').hasMatch(v) ||
                                          !RegExp(r'[^A-Za-z0-9]')
                                              .hasMatch(v))) {
                                    return 'Use 12+ characters with upper/lowercase, a number\nand symbol; maximum 72 UTF-8 bytes.';
                                  }
                                  return null;
                                },
                              ),
                              if (change) ...[
                                const SizedBox(height: 18),
                                TextFormField(
                                  controller: _confirmation,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm personal password',
                                  ),
                                  validator: (v) => v == _password.text
                                      ? null
                                      : 'Passwords do not match',
                                ),
                              ],
                            ],
                            if (verify) ...[
                              TextFormField(
                                controller: _code,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                  labelText: '6-digit verification code',
                                  prefixIcon: Icon(
                                    Icons.mark_email_read_outlined,
                                  ),
                                ),
                                validator: (v) =>
                                    RegExp(r'^\d{6}$').hasMatch(v ?? '')
                                    ? null
                                    : 'Enter the 6-digit code',
                              ),
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (_resendAt != null &&
                                            DateTime.now().isBefore(
                                              _resendAt!,
                                            )) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Please wait 60 seconds before resending.',
                                                  ),
                                                ),
                                              );
                                          return;
                                        }
                                        if (await auth.sendVerificationOtp(
                                          resend: _resendAt != null,
                                        )) {
                                          _resendAt = DateTime.now().add(
                                            const Duration(seconds: 60),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.send_outlined, size: 18),
                                label: const Text('Send / resend code'),
                              ),
                            ],
                            if (auth.errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  auth.errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            if (auth.otpMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  auth.otpMessage!,
                                  style: const TextStyle(color: AppTheme.teal),
                                ),
                              ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (!_form.currentState!.validate()) {
                                          return;
                                        }
                                        if (change) {
                                          if (await auth.changeInitialPassword(
                                            _password.text,
                                          )) {
                                            _password.clear();
                                            _confirmation.clear();
                                          }
                                        } else if (verify) {
                                          if (await auth.verifyEmailOtp(
                                            _code.text.trim(),
                                          )) {
                                            _password.clear();
                                            _code.clear();
                                          }
                                        } else {
                                          await auth.login(
                                            email: _email.text,
                                            password: _password.text,
                                          );
                                        }
                                      },
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward, size: 18),
                                label: Text(
                                  change
                                      ? 'Save personal password'
                                      : verify
                                      ? 'Verify email'
                                      : 'Sign in',
                                ),
                              ),
                            ),
                            if (verify || change)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : auth.cancelEmailVerification,
                                child: const Text('Back to sign in'),
                              ),
                            const SizedBox(height: 32),
                            const Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: AppTheme.muted,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Your workspace. Securely connected.',
                                    style: TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool light;
  const _Brand({this.light = false});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/images/thh_workflow_logo.png',
          width: 64,
          height: 64,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'THH',
        style: TextStyle(
          color: light ? Colors.white : AppTheme.ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'WORKFLOW',
        style: TextStyle(
          color: light ? const Color(0xFFCEC7E7) : AppTheme.muted,
          fontSize: 11,
          letterSpacing: 2,
        ),
      ),
    ],
  );
}
