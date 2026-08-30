import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/social_auth_service.dart';
import '../core/theme/app_theme.dart';
import 'social_sign_in_button.dart';

/// A "continue with" divider plus Google and Apple sign-in buttons.
///
/// Runs the native provider flow, sends the ID token to the backend and,
/// on success, calls [onSuccess]. Loads one provider at a time and shows
/// errors via [ScaffoldMessenger].
class SocialSignInSection extends StatefulWidget {
  final VoidCallback onSuccess;

  const SocialSignInSection({super.key, required this.onSuccess});

  @override
  State<SocialSignInSection> createState() => _SocialSignInSectionState();
}

class _SocialSignInSectionState extends State<SocialSignInSection> {
  final SocialAuthService _social = SocialAuthService.instance;
  final AuthService _auth = AuthService();

  String? _activeProvider;
  bool get _busy => _activeProvider != null;

  // ============================================================
  // PROVIDER FLOW
  // ============================================================

  Future<void> _handleProvider(String provider) async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _activeProvider = provider;
    });

    try {
      final result = await switch (provider) {
        'google' => _social.signInWithGoogle(),
        'apple' => _social.signInWithApple(),
        _ => throw Exception('Unsupported sign-in provider.'),
      };

      await _auth.socialLogin(
        provider: result.provider,
        idToken: result.idToken,
        nonce: result.nonce,
      );

      if (!mounted) return;

      widget.onSuccess();
    } catch (error) {
      if (!mounted) return;

      var message = error
          .toString()
          .replaceFirst('Exception: ', '')
          .trim();

      if (message.isEmpty) {
        message = 'Sign-in failed. Please try again.';
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context)
                    .extension<AppStatusColors>()
                    ?.error ??
                AppColors.error,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _activeProvider = null;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OrDivider(),
        const SizedBox(height: 16),
        SocialSignInButton(
          label: 'Continue with Google',
          backgroundColor: const Color(0xFFFFFFFF),
          foregroundColor: const Color(0xFF1F2937),
          loading: _activeProvider == 'google',
          onPressed: _busy ? null : () => _handleProvider('google'),
          icon: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Icon(
              Icons.g_mobiledata,
              size: 22,
              color: Color(0xFF4285F4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SocialSignInButton(
          label: 'Continue with Apple',
          backgroundColor: const Color(0xFF000000),
          foregroundColor: const Color(0xFFFFFFFF),
          loading: _activeProvider == 'apple',
          onPressed: _busy ? null : () => _handleProvider('apple'),
          icon: const Icon(
            Icons.apple,
            size: 24,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
