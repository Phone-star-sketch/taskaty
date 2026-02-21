import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class TaskDetailsPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic>? assignment;

  const TaskDetailsPage({
    super.key,
    required this.task,
    this.assignment,
  });

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsState();
}

class _TaskDetailsState extends State<TaskDetailsPage> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingFile = false;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  late String _selectedStatus;
  late String _selectedPriority;
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _attachments = [];
  Map<String, dynamic> _taskData = {}; // Add this to store updated task data
  late RealtimeChannel _taskChannel; // Add this for real-time updates
  List<Map<String, dynamic>> _userNotes = [];
  List<Map<String, dynamic>> _allUsers = []; // Add this for user selection
  List<String> _currentAssignedUserIds = []; // Track current assignments

  @override
  void initState() {
    super.initState();
    // Initialize date formatting for Arabic locale
    initializeDateFormatting('ar', null).then((_) {
      setState(() {
        // Defensive: Only set if not null and is String
        final createdAt = widget.task['created_at'];
        final endAt = widget.task['end_at'];
        _startDateController.text = _formatArabicDate(createdAt ?? '');
        _endDateController.text = _formatArabicDate(endAt ?? '');
      });
    });
    _initializeControllers();
    _loadAttachments();
    _fetchTaskData(); // Fetch complete task data including status
    _fetchUserNotes(); // Add this
    _setupRealtimeListener(); // Add real-time listener
    _fetchAllUsers(); // Add this
    _loadCurrentAssignments(); // Add this
  }

  void _initializeControllers() {
    _titleController.text = widget.task['title'] ?? '';
    _descriptionController.text = widget.task['description'] ?? '';

    // Initialize status from task data (same source as card)
    _selectedStatus =
        widget.task['status'] ?? 'in_progress'; // Use consistent default
    _selectedPriority = widget.task['priority'] ?? 'عادي';

    // Safely parse dates, fallback to now if null or invalid
    final createdAt = widget.task['created_at'];
    final endAt = widget.task['end_at'];
    try {
      _startDate =
          (createdAt != null && createdAt is String && createdAt.isNotEmpty)
              ? DateTime.parse(createdAt)
              : DateTime.now();
    } catch (_) {
      _startDate = DateTime.now();
    }
    try {
      _endDate = (endAt != null && endAt is String && endAt.isNotEmpty)
          ? DateTime.parse(endAt)
          : DateTime.now();
    } catch (_) {
      _endDate = DateTime.now();
    }
    _startDateController.text = _formatArabicDate(createdAt ?? '');
    _endDateController.text = _formatArabicDate(endAt ?? '');
  }

  @override
  void dispose() {
    _taskChannel.unsubscribe(); // Clean up the channel
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  // Add method to setup real-time listener
  void _setupRealtimeListener() {
    _taskChannel = Supabase.instance.client
        .channel('task_${widget.task['id']}_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.task['id'],
          ),
          callback: (payload) {
            if (mounted) {
              // Update local task data when database changes
              final newData = payload.newRecord;
              setState(() {
                _taskData = {..._taskData, ...newData};
                // Update status from the real-time data (same source as card)
                _selectedStatus = newData['status'] ?? 'in_progress';
                _selectedPriority = newData['priority'] ?? _selectedPriority;

                // Update controllers if not editing
                if (!_isEditing) {
                  _titleController.text =
                      newData['title'] ?? _titleController.text;
                  _descriptionController.text =
                      newData['description'] ?? _descriptionController.text;

                  // Update date controllers
                  if (newData['created_at'] != null) {
                    _startDateController.text =
                        _formatArabicDate(newData['created_at']);
                    try {
                      _startDate = DateTime.parse(newData['created_at']);
                    } catch (_) {}
                  }
                  if (newData['end_at'] != null) {
                    _endDateController.text =
                        _formatArabicDate(newData['end_at']);
                    try {
                      _endDate = DateTime.parse(newData['end_at']);
                    } catch (_) {}
                  }
                }
              });

              // Show a subtle notification about the update
              if (!_isEditing) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم تحديث المهمة'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.blue.shade600,
                  ),
                );
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'task_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: widget.task['id'],
          ),
          callback: (payload) {
            if (mounted) {
              // Refresh user notes when assignments are updated
              _fetchUserNotes();

              // Show notification for new user notes
              final newNote = payload.newRecord['user_note'];
              final oldNote = payload.oldRecord?['user_note'];

              if (newNote != null && newNote != oldNote && newNote.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم إضافة ملاحظة جديدة من المستخدم'),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.blue.shade600,
                    action: SnackBarAction(
                      label: 'عرض',
                      textColor: Colors.white,
                      onPressed: () {
                        // Scroll to user notes section if needed
                      },
                    ),
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  // Also listen to task assignments changes
  void _setupAssignmentRealtimeListener() {
    final assignmentChannel = Supabase.instance.client
        .channel('task_assignments_${widget.task['id']}_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'task_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: widget.task['id'],
          ),
          callback: (payload) {
            if (mounted && !_isEditing) {
              // Refresh task data when assignments are updated
              _fetchTaskData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Update task details including status in tasks table
      final updatedData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'priority': _selectedPriority,
        'status': _selectedStatus, // Primary status in tasks table
        'created_at': _startDate!.toIso8601String(),
        'end_at': _endDate!.toIso8601String(),
      };

      await Supabase.instance.client
          .from('tasks')
          .update(updatedData)
          .eq('id', widget.task['id']);

      // Keep task assignments status in sync
      await Supabase.instance.client
          .from('task_assignments')
          .update({'status': _selectedStatus}).eq('task_id', widget.task['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التغييرات بنجاح')),
        );
        setState(() => _isEditing = false);
        // Refresh the task data
        await _fetchTaskData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadAttachments() async {
    try {
      final response = await Supabase.instance.client
          .from('task_attachments')
          .select()
          .eq('task_id', widget.task['id']);

      if (mounted) {
        setState(() {
          _attachments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      setState(() => _isUploadingFile = true);

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      // Upload to Supabase Storage
      await Supabase.instance.client.storage
          .from('files')
          .uploadBinary(fileName, file.bytes!);

      // Get the public URL
      final fileUrl =
          Supabase.instance.client.storage.from('files').getPublicUrl(fileName);

      // Save attachment record
      final response = await Supabase.instance.client
          .from('task_attachments')
          .insert({
            'task_id': widget.task['id'],
            'file_name': file.name,
            'file_url': fileUrl,
            'file_type': file.extension,
            'uploaded_by': Supabase.instance.client.auth.currentUser!.id,
          })
          .select()
          .single();

      if (mounted) {
        setState(() {
          _attachments.add(response);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع الملف بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في رفع الملف: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
        return Icons.archive_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _downloadFile(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في فتح الملف: ${e.toString()}')),
        );
      }
    }
  }

  // Add method to fetch complete task data
  Future<void> _fetchTaskData() async {
    try {
      final response = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .eq('id', widget.task['id'])
          .single();

      if (mounted && response != null) {
        setState(() {
          _taskData = response;
          // Use the same status source as the card
          _selectedStatus = response['status'] ?? 'in_progress';
          _selectedPriority = response['priority'] ?? 'عادي';

          // Update controllers with fresh data
          if (!_isEditing) {
            _titleController.text = response['title'] ?? '';
            _descriptionController.text = response['description'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching task data: $e');
    }
  }

  // Add method to fetch user notes for this task
  Future<void> _fetchUserNotes() async {
    try {
      final response = await Supabase.instance.client
          .from('task_assignments')
          .select('''
            id,
            user_note,
            updated_at,
            assignee:profiles!user_id (
              name,
              avatar_url
            )
          ''')
          .eq('task_id', widget.task['id'])
          .not('user_note', 'is', null)
          .neq('user_note', '')
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _userNotes = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching user notes: $e');
    }
  }

  // Add method to fetch all available users
  Future<void> _fetchAllUsers() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, name, avatar_url, role')
          .eq('role', 'user');

      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
    }
  }

  // Add method to load current assignments
  Future<void> _loadCurrentAssignments() async {
    try {
      final response = await Supabase.instance.client
          .from('task_assignments')
          .select('user_id')
          .eq('task_id', widget.task['id']);

      if (mounted) {
        setState(() {
          _currentAssignedUserIds = response
              .map((assignment) => assignment['user_id'].toString())
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading current assignments: $e');
    }
  }

  // Add method to show user assignment dialog
  Future<void> _showUserAssignmentDialog() async {
    List<String> selectedUserIds = List.from(_currentAssignedUserIds);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _UserAssignmentDialog(
        allUsers: _allUsers,
        currentAssignedUserIds: selectedUserIds,
      ),
    );

    if (result != null) {
      await _updateTaskAssignments(result);
    }
  }

  // Add method to update task assignments
  Future<void> _updateTaskAssignments(List<String> newUserIds) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      // Remove admin from assignments if accidentally included
      newUserIds.removeWhere((id) => id == currentUserId);

      // Get users to remove (in current but not in new)
      final usersToRemove = _currentAssignedUserIds
          .where((id) => !newUserIds.contains(id))
          .toList();

      // Get users to add (in new but not in current)
      final usersToAdd = newUserIds
          .where((id) => !_currentAssignedUserIds.contains(id))
          .toList();

      // Remove unassigned users
      if (usersToRemove.isNotEmpty) {
        await Supabase.instance.client
            .from('task_assignments')
            .delete()
            .eq('task_id', widget.task['id'])
            .inFilter('user_id', usersToRemove);
      }

      // Add new assigned users
      if (usersToAdd.isNotEmpty) {
        final assignmentInserts = usersToAdd
            .map((userId) => {
                  'task_id': widget.task['id'],
                  'user_id': userId,
                  'created_at': _startDate?.toIso8601String() ??
                      widget.task['created_at'],
                  'end_at':
                      _endDate?.toIso8601String() ?? widget.task['end_at'],
                  'status': _selectedStatus,
                })
            .toList();

        await Supabase.instance.client
            .from('task_assignments')
            .insert(assignmentInserts);

        // Send notifications to newly assigned users
        for (String userId in usersToAdd) {
          try {
            await Supabase.instance.client.functions.invoke(
              'notify-task-assignment',
              body: {
                'task_id': widget.task['id'],
                'user_id': userId,
                'assigned_by_id': currentUserId,
                'type': 'task_assigned',
                'task_title': _titleController.text.trim(),
              },
            );
          } catch (e) {
            debugPrint('Failed to send notification to user $userId: $e');
          }
        }
      }

      // Update local state
      setState(() {
        _currentAssignedUserIds = List.from(newUserIds);
      });

      // Refresh task data
      await _fetchTaskData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث تعيينات المهمة بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث التعيينات: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get all assigned users
    final assignments = widget.task['task_assignments'] as List<dynamic>?;

    // Use current task data or fallback to widget data with real-time updates
    final currentTitle =
        _taskData['title'] ?? widget.task['title'] ?? 'بدون عنوان';
    final currentDescription =
        _taskData['description'] ?? widget.task['description'];
    // Use the same status source as the card - prioritize _selectedStatus which gets updated from real-time
    final currentStatus =
        _selectedStatus; // This matches what's shown in the card
    final currentPriority =
        _taskData['priority'] ?? widget.task['priority'] ?? 'عادي';

    return Scaffold(
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              surfaceTintColor: colorScheme.surface,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Use the image as the background for the title section
                    Image.asset(
                      'assets/background.jpg',
                      fit: BoxFit.cover,
                    ),
                    // Add status indicator overlay on the title - now matches card status
                    Positioned(
                      top: 80,
                      right: 32,
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 300), // Add animation
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(currentStatus).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(currentStatus),
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getStatusText(currentStatus),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(right: 32.0, bottom: 24.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            currentTitle,
                            key:
                                ValueKey(currentTitle), // Add key for animation
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_isEditing)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: Colors.white), // Rounded icon
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                            _initializeControllers(); // Revert changes
                          });
                        },
                      ),
                      _isSaving
                          ? Padding(
                              padding: const EdgeInsets.all(
                                  12.0), // Padding for loader
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5, // Slightly thicker stroke
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(Icons.save_rounded,
                                  color: Colors.white), // Rounded icon
                              onPressed: _saveChanges,
                            ),
                    ],
                  )
                else
                  IconButton(
                    icon: Icon(Icons.edit_rounded,
                        color: Colors.white), // Rounded icon
                    onPressed: () => setState(() => _isEditing = true),
                  ),
                const SizedBox(width: 8), // Spacing for actions
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Field (only visible when editing)
                      if (_isEditing) ...[
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'عنوان المهمة',
                            filled: true,
                            fillColor:
                                colorScheme.surfaceVariant.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: colorScheme.primary, width: 2),
                            ),
                            prefixIcon: Icon(Icons.title,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'عنوان المهمة مطلوب';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Status Card - Always visible with current status (animated) - now matches card
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildStatusCard(context, theme, colorScheme),
                      ),
                      const SizedBox(height: 24),

                      // Priority Display - Always visible (animated)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildPriorityCard(context, theme, colorScheme),
                      ),
                      const SizedBox(height: 24),

                      // Priority Selection (only visible when editing)
                      if (_isEditing) ...[
                        _buildPrioritySelection(context, theme, colorScheme),
                        const SizedBox(height: 24),
                      ],

                      // Dates Selection (only visible when editing)
                      if (_isEditing) ...[
                        _buildDatesSelection(context, theme, colorScheme),
                        const SizedBox(height: 24),
                      ],

                      // Description Section with real-time updates
                      Text(
                        'الوصف',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_isEditing)
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 5, // More lines for description
                          minLines: 3,
                          decoration: InputDecoration(
                            hintText: 'أدخل تفاصيل المهمة هنا...',
                            filled: true,
                            fillColor:
                                colorScheme.surfaceVariant.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: colorScheme.primary, width: 2),
                            ),
                          ),
                        )
                      else
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            key: ValueKey(
                                currentDescription), // Add key for animation
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color:
                                  colorScheme.surfaceVariant.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withOpacity(0.5)),
                            ),
                            child: Text(
                              currentDescription ?? 'لا يوجد وصف لهذه المهمة.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.85),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.justify,
                            ),
                          ),
                        ),

                      const SizedBox(height: 32), // More spacing

                      // Attachments Section
                      _buildAttachmentsList(context, theme, colorScheme),

                      const SizedBox(height: 32),

                      // User Notes Section - Add this before Assignment Info
                      _buildUserNotesSection(context, theme, colorScheme),

                      const SizedBox(height: 32),

                      // Assignment Info
                      Row(children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primary.withOpacity(0.18),
                                  colorScheme.primary.withOpacity(0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary.withOpacity(0.22),
                                    colorScheme.primary.withOpacity(0.08),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        colorScheme.primary.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: _buildInfoCard(
                                  context,
                                  'منشئ المهمة',
                                  widget.task['creator_profile'],
                                  Icons.person_outline_rounded,
                                  colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.secondary.withOpacity(0.18),
                                  colorScheme.secondary.withOpacity(0.08),
                                ],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      colorScheme.secondary.withOpacity(0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.secondary.withOpacity(0.22),
                                    colorScheme.secondary.withOpacity(0.08),
                                  ],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        colorScheme.secondary.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.assignment_ind_outlined,
                                            color: colorScheme.secondary,
                                            size: 28),
                                        const SizedBox(width: 12),
                                        Text(
                                          'معين إلى',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        const Spacer(),
                                        // Add edit button when editing
                                        if (_isEditing)
                                          IconButton(
                                            icon: Icon(
                                              Icons.edit_rounded,
                                              color: colorScheme.secondary,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _showUserAssignmentDialog,
                                            tooltip: 'تعديل التعيينات',
                                            style: IconButton.styleFrom(
                                              backgroundColor: colorScheme
                                                  .secondary
                                                  .withOpacity(0.1),
                                              padding: const EdgeInsets.all(8),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    assignments != null &&
                                            assignments.isNotEmpty
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: List.generate(
                                                assignments.length, (idx) {
                                              final assignee = assignments[idx]
                                                  ['assignee_profile'];
                                              final name = assignee?['name']
                                                      ?.toString() ??
                                                  'غير محدد';
                                              final avatarUrl =
                                                  assignee?['avatar_url']
                                                      ?.toString();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 12.0),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 20,
                                                      backgroundColor:
                                                          colorScheme.secondary
                                                              .withOpacity(
                                                                  0.15),
                                                      backgroundImage:
                                                          avatarUrl != null &&
                                                                  avatarUrl
                                                                      .isNotEmpty
                                                              ? NetworkImage(
                                                                  avatarUrl)
                                                              : null,
                                                      child: avatarUrl ==
                                                                  null ||
                                                              avatarUrl.isEmpty
                                                          ? Text(
                                                              name.isNotEmpty
                                                                  ? name[0]
                                                                      .toUpperCase()
                                                                  : '?',
                                                              style: theme
                                                                  .textTheme
                                                                  .titleLarge
                                                                  ?.copyWith(
                                                                color: colorScheme
                                                                    .secondary,
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: theme
                                                            .textTheme.bodyLarge
                                                            ?.copyWith(
                                                          color: colorScheme
                                                              .onSurface,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          )
                                        : Text(
                                            'غير محدد',
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                              color: theme
                                                  .textTheme.bodySmall?.color,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // Timeline (always visible)
                      _buildTimeline(context, theme, colorScheme,
                          widget.task['created_at']),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.onPrimary, // Match icon color
                      ),
                    )
                  : Icon(Icons.save_rounded,
                      color: colorScheme.onPrimary), // Use rounded icon
              label: Text(
                _isSaving ? 'جاري الحفظ...' : 'حفظ التغييرات',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
              backgroundColor: colorScheme.primary, // Primary color for FAB
              elevation: 8, // More prominent shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), // Rounded FAB
              ),
            )
          : null,
    );
  }

  Widget _buildStatusCard(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    // Use _selectedStatus which matches what's displayed in the card
    final statusColor = _getStatusColor(_selectedStatus);
    return AnimatedContainer(
      key: ValueKey(_selectedStatus), // Add key for animation
      duration: const Duration(milliseconds: 300),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 24, // Increased padding
            vertical: 20,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withOpacity(
                    0.9), // Slightly less opacity for the gradient effect
                statusColor.withOpacity(0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.4), // More pronounced shadow
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'حالة المهمة',
                style: theme.textTheme.labelMedium?.copyWith(
                  // Smaller, clearer label
                  color: Colors.white.withOpacity(0.8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10), // Spacing
              Row(
                children: [
                  Icon(
                    _getStatusIcon(_selectedStatus),
                    color: Colors.white,
                    size: 32, // Larger icon
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    // Use Expanded to handle long text or dropdowns
                    child: _isEditing
                        ? DropdownButtonHideUnderline(
                            // Hide underline for cleaner look
                            child: DropdownButton<String>(
                              value: _selectedStatus,
                              isExpanded: true, // Take full width
                              icon: const Icon(Icons.arrow_drop_down_rounded,
                                  color: Colors.white70),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              dropdownColor: statusColor.withOpacity(
                                  0.9), // Match dropdown color to card
                              items:
                                  ['new', 'pending', 'in_progress', 'completed']
                                      .map((status) => DropdownMenuItem(
                                            value: status,
                                            child: Text(
                                              _getStatusText(status),
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedStatus = value);
                                }
                              },
                            ),
                          )
                        : Text(
                            _getStatusText(_selectedStatus),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              // More prominent display text
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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

  Widget _buildPrioritySelection(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الأولوية',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedPriority,
              decoration: InputDecoration(
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                prefixIcon: Icon(Icons.priority_high_rounded,
                    color: _getPriorityColor(_selectedPriority)),
              ),
              items: ['هام للغاية', 'هام جدا', 'هام', 'عادي']
                  .map((priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority, style: theme.textTheme.bodyLarge),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPriority = value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityCard(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final currentPriority =
        _taskData['priority'] ?? widget.task['priority'] ?? 'عادي';
    final priorityColor = _getPriorityColor(currentPriority);

    return AnimatedContainer(
      key: ValueKey(currentPriority), // Add key for animation
      duration: const Duration(milliseconds: 300),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                priorityColor.withOpacity(0.1),
                priorityColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: priorityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getPriorityIcon(currentPriority),
                  color: priorityColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأولوية',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        currentPriority,
                        key: ValueKey(currentPriority),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatesSelection(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تواريخ المهمة',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startDateController,
                    readOnly: true,
                    onTap: () => _selectDate(context, true),
                    decoration: InputDecoration(
                      labelText: 'تاريخ البداية',
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colorScheme.primary, width: 2),
                      ),
                      suffixIcon: Icon(Icons.calendar_month_rounded,
                          color: colorScheme.primary),
                    ),
                    validator: (value) {
                      if (_startDate == null) {
                        return 'يرجى اختيار تاريخ البداية';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _endDateController,
                    readOnly: true,
                    onTap: () => _selectDate(context, false),
                    decoration: InputDecoration(
                      labelText: 'تاريخ الانتهاء',
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colorScheme.secondary, width: 2),
                      ),
                      suffixIcon: Icon(Icons.calendar_month_rounded,
                          color: colorScheme.secondary),
                    ),
                    validator: (value) {
                      if (_endDate == null) {
                        return 'يرجى اختيار تاريخ الانتهاء';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsList(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'المرفقات',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_isEditing)
              _isUploadingFile
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : IconButton.filled(
                      // Use filled button for upload action
                      icon: const Icon(Icons.cloud_upload_rounded),
                      onPressed: _pickAndUploadFile,
                      tooltip: 'رفع ملف جديد',
                      color: colorScheme.primary,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        foregroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
          ],
        ),
        const SizedBox(height: 12),
        if (_attachments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Center(
              child: Text(
                'لا توجد مرفقات حاليًا. اضغط على أيقونة الرفع لإضافة ملف.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _attachments.length,
            itemBuilder: (context, index) {
              final attachment = _attachments[index];
              return Card(
                margin: const EdgeInsets.only(
                    bottom: 10), // Spacing between attachments
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Icon(_getFileIcon(attachment['file_type']),
                      color: colorScheme.primary, size: 28),
                  title: Text(
                    attachment['file_name'],
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${attachment['file_type']?.toUpperCase() ?? 'FILE'} • ${_formatDate(attachment['created_at'] ?? DateTime.now().toIso8601String())}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.download_rounded,
                        color: colorScheme.secondary),
                    onPressed: () => _downloadFile(attachment['file_url']),
                    tooltip: 'تنزيل الملف',
                  ),
                  onTap: () => _downloadFile(
                      attachment['file_url']), // Also download on tile tap
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, String title,
      Map<String, dynamic>? user, IconData icon, Color accentColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20), // Consistent padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 28), // Larger icon
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16), // Increased spacing
            if (user != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 24, // Larger avatar
                    backgroundColor: accentColor.withOpacity(0.15),
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    // Move 'child' to the end
                    child: user['avatar_url'] == null
                        ? Text(
                            user['name']?[0].toUpperCase() ?? '?',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: accentColor),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      user['name'] ?? 'غير معروف',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'غير محدد',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, ThemeData theme,
      ColorScheme colorScheme, String? createdAt) {
    final startDate = widget.task['created_at'];
    final endDate = widget.task['end_at'];

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_note_rounded,
                      color: colorScheme.primary, size: 30),
                  const SizedBox(width: 16),
                  Text(
                    'المواعيد',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDateRectangle(
                    context,
                    'تاريخ البداية',
                    startDate ?? '',
                    Icons.play_circle_fill_rounded,
                    colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                  _buildDateRectangle(
                    context,
                    'تاريخ الانتهاء',
                    endDate ?? '',
                    Icons.flag_rounded,
                    colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRectangle(BuildContext context, String label, String date,
      IconData icon, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.13),
              color.withOpacity(0.22),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.13), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child:
                    Icon(icon, color: color, size: 24), // Slightly smaller icon
              ),
              const SizedBox(width: 14),
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.85),
                        fontWeight: FontWeight.bold,
                        fontSize: 14, // Slightly smaller label
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatArabicDate(date),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 15, // Reduced font size for date
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: const Locale('ar'), // For Arabic date picker
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          _startDateController.text = _formatArabicDate(picked);
          // Ensure end date is not before start date
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
            _endDateController.text = _formatArabicDate(_startDate!);
          }
        } else {
          _endDate = picked;
          _endDateController.text = _formatArabicDate(picked);
          // Ensure start date is not after end date
          if (_startDate != null && _startDate!.isAfter(_endDate!)) {
            _startDate = _endDate;
            _startDateController.text = _formatArabicDate(_endDate!);
          }
        }
      });
    }
  }

  // Helper functions (unchanged functionally, but adjusted for consistency)
  String _formatArabicDate(dynamic dateString) {
    if (dateString == null || (dateString is String && dateString.isEmpty))
      return 'غير محدد';
    DateTime date;
    try {
      if (dateString is DateTime) {
        date = dateString;
      } else if (dateString is String && dateString.isNotEmpty) {
        date = DateTime.parse(dateString.toString()).toLocal();
      } else {
        return 'غير محدد';
      }
    } catch (_) {
      return 'غير محدد';
    }
    final DateFormat formatter = DateFormat(
        'EEEE، d MMMM y', 'ar'); // Specify Arabic locale if available

    final List<String> arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    final List<String> arabicDays = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    final dayName = arabicDays[date.weekday - 1];
    final monthName = arabicMonths[date.month - 1];
    return '$dayName، ${date.day} $monthName ${date.year}';
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'تم التنفيذ';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'pending':
        return 'قيد الانتظار';
      default:
        return 'جديدة';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF4CAF50); // Match card colors exactly
      case 'in_progress':
        return const Color(0xFF2196F3); // Match card colors exactly
      case 'pending':
        return const Color(0xFFFF9800); // Match card colors exactly
      default:
        return const Color(0xFF9E9E9E); // Match card colors exactly
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.pending_actions_rounded; // More descriptive icon
      case 'pending':
        return Icons.schedule_rounded; // Clock icon for pending
      default:
        return Icons.fiber_new_rounded;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'هام للغاية':
        return Colors.red.shade700;
      case 'هام جدا':
        return Colors.red.shade600;
      case 'هام':
        return Colors.orange.shade700;
      case 'عادي':
        return Colors.blue.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return DateFormat('yyyy-MM-dd')
        .format(date); // Use intl for consistent formatting
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'هام للغاية':
        return Icons.priority_high_rounded;
      case 'هام جدا':
        return Icons.warning_rounded;
      case 'هام':
        return Icons.warning_amber_rounded;
      case 'عادي':
        return Icons.low_priority_rounded;
      default:
        return Icons.low_priority_rounded;
    }
  }

  // Add method to build user notes section for admins
  Widget _buildUserNotesSection(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: colorScheme.secondary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'ملاحظات المستخدمين',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.secondary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_userNotes.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_userNotes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surfaceVariant.withOpacity(0.3),
                  colorScheme.surfaceVariant.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 48,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'لا توجد ملاحظات من المستخدمين',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ستظهر ملاحظات واستفسارات المستخدمين هنا',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _userNotes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final noteData = _userNotes[index];
              final assignee = noteData['assignee'] as Map<String, dynamic>?;
              final userName = assignee?['name'] ?? 'مستخدم غير معروف';
              final userAvatar = assignee?['avatar_url'];
              final note = noteData['user_note'] ?? '';
              final updatedAt = noteData['updated_at'];

              return AnimatedContainer(
                duration: Duration(milliseconds: 300 + (index * 100)),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          colorScheme.secondaryContainer.withOpacity(0.1),
                          colorScheme.secondaryContainer.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.secondary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor:
                                    colorScheme.secondary.withOpacity(0.2),
                                backgroundImage: userAvatar != null
                                    ? NetworkImage(userAvatar)
                                    : null,
                                child: userAvatar == null
                                    ? Text(
                                        userName.isNotEmpty
                                            ? userName[0].toUpperCase()
                                            : 'M',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: colorScheme.secondary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.secondary,
                                      ),
                                    ),
                                    if (updatedAt != null)
                                      Text(
                                        _formatArabicDate(updatedAt),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chat_bubble_rounded,
                                color: colorScheme.secondary.withOpacity(0.6),
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              note,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                                color: colorScheme.onSurface,
                              ),
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
      ],
    );
  }
}

// Add new dialog widget for user assignment
class _UserAssignmentDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allUsers;
  final List<String> currentAssignedUserIds;

  const _UserAssignmentDialog({
    required this.allUsers,
    required this.currentAssignedUserIds,
  });

  @override
  State<_UserAssignmentDialog> createState() => _UserAssignmentDialogState();
}

class _UserAssignmentDialogState extends State<_UserAssignmentDialog> {
  late List<String> selectedUserIds;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    selectedUserIds = List.from(widget.currentAssignedUserIds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter users based on search query
    final filteredUsers = widget.allUsers.where((user) {
      final name = user['name']?.toString().toLowerCase() ?? '';
      return name.contains(searchQuery.toLowerCase());
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.people_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تعديل تعيينات المهمة',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search field
            TextField(
              decoration: InputDecoration(
                hintText: 'البحث عن مستخدم...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Selected users count
            if (selectedUserIds.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'محدد: ${selectedUserIds.length} مستخدم',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Users list
            Expanded(
              child: ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final userId = user['id'].toString();
                  final isSelected = selectedUserIds.contains(userId);
                  final userName = user['name'] ?? 'مستخدم غير معروف';
                  final userAvatar = user['avatar_url'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.1)
                          : colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        backgroundImage: userAvatar != null
                            ? NetworkImage(userAvatar)
                            : null,
                        child: userAvatar == null
                            ? Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        userName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: colorScheme.primary,
                            )
                          : Icon(
                              Icons.circle_outlined,
                              color: colorScheme.outline,
                            ),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            selectedUserIds.remove(userId);
                          } else {
                            selectedUserIds.add(userId);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: colorScheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(selectedUserIds),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('حفظ التغييرات'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
