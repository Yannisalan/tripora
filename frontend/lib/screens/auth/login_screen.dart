import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/utils/logger.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/social_sign_in_section.dart';
import '../planner/planner_screen.dart';

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

  // ============================================================
  // LOGIN
  // ============================================================

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

      _goToPlanner();
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

  // ============================================================
  // NAVIGATE TO PLANNER
  // ============================================================

  void _goToPlanner() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const PlannerScreen(),
      ),
      (route) => false,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          context.triporaColors.backgroundColor,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Sign In',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.triporaColors.textPrimary,
          ),
        ),
      ),

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 400),

            child: Form(
              key: _formKey,

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [
                  // ==================================================
                  // BRAND MARK
                  // ==================================================

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
                            offset:
                                const Offset(0, 10),
                          ),
                        ],
                      ),

                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(22),

                        child: Image.asset(
                          'assets/logo_new.png',
                          fit: BoxFit.cover,

                          errorBuilder:
                              (context, error, stackTrace) {
                            return Container(
                              alignment:
                                  Alignment.center,

                              decoration:
                                  const BoxDecoration(
                                gradient:
                                    AppColors
                                        .brandGradient,
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

                  // ==================================================
                  // TITLE
                  // ==================================================

                  Text(
                    'Welcome back to Tripora',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color:
                          context.triporaColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Sign in to continue planning your trip.',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 15,
                      color:
                          context.triporaColors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ==================================================
                  // SOCIAL SIGN-IN
                  //
                  // Google + Apple remain implemented for
                  // Android/iOS but are hidden on Flutter Web.
                  // ==================================================

                  if (!kIsWeb) ...[
                    SocialSignInSection(
                      onSuccess: () {
                        if (!mounted) return;
                        _goToPlanner();
                      },
                    ),

                    const SizedBox(height: 24),

                    const _FieldsDivider(),

                    const SizedBox(height: 24),
                  ],

                  // ==================================================
                  // EMAIL
                  // ==================================================

                  TextFormField(
                    controller: _emailController,

                    keyboardType:
                        TextInputType.emailAddress,

                    textInputAction:
                        TextInputAction.next,

                    enabled: !_isLoading,

                    decoration:
                        const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email',
                      prefixIcon:
                          Icon(Icons.email_outlined),
                    ),

                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'Please enter your email.';
                      }

                      if (!value.contains('@')) {
                        return 'Please enter a valid email.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ==================================================
                  // PASSWORD
                  // ==================================================

                  TextFormField(
                    controller: _passwordController,

                    obscureText:
                        _obscurePassword,

                    textInputAction:
                        TextInputAction.done,

                    enabled: !_isLoading,

                    onFieldSubmitted: (_) {
                      if (!_isLoading) {
                        _login();
                      }
                    },

                    decoration:
                        InputDecoration(
                      labelText: 'Password',
                      hintText:
                          'Enter your password',

                      prefixIcon:
                          const Icon(
                        Icons.lock_outline,
                      ),

                      suffixIcon:
                          IconButton(
                        tooltip:
                            _obscurePassword
                                ? 'Show password'
                                : 'Hide password',

                        onPressed:
                            _isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _obscurePassword =
                                          !_obscurePassword;
                                    });
                                  },

                        icon: Icon(
                          _obscurePassword
                              ? Icons
                                  .visibility_outlined
                              : Icons
                                  .visibility_off_outlined,
                        ),
                      ),
                    ),

                    validator: (value) {
                      if (value == null ||
                          value.isEmpty) {
                        return 'Please enter your password.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // ==================================================
                  // SIGN IN BUTTON
                  // ==================================================

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

                          : const Text(
                              'Sign In',

                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [
                      const Text(
                        "Don't have an account? ",
                      ),

                      TextButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed(
                                      '/register',
                                    );
                                  },

                        child:
                            const Text('Sign up'),
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

// ================================================================
// SOCIAL FIELDS DIVIDER
// ================================================================

class _FieldsDivider extends StatelessWidget {
  const _FieldsDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(),
        ),

        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 12,
          ),

          child: Text(
            'or with email',

            style: TextStyle(
              color:
                  context.triporaColors.textMuted,
              fontWeight:
                  FontWeight.w500,
            ),
          ),
        ),

        const Expanded(
          child: Divider(),
        ),
      ],
    );
  }
}