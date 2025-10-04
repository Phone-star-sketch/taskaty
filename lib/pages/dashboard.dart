import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/pdf_report_generator.dart';
import 'package:taskaty/pages/task_details_page.dart';
import 'package:taskaty/pages/modern_task_card.dart' as task_card;
import 'package:table_calendar/table_calendar.dart'; // Keep this import for isSameDay
import 'package:taskaty/pages/task_calendar.dart'; // Import your new calendar widget
import 'package:collection/collection.dart'; // **ADD THIS IMPORT**
import 'package:taskaty/pages/appbar_sidebar.dart'; // Import the new Sidebar widget
import 'package:taskaty/pages/recurring_tasks_page.dart';

class DashboardPage extends StatefulWidget {
  static const route = '/admin/dashboard';
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _allTasks = [];
  Map<String, Map<String, dynamic>> _usersCache = {};
  bool _isLoading = false;
  String _selectedFilter = 'الكل';

  // Calendar related variables
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  late AnimationController _calendarAnimationController;
  late Animation<double> _calendarAnimation;

  // Task selection
  Set<int> _selectedTaskIds = {};

  List<Map<String, dynamic>> _filteredTasks = [];

  // Add new state variable for today/all filter
  bool _showTodayOnly = true;

  // Add status filter state
  String? _statusFilter;

  // Add real-time channel for tasks
  late RealtimeChannel _tasksChannel;

  @override
  void initState() {
    super.initState();
    _fetchAllTasks();
    _setupRealtimeListener(); // Add real-time listener

    _calendarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _calendarAnimation = CurvedAnimation(
      parent: _calendarAnimationController,
      curve: Curves.easeInOut,
    );
    _calendarAnimationController.forward();
  }

  @override
  void dispose() {
    _calendarAnimationController.dispose();
    _tasksChannel.unsubscribe(); // Clean up real-time listener
    super.dispose();
  }

  // Add method to setup real-time listener for tasks
  void _setupRealtimeListener() {
    _tasksChannel = Supabase.instance.client
        .channel('dashboard_tasks_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (payload) {
            if (mounted) {
              // Refresh tasks when any task is updated, inserted, or deleted
              _fetchAllTasks();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_assignments',
          callback: (payload) {
            if (mounted) {
              // Refresh tasks when assignments change
              _fetchAllTasks();
            }
          },
        )
        .subscribe();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      if (isSameDay(_selectedDay, selectedDay)) {
        // If the same day is selected again, deselect it
        _selectedDay = null;
        _applyCurrentFilter();
      } else {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _filterTasksByDate(selectedDay);
      }
    });
  }

  void _filterTasksByDate(DateTime selectedDate) {
    final startOfDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    setState(() {
      final filteredByDate = _allTasks.where((task) {
        // Ensure 'created_at' is not null before parsing
        if (task['created_at'] == null) return false;
        final createdAt = DateTime.parse(task['created_at']);
        return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
      }).toList();

      // Apply status filter if active
      final statusFiltered = _statusFilter != null
          ? filteredByDate
              .where((task) => _getTaskStatus(task) == _statusFilter)
              .toList()
          : filteredByDate;

      // Apply status-based sorting to filtered tasks
      _filteredTasks = _sortTasksByStatusPriority(statusFiltered);
    });
  }

  List<Map<String, dynamic>> _getTasksForDay(DateTime day) {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final tasksForDay = _allTasks.where((task) {
      // Ensure 'created_at' is not null before parsing
      if (task['created_at'] == null) return false;
      final createdAt = DateTime.parse(task['created_at']);
      return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
    }).toList();

    // Apply status-based sorting to tasks for the day
    return _sortTasksByStatusPriority(tasksForDay);
  }

  // Add method to sort tasks by status priority
  List<Map<String, dynamic>> _sortTasksByStatusPriority(
      List<Map<String, dynamic>> tasks) {
    final sortedTasks = List<Map<String, dynamic>>.from(tasks);

    sortedTasks.sort((a, b) {
      final statusA = a['status'] ?? 'in_progress';
      final statusB = b['status'] ?? 'in_progress';

      // Define priority order: in_progress (1), completed (2)
      int getPriority(String status) {
        switch (status) {
          case 'in_progress':
            return 1;
          case 'completed':
            return 2;
          default:
            return 1;
        }
      }

      final priorityA = getPriority(statusA);
      final priorityB = getPriority(statusB);

      // If priorities are different, sort by priority
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      // If same priority, sort by creation date (newest first)
      final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
      return dateB.compareTo(dateA);
    });

    return sortedTasks;
  }

  Future<void> _fetchAllTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasksResponse = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .order('created_at', ascending: false);

      if (tasksResponse == null) {
        setState(() {
          _allTasks = [];
          _filteredTasks = [];
          _isLoading = false;
        });
        return;
      }

      final tasks = List<Map<String, dynamic>>.from(tasksResponse);

      final assignmentsResponse =
          await Supabase.instance.client.from('task_assignments').select('*');

      final assignments = assignmentsResponse != null
          ? List<Map<String, dynamic>>.from(assignmentsResponse)
          : <Map<String, dynamic>>[];

      Set<String> userIds = {};
      for (final task in tasks) {
        if (task['created_by'] != null) {
          userIds.add(task['created_by'].toString());
        }
      }
      for (final assignment in assignments) {
        if (assignment['user_id'] != null) {
          userIds.add(assignment['user_id'].toString());
        }
      }

      _usersCache.clear();
      if (userIds.isNotEmpty) {
        final usersResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, name, avatar_url')
            .inFilter('id', userIds.toList());

        if (usersResponse != null) {
          final users = List<Map<String, dynamic>>.from(usersResponse);
          for (final user in users) {
            _usersCache[user['id'].toString()] = user;
          }
        }
      }

      final enrichedTasks = tasks.map((task) {
        final taskId = task['id'];
        final taskAssignments = assignments
            .where((assignment) => assignment['task_id'] == taskId)
            .map((assignment) {
          if (assignment['user_id'] != null) {
            assignment['assignee_profile'] =
                _usersCache[assignment['user_id'].toString()];
          }
          return assignment;
        }).toList();

        // Remove duplicate assignments for the same user
        final Map<String, Map<String, dynamic>> uniqueAssignments = {};
        for (final assignment in taskAssignments) {
          final userId = assignment['user_id']?.toString();
          if (userId != null) {
            if (!uniqueAssignments.containsKey(userId)) {
              uniqueAssignments[userId] = assignment;
            } else {
              // Keep the most recent assignment status
              final existingDate = DateTime.tryParse(
                  uniqueAssignments[userId]!['created_at'] ?? '');
              final currentDate =
                  DateTime.tryParse(assignment['created_at'] ?? '');

              if (currentDate != null &&
                  existingDate != null &&
                  currentDate.isAfter(existingDate)) {
                uniqueAssignments[userId] = assignment;
              }
            }
          }
        }

        task['task_assignments'] = uniqueAssignments.values.toList();
        if (task['created_by'] != null) {
          task['creator_profile'] = _usersCache[task['created_by'].toString()];
        }

        // Ensure task has status from tasks table (this is the key change)
        task['status'] = task['status'] ?? 'in_progress';

        return task;
      }).toList();

      if (mounted) {
        setState(() {
          // Apply status-based sorting to all tasks
          _allTasks = _sortTasksByStatusPriority(enrichedTasks);
          // Apply filter based on current state
          if (_selectedDay != null) {
            _filterTasksByDate(_selectedDay!);
          } else {
            _applyCurrentFilter();
          }
          debugPrint('Fetched Tasks: ${_allTasks.length}');
        });
      }
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب المهام: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateTaskStatus(int taskId, String status) async {
    try {
      // Update status in tasks table (primary source of truth)
      await Supabase.instance.client
          .from('tasks')
          .update({'status': status}).eq('id', taskId);

      // Also update assignment status to keep them in sync
      await Supabase.instance.client
          .from('task_assignments')
          .update({'status': status}).eq('task_id', taskId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('تم تحديث حالة المهمة إلى: ${_getStatusText(status)}'),
            backgroundColor: _getStatusColor(status),
          ),
        );
        // Real-time listener will automatically refresh the tasks
      }
    } catch (e) {
      debugPrint('Error updating task status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث حالة المهمة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generatePdfReport() async {
    final selectedTasks = (_selectedDay != null ? _filteredTasks : _allTasks)
        .where((t) => _selectedTaskIds.contains(t['id']))
        .toList();

    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تحديد المهام التي تريد تصديرها إلى PDF.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // `WidgetsFlutterBinding.ensureInitialized()` is typically called once at the very start of main()
    // and is not needed here.
    final pdfGenerator = PdfReportGenerator();
    await pdfGenerator.generateAndOpenPdf(selectedTasks);
  }

  // New method to show the calendar as a bottom sheet
  void _showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the bottom sheet to be full height
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8, // Start with 80% of the screen height
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false, // Set to false to allow initialChildSize to work
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'اختر تاريخًا',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: TaskCalendar(
                        focusedDay: _focusedDay,
                        selectedDay: _selectedDay,
                        calendarFormat: _calendarFormat,
                        onDaySelected: (day, focusedDay) {
                          _onDaySelected(day, focusedDay);
                          Navigator.pop(
                              context); // Close bottom sheet after selection
                        },
                        onFormatChanged: (format) {
                          setState(() {
                            _calendarFormat = format;
                          });
                        },
                        onPageChanged: (focusedDay) {
                          _focusedDay = focusedDay;
                        },
                        eventLoader: _getTasksForDay,
                        animation: _calendarAnimation,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // New method to handle select all functionality
  void _handleSelectAll() {
    final displayTasks = _selectedDay != null ? _filteredTasks : _allTasks;
    setState(() {
      if (_selectedTaskIds.length == displayTasks.length &&
          displayTasks.isNotEmpty) {
        _selectedTaskIds.clear();
      } else {
        _selectedTaskIds = displayTasks.map((t) => t['id'] as int).toSet();
      }
    });
  }

  // Update method to handle show all tasks
  void _handleShowAllTasks() {
    setState(() {
      _selectedDay = null;
      _showTodayOnly = false;
      _filteredTasks = _sortTasksByStatusPriority(_allTasks);
    });
  }

  // Add new method to show today's tasks
  void _handleShowTodayTasks() {
    setState(() {
      _selectedDay = null;
      _showTodayOnly = true;
      _filterTasksByToday();
    });
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    try {
      // Delete task assignments first (foreign key constraint)
      await Supabase.instance.client
          .from('task_assignments')
          .delete()
          .eq('task_id', task['id']);

      // Delete the task
      await Supabase.instance.client
          .from('tasks')
          .delete()
          .eq('id', task['id']);

      // Remove from local lists
      setState(() {
        _allTasks.removeWhere((t) => t['id'] == task['id']);
        _filteredTasks.removeWhere((t) => t['id'] == task['id']);
        _selectedTaskIds.remove(task['id']);
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المهمة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في حذف المهمة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // New method to filter tasks by status
  void _filterTasksByStatus(String? status) {
    setState(() {
      _statusFilter = status;
      _selectedTaskIds.clear(); // Clear selections when filter changes
      _applyCurrentFilter();
    });
  }

  void _applyCurrentFilter() {
    List<Map<String, dynamic>> baseTasks;

    if (_showTodayOnly) {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      baseTasks = _allTasks.where((task) {
        if (task['created_at'] == null) return false;
        final createdAt = DateTime.parse(task['created_at']);
        return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
      }).toList();
    } else {
      baseTasks = _allTasks;
    }

    // Apply status filter if active
    final statusFiltered = _statusFilter != null
        ? baseTasks
            .where((task) => _getTaskStatus(task) == _statusFilter)
            .toList()
        : baseTasks;

    setState(() {
      _filteredTasks = _sortTasksByStatusPriority(statusFiltered);
    });
  }

  void _filterTasksByToday() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final filteredByDate = _allTasks.where((task) {
      if (task['created_at'] == null) return false;
      final createdAt = DateTime.parse(task['created_at']);
      return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
    }).toList();

    // Apply status filter if active
    final statusFiltered = _statusFilter != null
        ? filteredByDate
            .where((task) => _getTaskStatus(task) == _statusFilter)
            .toList()
        : filteredByDate;

    setState(() {
      _filteredTasks = _sortTasksByStatusPriority(statusFiltered);
    });
  }

  // Add method to get task status consistently
  String _getTaskStatus(Map<String, dynamic> task) {
    return task['status'] ?? 'in_progress';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayTasks = _selectedDay != null ? _filteredTasks : _filteredTasks;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).pushNamed(AdminDashboard.route).then((_) {
                  _fetchAllTasks();
                });
              },
              icon: const Icon(Icons.add_task),
              label: const Text('إنشاء مهمة'),
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    // Changed to CustomScrollView for overall scrolling
                    slivers: [
                      SliverToBoxAdapter(
                        child:
                            _buildStatsCard(colorScheme, theme, displayTasks),
                      ),
                      // The TaskCalendar widget is now opened via a button, so it's removed from here
                      if (displayTasks.isEmpty)
                        SliverToBoxAdapter(
                          child: Center(
                            child: Container(
                              margin:
                                  const EdgeInsets.all(40), // Increased from 32
                              padding:
                                  const EdgeInsets.all(40), // Increased from 32
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(
                                    24), // Increased from 20
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 15, // Increased from 10
                                    offset:
                                        const Offset(0, 8), // Increased from 5
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _selectedDay != null
                                        ? Icons.event_busy
                                        : Icons.assignment_outlined,
                                    size: 80, // Increased from 64
                                    color: colorScheme.primary.withOpacity(0.5),
                                  ),
                                  const SizedBox(
                                      height: 24), // Increased from 16
                                  Text(
                                    _selectedDay != null
                                        ? 'لا توجد مهام في هذا اليوم'
                                        : 'لا توجد مهام حالياً',
                                    style: theme.textTheme
                                        .headlineSmall, // Keep same size for readability
                                  ),
                                  const SizedBox(
                                      height: 12), // Increased from 8
                                  Text(
                                    _selectedDay != null
                                        ? 'جرب اختيار يوم آخر من التقويم'
                                        : 'قم بإنشاء مهمة جديدة باستخدام زر إنشاء مهمة',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      // Changed from bodyMedium
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding:
                              const EdgeInsets.all(20), // Increased from 16
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 450, // Increased from 400
                              mainAxisSpacing: 20, // Increased from 16
                              crossAxisSpacing: 20, // Increased from 16
                              mainAxisExtent: 320, // Increased from 280
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= displayTasks.length) return null;
                                final task = displayTasks[index];
                                final isSelected =
                                    _selectedTaskIds.contains(task['id']);
                                return task_card.ModernTaskCard(
                                  task: task,
                                  isSelected: isSelected,
                                  onSelectionChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedTaskIds.add(task['id']);
                                      } else {
                                        _selectedTaskIds.remove(task['id']);
                                      }
                                    });
                                  },
                                  onTap: () {
                                    final assignments =
                                        task['task_assignments'];
                                    Map<String, dynamic>? assignment;

                                    if (assignments is List &&
                                        assignments.isNotEmpty) {
                                      // Explicitly cast to List<Map<String, dynamic>> for firstWhereOrNull
                                      final List<Map<String, dynamic>>
                                          typedAssignments =
                                          List<Map<String, dynamic>>.from(
                                              assignments);

                                      // Use firstWhereOrNull to find an 'in_progress' assignment
                                      assignment = typedAssignments
                                          .firstWhereOrNull((a) =>
                                              a['status'] == 'in_progress');

                                      // If no 'in_progress' assignment was found, use the first one
                                      if (assignment == null) {
                                        assignment = typedAssignments
                                            .firstOrNull; // Use firstOrNull for safety
                                      }
                                    }

                                    // Now, pass `assignment` (which can be null) to the details page
                                    Navigator.of(context)
                                        .push(
                                      MaterialPageRoute(
                                        builder: (context) => TaskDetailsPage(
                                          task: task,
                                          assignment:
                                              assignment, // This is now correctly typed as Map<String, dynamic>?
                                        ),
                                      ),
                                    )
                                        .then((_) {
                                      _fetchAllTasks();
                                    });
                                  },
                                  onDelete: _deleteTask,
                                  colorScheme: colorScheme,
                                  theme: theme,
                                );
                              },
                              childCount: displayTasks.length,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Add the sidebar overlay
          DashboardSidebar(
            onCalendarPressed: _showCalendarBottomSheet,
            onShowAllTasks: _handleShowAllTasks,
            onShowTodayTasks: _handleShowTodayTasks, // Add this line
            onGeneratePdf: _generatePdfReport,
            onRefresh: _fetchAllTasks,
            onSelectAll: _handleSelectAll,
            isAllSelected: _selectedTaskIds.length == displayTasks.length,
            selectedCount: _selectedTaskIds.length,
            totalTasks: displayTasks.length,
            showTodayOnly: _showTodayOnly, // Add this line
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color, ThemeData theme,
      {VoidCallback? onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: isActive ? Border.all(color: color, width: 2) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: isActive ? color : null,
              ),
              textAlign: TextAlign.center,
            ),
            if (onTap != null) const SizedBox(height: 4),
            if (onTap != null)
              Text(
                'انقر للتصفية',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(ColorScheme colorScheme, ThemeData theme,
      List<Map<String, dynamic>> tasks) {
    final completedTasks = _allTasks.where((task) {
      return task['status'] == 'completed';
    }).length;

    final inProgressTasks = _allTasks.where((task) {
      return task['status'] == 'in_progress' || task['status'] == null;
    }).length;

    final recurringTasks = _allTasks.where((task) {
      return task['is_recurring'] == true;
    }).length;

    return Card(
      margin: const EdgeInsets.all(20),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surface,
              colorScheme.surface.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              // Show appropriate header with clear filter option
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _selectedDay != null
                              ? 'مهام يوم ${_formatDate(_selectedDay.toString())}'
                              : _showTodayOnly
                                  ? 'مهام اليوم'
                                  : 'جميع المهام',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (_statusFilter != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _filterTasksByStatus(null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.clear, color: Colors.red, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'إلغاء التصفية',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Updated stats grid with clickable items
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  _buildStatItem(
                    'إجمالي المهام',
                    _allTasks.length.toString(),
                    Icons.assignment,
                    colorScheme.primary,
                    theme,
                    onTap: () => _filterTasksByStatus(null),
                    isActive: _statusFilter == null,
                  ),
                  _buildStatItem(
                    'قيد التنفيذ',
                    inProgressTasks.toString(),
                    Icons.pending_actions,
                    colorScheme.secondary,
                    theme,
                    onTap: () => _filterTasksByStatus('in_progress'),
                    isActive: _statusFilter == 'in_progress',
                  ),
                  _buildStatItem(
                    'تم التنفيذ',
                    completedTasks.toString(),
                    Icons.task_alt,
                    Colors.green,
                    theme,
                    onTap: () => _filterTasksByStatus('completed'),
                    isActive: _statusFilter == 'completed',
                  ),
                  _buildStatItem(
                    'المهام المتكررة',
                    recurringTasks.toString(),
                    Icons.repeat_rounded,
                    const Color(0xFF10B981),
                    theme,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RecurringTasksPage(),
                      ),
                    ),
                    isActive: false,
                  ),
                ],
              ),
              // Add status filter indicator
              if (_statusFilter != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _statusFilter == 'completed'
                        ? Colors.green.withOpacity(0.1)
                        : colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'تصفية حسب: ${_getStatusText(_statusFilter!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _statusFilter == 'completed'
                          ? Colors.green
                          : colorScheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'تاريخ غير صالح';
    }
  }

  Widget _buildUserInfo(String label, Map<String, dynamic>? user,
      ColorScheme colorScheme, ThemeData theme) {
    if (user == null) {
      return Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              color: colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                'غير محدد',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final name = user['name']?.toString() ?? 'غير معروف';
    final avatarUrl = user['avatar_url']?.toString();

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
