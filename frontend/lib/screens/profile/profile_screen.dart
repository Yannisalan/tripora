import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/social_auth_service.dart';
import '../../widgets/shimmer_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showPasswordFields = false;

  String? _errorMessage;
  String? _successMessage;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _authService.getCurrentUser();
      final user = response['user'] as Map<String, dynamic>;

      if (!mounted) return;

      _nameController.text = (user['name'] ?? '').toString();
      _emailController.text = (user['email'] ?? '').toString();

      if (!AppPreferences.instance.loadedFromStorage) {
        final language =
            (user['preferredLanguage'] ?? 'en').toString().trim();
        final currency =
            (user['preferredCurrency'] ?? 'USD').toString().trim();

        await AppPreferences.instance.setLanguage(language);
        await AppPreferences.instance.setCurrency(currency);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final newPassword = _newPasswordController.text.trim();
      final currentPassword = _currentPasswordController.text;

      final response = await _authService.updateCurrentUser(
        name: name,
        email: email,
        password: newPassword.isEmpty ? null : newPassword,
        currentPassword:
            currentPassword.isEmpty ? null : currentPassword,
        preferredLanguage: AppPreferences.instance.language,
        preferredCurrency: AppPreferences.instance.currency,
      );

      final user = response['user'] as Map<String, dynamic>;

      if (!mounted) return;

      _nameController.text = (user['name'] ?? '').toString();
      _emailController.text = (user['email'] ?? '').toString();

      await AppPreferences.instance.setLanguage(
        (user['preferredLanguage'] ?? 'en').toString().trim(),
      );

      await AppPreferences.instance.setCurrency(
        (user['preferredCurrency'] ?? 'USD').toString().trim(),
      );

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      _showPasswordFields = false;

      setState(() {
        _isSaving = false;
        _successMessage = context.tr('profile.updatedSuccess');
      });

      HapticFeedback.mediumImpact();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _syncPreferences() async {
    try {
      await _authService.updateCurrentUser(
        preferredLanguage: AppPreferences.instance.language,
        preferredCurrency: AppPreferences.instance.currency,
      );

      if (!mounted) return;

      setState(() {
        _successMessage = context.tr('profile.prefSynced');
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _logout() async {
    await SocialAuthService.instance.signOutGoogle();
    await _authService.logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final colors = context.triporaColors;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            context.tr('profile.deleteAccountQuestion'),
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          content: Text(
            context.tr('profile.deleteAccountWarning'),
            style: TextStyle(
              fontFamily: 'Manrope',
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                context.tr('common.cancel'),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor:
                    Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                context.tr('common.delete'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.deleteAccount();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        final colors = context.triporaColors;
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          backgroundColor: colors.backgroundColor,
          appBar: AppBar(
            backgroundColor: colors.backgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: 20,
            title: Text(
              context.tr('profile.myAccount'),
              style: TextStyle(
                fontFamily: 'Noto Serif',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: context.headingColor,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _logout,
                tooltip: context.tr('profile.logout'),
                icon: Icon(
                  Icons.logout_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _isLoading
              ? const ProfileScreenShimmer()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;

                    final horizontalPadding = isDesktop
                        ? 40.0
                        : constraints.maxWidth > 600
                            ? 24.0
                            : 16.0;

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        48,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 920,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _buildProfileHeader(),

                                const SizedBox(height: 24),

                                if (_errorMessage != null) ...[
                                  _buildMessageBanner(
                                    message: _errorMessage!,
                                    isError: true,
                                  ),
                                  const SizedBox(height: 20),
                                ],

                                if (_successMessage != null) ...[
                                  _buildMessageBanner(
                                    message: _successMessage!,
                                    isError: false,
                                  ),
                                  const SizedBox(height: 20),
                                ],

                                _buildSectionLabel(
                                  eyebrow: context.tr(
                                    'profile.accountEyebrow',
                                  ),
                                  title: context.tr(
                                    'profile.personalDetails',
                                  ),
                                ),

                                const SizedBox(height: 14),

                                _buildField(
                                  controller: _nameController,
                                  label: context.tr('profile.fullName'),
                                  hint: context.tr(
                                    'profile.fullNameHint',
                                  ),
                                  icon: Icons.person_outline,
                                  textInputAction:
                                      TextInputAction.next,
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return context.tr(
                                        'profile.nameRequired',
                                      );
                                    }

                                    return null;
                                  },
                                ),

                                const SizedBox(height: 14),

                                _buildField(
                                  controller: _emailController,
                                  label: context.tr(
                                    'profile.emailAddress',
                                  ),
                                  hint: context.tr(
                                    'profile.emailHint',
                                  ),
                                  icon: Icons.email_outlined,
                                  keyboardType:
                                      TextInputType.emailAddress,
                                  textInputAction:
                                      TextInputAction.next,
                                  validator: (value) {
                                    final email =
                                        (value ?? '').trim();

                                    if (email.isEmpty) {
                                      return context.tr(
                                        'profile.emailRequired',
                                      );
                                    }

                                    if (!email.contains('@')) {
                                      return context.tr(
                                        'profile.emailInvalid',
                                      );
                                    }

                                    return null;
                                  },
                                ),

                                const SizedBox(height: 32),

                                _buildSectionLabel(
                                  eyebrow: context.tr(
                                    'profile.travelSettingsEyebrow',
                                  ),
                                  title: context.tr(
                                    'profile.preferences',
                                  ),
                                ),

                                const SizedBox(height: 14),

                                _buildAppearanceToggle(),

                                const SizedBox(height: 14),

                                _buildDropdown<String>(
                                  value: AppPreferences.instance.language,
                                  label: context.tr(
                                    'profile.preferredLanguage',
                                  ),
                                  icon: Icons.language_outlined,
                                  items: [
                                    DropdownMenuItem(
                                      value: 'en',
                                      child: Text(
                                        context.tr(
                                          'languages.english',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'es',
                                      child: Text(
                                        context.tr(
                                          'languages.spanish',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'fr',
                                      child: Text(
                                        context.tr(
                                          'languages.french',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'de',
                                      child: Text(
                                        context.tr(
                                          'languages.german',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'it',
                                      child: Text(
                                        context.tr(
                                          'languages.italian',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pt',
                                      child: Text(
                                        context.tr(
                                          'languages.portuguese',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      AppPreferences.instance
                                          .setLanguage(value);

                                      _syncPreferences();
                                    }
                                  },
                                ),

                                const SizedBox(height: 14),

                                _buildDropdown<String>(
                                  value: AppPreferences.instance.currency,
                                  label: context.tr(
                                    'profile.preferredCurrency',
                                  ),
                                  icon: Icons.payments_outlined,
                                  items: [
                                    DropdownMenuItem(
                                      value: 'USD',
                                      child: Text(
                                        context.tr(
                                          'currencies.usd',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'EUR',
                                      child: Text(
                                        context.tr(
                                          'currencies.eur',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'GBP',
                                      child: Text(
                                        context.tr(
                                          'currencies.gbp',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'CAD',
                                      child: Text(
                                        context.tr(
                                          'currencies.cad',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AUD',
                                      child: Text(
                                        context.tr(
                                          'currencies.aud',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AED',
                                      child: Text(
                                        context.tr(
                                          'currencies.aed',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'JPY',
                                      child: Text(
                                        context.tr(
                                          'currencies.jpy',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'CHF',
                                      child: Text(
                                        context.tr(
                                          'currencies.chf',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'INR',
                                      child: Text(
                                        context.tr(
                                          'currencies.inr',
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'CFA',
                                      child: Text(
                                        context.tr(
                                          'currencies.cfa',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      AppPreferences.instance
                                          .setCurrency(value);

                                      _syncPreferences();
                                    }
                                  },
                                ),

                                const SizedBox(height: 32),

                                _buildSectionLabel(
                                  eyebrow: context.tr(
                                    'profile.accountSecurity',
                                  ),
                                  title: context.tr(
                                    'profile.password',
                                  ),
                                ),

                                const SizedBox(height: 14),

                                _buildPasswordToggle(),

                                if (_showPasswordFields) ...[
                                  const SizedBox(height: 16),

                                  _buildField(
                                    controller:
                                        _currentPasswordController,
                                    label: context.tr(
                                      'profile.currentPassword',
                                    ),
                                    hint: context.tr(
                                      'profile.currentPasswordHint',
                                    ),
                                    icon: Icons.lock_outline,
                                    obscureText: true,
                                  ),

                                  const SizedBox(height: 14),

                                  _buildField(
                                    controller:
                                        _newPasswordController,
                                    label: context.tr(
                                      'profile.newPassword',
                                    ),
                                    hint: context.tr(
                                      'profile.newPasswordHint',
                                    ),
                                    icon: Icons.lock_reset_outlined,
                                    obscureText: true,
                                    validator: (value) {
                                      if (_showPasswordFields &&
                                          (value ?? '')
                                              .trim()
                                              .isNotEmpty &&
                                          (value ?? '')
                                              .trim()
                                              .length <
                                              6) {
                                        return context.tr(
                                          'profile.passwordTooShort',
                                        );
                                      }

                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 14),

                                  _buildField(
                                    controller:
                                        _confirmPasswordController,
                                    label: context.tr(
                                      'profile.confirmPassword',
                                    ),
                                    hint: context.tr(
                                      'profile.confirmPasswordHint',
                                    ),
                                    icon:
                                        Icons.verified_user_outlined,
                                    obscureText: true,
                                    validator: (value) {
                                      if (_showPasswordFields &&
                                          _newPasswordController.text
                                              .trim()
                                              .isNotEmpty &&
                                          (value ?? '').trim() !=
                                              _newPasswordController
                                                  .text
                                                  .trim()) {
                                        return context.tr(
                                          'profile.passwordMismatch',
                                        );
                                      }

                                      return null;
                                    },
                                  ),
                                ],

                                const SizedBox(height: 28),

                                _buildSaveButton(),

                                const SizedBox(height: 36),

                                _buildDangerZone(),

                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildProfileHeader() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    final displayName = _nameController.text.trim().isEmpty
        ? context.tr('profile.yourProfile')
        : _nameController.text.trim();

    final email = _emailController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1E1B4B),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;

          final identity = Row(
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 32,
                  color: scheme.onPrimary,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('profile.travelerProfile'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: context.appStatus.info,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Noto Serif',
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: context.headingColor,
                      ),
                    ),

                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return identity;
          }

          return Row(
            children: [
              Expanded(child: identity),

              const SizedBox(width: 24),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      context.tr('profile.triporaTraveler'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageBanner({
    required String message,
    required bool isError,
  }) {
    final color = isError
        ? context.appStatus.error
        : context.appStatus.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : Icons.check_circle_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                height: 1.45,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({
    required String eyebrow,
    required String title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: context.appStatus.info,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: context.headingColor,
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: colors.textMuted,
          size: 21,
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 1.3,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: context.appStatus.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: context.appStatus.error,
            width: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: colors.textMuted,
          size: 21,
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(8),
          ),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 1.3,
          ),
        ),
      ),
      dropdownColor: colors.surface,
    );
  }

  Widget _buildAppearanceToggle() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.dark_mode_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('profile.appearance'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('profile.appearanceDescription'),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          SegmentedButton<ThemeMode>(
            key: ValueKey(
              'appearance-${AppPreferences.instance.themeMode}',
            ),
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(
                  context.tr('profile.light'),
                ),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(
                  Icons.brightness_auto_outlined,
                ),
                label: Text(
                  context.tr('profile.system'),
                ),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(
                  Icons.dark_mode_outlined,
                ),
                label: Text(
                  context.tr('profile.dark'),
                ),
              ),
            ],
            selected: {
              AppPreferences.instance.themeMode,
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            onSelectionChanged: (selection) {
              AppPreferences.instance.setThemeMode(
                selection.first,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordToggle() {
    final colors = context.triporaColors;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.lock_outline,
              size: 20,
              color: scheme.primary,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('profile.changePassword'),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr('profile.changePasswordDescription'),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          Switch.adaptive(
            value: _showPasswordFields,
            activeTrackColor: scheme.primary,
            onChanged: (value) {
              setState(() {
                _showPasswordFields = value;

                if (!value) {
                  _currentPasswordController.clear();
                  _newPasswordController.clear();
                  _confirmPasswordController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveProfile,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(
            alpha: 0.55,
          ),
          disabledForegroundColor: scheme.onPrimary.withValues(
            alpha: 0.7,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        icon: _isSaving
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : Icon(
                Icons.check_rounded,
                size: 19,
                color: scheme.onPrimary,
              ),
        label: Text(
          _isSaving
              ? context.tr('profile.saving')
              : context.tr('profile.saveChanges'),
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    final colors = context.triporaColors;
    final errorColor = Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: errorColor.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 19,
                color: errorColor,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('profile.dangerZone'),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            context.tr('profile.deleteAccount'),
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.headingColor,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            context.tr('profile.deleteAccountDescription'),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              height: 1.45,
              color: colors.textMuted,
            ),
          ),

          const SizedBox(height: 14),

          TextButton.icon(
            onPressed:
                _isDeleting ? null : _confirmDeleteAccount,
            style: TextButton.styleFrom(
              foregroundColor: errorColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: _isDeleting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: errorColor,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline,
                    size: 19,
                  ),
            label: Text(
              _isDeleting
                  ? context.tr('profile.deleting')
                  : context.tr('profile.deleteMyAccount'),
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}