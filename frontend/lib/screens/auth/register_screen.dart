import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/social_sign_in_section.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  String? _statusMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // REGISTER
  // ============================================================

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms || !_acceptedPrivacy) {
      setState(() {
        _statusMessage =
            'Please accept the Terms & Conditions and Privacy Policy to continue.';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Please accept the Terms & Conditions and Privacy Policy.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final response = await _authService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              response['message']?.toString() ?? 'Account created.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppStatusColors>()?.success ??
                    AppColors.success,
          ),
        );

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;

      String message = error.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }

      setState(() {
        _isLoading = false;
        _statusMessage = message;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppStatusColors>()?.error ??
                    AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.triporaColors.backgroundColor,

      // ============================================================
      // APP BAR
      // ============================================================

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Create Account',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.triporaColors.textPrimary,
          ),
        ),
      ),

      // ============================================================
      // BODY
      // ============================================================

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),

            child: Form(
              key: _formKey,

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  // ==================================================
                  // BRAND LOGO
                  // ==================================================

                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
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
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/logo_new.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                gradient: AppColors.brandGradient,
                              ),
                              child: const Icon(
                                Icons.explore,
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
                    'Create your Tripora account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.triporaColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Join Tripora and start planning your next adventure.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.triporaColors.textMuted,
                    ),
                  ),

                  // ==================================================
                  // SOCIAL SIGN-IN
                  // ==================================================
                  //
                  // Google and Apple remain implemented for Android/iOS,
                  // but are hidden on Flutter Web.
                  // ==================================================

                  if (!kIsWeb) ...[
                    const SizedBox(height: 32),

                    SocialSignInSection(
                      onSuccess: () {
                        if (!mounted) return;

                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.home,
                          (route) => false,
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    const _FieldsDivider(),

                    const SizedBox(height: 24),
                  ] else ...[
                    const SizedBox(height: 32),
                  ],

                  // ==================================================
                  // NAME
                  // ==================================================

                  TextFormField(
                    controller: _nameController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Enter your name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Please enter your name.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ==================================================
                  // EMAIL
                  // ==================================================

                  TextFormField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final email = (value ?? '').trim();

                      if (email.isEmpty) {
                        return 'Please enter your email.';
                      }

                      if (!email.contains('@')) {
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
                    enabled: !_isLoading,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock_outline),

                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
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
                      if ((value ?? '').length < 6) {
                        return 'Password must be at least 6 characters.';
                      }

                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!_isLoading) {
                        _register();
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // ==================================================
                  // TERMS & CONDITIONS
                  // ==================================================

                  _ConsentRow(
                    leading: 'I agree to the',
                    label: 'Terms & Conditions',
                    route: AppRoutes.terms,
                    value: _acceptedTerms,
                    onChanged: _isLoading
                        ? null
                        : (value) {
                            setState(() {
                              _acceptedTerms = value;
                            });
                          },
                  ),

                  // ==================================================
                  // PRIVACY POLICY
                  // ==================================================

                  _ConsentRow(
                    leading: 'I have read the',
                    label: 'Privacy Policy',
                    route: AppRoutes.privacy,
                    value: _acceptedPrivacy,
                    onChanged: _isLoading
                        ? null
                        : (value) {
                            setState(() {
                              _acceptedPrivacy = value;
                            });
                          },
                  ),

                  const SizedBox(height: 8),

                  // ==================================================
                  // CREATE ACCOUNT BUTTON
                  // ==================================================

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: GradientButton(
                      onPressed: _isLoading ? null : _register,
                      height: 52,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Create Account',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  // ==================================================
                  // STATUS MESSAGE
                  // ==================================================

                  if (_statusMessage != null) ...[
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ==================================================
                  // LOGIN LINK
                  // ==================================================

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? '),

                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/login',
                                  (route) => false,
                                );
                              },
                        child: const Text('Sign in'),
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

// ============================================================
// EMAIL DIVIDER
// ============================================================

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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or with email',
            style: TextStyle(
              color: context.triporaColors.textMuted,
              fontWeight: FontWeight.w500,
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

// ============================================================
// CONSENT ROW
// ============================================================

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.leading,
    required this.label,
    required this.route,
    required this.value,
    required this.onChanged,
  });

  final String leading;
  final String label;
  final String route;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return InkWell(
      onTap: onChanged == null
          ? null
          : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),

      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),

        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (_) => onChanged!(!value),
                visualDensity: VisualDensity.compact,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: '$leading ',
                    ),

                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pushNamed(route);
                        },
                        child: Text(
                          label,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),

                    const TextSpan(
                      text: '.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
