import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class VerifyEmailPage extends StatefulWidget {
  final String? email;
  final String? token;

  const VerifyEmailPage({
    super.key,
    this.email,
    this.token,
  });

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final TextEditingController _codeController =
      TextEditingController();

  bool _isLoading = false;
  bool _isResending = false;

  String? _errorMessage;
  String? _successMessage;

  int _secondsRemaining = 600;

  Timer? _timer;

  // CHANGE THIS TO YOUR DEPLOYED BACKEND URL
  static const String baseUrl =
      'https://YOUR-BACKEND.onrender.com';

  @override
  void initState() {
    super.initState();

    if (widget.token != null &&
        widget.token!.isNotEmpty) {
      _codeController.text = widget.token!;
    }

    _startCountdown();

    // Automatically verify if a token was supplied
    // through the email link.
    if (widget.token != null &&
        widget.token!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyEmail();
      });
    }
  }

  void _startCountdown() {
    _timer?.cancel();

    setState(() {
      _secondsRemaining = 600;
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_secondsRemaining <= 0) {
          timer.cancel();
          return;
        }

        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      },
    );
  }

  String _formatTime() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _verifyEmail() async {
    final token = _codeController.text.trim();

    if (token.length != 6) {
      setState(() {
        _errorMessage =
            'Please enter the 6-digit verification code.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$baseUrl/api/auth/verify-email',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 &&
          data['success'] == true) {
        setState(() {
          _successMessage =
              'Email verified successfully!';
        });

        _timer?.cancel();

        await Future.delayed(
          const Duration(milliseconds: 800),
        );

        if (!mounted) return;

        // Navigate to your login/home page.
        Navigator.pushReplacementNamed(
          context,
          '/login',
        );
      } else {
        setState(() {
          _errorMessage =
              data['message'] ??
              'Verification failed.';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to connect to Tripora. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (widget.email == null ||
        widget.email!.isEmpty) {
      setState(() {
        _errorMessage =
            'Your email address is missing.';
      });
      return;
    }

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$baseUrl/api/auth/resend-verification',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': widget.email,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 &&
          data['success'] == true) {
        _codeController.clear();

        _startCountdown();

        setState(() {
          _successMessage =
              'A new verification code has been sent.';
        });
      } else {
        setState(() {
          _errorMessage =
              data['message'] ??
              'Failed to resend verification code.';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Unable to connect to Tripora.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 450,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [

                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 70,
                ),

                const SizedBox(height: 24),

                const Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  widget.email != null
                      ? 'We sent a verification code to ${widget.email}.'
                      : 'Enter the verification code sent to your email.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 32),

                TextField(
                  controller: _codeController,
                  keyboardType:
                      TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter
                        .digitsOnly,
                  ],
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText:
                        'Verification code',
                    hintText: '000000',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),

                const SizedBox(height: 16),

                if (_secondsRemaining > 0)
                  Text(
                    'Code expires in ${_formatTime()}',
                    textAlign: TextAlign.center,
                  )
                else
                  const Text(
                    'This code has expired.',
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 20),

                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                    ),
                  ),

                if (_successMessage != null)
                  Text(
                    _successMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.green,
                    ),
                  ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _isLoading
                            ? null
                            : _verifyEmail,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Verify Email',
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                TextButton(
                  onPressed:
                      (_isResending ||
                              _secondsRemaining > 0)
                          ? null
                          : _resendCode,
                  child: _isResending
                      ? const Text(
                          'Sending...',
                        )
                      : Text(
                          _secondsRemaining > 0
                              ? 'Resend code available after expiry'
                              : 'Resend verification code',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}