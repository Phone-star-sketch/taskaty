import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' as gfonts;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:taskaty/auth/login.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:taskaty/pages/dashboard.dart'; // Add dashboard import

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController(); // Add this line
  final _secPasswordController =
      TextEditingController(); // New second password controller
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  Uint8List? _imageBytes; // Store image bytes for web compatibility
  String? _imageName; // Store the image name

  // Function to pick an image from the gallery
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      if (kIsWeb) {
        // Handle web platform
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imageName = pickedFile.name;
        });
      } else {
        // Handle mobile platforms
        final file = File(pickedFile.path);
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imageName = path.basename(pickedFile.path);
        });
      }
    }
  }

  // Function to handle user signup and image upload
  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;

      // Sign up the user
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        String? avatarUrl;
        String? fcmToken;

        // Get FCM token
        try {
          fcmToken = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          print('FCM token error: $e');
          fcmToken = null;
        }

        // Upload profile image if selected
        if (_imageBytes != null && _imageName != null) {
          final userId = response.user!.id;
          try {
            final String mimeType =
                _imageName!.endsWith('.png') ? 'image/png' : 'image/jpeg';

            // Create unique filename
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final uniqueFilename = '${userId}_${timestamp}_${_imageName}';

            // Upload image to Supabase Storage
            await supabase.storage.from('profile').uploadBinary(
                  uniqueFilename,
                  _imageBytes!,
                  fileOptions: FileOptions(
                    contentType: mimeType,
                    upsert: true,
                  ),
                );

            // Get the public URL of the uploaded image
            avatarUrl =
                supabase.storage.from('profile').getPublicUrl(uniqueFilename);
          } catch (e) {
            print('Storage error details: $e');
            if (e is StorageException) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('خطأ في رفع الصورة: ${e.message}')),
              );
            }
            // Continue with signup even if image upload fails
            avatarUrl = null;
          }
        }

        // Insert or update the user's profile, including fcm_token
        await supabase.from('profiles').upsert({
          'id': response.user!.id,
          'name': _nameController.text.trim(),
          'full_name': _emailController.text.trim(),
          'avatar_url': avatarUrl,
          'role': 'user', // Add default role
          'fcm_token': fcmToken, // Save FCM token
          'secpass': int.tryParse(_secPasswordController.text.trim()) ??
              0, // Convert to int8
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم انشاء مستخدم بنجاح'),
            ),
          );
          // Do not navigate to another page, remain on signup
        }
      } else {
        throw Exception('حدث خطأ أثناء تسجيل الحساب.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.shade300, Colors.blue.shade300],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Modern back button positioned at top
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Main content
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20), // Add top spacing
                        Text(
                          'إنشاء حساب',
                          style: gfonts.GoogleFonts.poppins(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'انضم إلينا اليوم',
                          style: gfonts.GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            backgroundImage: _imageBytes != null
                                ? MemoryImage(_imageBytes!)
                                : null,
                            child: _imageBytes == null
                                ? Icon(Icons.add_a_photo,
                                    size: 50, color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _nameController,
                          label: 'الاسم',
                          icon: Icons.person,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال الاسم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          label: 'البريد الإلكتروني',
                          icon: Icons.email,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال البريد الإلكتروني';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                .hasMatch(value)) {
                              return 'يرجى إدخال بريد إلكتروني صحيح';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'كلمة المرور',
                          icon: Icons.lock,
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كلمة المرور';
                            }
                            if (value.length < 6) {
                              return 'يجب أن تكون كلمة المرور على الأقل 6 أحرف';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'تأكيد كلمة المرور',
                          icon: Icons.lock,
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى تأكيد كلمة المرور';
                            }
                            if (value != _passwordController.text) {
                              return 'كلمات المرور غير متطابقة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
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
                        _isLoading
                            ? const SpinKitCircle(
                                color: Colors.white, size: 50.0)
                            : ElevatedButton(
                                onPressed: _signup,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.purple.shade700,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 8,
                                  shadowColor: Colors.black26,
                                ),
                                child: Text(
                                  'إنشاء حساب',
                                  style: gfonts.GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 16),

                        const SizedBox(height: 20), // Add bottom spacing
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: gfonts.GoogleFonts.poppins(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
      ),
      validator: validator,
    );
  }
}
