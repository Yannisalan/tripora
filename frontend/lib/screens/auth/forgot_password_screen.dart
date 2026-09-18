import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/gradient_button.dart';

/// Account recovery flow: request a one-time code, verify it, set a new
/// password. All three steps live on this single screen so the flow is
/// resilient to a full app restart between steps (only the current step's
/// progress is ephemeral).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _ResetStep { requestCode, verifyCode, newPassword }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  _ResetStep _step = _ResetStep.requestCode;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _resetToken;
  String? _email;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _titleForStep() {
    switch (_step) {
      case _ResetStep.requestCode:
        return context.tr('forgotPassword.resetTitle');

      case _ResetStep.verifyCode:
        return context.tr('forgotPassword.checkEmail');

      case _ResetStep.newPassword:
        return context.tr('forgotPassword.newPasswordTitle');
    }
  }

  Future<void> _requestCode() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.forgotPassword(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _email = _emailController.text.trim();
        _step = _ResetStep.verifyCode;
      });

      _showMessage(
        context.tr('forgotPassword.emailSent'),
      );
    } catch (error) {
      appLog('FORGOT PASSWORD ERROR: $error');

      if (!mounted) return;

      _showMessage(
        _cleanError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final token = await _authService.verifyResetCode(
        email: _email ?? _emailController.text.trim(),
        code: _codeController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _resetToken = token;
        _step = _ResetStep.newPassword;
      });
    } catch (error) {
      appLog('VERIFY RESET CODE ERROR: $error');

      if (!mounted) return;

      _showMessage(
        _cleanError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.resetPassword(
        resetToken: _resetToken ?? '',
        password: _passwordController.text,
      );

      if (!mounted) return;

      _showMessage(
        context.tr('forgotPassword.resetSuccess'),
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.login,
        (route) => false,
      );
    } catch (error) {
      appLog('RESET PASSWORD ERROR: $error');

      if (!mounted) return;

      final message = _cleanError(error);

      // A stale/expired token means the code step must restart.
      if (message.toLowerCase().contains('token')) {
        setState(() {
          _step = _ResetStep.requestCode;
          _resetToken = null;
        });
      }

      _showMessage(
        message,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _cleanError(Object error) {
    var message = error.toString();

    if (message.startsWith('Exception: ')) {
      message = message.substring(11);
    }

    return message;
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Theme.of(context)
                      .extension<AppStatusColors>()
                      ?.error ??
                  AppColors.error
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == _ResetStep.verifyCode) {
              setState(() {
                _step = _ResetStep.requestCode;
              });
            } else if (_step == _ResetStep.newPassword) {
              setState(() {
                _step = _ResetStep.verifyCode;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _titleForStep(),
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
            constraints: const BoxConstraints(
              maxWidth: 400,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.lock_reset,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    _titleForStep(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _subtitleForStep(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 28),

                  _buildStepFields(colors),

                  const SizedBox(height: 24),

                  SizedBox(
                    height: 52,
                    child: GradientButton(
                      onPressed: _isLoading ? null : _submitStep,
                      height: 52,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_submitLabel()),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              AppRoutes.login,
                              (route) => false,
                            );
                          },
                    child: Text(
                      context.tr('forgotPassword.backToSignIn'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleForStep() {
    switch (_step) {
      case _ResetStep.requestCode:
        return context.tr(
          'forgotPassword.requestSubtitle',
        );

      case _ResetStep.verifyCode:
        return context.tr(
          'forgotPassword.verifySubtitle',
        );

      case _ResetStep.newPassword:
        return context.tr(
          'forgotPassword.newPasswordSubtitle',
        );
    }
  }

  String _submitLabel() {
    switch (_step) {
      case _ResetStep.requestCode:
        return context.tr(
          'forgotPassword.sendResetCode',
        );

      case _ResetStep.verifyCode:
        return context.tr(
          'forgotPassword.verifyCode',
        );

      case _ResetStep.newPassword:
        return context.tr(
          'forgotPassword.resetPassword',
        );
    }
  }

  void _submitStep() {
    switch (_step) {
      case _ResetStep.requestCode:
        _requestCode();

      case _ResetStep.verifyCode:
        _verifyCode();

      case _ResetStep.newPassword:
        _resetPassword();
    }
  }

  Widget _buildStepFields(TriporaColors colors) {
    switch (_step) {
      case _ResetStep.requestCode:
        return TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _submitStep(),
          decoration: InputDecoration(
            labelText: context.tr('login.email'),
            hintText: context.tr('login.emailHint'),
            prefixIcon: const Icon(
              Icons.email_outlined,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return context.tr('login.emailRequired');
            }

            if (!value.contains('@')) {
              return context.tr('login.emailInvalid');
            }

            return null;
          },
        );

      case _ResetStep.verifyCode:
        return TextFormField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          maxLength: 6,
          onFieldSubmitted: (_) => _submitStep(),
          decoration: InputDecoration(
            labelText: context.tr(
              'forgotPassword.codeLabel',
            ),
            hintText: context.tr(
              'forgotPassword.codeHint',
            ),
            prefixIcon: const Icon(
              Icons.pin_outlined,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().length != 6) {
              return context.tr(
                'forgotPassword.codeRequired',
              );
            }

            return null;
          },
        );

      case _ResetStep.newPassword:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: context.tr(
                  'forgotPassword.newPassword',
                ),
                hintText: context.tr(
                  'forgotPassword.newPasswordHint',
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline,
                ),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? context.tr('login.showPassword')
                      : context.tr('login.hidePassword'),
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _obscurePassword =
                                !_obscurePassword;
                          });
                        },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.tr(
                    'forgotPassword.passwordRequired',
                  );
                }

                if (value.length < 8) {
                  return context.tr(
                    'forgotPassword.passwordTooShort',
                  );
                }

                return null;
              },
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _confirmController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              enabled: !_isLoading,
              onFieldSubmitted: (_) => _submitStep(),
              decoration: InputDecoration(
                labelText: context.tr(
                  'forgotPassword.confirmPassword',
                ),
                hintText: context.tr(
                  'forgotPassword.confirmPasswordHint',
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.tr(
                    'forgotPassword.confirmRequired',
                  );
                }

                if (value != _passwordController.text) {
                  return context.tr(
                    'forgotPassword.passwordMismatch',
                  );
                }

                return null;
              },
            ),
          ],
        );
    }
  }
}
