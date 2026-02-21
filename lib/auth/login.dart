import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:taskaty/auth/signup.dart'; // Assuming this path is correct
import 'package:taskaty/pages/dashboard.dart'; // Assuming this path is correct
import 'package:taskaty/pages/user_Dashboard.dart'; // Fixed import path
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'dart:ui'; // For ImageFilter.blur, if you decide to re-introduce it subtly
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:taskaty/services/notification_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _secPasswordController =
      TextEditingController(); // New second password controller
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController
      _floatingController; // Keeping for potential future use or subtle background elements
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _floatingAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _floatingAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _floatingController,
      curve: Curves.easeInOut,
    ));

    // Check for existing session
    _checkSession();

    // Start animations
    Future.delayed(const Duration(milliseconds: 500), () {
      _slideController.forward();
      _fadeController.forward();
    });
  }

  Future<void> _checkSession() async {
    try {
      final supabase = Supabase.instance.client;
      final Session? session = supabase.auth.currentSession;

      if (session != null && session.user != null) {
        final response = await supabase
            .from('profiles')
            .select('role')
            .eq('id', session.user.id)
            .single();

        if (mounted && response != null) {
          final userRole = response['role'] as String?;

          if (userRole == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UserDashboard()),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Session check error: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _secPasswordController.dispose(); // Dispose new controller
    _slideController.dispose();
    _fadeController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;

      // First authenticate with email and password
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        // Get the user's profile data including secpass
        final userId = supabase.auth.currentUser!.id;
        final response = await supabase
            .from('profiles')
            .select('role, secpass')
            .eq('id', userId)
            .single();

        // Validate second password
        final storedSecpass = response['secpass'] as int?;
        final enteredSecpass =
            int.tryParse(_secPasswordController.text.trim()) ?? 0;

        if (storedSecpass != enteredSecpass) {
          throw Exception('كلمة المرور الثانية غير صحيحة');
        }

        // --- Enhanced FCM token checking and saving ---
        if (!kIsWeb) {
          try {
            // Check if user has FCM token, if not create and save a new one
            await NotificationService.checkAndEnsureFCMToken(userId);
            debugPrint('FCM token checked and ensured for user: $userId');
          } catch (e) {
            debugPrint('Failed to check/ensure FCM token: $e');

            // Additional fallback
            try {
              await NotificationService.getAndSaveFCMToken(userId);
              debugPrint('Fallback FCM token save successful');
            } catch (fallbackError) {
              debugPrint('All FCM token operations failed: $fallbackError');
            }
          }
        }
        // ----------------------------------------

        if (response != null) {
          final userRole = response['role'] as String?;
          _showCustomSnackBar('تم تسجيل الدخول بنجاح!', isSuccess: true);

          // Navigate based on user role
          if (userRole == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UserDashboard()),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar('خطأ: ${e.toString()}', isSuccess: false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCustomSnackBar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
        backgroundColor:
            isSuccess ? Colors.green.shade600 : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive layout
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    // Define a breakpoint for mobile vs. desktop layout
    const double mobileBreakpoint = 600.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < mobileBreakpoint) {
              // Mobile layout: Stack with background image and scrollable form
              return Stack(
                children: [
                  // Background Image
                  Positioned.fill(
                    child: Image.asset(
                      'assets/background_login.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  // Overlay for subtle blur or darkening (optional)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3), // Subtle overlay
                    ),
                  ),
                  // Login Form (scrollable)
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints
                            .maxHeight, // Ensure it takes full height
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 48.0),
                          child: Container(
                            width:
                                screenWidth * 0.9, // Take more width on mobile
                            padding: const EdgeInsets.all(
                                24.0), // Slightly less padding for mobile
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                  0.95), // Slightly transparent white
                              borderRadius: BorderRadius.circular(
                                  16.0), // More rounded corners
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      /// App Logo/Icon
                                      Align(
                                        alignment: Alignment.center,
                                        child: Image.asset(
                                          'assets/icon.png', // Update path if needed
                                          width: 70,
                                          height: 70,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(
                                          height: 24), // Reduced spacing

                                      // Welcome Text
                                      Text(
                                        'أهلاً بك مرة أخرى',
                                        style: GoogleFonts.cairo(
                                          fontSize: 26, // Adjusted font size
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(
                                          height: 6), // Reduced spacing
                                      Text(
                                        'سجل دخولك لمتابعة مهامك',
                                        style: GoogleFonts.cairo(
                                          fontSize: 14, // Adjusted font size
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(
                                          height: 36), // Reduced spacing

                                      // Email Field
                                      _buildModernTextField(
                                        controller: _emailController,
                                        label: 'البريد الإلكتروني',
                                        icon: Icons.email_rounded,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'يرجى إدخال البريد الإلكتروني';
                                          }
                                          if (!RegExp(
                                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                              .hasMatch(value)) {
                                            return 'يرجى إدخال بريد إلكتروني صحيح';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(
                                          height: 16), // Reduced spacing

                                      // Password Field
                                      _buildModernTextField(
                                        controller: _passwordController,
                                        label: 'كلمة المرور',
                                        icon: Icons.lock_rounded,
                                        obscureText: !_isPasswordVisible,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _isPasswordVisible
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                            color: Colors.grey,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _isPasswordVisible =
                                                  !_isPasswordVisible;
                                            });
                                          },
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'يرجى إدخال كلمة المرور';
                                          }
                                          if (value.length < 6) {
                                            return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Second Password Field
                                      _buildModernTextField(
                                        controller: _secPasswordController,
                                        label: 'كلمة المرور الثانية',
                                        icon: Icons.security,
                                        obscureText: true,
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'يرجى إدخال كلمة المرور الثانية';
                                          }
                                          if (int.tryParse(value) == null) {
                                            return 'يجب أن تكون كلمة المرور الثانية رقماً';
                                          }
                                          if (value.length < 4) {
                                            return 'يجب أن تكون كلمة المرور الثانية على الأقل 4 أرقام';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 24),

                                      // Login Button
                                      _isLoading
                                          ? Container(
                                              height:
                                                  50, // Slightly smaller height
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF667eea),
                                                borderRadius: BorderRadius.circular(
                                                    10), // Slightly less rounded
                                              ),
                                              child: const Center(
                                                child: SpinKitThreeBounce(
                                                  color: Colors.white,
                                                  size:
                                                      25, // Slightly smaller spinner
                                                ),
                                              ),
                                            )
                                          : ElevatedButton(
                                              onPressed: _login,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color.fromARGB(
                                                        255, 88, 55, 230),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical:
                                                      16.0, // Adjusted padding
                                                  horizontal: 40.0,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10.0),
                                                ),
                                                elevation:
                                                    4, // Slightly less elevation
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.login_rounded,
                                                    color: Colors.white,
                                                    size:
                                                        22, // Slightly smaller icon
                                                  ),
                                                  const SizedBox(
                                                      width:
                                                          10), // Reduced spacing
                                                  Text(
                                                    'تسجيل الدخول',
                                                    style: GoogleFonts.cairo(
                                                      fontSize:
                                                          18, // Adjusted font size
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                      const SizedBox(
                                          height: 24), // Reduced spacing
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Desktop layout: Row with form on left and image on right
              return Row(
                children: [
                  // Left half: Login form
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(32.0),
                        constraints: BoxConstraints(
                          maxWidth: screenWidth * 0.4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // App Logo/Icon
                                  Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF667eea),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: Image.asset(
                                        'assets/icon.png', // Update path if needed
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),

                                  // Welcome Text
                                  Text(
                                    'أهلاً بك مرة أخرى',
                                    style: GoogleFonts.cairo(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'سجل دخولك لمتابعة مهامك',
                                    style: GoogleFonts.cairo(
                                      fontSize: 15,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 48),

                                  // Email Field
                                  _buildModernTextField(
                                    controller: _emailController,
                                    label: 'البريد الإلكتروني',
                                    icon: Icons.email_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'يرجى إدخال البريد الإلكتروني';
                                      }
                                      if (!RegExp(
                                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                          .hasMatch(value)) {
                                        return 'يرجى إدخال بريد إلكتروني صحيح';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),

                                  // Password Field
                                  _buildModernTextField(
                                    controller: _passwordController,
                                    label: 'كلمة المرور',
                                    icon: Icons.lock_rounded,
                                    obscureText: !_isPasswordVisible,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'يرجى إدخال كلمة المرور';
                                      }
                                      if (value.length < 6) {
                                        return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),

                                  // Second Password Field
                                  _buildModernTextField(
                                    controller: _secPasswordController,
                                    label: 'كلمة المرور الثانية',
                                    icon: Icons.security,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'يرجى إدخال كلمة المرور الثانية';
                                      }
                                      if (int.tryParse(value) == null) {
                                        return 'يجب أن تكون كلمة المرور الثانية رقماً';
                                      }
                                      if (value.length < 4) {
                                        return 'يجب أن تكون كلمة المرور الثانية على الأقل 4 أرقام';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 32),

                                  // Login Button
                                  _isLoading
                                      ? Container(
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF667eea),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Center(
                                            child: SpinKitThreeBounce(
                                              color: Colors.white,
                                              size: 30,
                                            ),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color.fromARGB(
                                                    255, 88, 55, 230),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 20.0,
                                              horizontal: 50.0,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            elevation: 5,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.login_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'تسجيل الدخول',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 20,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Right half: Background image
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: double.infinity,
                      child: Image.asset(
                        'assets/background_login.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black),
        prefixIcon: Icon(
          icon,
          color: Colors.grey,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(
            color: Colors.red.withOpacity(0.6),
            width: 2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(
            color: Colors.red.withOpacity(0.8),
            width: 2,
          ),
        ),
        errorStyle: GoogleFonts.cairo(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }
}

// Here there is a fcm_token didn't saved in the database

Widget _buildModernTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  Widget? suffixIcon,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    textDirection: TextDirection.rtl,
    style: const TextStyle(color: Colors.black),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black),
      prefixIcon: Icon(
        icon,
        color: Colors.grey,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: Colors.blue),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.6),
          width: 2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.8),
          width: 2,
        ),
      ),
      errorStyle: GoogleFonts.cairo(
        color: Colors.red.shade700,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    ),
    validator: validator,
  );
}

// Here there is a fcm_token didn't saved in the database
