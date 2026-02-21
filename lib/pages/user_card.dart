import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UserTaskCard extends StatefulWidget {
  final Map<String, dynamic> assignment;
  final VoidCallback? onStatusUpdated;
  final VoidCallback? onRefresh;

  const UserTaskCard({
    super.key,
    required this.assignment,
    this.onStatusUpdated,
    this.onRefresh,
  });

  @override
  State<UserTaskCard> createState() => _UserTaskCardState();
}

class _UserTaskCardState extends State<UserTaskCard>
    with TickerProviderStateMixin {
  late AnimationController _cardAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _cardAnimation;
  late Animation<double> _pulseAnimation;

  List<Map<String, dynamic>> _taskAttachments = [];
  final TextEditingController _noteController = TextEditingController();
  bool _isSavingNote = false;
  bool _isLoadingAttachments = false;
  String _modalCurrentStatus = ''; // <-- Add this line

  @override
  void initState() {
    super.initState();

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.easeOutBack,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));

    _cardAnimationController.forward();

    final task = widget.assignment['task'] as Map<String, dynamic>;
    if (task['priority'] == 'عالية') {
      _pulseAnimationController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _cardAnimationController.dispose();
    _pulseAnimationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _fetchTaskAttachments(dynamic taskId) async {
    if (!mounted) return;

    setState(() => _isLoadingAttachments = true);

    try {
      final int parsedTaskId =
          taskId is String ? int.parse(taskId) : taskId as int;

      final response = await Supabase.instance.client
          .from('task_attachments')
          .select()
          .eq('task_id', parsedTaskId);

      if (mounted) {
        setState(() {
          _taskAttachments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAttachments = false);
      }
    }
  }

  Future<String> _fetchUserNote(int assignmentId) async {
    try {
      final response = await Supabase.instance.client
          .from('task_assignments')
          .select('user_note')
          .eq('id', assignmentId)
          .single();

      return response['user_note'] ?? '';
    } catch (e) {
      debugPrint('Error fetching user note: $e');
      return '';
    }
  }

  Future<void> _updateUserNote(int assignmentId, String note) async {
    try {
      setState(() => _isSavingNote = true);

      await Supabase.instance.client
          .from('task_assignments')
          .update({'user_note': note.trim()}).eq('id', assignmentId);

      if (mounted) {
        _showSnackBar('تم حفظ الملاحظة بنجاح', isError: false);
      }
    } catch (e) {
      debugPrint('Error updating user note: $e');
      if (mounted) {
        _showSnackBar('خطأ في حفظ الملاحظة: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingNote = false);
      }
    }
  }

  Future<void> _updateTaskStatus(int assignmentId, String newStatus) async {
    try {
      final assignmentResponse = await Supabase.instance.client
          .from('task_assignments')
          .select('task_id')
          .eq('id', assignmentId)
          .single();

      final taskId = assignmentResponse['task_id'];

      await Future.wait([
        Supabase.instance.client
            .from('tasks')
            .update({'status': newStatus}).eq('id', taskId),
        Supabase.instance.client
            .from('task_assignments')
            .update({'status': newStatus}).eq('id', assignmentId),
      ]);

      if (mounted) {
        _showSnackBar('تم تحديث حالة المهمة بنجاح', isError: false);
        widget.onStatusUpdated?.call();
      }
    } catch (e) {
      debugPrint('Error updating task status: $e');
      if (mounted) {
        _showSnackBar('خطأ في تحديث حالة المهمة: ${e.toString()}',
            isError: true);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatArabicDate(String? dateStr) {
    if (dateStr == null) return 'تاريخ غير معروف';
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final difference = now.difference(date);

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
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت'
    ];

    if (difference.inDays == 0) {
      return 'اليوم';
    } else if (difference.inDays == 1) {
      return 'أمس';
    } else if (difference.inDays < 7) {
      return 'قبل ${difference.inDays} أيام';
    } else {
      final dayName = arabicDays[date.weekday % 7];
      final monthName = arabicMonths[date.month - 1];
      return '$dayName، ${date.day} $monthName ${date.year}';
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'عالية':
        return Colors.red;
      case 'متوسطة':
        return Colors.orange;
      case 'منخفضة':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'عالية':
        return Icons.priority_high;
      case 'متوسطة':
        return Icons.remove;
      case 'منخفضة':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'تم التنفيذ';
      default:
        return 'قيد التنفيذ';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'in_progress':
        return Icons.running_with_errors;
      case 'completed':
        return Icons.task_alt;
      default:
        return Icons.fiber_new;
    }
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.document_scanner;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _downloadFile(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url))) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('خطأ في فتح الملف: ${e.toString()}', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = widget.assignment['task'] as Map<String, dynamic>;
    final status = task['status'] ?? widget.assignment['status'] ?? 'new';
    final priority = task['priority'] ?? 'عادي';
    final creator = task['creator'] as Map<String, dynamic>;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _cardAnimation,
        builder: (context, child) => Transform.scale(
          scale: _cardAnimation.value,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: priority == 'عالية' ? _pulseAnimation.value : 1.0,
              child: _buildTaskCard(
                  task, status, priority, creator, colorScheme, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> task,
    String status,
    String priority,
    Map<String, dynamic> creator,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 8,
        shadowColor: statusColor.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () =>
              _showTaskDetails(task, status, priority, colorScheme, theme),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surface,
                  colorScheme.surfaceContainer.withOpacity(0.5),
                  statusColor.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: statusColor.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(task, status, priority, creator, statusColor,
                      colorScheme, theme),
                  const SizedBox(height: 16),
                  _buildDescription(task, colorScheme, theme),
                  const SizedBox(height: 16),
                  _buildTimeInfo(task, colorScheme, theme),
                  const SizedBox(height: 16),
                  _buildFooter(task, colorScheme, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    Map<String, dynamic> task,
    String status,
    String priority,
    Map<String, dynamic> creator,
    Color statusColor,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Hero(
          tag: 'task_status_${task['id']}',
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [statusColor, statusColor.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _getStatusIcon(status),
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task['title'] ?? 'بدون عنوان',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                    backgroundImage: creator['avatar_url'] != null
                        ? NetworkImage(creator['avatar_url'])
                        : null,
                    child: creator['avatar_url'] == null
                        ? Icon(Icons.person,
                            size: 16, color: colorScheme.primary)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'بواسطة: ${creator['name'] ?? 'غير معروف'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _getPriorityColor(priority),
                _getPriorityColor(priority).withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _getPriorityColor(priority).withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getPriorityIcon(priority),
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                priority,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(
    Map<String, dynamic> task,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (task['description'] == null || task['description'].isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainer.withOpacity(0.3),
            colorScheme.surfaceContainer.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Text(
        task['description'],
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.8),
          height: 1.6,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTimeInfo(
    Map<String, dynamic> task,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    DateTime? endDate;
    if (task['end_at'] != null) {
      endDate = DateTime.tryParse(task['end_at']);
    }

    String dueDateText = 'غير محدد';
    Color timerColor = colorScheme.onSurface;
    IconData timerIcon = Icons.calendar_today_outlined;

    if (endDate != null) {
      final now = DateTime.now();
      final diff = endDate.difference(now);

      dueDateText = _formatDueDateArabic(task['end_at']);

      if (diff.isNegative) {
        timerColor = Colors.red;
        timerIcon = Icons.event_busy;
      } else if (diff.inDays <= 2) {
        timerColor = Colors.orange;
        timerIcon = Icons.event;
      } else {
        timerColor = Colors.green;
        timerIcon = Icons.event_available;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            timerColor.withOpacity(0.1),
            timerColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: timerColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            timerIcon,
            color: timerColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'موعد الانتهاء',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: timerColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (endDate != null)
                  Text(
                    dueDateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: timerColor.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDueDateArabic(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    final date = DateTime.parse(dateStr);

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

    final monthName = arabicMonths[date.month - 1];
    return '${date.day} $monthName ${date.year}';
  }

  Widget _buildFooter(
    Map<String, dynamic> task,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'تم الإنشاء: ${_formatDueDateArabic(task['created_at'])}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.touch_app_rounded,
          color: colorScheme.primary.withOpacity(0.6),
          size: 20,
        ),
      ],
    );
  }

  void _showTaskDetails(
    Map<String, dynamic> task,
    String status,
    String priority,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    setState(() => _taskAttachments.clear());
    _noteController.clear();

    final taskId = task['id'];
    String currentStatus =
        task['status'] ?? widget.assignment['status'] ?? 'pending';

    if (taskId != null) {
      Future.wait([
        _fetchTaskAttachments(taskId),
        _fetchUserNote(widget.assignment['id']),
      ]).then((results) {
        if (!mounted) return;

        final userNote = results[1] as String;
        _noteController.text = userNote;

        // Fix: Properly initialize _modalCurrentStatus
        setState(() {
          // If status is pending/new, start with in_progress, otherwise use actual status
          if (currentStatus == 'pending' || currentStatus == 'new') {
            _modalCurrentStatus = 'in_progress';
          } else {
            _modalCurrentStatus = currentStatus;
          }
        });

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _buildTaskDetailsModal(
            task,
            _modalCurrentStatus,
            priority,
            colorScheme,
            theme,
          ),
        );
      });
    }
  }

  Widget _buildTaskDetailsModal(
    Map<String, dynamic> task,
    String currentStatus,
    String priority,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return StatefulBuilder(
      builder: (context, setModalState) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildModalHeader(task, priority, colorScheme, theme),
                        const SizedBox(height: 24),
                        _buildStatusSection(
                          _modalCurrentStatus,
                          colorScheme,
                          theme,
                          (String newStatus) {
                            setModalState(() {
                              setState(() {
                                _modalCurrentStatus = newStatus;
                              });
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        if (task['description'] != null &&
                            task['description'].isNotEmpty)
                          _buildDescriptionSection(task, colorScheme, theme),
                        const SizedBox(height: 24),
                        _buildAttachmentsSection(colorScheme, theme),
                        const SizedBox(height: 24),
                        _buildUserNotesSection(
                            colorScheme, theme, setModalState),
                        const SizedBox(height: 32),
                        _buildActionButtons(
                          _modalCurrentStatus,
                          task,
                          colorScheme,
                          theme,
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
    );
  }

  Widget _buildModalHeader(
    Map<String, dynamic> task,
    String priority,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getPriorityColor(priority).withOpacity(0.1),
            _getPriorityColor(priority).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getPriorityColor(priority).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getPriorityColor(priority),
                  _getPriorityColor(priority).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _getPriorityColor(priority).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _getPriorityIcon(priority),
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title'] ?? 'مهمة بدون عنوان',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(priority).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'أولوية $priority',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _getPriorityColor(priority),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(
    String currentStatus,
    ColorScheme colorScheme,
    ThemeData theme,
    Function(String) onStatusChanged,
  ) {
    // Remove the forced displayStatus conversion - let user select any status
    String displayStatus = currentStatus;
    // If status is pending/new, default to in_progress for display but allow all options
    if (currentStatus == 'pending' || currentStatus == 'new') {
      displayStatus = 'in_progress';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withOpacity(0.3),
            colorScheme.primaryContainer.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.track_changes_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'حالة المهمة',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _modalCurrentStatus, // Use the actual modal status instead of displayStatus
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Row(
                      children: [
                        Icon(Icons.running_with_errors,
                            color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        const Text('قيد التنفيذ'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Row(
                      children: [
                        Icon(Icons.task_alt, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text('تم التنفيذ'),
                      ],
                    ),
                  ),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    onStatusChanged(newValue);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(
    Map<String, dynamic> task,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                color: colorScheme.secondary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'وصف المهمة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            task['description'],
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.tertiary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_file_rounded,
                color: colorScheme.tertiary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'المرفقات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.tertiary,
                ),
              ),
              if (_isLoadingAttachments) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.tertiary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_taskAttachments.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'لا توجد مرفقات',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _taskAttachments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final attachment = _taskAttachments[index];
                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getFileIcon(attachment['file_type']),
                        color: colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      attachment['file_name'],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.download_rounded,
                        color: colorScheme.primary,
                      ),
                      onPressed: () => _downloadFile(attachment['file_url']),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserNotesSection(
    ColorScheme colorScheme,
    ThemeData theme,
    StateSetter setModalState,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.errorContainer.withOpacity(0.2),
            colorScheme.errorContainer.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.note_add_rounded,
                color: colorScheme.error,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'ملاحظات للمدير',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'أضف ملاحظاتك أو استفساراتك للمدير هنا',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _noteController,
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'اكتب ملاحظاتك هنا...',
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.edit_note_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingNote
                  ? null
                  : () async {
                      await _updateUserNote(
                          widget.assignment['id'], _noteController.text);
                      setModalState(() {});
                    },
              icon: _isSavingNote
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isSavingNote ? 'جاري الحفظ...' : 'حفظ الملاحظة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    String currentStatus,
    Map<String, dynamic> task,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final originalStatus =
        task['status'] ?? widget.assignment['status'] ?? 'pending';
    final bool hasChanges = currentStatus != originalStatus &&
        ((currentStatus == 'completed' && originalStatus != 'completed') ||
            (currentStatus == 'in_progress' && originalStatus != 'in_progress'));

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            label: const Text('إغلاق'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: !hasChanges
                ? null
                : () async {
                    try {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                      await _updateTaskStatus(
                          widget.assignment['id'], currentStatus);
                      Navigator.pop(context); // dismiss progress
                      Navigator.pop(context); // dismiss modal
                    } catch (e) {
                      Navigator.pop(context);
                      _showSnackBar('خطأ في حفظ التغييرات: ${e.toString()}',
                          isError: true);
                    }
                  },
            icon: Icon(
                hasChanges ? Icons.save_rounded : Icons.check_circle_rounded),
            label: Text(hasChanges ? 'حفظ التغييرات' : 'لا توجد تغييرات'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  hasChanges ? colorScheme.primary : colorScheme.surfaceVariant,
              foregroundColor: hasChanges
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}