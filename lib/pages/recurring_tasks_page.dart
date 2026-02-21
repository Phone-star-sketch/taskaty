import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/services/task_service.dart';
import 'package:google_fonts/google_fonts.dart';

class RecurringTasksPage extends StatefulWidget {
  const RecurringTasksPage({super.key});

  @override
  State<RecurringTasksPage> createState() => _RecurringTasksPageState();
}

class _RecurringTasksPageState extends State<RecurringTasksPage> {
  List<Map<String, dynamic>> _recurringTasks = [];
  bool _isLoading = false;

  final Map<String, String> _recurrenceLabels = {
    'every_minute': 'كل دقيقة (للاختبار)',
    'daily': 'يومياً',
    'weekly': 'أسبوعياً', 
    'monthly': 'شهرياً',
  };

  @override
  void initState() {
    super.initState();
    _fetchRecurringTasks();
  }

  Future<void> _fetchRecurringTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasks = await TaskService.getRecurringTasks();
      if (mounted) {
        setState(() {
          _recurringTasks = tasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('خطأ في جلب المهام المتكررة: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _cancelRecurringTask(int taskId, String taskTitle) async {
    print('🚀 Attempting to cancel recurring task: $taskId - $taskTitle'); // Debug log
    
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'إلغاء التكرار',
          style: TextStyle(fontFamily: 'Cairo'),
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          'هل أنت متأكد من إلغاء تكرار المهمة "$taskTitle"؟\n\nسيتم الاحتفاظ بالمهام المنشأة مسبقاً ولكن لن يتم إنشاء مهام جديدة.',
          style: const TextStyle(fontFamily: 'Cairo'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إلغاء التكرار', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    print('🤔 User confirmation: $confirmed'); // Debug log

    if (confirmed == true) {
      print('✅ User confirmed, calling TaskService...'); // Debug log
      
      // Show loading indicator
      if (mounted) {
        _showSnackBar('جاري إلغاء التكرار...', isError: false);
      }
      
      try {
        final success = await TaskService.cancelRecurringTask(taskId: taskId);
        print('📋 TaskService result: $success'); // Debug log
        
        if (success && mounted) {
          _showSnackBar('تم إلغاء التكرار بنجاح', isError: false);
          print('🔄 Refreshing tasks list...'); // Debug log
          await _fetchRecurringTasks(); // Refresh the list
          print('✅ Tasks list refreshed'); // Debug log
        } else if (mounted) {
          _showSnackBar('فشل في إلغاء التكرار', isError: true);
          print('❌ Failed to cancel recurring task'); // Debug log
        }
      } catch (e) {
        print('💥 Exception in _cancelRecurringTask: $e'); // Debug log
        if (mounted) {
          _showSnackBar('خطأ: ${e.toString()}', isError: true);
        }
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
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
          title: Text(
            'إدارة المهام المتكررة',
            style: GoogleFonts.cairo(
              color: const Color(0xFF1E293B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              )
            : _recurringTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.repeat_rounded,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد مهام متكررة',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قم بإنشاء مهمة جديدة وفعل خيار التكرار',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchRecurringTasks,
                    color: const Color(0xFF6366F1),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _recurringTasks.length,
                      itemBuilder: (context, index) {
                        final task = _recurringTasks[index];
                        return _buildRecurringTaskCard(task);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildRecurringTaskCard(Map<String, dynamic> task) {
    final String title = task['title'] ?? 'بدون عنوان';
    final String description = task['description'] ?? '';
    final String priority = task['priority'] ?? 'عادي';
    final String recurrenceType = task['recurrence_type'] ?? 'daily';
    final int taskId = task['id'];
    final int generatedCount = task['generated_count'] ?? 0;
    final String? lastGeneratedAt = task['last_generated_at'];
    final String? nextOccurrence = task['next_occurrence'];
    final String? recurrenceEndDate = task['recurrence_end_date'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and priority
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(priority).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    priority,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: _getPriorityColor(priority),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            
            const SizedBox(height: 12),
            
            // Compact Statistics Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  // Stats Row - More compact
                  Row(
                    children: [
                      _buildCompactStatChip('عدد', generatedCount.toString(), Icons.task_alt, Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCompactStatChip('نوع', _recurrenceLabels[recurrenceType] ?? recurrenceType, Icons.repeat_rounded, const Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Compact info rows in a single row when possible
                  Row(
                    children: [
                      // Next occurrence
                      if (nextOccurrence != null) ...[
                        Expanded(
                          child: _buildInfoRow(Icons.schedule_rounded, 'القادم', _formatDate(nextOccurrence), Colors.orange[600]!),
                        ),
                        if (lastGeneratedAt != null || recurrenceEndDate != null) const SizedBox(width: 8),
                      ],
                      // Last generated or end date
                      if (lastGeneratedAt != null) ...[
                        Expanded(
                          child: _buildInfoRow(Icons.history_rounded, 'آخر', _formatDate(lastGeneratedAt), Colors.grey[600]!),
                        ),
                      ] else if (recurrenceEndDate != null) ...[
                        Expanded(
                          child: _buildInfoRow(Icons.event_busy_rounded, 'ينتهي', _formatDate(recurrenceEndDate), Colors.red[400]!),
                        ),
                      ],
                    ],
                  ),
                  // Second row for end date if both last generated and end date exist
                  if (lastGeneratedAt != null && recurrenceEndDate != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoRow(Icons.event_busy_rounded, 'ينتهي', _formatDate(recurrenceEndDate), Colors.red[400]!),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Compact Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editRecurringTask(task),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text(
                      'تعديل',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelRecurringTask(taskId, title),
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: Text(
                      'إلغاء',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  // Compact stat chip for better space usage
  Widget _buildCompactStatChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 9,
                  color: color.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Compact info row for displaying dates and status
  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 9,
                    color: color.withOpacity(0.7),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format dates
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = date.difference(now);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'الآن';
          }
          return '${difference.inMinutes} دقيقة';
        }
        return '${difference.inHours} ساعة';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} يوم';
      } else {
        return 'منذ ${difference.inDays.abs()} يوم';
      }
    } catch (e) {
      return dateString;
    }
  }

  // Method to edit recurring task
  Future<void> _editRecurringTask(Map<String, dynamic> task) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditRecurringTaskDialog(
        task: task,
        recurrenceLabels: _recurrenceLabels,
      ),
    );

    if (result != null) {
      final success = await TaskService.updateRecurringTask(
        taskId: task['id'],
        recurrenceType: result['recurrence_type'],
        recurrenceEndDate: result['recurrence_end_date'],
      );

      if (success && mounted) {
        _showSnackBar('تم تحديث إعدادات التكرار بنجاح', isError: false);
        _fetchRecurringTasks(); // Refresh the list
      } else if (mounted) {
        _showSnackBar('فشل في تحديث إعدادات التكرار', isError: true);
      }
    }
  }
}

// Dialog for editing recurring task
class _EditRecurringTaskDialog extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, String> recurrenceLabels;

  const _EditRecurringTaskDialog({
    required this.task,
    required this.recurrenceLabels,
  });

  @override
  State<_EditRecurringTaskDialog> createState() => _EditRecurringTaskDialogState();
}

class _EditRecurringTaskDialogState extends State<_EditRecurringTaskDialog> {
  late String _selectedRecurrenceType;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _selectedRecurrenceType = widget.task['recurrence_type'] ?? 'daily';
    _selectedEndDate = widget.task['recurrence_end_date'] != null 
        ? DateTime.parse(widget.task['recurrence_end_date'])
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          'تعديل إعدادات التكرار',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'نوع التكرار:',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedRecurrenceType,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: widget.recurrenceLabels.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    style: GoogleFonts.cairo(),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedRecurrenceType = value!);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'تاريخ الانتهاء (اختياري):',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedEndDate ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _selectedEndDate = date);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      _selectedEndDate != null 
                          ? '${_selectedEndDate!.day}/${_selectedEndDate!.month}/${_selectedEndDate!.year}'
                          : 'اختر تاريخ الانتهاء',
                      style: GoogleFonts.cairo(
                        color: _selectedEndDate != null ? Colors.black87 : Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    if (_selectedEndDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedEndDate = null),
                        child: Icon(Icons.clear, color: Colors.grey[600], size: 20),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop({
              'recurrence_type': _selectedRecurrenceType,
              'recurrence_end_date': _selectedEndDate,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: Text('حفظ', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}
