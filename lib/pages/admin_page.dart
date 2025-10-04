import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:taskaty/services/notification_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AdminDashboard extends StatefulWidget {
  static const route = '/admin/create-task';
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<String> _selectedUserIds = []; // Changed to List for multiple users
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  bool _isUploadingFiles = false;
  List<PlatformFile> _selectedFiles = [];

  late AnimationController _animationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedPriority = 'عادي';
  final List<String> _priorities = ['هام للغاية', 'هام جدا', 'هام', 'عادي'];
  String _selectedStatus = 'in_progress';
  final List<String> _statuses = ['in_progress', 'completed'];
  
  // إعدادات التكرار
  bool _isRecurring = false;
  String _recurrenceType = 'every_minute';
  final List<String> _recurrenceTypes = ['every_minute', 'daily', 'weekly', 'monthly'];
  final Map<String, String> _recurrenceLabels = {
    'every_minute': 'كل دقيقة (للاختبار)',
    'daily': 'يومياً',
    'weekly': 'أسبوعياً', 
    'monthly': 'شهرياً',
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.easeOutBack,
    ));
    _fetchUsers();
    _animationController.forward();
    _cardAnimationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cardAnimationController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, name, avatar_url, role')
          .eq('role', 'user');

      if (mounted && response != null) {
        setState(() {
          _users =
              response.map((user) => user as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('خطأ في جلب المستخدمين: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate() ||
        _selectedUserIds.isEmpty ||
        _startDate == null ||
        _endDate == null) {
      _showSnackBar(
          'يرجى ملء جميع الحقول المطلوبة وتعيين مستخدم واحد على الأقل',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get current admin user ID
      final adminUserId = Supabase.instance.client.auth.currentUser!.id;
      print('Admin user ID (who is creating the task): $adminUserId');
      print('Selected user IDs (who will receive the task): $_selectedUserIds');

      // Remove duplicates from selected user IDs
      final uniqueUserIds = _selectedUserIds.toSet().toList();

      // Remove admin user ID if accidentally included
      uniqueUserIds.removeWhere((id) => id == adminUserId);

      if (uniqueUserIds.isEmpty) {
        _showSnackBar('لا يمكن تعيين المهمة لنفسك. يرجى اختيار مستخدمين آخرين.',
            isError: true);
        setState(() => _isLoading = false);
        return;
      }

      // Insert task
      final taskResponse = await Supabase.instance.client.from('tasks').insert({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'created_by': adminUserId,
        'created_at': _startDate!.toIso8601String(),
        'end_at': _endDate!.toIso8601String(),
        'priority': _selectedPriority,
        'is_recurring': _isRecurring,
        'recurrence_type': _isRecurring ? _recurrenceType : null,
      }).select();

      final taskId = taskResponse[0]['id'] as int;
      print('Created task with ID: $taskId');

      // Upload attachments if any
      if (_selectedFiles.isNotEmpty) {
        setState(() => _isUploadingFiles = true);

        for (var file in _selectedFiles) {
          if (file.bytes != null) {
            final fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

            await Supabase.instance.client.storage
                .from('files')
                .uploadBinary(fileName, file.bytes!);

            final fileUrl = Supabase.instance.client.storage
                .from('files')
                .getPublicUrl(fileName);

            await Supabase.instance.client.from('task_attachments').insert({
              'task_id': taskId,
              'file_name': file.name,
              'file_url': fileUrl,
              'file_type': file.extension,
              'uploaded_by': adminUserId,
            });
          }
        }
      }

      // Prepare batch insert for task assignments
      final List<Map<String, dynamic>> assignmentInserts = [];

      for (String userId in uniqueUserIds) {
        print('Processing assignment for user: $userId');

        // Get user details for logging
        final userDetails = _users.firstWhere(
          (u) => u['id'].toString() == userId,
          orElse: () => {'name': 'Unknown User'},
        );
        print('Assigning to user: ${userDetails['name']} (ID: $userId)');

        // Add to batch insert
        assignmentInserts.add({
          'task_id': taskId,
          'user_id': userId,
          'created_at': _startDate!.toIso8601String(),
          'end_at': _endDate!.toIso8601String(),
          'status': _selectedStatus,
        });
      }

      // Batch insert all assignments at once
      if (assignmentInserts.isNotEmpty) {
        await Supabase.instance.client
            .from('task_assignments')
            .insert(assignmentInserts);
        print('Created ${assignmentInserts.length} task assignments');
      }

      // Send notifications to assigned users using Edge Function
      for (String userId in uniqueUserIds) {
        // Skip sending notification to admin (should not be in uniqueUserIds, but double-check)
        if (userId == adminUserId) continue;

        // Get user details for notification
        final userDetails = _users.firstWhere(
          (u) => u['id'].toString() == userId,
          orElse: () => {'name': 'Unknown User'},
        );

        print('Calling Edge Function for user: $userId, task: $taskId');

        try {
          final notificationResponse =
              await Supabase.instance.client.functions.invoke(
            'notify-task-assignment',
            body: {
              'task_id': taskId,
              'user_id': userId,
              'assigned_by_id': adminUserId,
              'type': 'task_assigned',
              'task_title': _titleController.text.trim(),
            },
          );

          print(
              'Edge Function response status: ${notificationResponse.status}');
          print('Edge Function response data: ${notificationResponse.data}');

          if (notificationResponse.status != 200) {
            print('Edge Function error: ${notificationResponse.data}');
            _showSnackBar(
              'تم إنشاء المهمة بنجاح ولكن فشل في إرسال الإشعار للمستخدم ${userDetails['name']}',
              isError: true,
            );
          } else {
            print(
                'Successfully sent notification to user: ${userDetails['name']}');
          }
        } catch (edgeFunctionError) {
          print('Edge Function call failed: $edgeFunctionError');
          _showSnackBar(
            'تم إنشاء المهمة بنجاح ولكن فشل في إرسال الإشعار للمستخدم ${userDetails['name']}: ${edgeFunctionError.toString()}',
            isError: true,
          );
        }
      }

      if (mounted) {
        _showSnackBar('تم إنشاء المهمة وتعيينها بنجاح!', isError: false);
        _clearForm();
        Navigator.pop(context);
      }
    } catch (e) {
      print('Task creation error: $e');
      if (mounted) {
        _showSnackBar('خطأ: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploadingFiles = false;
        });
      }
    }
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _startDateController.clear();
    _endDateController.clear();
    setState(() {
      _selectedUserIds.clear();
      _startDate = null;
      _endDate = null;
      _selectedPriority = 'عادي';
      _selectedStatus = 'in_progress';
      _selectedFiles.clear();
      _isRecurring = false;
      _recurrenceType = 'every_minute';
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? const Color(0xFFFF5252) : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFF6366F1),
                  surface: Theme.of(context).colorScheme.surface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _startDateController.text = _formatDate(picked);
        } else {
          _endDate = picked;
          _endDateController.text = _formatDate(picked);
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'تم التنفيذ';
      case 'in_progress':
        return 'قيد التنفيذ';
      default:
        return 'قيد التنفيذ';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF10B981);
      case 'in_progress':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'هام للغاية':
        return const Color(0xFFDC2626);
      case 'هام جدا':
        return const Color(0xFFEA580C);
      case 'هام':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF059669);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
      );

      if (result != null) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      _showSnackBar('خطأ في اختيار الملفات: ${e.toString()}', isError: true);
    }
  }

  Widget _buildModernAttachmentsList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.attach_file_rounded,
                        color: Color(0xFF6366F1),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'المرفقات',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إضافة'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                    foregroundColor: const Color(0xFF6366F1),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedFiles.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedFiles.length,
              itemBuilder: (context, index) {
                final file = _selectedFiles[index];
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getFileColor(file.extension).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getFileIcon(file.extension),
                        color: _getFileColor(file.extension),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${(file.size / 1024).toStringAsFixed(2)} KB',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () =>
                          setState(() => _selectedFiles.removeAt(index)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (_selectedFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لم يتم اختيار أي ملفات',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xlsx':
      case 'xls':
        return Icons.table_chart_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFDC2626);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Color(0xFF059669);
      case 'doc':
      case 'docx':
        return const Color(0xFF2563EB);
      case 'xlsx':
      case 'xls':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Widget _buildModernUserSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.people_rounded,
                    color: Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'تعيين المهمة إلى',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (_selectedUserIds.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedUserIds.length} محدد',
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_selectedUserIds.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المستخدمون المحددون:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedUserIds.map((userId) {
                            final user = _users.firstWhere(
                              (u) => u['id'].toString() == userId,
                              orElse: () =>
                                  {'name': 'Unknown', 'avatar_url': null},
                            );
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: const Color(0xFF6366F1),
                                    backgroundImage: user['avatar_url'] != null
                                        ? NetworkImage(user['avatar_url'])
                                        : null,
                                    child: user['avatar_url'] == null
                                        ? Text(
                                            (user['name']?[0] ?? '?')
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    user['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => setState(
                                        () => _selectedUserIds.remove(userId)),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final userId = user['id'].toString();
                      final isSelected = _selectedUserIds.contains(userId);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Material(
                          color: isSelected
                              ? const Color(0xFF6366F1).withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(userId);
                                } else {
                                  _selectedUserIds.add(userId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF6366F1)
                                        .withOpacity(0.1),
                                    backgroundImage: user['avatar_url'] != null
                                        ? NetworkImage(user['avatar_url'])
                                        : null,
                                    child: user['avatar_url'] == null
                                        ? Text(
                                            (user['name']?[0] ?? '?')
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              color: Color(0xFF6366F1),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      user['name'] ?? 'مستخدم غير معروف',
                                      style: TextStyle(
                                        color: isSelected
                                            ? const Color(0xFF6366F1)
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF6366F1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'لوحة تحكم المدير',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 16),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                ),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (mounted) {
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
              ),
            ),
          ],
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modern Header Section
                    AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _slideAnimation.value),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFF8B5CF6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF6366F1).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.assignment_ind_rounded,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'إنشاء مهمة جديدة',
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'قم بتعيين المهام لأعضاء الفريق وتتبع التقدم بسهولة',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Modern Form Section
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Task Title Field
                            _buildModernTextField(
                              controller: _titleController,
                              label: 'عنوان المهمة',
                              hint: 'أدخل عنواناً وصفياً للمهمة',
                              icon: Icons.title_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'يرجى إدخال عنوان المهمة';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            // Task Description Field
                            _buildModernTextField(
                              controller: _descriptionController,
                              label: 'وصف المهمة',
                              hint: 'أدخل تفاصيل المهمة',
                              icon: Icons.description_rounded,
                              maxLines: 3,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'يرجى إدخال وصف المهمة';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            // Start Date Field
                            GestureDetector(
                              onTap: () => _selectDate(context, true),
                              child: AbsorbPointer(
                                child: _buildModernTextField(
                                  controller: _startDateController,
                                  label: 'تاريخ البدء',
                                  hint: 'اختر تاريخ البدء',
                                  icon: Icons.calendar_today_rounded,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'يرجى اختيار تاريخ البدء';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // End Date Field
                            GestureDetector(
                              onTap: () => _selectDate(context, false),
                              child: AbsorbPointer(
                                child: _buildModernTextField(
                                  controller: _endDateController,
                                  label: 'تاريخ الانتهاء',
                                  hint: 'اختر تاريخ الانتهاء',
                                  icon: Icons.event_rounded,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'يرجى اختيار تاريخ الانتهاء';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Priority Dropdown
                            _buildModernDropdown(
                              label: 'الأولوية',
                              value: _selectedPriority,
                              items: _priorities,
                              icon: Icons.priority_high_rounded,
                              color: _getPriorityColor(_selectedPriority),
                              onChanged: (value) {
                                setState(() {
                                  _selectedPriority = value!;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            // Status Dropdown
                            _buildModernDropdown(
                              label: 'الحالة',
                              value: _selectedStatus,
                              items: _statuses,
                              icon: Icons.flag_rounded,
                              color: _getStatusColor(_selectedStatus),
                              itemTextBuilder: _getStatusText,
                              onChanged: (value) {
                                setState(() {
                                  _selectedStatus = value!;
                                });
                              },
                            ),
                            const SizedBox(height: 24),
                            // Recurring Task Section
                            _buildRecurringSection(),
                            const SizedBox(height: 24),
                            // User Selector
                            _buildModernUserSelector(),
                            const SizedBox(height: 24),
                            // Attachments
                            _buildModernAttachmentsList(),
                            const SizedBox(height: 32),
                            // Submit Button
                            ElevatedButton.icon(
                              onPressed: _isLoading || _isUploadingFiles
                                  ? null
                                  : _createTask,
                              icon: _isLoading || _isUploadingFiles
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check_circle_outline_rounded),
                              label: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  _isLoading || _isUploadingFiles
                                      ? 'جاري إنشاء المهمة...'
                                      : 'إنشاء المهمة',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Modern TextField builder
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF6366F1)),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
      style: const TextStyle(fontSize: 16),
      textAlign: TextAlign.right,
    );
  }

  // Modern Dropdown builder
  Widget _buildModernDropdown({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required Color color,
    String Function(String)? itemTextBuilder,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                itemTextBuilder != null ? itemTextBuilder(item) : item,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // Recurring Task Section Widget
  Widget _buildRecurringSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isRecurring 
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.repeat_rounded,
                    color: _isRecurring 
                        ? const Color(0xFF10B981)
                        : Colors.grey[600],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'إعدادات التكرار',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Checkbox للمهمة المتكررة
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: CheckboxListTile(
                    title: const Text(
                      'هل هذه مهمة متكررة؟',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'ستتم إعادة إنشاء هذه المهمة تلقائياً حسب الجدولة المحددة',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _isRecurring,
                    onChanged: (value) {
                      setState(() {
                        _isRecurring = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF10B981),
                    checkColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                
                // Dropdown لنوع التكرار (يظهر فقط إذا كان التكرار مفعل)
                if (_isRecurring) ...[
                  const SizedBox(height: 16),
                  _buildModernDropdown(
                    label: 'نوع التكرار',
                    value: _recurrenceType,
                    items: _recurrenceTypes,
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFF10B981),
                    itemTextBuilder: (type) => _recurrenceLabels[type] ?? type,
                    onChanged: (value) {
                      setState(() {
                        _recurrenceType = value!;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> sendFCMNotificationToUser(
    String userId, String title, String body, Map<String, dynamic> data) async {
  // Fetch the user's FCM token from Supabase (now from profiles table)
  final response = await Supabase.instance.client
      .from('profiles')
      .select('fcm_token')
      .eq('id', userId)
      .single();

  final fcmToken = response?['fcm_token'];
  if (fcmToken == null) return false;

  // WARNING: Never expose your server key in production!
  const String serverKey = 'YOUR_FCM_SERVER_KEY_HERE';

  final fcmResponse = await http.post(
    Uri.parse('https://fcm.googleapis.com/fcm/send'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'key=$serverKey',
    },
    body: jsonEncode({
      'to': fcmToken,
      'notification': {
        'title': title,
        'body': body,
      },
      'data': data,
    }),
  );

  return fcmResponse.statusCode == 200;
}
