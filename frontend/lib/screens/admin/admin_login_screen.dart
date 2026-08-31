import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/admin_service.dart';
import '../../widgets/gradient_button.dart';

/// Signed-out entry point for the admin dashboard: collects the admin token,
/// validates it against the backend, and (on success) stores it and moves to
/// the dashboard.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final AdminService _adminService = AdminService();
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  bool _isChecking = false;
  bool _obscureToken = true;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    final token = _tokenController.text.trim();

    try {
      final valid = await _adminService.checkToken(token: token);

      if (!mounted) return;

      if (!valid) {
        setState(() {
          _isChecking = false;
          _errorMessage = 'That admin token was rejected by the server.';
        });
        return;
      }

      await _adminService.saveToken(token);

      if (!mounted) return;

      // AdminDashboardRoute owns its own history; push it as a root and clear
      // the login screen from the stack.
      Navigator.of(context).pushReplacementNamed(AppRoutes.adminDashboard);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
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
        title: const Text(
          'Tripora Admin',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Sign in to the dashboard',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the admin access token to view site analytics.',
                    style: TextStyle(color: colors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Admin token',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscureToken = !_obscureToken);
                        },
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Please enter the admin token.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.appStatus.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.appStatus.error.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: colors.appStatus.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: GradientButton(
                      onPressed: _isChecking ? null : _submit,
                      height: 52,
                      icon: _isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_open, color: Colors.white),
                      label: Text(
                        _isChecking ? 'Verifying…' : 'Access dashboard',
                        style: const TextStyle(color: Colors.white),
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
