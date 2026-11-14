import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/design/glass/glass_background.dart';
import '../../core/design/glass/glass_surface.dart';
import '../../core/design/glass/glass_tokens.dart';
import '../../core/security/turnstile/turnstile_field.dart';
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

  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _emailController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final TurnstileController _turnstile =
      TurnstileController(action: 'register');

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
    _turnstile.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms || !_acceptedPrivacy) {
      setState(() {
        _statusMessage =
            context.tr('register.acceptTermsMessage');
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.tr('register.acceptTermsSnack'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    if (!_turnstile.readyToSubmit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.tr('turnstile.required')),
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
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final turnstileToken = _turnstile.token;
      final honeypot = _turnstile.honeypotValue;
      // Tokens are single use: whatever happens next, get a fresh one.
      _turnstile.reset();

      await _authService.register(
        name: _nameController.text.trim(),
        email: email,
        password: password,
        turnstileToken: turnstileToken,
        honeypot: honeypot,
      );

      if (!mounted) return;

      // The backend answers the same way for new and already-registered
      // addresses (no account enumeration). Signing in with the password
      // just chosen tells the two apart for the person who owns it.
      Map<String, dynamic>? session;
      try {
        session = await _authService.login(email: email, password: password);
      } catch (_) {
        session = null;
      }

      if (!mounted) return;

      if (session == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr('register.checkEmail')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
        return;
      }

      final user = session['user'];
      if (user is Map && user['emailVerified'] == true) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.verifyEmail,
        (route) => false,
        arguments: email,
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
                Theme.of(context)
                        .extension<AppStatusColors>()
                        ?.error ??
                    AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.triporaColors;

    return GlassBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.tr('register.title'),
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
              maxWidth: 420,
            ),
            child: Form(
              key: _formKey,
              child: GlassSurface(
                padding: const EdgeInsets.all(24),
                borderRadius:
                    BorderRadius.circular(GlassRadius.lg),
                child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // BRAND LOGO
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

                  // TITLE
                  Text(
                    context.tr('register.heading'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    context.tr('register.subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textMuted,
                    ),
                  ),

                  // SOCIAL SIGN-IN
                  // Social buttons are API-gated off (AppConfig.showThirdPartyAuth);
                  // without them the "or with email" divider would have nothing above it.
                  if (!kIsWeb && AppConfig.showThirdPartyAuth) ...[
                    const SizedBox(height: 32),

                    SocialSignInSection(
                      onSuccess: () {
                        if (!mounted) return;

                        Navigator.of(context)
                            .pushNamedAndRemoveUntil(
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

                  // NAME
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isLoading,
                    textInputAction:
                        TextInputAction.next,
                    decoration: InputDecoration(
                      labelText:
                          context.tr('register.name'),
                      hintText:
                          context.tr('register.nameHint'),
                      filled: true,
                      fillColor:
                          colors.surface.withValues(alpha: 0.35),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return context.tr(
                          'register.nameRequired',
                        );
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // EMAIL
                  TextFormField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    keyboardType:
                        TextInputType.emailAddress,
                    textInputAction:
                        TextInputAction.next,
                    decoration: InputDecoration(
                      labelText:
                          context.tr('login.email'),
                      hintText:
                          context.tr('login.emailHint'),
                      filled: true,
                      fillColor:
                          colors.surface.withValues(alpha: 0.35),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                      ),
                    ),
                    validator: (value) {
                      final email =
                          (value ?? '').trim();

                      if (email.isEmpty) {
                        return context.tr(
                          'login.emailRequired',
                        );
                      }

                      if (!email.contains('@')) {
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
                    enabled: !_isLoading,
                    obscureText: _obscurePassword,
                    textInputAction:
                        TextInputAction.done,
                    decoration: InputDecoration(
                      labelText:
                          context.tr('login.password'),
                      hintText:
                          context.tr('login.passwordHint'),
                      filled: true,
                      fillColor:
                          colors.surface.withValues(alpha: 0.35),
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
                      if ((value ?? '').length < 8) {
                        return context.tr(
                          'register.passwordTooShort',
                        );
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

                  // TERMS & CONDITIONS
                  _ConsentRow(
                    leading:
                        context.tr('register.agreeTo'),
                    label:
                        context.tr('register.terms'),
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

                  // PRIVACY POLICY
                  _ConsentRow(
                    leading:
                        context.tr('register.readThe'),
                    label:
                        context.tr(
                      'register.privacyPolicy',
                    ),
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

                  // BOT PROTECTION (Cloudflare Turnstile + web honeypot)
                  TurnstileField(controller: _turnstile),

                  const SizedBox(height: 12),

                  // CREATE ACCOUNT BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: GradientButton(
                      onPressed:
                          _isLoading ? null : _register,
                      height: 52,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              context.tr(
                                'register.title',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  // STATUS MESSAGE
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
                        borderRadius:
                            BorderRadius.circular(14),
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
                          color: Theme.of(context)
                              .colorScheme
                              .primary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // LOGIN LINK
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment:
                        WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.tr(
                          'register.haveAccount',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context)
                                    .pushNamedAndRemoveUntil(
                                  AppRoutes.login,
                                  (route) => false,
                                );
                              },
                        child: Text(
                          context.tr('login.signIn'),
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
        Flexible(
          flex: 3,
          child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          child: Text(
            context.tr('register.orWithEmail'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.triporaColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
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

    // The whole row is the control: one tap target of at least 48 px
    // that carries the checkbox state for assistive technology (the 24 px
    // box alone was below the 48 px minimum).
    return MergeSemantics(
      child: Semantics(
        checked: value,
        enabled: onChanged != null,
        child: InkWell(
      onTap: onChanged == null
          ? null
          : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
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
              child: ExcludeSemantics(
                child: Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (_) => onChanged!(!value),
                visualDensity:
                    VisualDensity.compact,
              ),
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
                          Navigator.of(context)
                              .pushNamed(route);
                        },
                        child: Text(
                          label,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                            fontWeight:
                                FontWeight.w700,
                            decoration:
                                TextDecoration.underline,
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
      ),
        ),
      ),
    );
  }
}
