import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/login_gate.dart';
import '../../core/design/glass/glass_background.dart';
import '../../core/design/glass/glass_surface.dart';
import '../../core/design/glass/glass_tokens.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/gradient_button.dart';

/// "Verify your email" step shown after registration, after signing in to
/// an unverified account, and whenever the backend answers
/// `403 email_unverified`.
///
/// Verification needs a signed-in session (password + inbox). Whether the
/// address is verified is always decided by the server's response; the app
/// never stores its own "verified" flag.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  /// Address shown in the instructions (display only).
  final String? email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _infoMessage;
  String? _email;

  /// Seconds until "send a new code" is allowed again.
  int _cooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
    _startCooldown(60);
    if (_email == null || _email!.isEmpty) {
      _loadEmail();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    try {
      final decoded = await _authService.getCurrentUser();
      final user = Map<String, dynamic>.from(decoded['user'] as Map);
      if (!mounted) return;
      if (user['emailVerified'] == true) {
        _finish(alreadyVerified: true);
        return;
      }
      setState(() => _email = user['email']?.toString());
    } catch (_) {
      // Not signed in any more: verification needs a session.
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.login,
        (route) => false,
      );
    }
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await _authService.verifyEmail(_codeController.text);
      if (!mounted) return;
      _finish();
    } on EmailVerificationException catch (error) {
      if (!mounted) return;
      if (error.code == 'unauthorized') {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
        return;
      }
      setState(() {
        _isVerifying = false;
        _errorMessage = error.code == 'code_expired'
            ? context.tr('verify.expired')
            : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await _authService.resendVerificationEmail();
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _isResending = false;
        _infoMessage = context.tr('verify.resent');
      });
      _startCooldown(60);
    } on EmailVerificationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorMessage = error.message;
      });
      if (error.retryAfterSeconds != null) {
        _startCooldown(error.retryAfterSeconds!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  void _finish({bool alreadyVerified = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              alreadyVerified ? 'verify.alreadyVerified' : 'verify.success',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              Theme.of(context).extension<AppStatusColors>()?.success ??
                  AppColors.success,
        ),
      );
    // Continue to whatever the user was trying to reach (or Home).
    LoginGate.apply(context);
  }

  Future<void> _useDifferentAccount() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;
    final busy = _isVerifying || _isResending;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text(
            context.tr('verify.title'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: GlassSurface(
                  padding: const EdgeInsets.all(24),
                  borderRadius: BorderRadius.circular(GlassRadius.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('verify.title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                          'verify.subtitle',
                          params: {'email': _email ?? ''},
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: colors.textMuted),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('verifyEmailCode'),
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        enabled: !busy,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onFieldSubmitted: (_) => _verify(),
                        decoration: InputDecoration(
                          labelText: context.tr('verify.codeLabel'),
                          filled: true,
                          fillColor: colors.surface.withValues(alpha: 0.35),
                          prefixIcon: const Icon(Icons.pin_outlined),
                        ),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.length != 6) {
                            return context.tr('verify.codeInvalid');
                          }
                          return null;
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_infoMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _infoMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: GradientButton(
                          onPressed: busy ? null : _verify,
                          height: 52,
                          child: _isVerifying
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(context.tr('verify.submit')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: (busy || _cooldown > 0) ? null : _resend,
                        child: Text(
                          _cooldown > 0
                              ? context.tr(
                                  'verify.resendIn',
                                  params: {'s': '$_cooldown'},
                                )
                              : context.tr('verify.resend'),
                        ),
                      ),
                      Text(
                        context.tr('verify.checkSpam'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: busy ? null : _useDifferentAccount,
                        child: Text(context.tr('verify.useDifferentAccount')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
