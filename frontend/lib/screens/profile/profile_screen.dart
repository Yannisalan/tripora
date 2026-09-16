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

  static const Color _midnight = Color(0xFF1E1B4B);
  static const Color _blue = Color(0xFF3B82F6);

  static const Color _canvas = Color(0xFFF8FAFC);
  static const Color _white = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF191C1E);
  static const Color _textSecondary = Color(0xFF475569);
  static const Color _textMuted = Color(0xFF64748B);

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

      // Only seed language/currency from the backend when the local
      // preferences have NOT yet been loaded from storage.  This
      // prevents backend values from clobbering locally-chosen prefs
      // when the sync to the server previously failed (e.g. Render
      // cold start).
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
        _successMessage = 'Your account was updated successfully.';
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

  /// Background fire-and-forget sync of the current language/currency to the
  /// server. A failed sync surfaces the backend's real error message briefly
  /// so the user can fix it (e.g. unsupported currency) but never blocks the
  /// local instant-apply.
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
    // End the native Google session (best-effort) so the account picker shows
    // again on the next sign-in, even though Tripora's own token is cleared.
    await SocialAuthService.instance.signOutGoogle();

    await _authService.logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Delete your account?',
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          content: const Text(
            'This permanently deletes your account, trips, and data. '
            'This action cannot be undone.',
            style: TextStyle(
              fontFamily: 'Manrope',
              height: 1.5,
              color: _textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor:
                    Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
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
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Text(
          context.tr('profile.myAccount'),
          style: const TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _midnight,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            tooltip: 'Log out',
            icon: const Icon(
              Icons.logout_outlined,
              color: _midnight,
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
                              eyebrow: context.tr('profile.accountEyebrow'),
                              title: context.tr('profile.personalDetails'),
                            ),
                            const SizedBox(height: 14),

                            _buildField(
                              controller: _nameController,
                              label: 'Full name',
                              hint: 'Enter your full name',
                              icon: Icons.person_outline,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Please enter your name.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            _buildField(
                              controller: _emailController,
                              label: 'Email address',
                              hint: 'you@example.com',
                              icon: Icons.email_outlined,
                              keyboardType:
                                  TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                final email = (value ?? '').trim();

                                if (email.isEmpty) {
                                  return 'Please enter your email.';
                                }

                                if (!email.contains('@')) {
                                  return 'Please enter a valid email address.';
                                }

                                return null;
                              },
                            ),

                            const SizedBox(height: 32),

                            _buildSectionLabel(
                              eyebrow:
                                  context.tr('profile.travelSettingsEyebrow'),
                              title: context.tr('profile.preferences'),
                            ),
                            const SizedBox(height: 14),

                            _buildAppearanceToggle(),

                            const SizedBox(height: 14),

                            _buildDropdown<String>(
                              value: AppPreferences.instance.language,
                              label: context.tr('profile.preferredLanguage'),
                              icon: Icons.language_outlined,
                              items: const [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                                DropdownMenuItem(
                                  value: 'es',
                                  child: Text('Spanish'),
                                ),
                                DropdownMenuItem(
                                  value: 'fr',
                                  child: Text('French'),
                                ),
                                DropdownMenuItem(
                                  value: 'de',
                                  child: Text('German'),
                                ),
                                DropdownMenuItem(
                                  value: 'it',
                                  child: Text('Italian'),
                                ),
                                DropdownMenuItem(
                                  value: 'pt',
                                  child: Text('Portuguese'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  AppPreferences.instance.setLanguage(value);
                                  _syncPreferences();
                                }
                              },
                            ),

                            const SizedBox(height: 14),

                            _buildDropdown<String>(
                              value: AppPreferences.instance.currency,
                              label: context.tr('profile.preferredCurrency'),
                              icon: Icons.payments_outlined,
                              items: const [
                                DropdownMenuItem(
                                  value: 'USD',
                                  child: Text('USD — US Dollar'),
                                ),
                                DropdownMenuItem(
                                  value: 'EUR',
                                  child: Text('EUR — Euro'),
                                ),
                                DropdownMenuItem(
                                  value: 'GBP',
                                  child: Text('GBP — British Pound'),
                                ),
                                DropdownMenuItem(
                                  value: 'CAD',
                                  child: Text('CAD — Canadian Dollar'),
                                ),
                                DropdownMenuItem(
                                  value: 'AUD',
                                  child: Text('AUD — Australian Dollar'),
                                ),
                                DropdownMenuItem(
                                  value: 'AED',
                                  child: Text('AED — UAE Dirham'),
                                ),
                                DropdownMenuItem(
                                  value: 'JPY',
                                  child: Text('JPY — Japanese Yen'),
                                ),
                                DropdownMenuItem(
                                  value: 'CHF',
                                  child: Text('CHF — Swiss Franc'),
                                ),
                                DropdownMenuItem(
                                  value: 'INR',
                                  child: Text('INR — Indian Rupee'),
                                ),
                                DropdownMenuItem(
                                  value: 'CFA',
                                  child: Text('CFA — West African Franc'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  AppPreferences.instance.setCurrency(value);
                                  _syncPreferences();
                                }
                              },
                            ),

                            const SizedBox(height: 32),

                            _buildSectionLabel(
                              eyebrow: 'ACCOUNT SECURITY',
                              title: 'Password',
                            ),
                            const SizedBox(height: 14),

                            _buildPasswordToggle(),

                            if (_showPasswordFields) ...[
                              const SizedBox(height: 16),
                              _buildField(
                                controller:
                                    _currentPasswordController,
                                label: 'Current password',
                                hint: 'Enter your current password',
                                icon: Icons.lock_outline,
                                obscureText: true,
                              ),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _newPasswordController,
                                label: 'New password',
                                hint: 'At least 6 characters',
                                icon: Icons.lock_reset_outlined,
                                obscureText: true,
                                validator: (value) {
                                  if (_showPasswordFields &&
                                      (value ?? '').trim().isNotEmpty &&
                                      (value ?? '').trim().length < 6) {
                                    return 'Password must be at least 6 characters.';
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              _buildField(
                                controller:
                                    _confirmPasswordController,
                                label: 'Confirm new password',
                                hint: 'Re-enter your new password',
                                icon: Icons.verified_user_outlined,
                                obscureText: true,
                                validator: (value) {
                                  if (_showPasswordFields &&
                                      _newPasswordController.text
                                          .trim()
                                          .isNotEmpty &&
                                      (value ?? '').trim() !=
                                          _newPasswordController.text
                                              .trim()) {
                                    return 'Passwords do not match.';
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
  }

  Widget _buildProfileHeader() {
    final displayName = _nameController.text.trim().isEmpty
        ? 'Your profile'
        : _nameController.text.trim();

    final email = _emailController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
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
                  color: _midnight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRAVELER PROFILE',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Noto Serif',
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: _midnight,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: _textMuted,
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
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_outlined,
                      size: 16,
                      color: _midnight,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Tripora traveler',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _midnight,
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
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: _blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Noto Serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _midnight,
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: _textMuted,
          size: 21,
        ),
        filled: true,
        fillColor: _white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: _midnight,
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
    // Key the form field by its selected value so the internal
    // FormFieldState is recreated whenever the underlying preference
    // changes externally. Without this, `initialValue` only applies on
    // first build and the dropdown keeps showing a stale selection.
    return DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: _textMuted,
          size: 21,
        ),
        filled: true,
        fillColor: _white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(
            color: _midnight,
            width: 1.3,
          ),
        ),
      ),
      dropdownColor: _white,
    );
  }

  /// Appearance control (Light / System / Dark) — persisted through
  /// [AppPreferences] and applied app-wide via MaterialApp.themeMode.
  Widget _buildAppearanceToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
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
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dark_mode_outlined,
                  size: 20,
                  color: _midnight,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Choose light, dark, or system theme.',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: _textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<ThemeMode>(
            key: ValueKey('appearance-${AppPreferences.instance.themeMode}'),
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {AppPreferences.instance.themeMode},
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
              AppPreferences.instance.setThemeMode(selection.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_outline,
              size: 20,
              color: _midnight,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change password',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Update your password securely.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _showPasswordFields,
            activeTrackColor: _midnight,
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
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveProfile,
        style: FilledButton.styleFrom(
          backgroundColor: _midnight,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _midnight.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        icon: _isSaving
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.check_rounded,
                size: 19,
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
    final errorColor = Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
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
              const Text(
                'DANGER ZONE',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Delete account',
            style: TextStyle(
              fontFamily: 'Noto Serif',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Permanently remove your account, saved trips, and associated data.',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              height: 1.45,
              color: _textMuted,
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
                  ? 'Deleting...'
                  : 'Delete my account',
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
