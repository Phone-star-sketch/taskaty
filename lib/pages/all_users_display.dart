import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class AllUsersDisplayPage extends StatefulWidget {
  const AllUsersDisplayPage({super.key});

  @override
  State<AllUsersDisplayPage> createState() => _AllUsersDisplayPageState();
}

class _AllUsersDisplayPageState extends State<AllUsersDisplayPage> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('profiles')
          .select('id, full_name, name, avatar_url, created_at, secpass, role')
          .order('created_at', ascending: false);

      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _filteredUsers = _users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('خطأ في تحميل المستخدمين: ${e.toString()}', isError: true);
    }
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          final fullName = (user['full_name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              fullName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _showEditDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['name'] ?? '');
    final secpassController =
        TextEditingController(text: user['secpass']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade50, Colors.purple.shade50],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تعديل بيانات المستخدم',
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              _buildEditTextField(
                controller: nameController,
                label: 'الاسم',
                icon: Icons.person,
              ),
              const SizedBox(height: 16),
              _buildEditTextField(
                controller: secpassController,
                label: 'كلمة المرور الثانية',
                icon: Icons.security,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'إلغاء',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateUser(
                        user['id'],
                        nameController.text,
                        secpassController.text,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'حفظ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.black54),
        prefixIcon: Icon(icon, color: Colors.blue.shade600),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Future<void> _updateUser(String userId, String name, String secpass) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.from('profiles').update({
        'name': name,
        'secpass': int.tryParse(secpass) ?? 0,
      }).eq('id', userId);

      Navigator.pop(context);
      _showSnackBar('تم تحديث بيانات المستخدم بنجاح');
      _loadUsers();
    } catch (e) {
      _showSnackBar('خطأ في تحديث البيانات: ${e.toString()}', isError: true);
    }
  }

  Future<void> _deleteUser(String userId, int index) async {
    try {
      final supabase = Supabase.instance.client;

      // Delete from database
      await supabase.from('profiles').delete().eq('id', userId);

      // Remove from UI immediately
      setState(() {
        _users.removeWhere((user) => user['id'] == userId);
        _filteredUsers.removeWhere((user) => user['id'] == userId);
      });

      _showSnackBar('تم حذف المستخدم بنجاح');
    } catch (e) {
      _showSnackBar('خطأ في حذف المستخدم: ${e.toString()}', isError: true);
    }
  }

  void _showDeleteConfirmDialog(Map<String, dynamic> user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'تأكيد الحذف',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade700,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'هل أنت متأكد من حذف المستخدم "${user['name'] ?? 'بدون اسم'}"؟\nلا يمكن التراجع عن هذا الإجراء.',
          style: GoogleFonts.cairo(
            fontSize: 14,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(user['id'], index);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'حذف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(color: Colors.white),
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _updateUserImage(String userId, String imagePath) async {
    try {
      final supabase = Supabase.instance.client;
      final file = File(imagePath);
      final fileName =
          'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Upload image to Supabase storage
      final uploadResponse =
          await supabase.storage.from('profile').upload(fileName, file);

      // Get public URL
      final imageUrl = supabase.storage.from('profile').getPublicUrl(fileName);

      // Update user profile with new image URL
      await supabase.from('profiles').update({
        'avatar_url': imageUrl,
      }).eq('id', userId);

      // Update UI immediately
      setState(() {
        final userIndex = _users.indexWhere((user) => user['id'] == userId);
        if (userIndex != -1) {
          _users[userIndex]['avatar_url'] = imageUrl;
        }
        final filteredUserIndex =
            _filteredUsers.indexWhere((user) => user['id'] == userId);
        if (filteredUserIndex != -1) {
          _filteredUsers[filteredUserIndex]['avatar_url'] = imageUrl;
        }
      });

      _showSnackBar('تم تحديث الصورة بنجاح');
    } catch (e) {
      _showSnackBar('خطأ في تحديث الصورة: ${e.toString()}', isError: true);
    }
  }

  void _showImagePickerDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'تغيير صورة المستخدم',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current Avatar Preview
            Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.purple.shade400],
                ),
              ),
              child: user['avatar_url'] != null
                  ? ClipOval(
                      child: Image.network(
                        user['avatar_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildDefaultAvatar(user['name']),
                      ),
                    )
                  : _buildDefaultAvatar(user['name']),
            ),

            // Image Source Options
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera, user),
                    icon: Icon(Icons.camera_alt, color: Colors.white),
                    label: Text(
                      'كاميرا',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery, user),
                    icon: Icon(Icons.photo_library, color: Colors.white),
                    label: Text(
                      'المعرض',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (user['avatar_url'] != null)
            TextButton(
              onPressed: () => _removeUserImage(user),
              child: Text(
                'حذف الصورة',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, Map<String, dynamic> user) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        Navigator.pop(context); // Close dialog
        await _updateUserImage(user['id'], image.path);
      }
    } catch (e) {
      _showSnackBar('خطأ في اختيار الصورة: ${e.toString()}', isError: true);
    }
  }

  Future<void> _removeUserImage(Map<String, dynamic> user) async {
    try {
      final supabase = Supabase.instance.client;

      // Update user profile to remove image URL
      await supabase.from('profiles').update({
        'avatar_url': null,
      }).eq('id', user['id']);

      // Update UI immediately
      setState(() {
        final userIndex = _users.indexWhere((u) => u['id'] == user['id']);
        if (userIndex != -1) {
          _users[userIndex]['avatar_url'] = null;
        }
        final filteredUserIndex =
            _filteredUsers.indexWhere((u) => u['id'] == user['id']);
        if (filteredUserIndex != -1) {
          _filteredUsers[filteredUserIndex]['avatar_url'] = null;
        }
      });

      Navigator.pop(context);
      _showSnackBar('تم حذف الصورة بنجاح');
    } catch (e) {
      _showSnackBar('خطأ في حذف الصورة: ${e.toString()}', isError: true);
    }
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final createdAt = DateTime.parse(user['created_at']);
    final formattedDate =
        '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    final userIndex = _filteredUsers.indexOf(user);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar with Edit Option
                GestureDetector(
                  onTap: () => _showImagePickerDialog(user),
                  child: Stack(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.purple.shade400
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: user['avatar_url'] != null
                            ? ClipOval(
                                child: Image.network(
                                  user['avatar_url'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildDefaultAvatar(user['name']),
                                ),
                              )
                            : _buildDefaultAvatar(user['name']),
                      ),
                      // Edit Icon Overlay
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['name'] ?? 'بدون اسم',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['full_name'] ?? 'بدون بريد إلكتروني',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: user['role'] == 'admin'
                              ? Colors.orange.shade100
                              : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user['role'] == 'admin' ? 'مدير' : 'مستخدم',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: user['role'] == 'admin'
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action Buttons
                Row(
                  children: [
                    // Edit Button
                    IconButton(
                      onPressed: () => _showEditDialog(user),
                      icon: Icon(
                        Icons.edit_rounded,
                        color: Colors.blue.shade600,
                        size: 24,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Delete Button
                    IconButton(
                      onPressed: () =>
                          _showDeleteConfirmDialog(user, userIndex),
                      icon: Icon(
                        Icons.delete_rounded,
                        color: Colors.red.shade600,
                        size: 24,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Additional Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoItem(
                    icon: Icons.calendar_today,
                    label: 'تاريخ التسجيل',
                    value: formattedDate,
                  ),
                  _buildInfoItem(
                    icon: Icons.security,
                    label: 'كلمة المرور الثانية',
                    value: user['secpass']?.toString() ?? 'غير محدد',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(String? name) {
    return Center(
      child: Text(
        name != null && name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: GoogleFonts.cairo(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(
            'جميع المستخدمين',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.blue.shade600,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterUsers,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'البحث عن مستخدم...',
                  hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Users List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: SpinKitWave(
                        color: Colors.blue.shade600,
                        size: 50,
                      ),
                    )
                  : _filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد مستخدمين',
                                style: GoogleFonts.cairo(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadUsers,
                          color: Colors.blue.shade600,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return _buildUserCard(user);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
