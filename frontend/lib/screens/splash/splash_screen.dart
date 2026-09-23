import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Animated launch screen.
///
/// Plays a short logo/name animation while the app starts, then fades
/// itself out and routes the user to the authenticated home shell if a
/// session token is stored, or to the login screen otherwise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Duration _animationDuration = Duration(milliseconds: 700);
  static const Duration _totalDuration = Duration(milliseconds: 1100);
  static const Duration _exitDuration = Duration(milliseconds: 400);

  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;

  // Separate controller so the whole splash content can fade OUT on its
  // own, instead of relying on the next route's transition to cover it.
  late final AnimationController _exitController;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    // Logo: fade in while scaling from 0.9 with a slight overshoot to 1.05,
    // then settling back down to 1.0.
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.9,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_controller);

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    // "Tripora" text fades in during the second half of the animation, once
    // the logo has mostly settled.
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    _exitController = AnimationController(vsync: this, duration: _exitDuration);

    // Fades the entire splash content from fully visible to fully
    // transparent right before navigating away.
    _exitOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    // Wait for the first real frame to be painted before starting the
    // animation/navigation timer. On a cold debug start (especially
    // desktop), engine/shader warm-up can otherwise consume the whole
    // animation before anything is actually visible on screen, so the
    // logo appears to just "pop in" already finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.forward();
      _scheduleNavigation();
    });
  }

  void _scheduleNavigation() {
    Future.delayed(_totalDuration, _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    var isLoggedIn = false;

    try {
      isLoggedIn = await AuthService().isLoggedIn();
    } catch (_) {
      isLoggedIn = false;
    }

    if (!mounted) return;

    // Fade the splash content itself out before swapping screens, so the
    // logo visibly dissolves instead of getting cut off underneath the
    // next route's transition.
    await _exitController.forward();

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacementNamed(isLoggedIn ? AppRoutes.home : AppRoutes.login);
  }

  @override
  void dispose() {
    _controller.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TriporaColors>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor =
        colors?.backgroundColor ??
        (isDark ? const Color(0xFF121212) : Colors.white);

    final textColor =
        colors?.textPrimary ??
        (isDark ? Colors.white : const Color(0xFF191C1E));

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _exitOpacity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _logoOpacity,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Image.asset(
                    'assets/splash/logo_new.png',
                    width: 160,
                    height: 160,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  'Tripora',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
