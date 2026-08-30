import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subscription_model.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/gradient_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final SubscriptionService _subService = SubscriptionService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showPasswordFields = false;
  bool _emailVerified = false;
  String? _errorMessage;
  String? _successMessage;

  SubscriptionModel? _subscription;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String _preferredLanguage = 'en';
  String _preferredCurrency = 'USD';

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
      _emailVerified = (user['emailVerified'] ?? false) == true;
      _preferredLanguage = (user['preferredLanguage'] ?? 'en')
          .toString()
          .trim();
      _preferredCurrency = (user['preferredCurrency'] ?? 'USD')
          .toString()
          .trim();

      setState(() {
        _isLoading = false;
      });

      if (AppConfig.premiumEnabled) {
        _loadSubscriptionStatus();
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      final status = await _subService.getStatus();
      if (!mounted) return;
      setState(() {
        _subscription = status;
      });
    } catch (_) {
      // The profile should still render even if subscription status can't
      // be fetched (e.g. not configured yet).
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
        currentPassword: currentPassword.isEmpty ? null : currentPassword,
        preferredLanguage: _preferredLanguage,
        preferredCurrency: _preferredCurrency,
      );

      final user = response['user'] as Map<String, dynamic>;

      if (!mounted) return;

      _nameController.text = (user['name'] ?? '').toString();
      _emailController.text = (user['email'] ?? '').toString();
      _emailVerified = (user['emailVerified'] ?? false) == true;
      _preferredLanguage = (user['preferredLanguage'] ?? 'en')
          .toString()
          .trim();
      _preferredCurrency = (user['preferredCurrency'] ?? 'USD')
          .toString()
          .trim();
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showPasswordFields = false;

      setState(() {
        _isSaving = false;
        _successMessage = 'Your account was updated successfully.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<void> _logout() async {
    await _authService.logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        actions: [
          IconButton(
            onPressed: _logout,
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFEFF6FF),
                              Color(0xFFF5F3FF),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x332563EB),
                                        blurRadius: 18,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    size: 32,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _nameController.text.isEmpty
                                            ? 'Your profile'
                                            : _nameController.text,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _emailController.text,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (AppConfig.premiumEnabled) ...[
                      _buildPremiumCard(),
                      const SizedBox(height: 20),
                    ],
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    if (_successMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          _successMessage!,
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ),
                    _buildSectionTitle('Personal details'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
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
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildSectionTitle('Email verification'),
                        const SizedBox(width: 10),
                        Chip(
                          label: Text(
                            _emailVerified ? 'Verified' : 'Unverified',
                          ),
                          backgroundColor: _emailVerified
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          avatar: Icon(
                            _emailVerified
                                ? Icons.check_circle
                                : Icons.warning_amber,
                            color: _emailVerified
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_emailVerified)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await _authService
                                  .resendVerification(
                                    email: _emailController.text.trim(),
                                  );
                              if (!mounted) return;
                              setState(() {
                                _successMessage =
                                    result['message']?.toString() ??
                                    'Verification email was resent.';
                              });
                            } catch (error) {
                              if (!mounted) return;
                              setState(() {
                                _errorMessage = error
                                    .toString()
                                    .replaceFirst('Exception: ', '')
                                    .trim();
                              });
                            }
                          },
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Resend verification'),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _buildSectionTitle('Preferences'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _preferredLanguage,
                      decoration: const InputDecoration(
                        labelText: 'Preferred language',
                        prefixIcon: Icon(Icons.language_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'es', child: Text('Spanish')),
                        DropdownMenuItem(value: 'fr', child: Text('French')),
                        DropdownMenuItem(value: 'de', child: Text('German')),
                        DropdownMenuItem(value: 'it', child: Text('Italian')),
                        DropdownMenuItem(
                          value: 'pt',
                          child: Text('Portuguese'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _preferredLanguage = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _preferredCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Preferred currency',
                        prefixIcon: Icon(Icons.attach_money_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('USD - US Dollar'),
                        ),
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text('EUR - Euro'),
                        ),
                        DropdownMenuItem(
                          value: 'GBP',
                          child: Text('GBP - British Pound'),
                        ),
                        DropdownMenuItem(
                          value: 'CAD',
                          child: Text('CAD - Canadian Dollar'),
                        ),
                        DropdownMenuItem(
                          value: 'AUD',
                          child: Text('AUD - Australian Dollar'),
                        ),
                        DropdownMenuItem(
                          value: 'AED',
                          child: Text('AED - UAE Dirham'),
                        ),
                        DropdownMenuItem(
                          value: 'JPY',
                          child: Text('JPY - Japanese Yen'),
                        ),
                        DropdownMenuItem(
                          value: 'CHF',
                          child: Text('CHF - Swiss Franc'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _preferredCurrency = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildSectionTitle('Security'),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _showPasswordFields,
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
                      title: const Text('Change password'),
                      subtitle: const Text('Update your password securely.'),
                    ),
                    if (_showPasswordFields) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Current password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                        validator: (value) {
                          if (_showPasswordFields &&
                              (value ?? '').trim().isNotEmpty &&
                              (value ?? '').trim().length < 6) {
                            return 'Password must be at least 6 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.check_circle_outline),
                        ),
                        validator: (value) {
                          if (_showPasswordFields &&
                              _newPasswordController.text.trim().isNotEmpty &&
                              (value ?? '').trim() !=
                                  _newPasswordController.text.trim()) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: GradientButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        height: 52,
                        icon: _isSaving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Changes',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPremiumCard() {
    final subscription = _subscription;
    final isPremium = subscription?.isPremium ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pushNamed(context, AppRoutes.premium);
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPremium
                      ? Icons.workspace_premium
                      : Icons.lock_open,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPremium
                          ? 'Premium member'
                          : 'Go Premium',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPremium
                          ? 'Unlock flight prices & weather'
                          : 'Flight prices & daily weather — from '
                              '${subscription?.priceLabel ?? '—'}/month',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.15),
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, AppRoutes.travel);
                          },
                          icon: const Icon(Icons.travel_explore, size: 18),
                          label: const Text('Premium Travel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
