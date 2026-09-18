import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/social_sign_in_section.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      _goToHome();
    } catch (error) {
      appLog('LOGIN ERROR: $error');

      if (!mounted) return;

      String message = error.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context)
                        .extension<AppStatusColors>()
                        ?.error ??
                    AppColors.error,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goToHome() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
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
        title: Text(
          context.tr('login.signIn'),
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
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // BRAND MARK
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/logo_new.png',
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) {
                            return Container(
                              alignment: Alignment.center,
                              decoration:
                                  const BoxDecoration(
                                gradient:
                                    AppColors.brandGradient,
                              ),
                              child: const Icon(
                                Icons.flight_takeoff,
                                color: Colors.white,
                                size: 36,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // TITLE
                  Text(
                    context.tr('login.welcomeBack'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    context.tr('login.subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // SOCIAL SIGN-IN
                  if (!kIsWeb) ...[
                    SocialSignInSection(
                      onSuccess: () {
                        if (!mounted) return;
                        _goToHome();
                      },
                    ),

                    const SizedBox(height: 24),

                    const _FieldsDivider(),

                    const SizedBox(height: 24),
                  ],

                  // EMAIL
                  TextFormField(
                    controller: _emailController,
                    keyboardType:
                        TextInputType.emailAddress,
                    textInputAction:
                        TextInputAction.next,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText:
                          context.tr('login.email'),
                      hintText:
                          context.tr('login.emailHint'),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                      ),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return context.tr(
                          'login.emailRequired',
                        );
                      }

                      if (!value.contains('@')) {
                        return context.tr(
                          'login.emailInvalid',
                        );
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // PASSWORD
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction:
                        TextInputAction.done,
                    enabled: !_isLoading,
                    onFieldSubmitted: (_) {
                      if (!_isLoading) {
                        _login();
                      }
                    },
                    decoration: InputDecoration(
                      labelText:
                          context.tr('login.password'),
                      hintText:
                          context.tr('login.passwordHint'),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                      ),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? context.tr(
                                'login.showPassword',
                              )
                            : context.tr(
                                'login.hidePassword',
                              ),
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
                      if (value == null ||
                          value.isEmpty) {
                        return context.tr(
                          'login.passwordRequired',
                        );
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // FORGOT PASSWORD
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context)
                                  .pushNamed(
                                AppRoutes.forgotPassword,
                              );
                            },
                      child: Text(
                        context.tr(
                          'login.forgotPassword',
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // SIGN IN BUTTON
                  SizedBox(
                    height: 52,
                    child: GradientButton(
                      onPressed:
                          _isLoading ? null : _login,
                      height: 52,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              context.tr(
                                'login.signIn',
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // SIGN UP
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Text(
                        context.tr('login.noAccount'),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context)
                                    .pushNamed(
                                  AppRoutes.register,
                                );
                              },
                        child: Text(
                          context.tr('login.signUp'),
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
    );
  }
}

class _FieldsDivider extends StatelessWidget {
  const _FieldsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider();
  }
}

