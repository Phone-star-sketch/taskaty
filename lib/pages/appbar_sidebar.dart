import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/auth/signup.dart';
import 'package:taskaty/pages/all_users_display.dart';

class DashboardSidebar extends StatefulWidget {
  final VoidCallback onCalendarPressed;
  final VoidCallback onShowAllTasks;
  final VoidCallback onShowTodayTasks; // Add this parameter
  final VoidCallback onGeneratePdf;
  final VoidCallback onRefresh;
  final VoidCallback onSelectAll;
  final bool isAllSelected;
  final int selectedCount;
  final int totalTasks;
  final bool showTodayOnly; // Add this parameter

  const DashboardSidebar({
    super.key,
    required this.onCalendarPressed,
    required this.onShowAllTasks,
    required this.onShowTodayTasks, // Add this parameter
    required this.onGeneratePdf,
    required this.onRefresh,
    required this.onSelectAll,
    required this.isAllSelected,
    required this.selectedCount,
    required this.totalTasks,
    required this.showTodayOnly, // Add this parameter
  });

  @override
  State<DashboardSidebar> createState() => _DashboardSidebarState();
}

class _DashboardSidebarState extends State<DashboardSidebar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late AnimationController _backgroundController;
  late StreamController<bool> isSidebarOpenStreamController;
  late Stream<bool> isSidebarOpenStream;
  late StreamSink<bool> isSidebarOpenSink;

  final _animationDuration = const Duration(milliseconds: 400);
  bool _isOpen = false;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();

    // Main sidebar animation
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    // Pulse animation for selected count
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Background gradient animation
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    isSidebarOpenStreamController = PublishSubject<bool>();
    isSidebarOpenStream = isSidebarOpenStreamController.stream;
    isSidebarOpenSink = isSidebarOpenStreamController.sink;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _backgroundController.dispose();
    isSidebarOpenStreamController.close();
    isSidebarOpenSink.close();
    super.dispose();
  }

  void _toggleSidebar() {
    HapticFeedback.lightImpact();
    setState(() {
      _isOpen = !_isOpen;
    });

    if (_isOpen) {
      _animationController.forward();
      isSidebarOpenSink.add(true);
    } else {
      _animationController.reverse();
      isSidebarOpenSink.add(false);
    }
  }

  Widget _buildModernEdgeTrigger() {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.3,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: _toggleSidebar,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            width: _isHovering ? 50 : 45,
            height: _isHovering ? 90 : 85,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667eea),
                  const Color(0xFF764ba2),
                  const Color(0xFF1BB5FD),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.6, 1.0],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(25),
                bottomLeft: Radius.circular(25),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1BB5FD).withOpacity(0.4),
                  blurRadius: _isHovering ? 20 : 12,
                  offset: const Offset(-3, 0),
                  spreadRadius: _isHovering ? 2 : 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(-2, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated chevron
                AnimatedRotation(
                  duration: const Duration(milliseconds: 300),
                  turns: _isHovering ? 0.1 : 0.0,
                  child: Icon(
                    _isOpen
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    color: Colors.white,
                    size: _isHovering ? 24 : 22,
                  ),
                ),

                const SizedBox(height: 6),

                // Pulsing counter
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final pulseValue =
                        math.sin(_pulseController.value * math.pi * 2) * 0.3 +
                            1.0;

                    return Transform.scale(
                      scale: widget.selectedCount > 0 ? pulseValue : 1.0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: widget.selectedCount > 0
                              ? Colors.white.withOpacity(0.9)
                              : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${widget.selectedCount}',
                            style: TextStyle(
                              color: widget.selectedCount > 0
                                  ? const Color(0xFF1BB5FD)
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? iconColor,
    bool isSpecial = false,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: isSpecial
                  ? const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : isDestructive
                      ? LinearGradient(
                          colors: [
                            Colors.red.shade400.withOpacity(0.15),
                            Colors.red.shade600.withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.12),
                            Colors.white.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
              border: Border.all(
                color: isDestructive
                    ? Colors.red.shade300.withOpacity(0.3)
                    : Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                if (isSpecial)
                  BoxShadow(
                    color: const Color(0xFF667eea).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSpecial
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    tooltip,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: isSpecial ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (isSpecial)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
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
  }

  Widget _buildAnimatedStatsCard() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                Colors.white.withOpacity(0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Animated progress ring
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: Stack(
                      children: [
                        // Background circle
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Progress indicator
                        CustomPaint(
                          size: const Size(50, 50),
                          painter: ProgressRingPainter(
                            progress: widget.totalTasks > 0
                                ? widget.selectedCount / widget.totalTasks
                                : 0.0,
                            color: const Color(0xFF1BB5FD),
                          ),
                        ),
                        // Center icon
                        Center(
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            color: const Color(0xFF1BB5FD),
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Stats text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المهام المحددة',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.selectedCount} من ${widget.totalTasks}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress bar
              Container(
                width: double.infinity,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widget.totalTasks > 0
                      ? widget.selectedCount / widget.totalTasks
                      : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1BB5FD), Color(0xFF667eea)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernSidebarContent() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        return Container(
          width: 320,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                    math.sin(_backgroundController.value * math.pi * 2) * 0.5 +
                        0.5)!,
                const Color(0xFF1BB5FD),
                const Color(0xFF4facfe),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.7, 1.0],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              bottomLeft: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(-8, 0),
              ),
              BoxShadow(
                color: const Color(0xFF1BB5FD).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(-5, 0),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Enhanced Header
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 32, 24, 32),
                  child: Column(
                    children: [
                      // Top row with enhanced icon and close button
                      Row(
                        children: [
                          // Glassmorphism dashboard icon
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.25),
                                  Colors.white.withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.dashboard_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const Spacer(),
                          // Enhanced close button
                          GestureDetector(
                            onTap: _toggleSidebar,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Enhanced stats container only
                      _buildAnimatedStatsCard(),
                    ],
                  ),
                ),

                // Enhanced Actions
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _buildEnhancedActionButton(
                          icon: Icons.calendar_today_rounded,
                          onPressed: widget.onCalendarPressed,
                          tooltip: 'اختيار تاريخ',
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.today_rounded,
                          onPressed: widget.onShowTodayTasks,
                          tooltip: 'مهام اليوم',
                          isSpecial: widget.showTodayOnly,
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.view_list_rounded,
                          onPressed: widget.onShowAllTasks,
                          tooltip: 'عرض جميع المهام',
                          isSpecial: !widget.showTodayOnly,
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.people_rounded,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AllUsersDisplayPage(),
                              ),
                            );
                          },
                          tooltip: 'عرض جميع المستخدمين',
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.person_add_rounded,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignupScreen(),
                              ),
                            );
                          },
                          tooltip: 'إضافة مستخدم جديد',
                          isSpecial: true,
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          onPressed: widget.onGeneratePdf,
                          tooltip: 'تصدير تقرير PDF',
                        ),
                        _buildEnhancedActionButton(
                          icon: widget.isAllSelected && widget.totalTasks > 0
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          onPressed: widget.onSelectAll,
                          tooltip: widget.isAllSelected && widget.totalTasks > 0
                              ? 'إلغاء تحديد الكل'
                              : 'تحديد الكل',
                        ),
                        _buildEnhancedActionButton(
                          icon: Icons.refresh_rounded,
                          onPressed: widget.onRefresh,
                          tooltip: 'تحديث',
                        ),
                        const SizedBox(height: 16),
                        _buildEnhancedActionButton(
                          icon: Icons.exit_to_app_rounded,
                          onPressed: () async {
                            await Supabase.instance.client.auth.signOut();
                            if (context.mounted) {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/', (route) => false);
                            }
                          },
                          tooltip: 'تسجيل الخروج',
                          iconColor: Colors.red.shade200,
                          isDestructive: true,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Enhanced overlay with blur effect
        if (_isOpen)
          GestureDetector(
            onTap: _toggleSidebar,
            child: AnimatedContainer(
              duration: _animationDuration,
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withOpacity(0.4),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.3),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ),

        // Enhanced sidebar with spring animation
        AnimatedPositioned(
          duration: _animationDuration,
          curve: Curves.easeOutBack,
          right: _isOpen ? 0 : -320,
          top: 0,
          bottom: 0,
          child: _buildModernSidebarContent(),
        ),

        // Enhanced edge trigger
        if (!_isOpen) _buildModernEdgeTrigger(),
      ],
    );
  }
}

// Custom painter for progress ring
class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw background circle
    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
