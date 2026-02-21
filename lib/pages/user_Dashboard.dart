import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'task_calendar.dart';
import 'user_card.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard>
    with TickerProviderStateMixin {
  // Constants
  static const double _headerExpandedHeight = 240.0;
  static const double _userAvatarRadius = 28.0;
  static const double _paddingLarge = 20.0;
  static const double _paddingMedium = 16.0;
  static const double _paddingSmall = 8.0;
  static const Duration _animationDuration = Duration(milliseconds: 1200);
  static const Duration _shortAnimationDuration = Duration(milliseconds: 400);

  // State variables
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = false;
  String _selectedFilter = 'اليوم';
  Map<String, dynamic>? _userProfile;

  // Animation controllers
  late AnimationController _animationController;
  late AnimationController _headerAnimationController;
  late AnimationController _calendarAnimationController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _calendarSlideAnimation;

  // Calendar state
  bool _isCalendarVisible = false;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  final List<String> _filterOptions = [
    'الكل',
    'أمس',
    'اليوم',
    'غداً',
    'قيد التنفيذ',
    'تم التنفيذ',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTasks();
      _fetchUserProfile();
    });
  }

  void _initializeAnimations() {
    // Initialize animation controllers
    _animationController = AnimationController(
      duration: _animationDuration,
      vsync: this,
    );

    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _calendarAnimationController = AnimationController(
      duration: _shortAnimationDuration,
      vsync: this,
    );

    // Initialize animations
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _calendarSlideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _calendarAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Start header animation
    _headerAnimationController.forward();
  }

  @override
  void dispose() {
    _calendarAnimationController.dispose();
    _headerAnimationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response =
          await Supabase.instance.client.from('task_assignments').select('''
            id,
            status,
            created_at,
            end_at,
            task_id,
            task:tasks (
              id,
              title,
              description,
              priority,
              status,
              created_at,
              end_at,
              creator:profiles!created_by (
                name,
                avatar_url
              )
            )
          ''').eq('user_id', userId).order('created_at', ascending: false);

      if (!mounted) return;

      // Process unique tasks
      final Map<int, Map<String, dynamic>> uniqueTasks = {};
      for (final assignment in response) {
        final taskData = assignment['task'] as Map<String, dynamic>?;
        if (taskData != null) {
          final taskId = taskData['id'] as int;
          if (!uniqueTasks.containsKey(taskId)) {
            uniqueTasks[taskId] = assignment;
          } else {
            final existingDate =
                DateTime.tryParse(uniqueTasks[taskId]!['created_at'] ?? '');
            final currentDate =
                DateTime.tryParse(assignment['created_at'] ?? '');
            if (currentDate != null &&
                existingDate != null &&
                currentDate.isAfter(existingDate)) {
              uniqueTasks[taskId] = assignment;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _tasks = uniqueTasks.values.toList();
        });

        // Trigger animations
        await _animationController.forward();
      }
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      if (mounted) {
        _showSnackBar('خطأ في جلب المهام: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchUserProfile() async {
    if (!mounted) return;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select('name, avatar_url, role')
          .eq('id', userId)
          .single();

      if (mounted && response != null) {
        setState(() {
          _userProfile = response;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: _paddingSmall),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(_paddingMedium),
      ),
    );
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'in_progress':
      case 'pending':
        return 'قيد التنفيذ';
      case 'completed':
        return 'تم التنفيذ';
      case 'new':
        return 'جديد';
      default:
        return 'قيد التنفيذ';
    }
  }

  void _toggleCalendarVisibility() {
    setState(() {
      _isCalendarVisible = !_isCalendarVisible;
    });

    if (_isCalendarVisible) {
      _calendarAnimationController.forward();
    } else {
      _calendarAnimationController.reverse();
    }
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedFilter = 'الكل'; // Reset filter when day is selected
      });
    }
  }

  void _onFormatChanged(CalendarFormat format) {
    if (_calendarFormat != format) {
      setState(() {
        _calendarFormat = format;
      });
    }
  }

  void _onPageChanged(DateTime focusedDay) {
    setState(() {
      _focusedDay = focusedDay;
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _tasks.where((task) {
      final taskData = task['task'] as Map<String, dynamic>;
      final endDateStr = taskData['end_at'] as String?;
      if (endDateStr == null) return false;
      final endDate = DateTime.tryParse(endDateStr);
      return endDate != null && isSameDay(endDate, day);
    }).toList();
  }

  List<Map<String, dynamic>> _getFilteredTasks() {
    List<Map<String, dynamic>> filtered = List.from(_tasks);

    // Apply calendar day filter first if selected
    if (_selectedDay != null) {
      filtered = filtered.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final endDateStr = taskData['end_at'] as String?;
        if (endDateStr == null) return false;
        final endDate = DateTime.tryParse(endDateStr);
        return endDate != null && isSameDay(endDate, _selectedDay!);
      }).toList();
      return filtered; // Return early for calendar selection
    }

    // Apply date filter
    if (_selectedFilter == 'أمس' ||
        _selectedFilter == 'اليوم' ||
        _selectedFilter == 'غداً') {
      final DateTime now = DateTime.now();
      late DateTime targetDate;

      switch (_selectedFilter) {
        case 'أمس':
          targetDate = now.subtract(const Duration(days: 1));
          break;
        case 'اليوم':
          targetDate = now;
          break;
        case 'غداً':
          targetDate = now.add(const Duration(days: 1));
          break;
      }

      filtered = filtered.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final endDateStr = taskData['end_at'] as String?;
        if (endDateStr == null) return false;
        final endDate = DateTime.tryParse(endDateStr);
        if (endDate == null) return false;

        return endDate.year == targetDate.year &&
            endDate.month == targetDate.month &&
            endDate.day == targetDate.day;
      }).toList();
    }
    // Apply status filter
    else if (_selectedFilter != 'الكل') {
      filtered = filtered.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final status = taskData['status'] ?? task['status'] ?? 'new';

        if (_selectedFilter == 'قيد التنفيذ') {
          return status == 'in_progress' ||
              status == 'pending' ||
              status == 'new';
        } else if (_selectedFilter == 'تم التنفيذ') {
          return status == 'completed';
        }

        return false;
      }).toList();
    }

    return filtered;
  }

  // Task statistics calculation methods
  int get _totalTasks => _tasks.length;

  int get _completedTasks => _tasks.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final status = taskData['status'] ?? task['status'] ?? 'new';
        return status == 'completed';
      }).length;

  int get _inProgressTasks => _tasks.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final status = taskData['status'] ?? task['status'] ?? 'new';
        return status == 'in_progress' ||
            status == 'pending' ||
            status == 'new';
      }).length;

  int get _overdueTasks => _tasks.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        final status = taskData['status'] ?? task['status'] ?? 'new';
        final endDateStr = taskData['end_at'] as String?;
        if (endDateStr != null && status != 'completed') {
          final endDate = DateTime.tryParse(endDateStr);
          return endDate != null && DateTime.now().isAfter(endDate);
        }
        return false;
      }).length;

  int get _highPriorityTasks => _tasks.where((task) {
        final taskData = task['task'] as Map<String, dynamic>;
        return taskData['priority'] == 'عالية';
      }).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filteredTasks = _getFilteredTasks();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: RefreshIndicator(
          onRefresh: () async {
            await _fetchTasks();
            await _fetchUserProfile();
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildModernAppBar(colorScheme, theme),
              _buildCalendarSection(),
              _buildFilterSection(colorScheme, theme),
              _buildTasksList(filteredTasks, colorScheme, theme),
            ],
          ),
        ),
        floatingActionButton: _buildFloatingActionButton(colorScheme),
      ),
    );
  }

  Widget _buildModernAppBar(ColorScheme colorScheme, ThemeData theme) {
    return SliverAppBar(
      expandedHeight: _headerExpandedHeight,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: AnimatedBuilder(
          animation: _headerAnimationController,
          builder: (context, child) => Transform.scale(
            scale: 0.8 + (_headerAnimationController.value * 0.2),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.8),
                    colorScheme.secondary,
                    colorScheme.tertiary,
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.4),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(_paddingMedium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FadeTransition(
                            opacity: _headerAnimationController,
                            child: _buildUserHeader(theme),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.5),
                            end: Offset.zero,
                          ).animate(_headerAnimationController),
                          child: _buildQuickStats(colorScheme, theme),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isCalendarVisible
                ? Icons.calendar_today
                : Icons.calendar_today_outlined,
            color: Colors.white,
            size: 28,
          ),
          onPressed: _toggleCalendarVisibility,
        ),
        const SizedBox(width: _paddingSmall),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 28),
          onPressed: () async {
            try {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            } catch (e) {
              if (mounted) {
                _showSnackBar('خطأ في تسجيل الخروج', isError: true);
              }
            }
          },
        ),
        const SizedBox(width: _paddingMedium),
      ],
    );
  }

  Widget _buildUserHeader(ThemeData theme) {
    return Row(
      children: [
        Hero(
          tag: 'user_avatar',
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: _userAvatarRadius,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage: _userProfile?['avatar_url'] != null
                  ? NetworkImage(_userProfile!['avatar_url'])
                  : null,
              child: _userProfile?['avatar_url'] == null
                  ? const Icon(Icons.person, color: Colors.white, size: 32)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: _paddingMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'مرحباً بعودتك',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _userProfile?['name'] ?? 'المستخدم',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  'لوحة المهام الشخصية',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            _fetchTasks();
            _fetchUserProfile();
          },
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(ColorScheme colorScheme, ThemeData theme) {
    return Row(
      children: [
        _buildQuickStatCard(
          'المهام',
          '$_totalTasks',
          Icons.assignment_rounded,
          Colors.white,
        ),
        const SizedBox(width: _paddingSmall),
        _buildQuickStatCard(
          'مكتملة',
          '$_completedTasks',
          Icons.check_circle_rounded,
          Colors.green.shade400,
        ),
        const SizedBox(width: _paddingSmall),
        _buildQuickStatCard(
          'متأخرة',
          '$_overdueTasks',
          Icons.warning_rounded,
          Colors.orange.shade400,
        ),
      ],
    );
  }

  Widget _buildQuickStatCard(
      String title, String value, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection() {
    return SliverToBoxAdapter(
      child: AnimatedBuilder(
        animation: _calendarSlideAnimation,
        builder: (context, child) {
          if (!_isCalendarVisible && _calendarSlideAnimation.value == 0.0) {
            return const SizedBox.shrink();
          }

          return SizeTransition(
            sizeFactor: _calendarSlideAnimation,
            child: FadeTransition(
              opacity: _calendarSlideAnimation,
              child: TaskCalendar(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                calendarFormat: _calendarFormat,
                onDaySelected: _onDaySelected,
                onFormatChanged: _onFormatChanged,
                onPageChanged: _onPageChanged,
                eventLoader: _getEventsForDay,
                animation: _calendarSlideAnimation,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterSection(ColorScheme colorScheme, ThemeData theme) {
    return SliverToBoxAdapter(
      child: Container(
        height: 60,
        margin: const EdgeInsets.symmetric(
          horizontal: _paddingLarge,
          vertical: _paddingSmall,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...List.generate(_filterOptions.length, (index) {
                final filter = _filterOptions[index];
                final isSelected = _selectedFilter == filter;

                Color? filterColor;
                if (filter == 'أمس') {
                  filterColor = Colors.grey;
                } else if (filter == 'اليوم') {
                  filterColor = Colors.blue;
                } else if (filter == 'غداً') {
                  filterColor = Colors.green;
                }

                return Container(
                  margin: const EdgeInsets.only(left: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(filter),
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = selected ? filter : 'اليوم';
                          if (filter == 'أمس' ||
                              filter == 'اليوم' ||
                              filter == 'غداً') {
                            _selectedDay = null;
                          }
                        });
                      },
                      backgroundColor: colorScheme.surface,
                      selectedColor: filterColor != null
                          ? filterColor.withOpacity(0.2)
                          : colorScheme.primaryContainer,
                      side: BorderSide(
                        color: isSelected
                            ? (filterColor ?? colorScheme.primary)
                            : colorScheme.outline.withOpacity(0.3),
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (filterColor ?? colorScheme.onPrimaryContainer)
                            : colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      elevation: isSelected ? 4 : 1,
                      padding: const EdgeInsets.symmetric(
                        horizontal: _paddingMedium,
                        vertical: _paddingSmall,
                      ),
                    ),
                  ),
                );
              }),
              if (_selectedFilter != 'اليوم' || _selectedDay != null)
                Container(
                  margin: const EdgeInsets.only(left: 12),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedFilter = 'اليوم';
                        _selectedDay = null;
                        _focusedDay = DateTime.now();
                      });
                    },
                    icon: const Icon(Icons.clear_all_rounded),
                    label: const Text('إعادة تعيين'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(
                        color: colorScheme.primary.withOpacity(0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
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

  Widget _buildTasksList(
    List<Map<String, dynamic>> filteredTasks,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: _paddingMedium),
              Text('جاري تحميل المهام...'),
            ],
          ),
        ),
      );
    }

    if (filteredTasks.isEmpty) {
      return SliverFillRemaining(
        child: _buildEmptyState(colorScheme, theme),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _paddingLarge),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final task = filteredTasks[index];
            return AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) => FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, 0.3 + (index * 0.1)),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _animationController,
                    curve: Interval(
                      (index * 0.1).clamp(0.0, 0.8),
                      1.0,
                      curve: Curves.easeOutBack,
                    ),
                  )),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: _paddingMedium),
                    child: UserTaskCard(
                      assignment: task,
                      onStatusUpdated: _fetchTasks,
                      onRefresh: _fetchTasks,
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: filteredTasks.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.1),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 80,
              color: colorScheme.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _getEmptyStateTitle(),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _getEmptyStateSubtitle(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _fetchTasks,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تحديث'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: _paddingMedium,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }

  String _getEmptyStateTitle() {
    switch (_selectedFilter) {
      case 'أمس':
        return 'لا توجد مهام كانت مستحقة أمس';
      case 'اليوم':
        return 'لا توجد مهام مستحقة اليوم';
      case 'غداً':
        return 'لا توجد مهام مستحقة غداً';
      case 'الكل':
        return 'لا توجد مهام معيّنة';
      default:
        return 'لا توجد مهام في هذا التصنيف';
    }
  }

  String _getEmptyStateSubtitle() {
    switch (_selectedFilter) {
      case 'أمس':
        return 'لم تكن هناك مهام مجدولة لأمس';
      case 'اليوم':
        return 'لا توجد مهام مجدولة لليوم الحالي';
      case 'غداً':
        return 'لا توجد مهام مجدولة لغداً';
      case 'الكل':
        return 'ستظهر المهام المعيّنة إليك هنا';
      default:
        return 'جرب تغيير المرشح أو تحديث القائمة';
    }
  }

  Widget _buildFloatingActionButton(ColorScheme colorScheme) {
    return FloatingActionButton.extended(
      onPressed: _fetchTasks,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('تحديث المهام'),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
