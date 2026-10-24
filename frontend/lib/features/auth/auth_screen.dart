import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/brand_widgets.dart';
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
  bool _obscure = true, _obscureConfirmation = true, _remember = true;
  int _resendSeconds = 0;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send(AuthProvider auth) async {
    if (_resendSeconds > 0) return;
    if (await auth.sendVerificationOtp(resend: _timer != null)) {
      if (!mounted) return;
      setState(() => _resendSeconds = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _resendSeconds--);
        if (_resendSeconds == 0) timer.cancel();
      });
    }
  }

  void _help(String title, String content) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
  int get _strength {
    final p = _password.text;
    return (p.length >= 12 && utf8.encode(p).length <= 72 ? 1 : 0) +
        (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p) ? 1 : 0) +
        (RegExp(r'[0-9]').hasMatch(p) ? 1 : 0) +
        (RegExp(r'[^A-Za-z0-9]').hasMatch(p) ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final verify = auth.requiresEmailVerification,
        change = auth.requiresPasswordChange,
        busy = auth.isLoading || auth.isOtpLoading;
    return Scaffold(
      body: WaveBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WorkflowBrand(),
                        const SizedBox(height: 24),
                        _hero(verify: verify, change: change),
                        const SizedBox(height: 18),
                        Surface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (verify) ...[
                                const SizedBox(height: 8),
                                _otpInput(busy),
                                const SizedBox(height: 22),
                                Text(
                                  'Code sent to',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  auth.verificationEmail ?? 'your work email',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      'Didn’t receive the code?',
                                      style: TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: busy || _resendSeconds > 0
                                          ? null
                                          : () => _send(auth),
                                      child: Text(
                                        _timer == null
                                            ? 'Send OTP'
                                            : 'Resend OTP',
                                      ),
                                    ),
                                  ],
                                ),
                                if (_resendSeconds > 0)
                                  Text(
                                    'Resend in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                const SizedBox(height: 14),
                              ] else ...[
                                if (!change) ...[
                                  TextFormField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    decoration: _decoration(
                                      'Email address',
                                      Icons.mail_outline_rounded,
                                      hint: 'you@company.com',
                                    ),
                                    validator: (v) =>
                                        v != null &&
                                            RegExp(
                                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                            ).hasMatch(v.trim())
                                        ? null
                                        : 'Enter your work email',
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  onChanged: (_) {
                                    if (change) setState(() {});
                                  },
                                  autofillHints: [
                                    change
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  decoration: _decoration(
                                    change ? 'New password' : 'Password',
                                    Icons.lock_outline_rounded,
                                    suffix: IconButton(
                                      tooltip: _obscure
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 21,
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
                                      return 'Use 12+ characters, upper/lowercase, a number\nand symbol (maximum 72 UTF-8 bytes).';
                                    }
                                    return null;
                                  },
                                ),
                                if (change) ...[
                                  const SizedBox(height: 16),
                                  _strengthIndicator(),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Use at least 12 characters, including uppercase, lowercase, a number and a symbol. Maximum 72 UTF-8 bytes.',
                                    style: TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 10,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _confirmation,
                                    obscureText: _obscureConfirmation,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    decoration: _decoration(
                                      'Confirm password',
                                      Icons.lock_outline_rounded,
                                      suffix: IconButton(
                                        tooltip: _obscureConfirmation
                                            ? 'Show confirmation'
                                            : 'Hide confirmation',
                                        onPressed: () => setState(
                                          () => _obscureConfirmation =
                                              !_obscureConfirmation,
                                        ),
                                        icon: Icon(
                                          _obscureConfirmation
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 21,
                                        ),
                                      ),
                                    ),
                                    validator: (v) => v == _password.text
                                        ? null
                                        : 'Passwords do not match',
                                  ),
                                ] else ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 32,
                                            height: 40,
                                            child: Checkbox(
                                              value: _remember,
                                              onChanged: busy
                                                  ? null
                                                  : (value) => setState(
                                                      () => _remember = value!,
                                                    ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'Remember me',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      TextButton(
                                        onPressed: () => _help(
                                          'Forgot password?',
                                          'Contact your company administrator to reset your password. After the reset, sign in with the temporary password and choose your own personal password.',
                                        ),
                                        child: const Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                              if (auth.errorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    auth.errorMessage!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (auth.otpMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 12,
                                  ),
                                  child: Text(
                                    auth.otpMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppTheme.teal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (!change) ...[
                                const SizedBox(height: 10),
                                GradientButton(
                                  label: verify ? 'Verify code' : 'Sign in',
                                  busy: busy,
                                  onPressed: busy
                                      ? null
                                      : () => _submit(auth, verify, change),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (change) ...[
                          const SizedBox(height: 18),
                          GradientButton(
                            label: 'Save new password',
                            busy: busy,
                            onPressed: busy
                                ? null
                                : () => _submit(auth, verify, change),
                          ),
                        ],
                        const SizedBox(height: 22),
                        if (verify || change)
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _backToSignIn(auth),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 20,
                              ),
                              label: const Text(
                                'Back to sign in',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        if (!verify && !change) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Flexible(
                                child: Text(
                                  'Need a workspace account?',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _help(
                                  'Request access',
                                  'Your company administrator or department manager can create your account. Ask them to register your work email so you can complete verification and personal password setup.',
                                ),
                                child: const Text(
                                  'Request access',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: AppTheme.muted,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Your workspace. Securely connected.',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _backToSignIn(AuthProvider auth) {
    _timer?.cancel();
    _timer = null;
    _resendSeconds = 0;
    _code.clear();
    _password.clear();
    _confirmation.clear();
    auth.cancelEmailVerification();
  }

  Future<void> _submit(AuthProvider auth, bool verify, bool change) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (change) {
      if (await auth.changeInitialPassword(_password.text)) {
        _password.clear();
        _confirmation.clear();
      }
    } else if (verify) {
      if (await auth.verifyEmailOtp(_code.text)) {
        _password.clear();
        _code.clear();
      }
    } else {
      await auth.login(
        email: _email.text,
        password: _password.text,
        rememberMe: _remember,
      );
    }
  }

  Widget _hero({required bool verify, required bool change}) => LayoutBuilder(
    builder: (context, c) {
      final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change
                ? 'CREATE A NEW PASSWORD'
                : verify
                ? 'SECURE ACCOUNT ACCESS'
                : 'LET’S MAKE THINGS HAPPEN',
            style: const TextStyle(
              color: AppTheme.teal,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            change
                ? 'Reset password'
                : verify
                ? 'Verify OTP'
                : 'Welcome back.',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontSize: c.maxWidth < 350 ? 28 : 32, height: 1.18),
          ),
          const SizedBox(height: 12),
          Text(
            change
                ? 'Choose a strong new password to secure your account.'
                : verify
                ? 'Enter the 6-digit code sent to your email to continue.'
                : 'Sign in to your account and keep your team moving forward.',
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            words,
            const Align(
              alignment: Alignment.centerRight,
              child: BrandIllustration('security', size: 160),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 6, child: words),
            Expanded(
              flex: 4,
              child: Transform.translate(
                offset: const Offset(14, 8),
                child: const BrandIllustration('security', size: 180),
              ),
            ),
          ],
        ),
      );
    },
  );
  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? hint,
    Widget? suffix,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
    prefixIcon: Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF1EAFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.teal, size: 23),
      ),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 62, minHeight: 64),
    suffixIcon: suffix,
  );
  Widget _strengthIndicator() {
    final strength = _strength;
    final color = strength == 4
        ? const Color(0xFF4CAF70)
        : strength >= 2
        ? const Color(0xFFE6AF38)
        : AppTheme.muted;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 24,
                height: 5,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: i < strength ? color : AppTheme.line,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
          ],
        ),
        Text(
          'Password strength: ${_password.text.isEmpty
              ? 'Not entered'
              : strength == 4
              ? 'Strong'
              : strength >= 2
              ? 'Fair'
              : 'Weak'}',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _otpInput(bool busy) => FormField<String>(
    validator: (_) => RegExp(r'^\d{6}$').hasMatch(_code.text)
        ? null
        : 'Enter the 6-digit code',
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 58,
          child: Stack(
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 6; i++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: i == 5 ? 0 : 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F4FF),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: i == _code.text.length
                                  ? AppTheme.teal.withValues(alpha: .5)
                                  : AppTheme.line,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            i < _code.text.length ? _code.text[i] : '',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: TextField(
                  key: const ValueKey('otp-input'),
                  controller: _code,
                  readOnly: busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(color: Colors.transparent),
                  showCursor: false,
                  enableInteractiveSelection: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '6-digit verification code',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: TextStyle(color: Colors.transparent),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (value) {
                    field.didChange(value);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        if (field.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              field.errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ),
  );
}
