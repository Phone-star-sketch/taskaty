import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/services/notification_service.dart';
import 'package:flutter/foundation.dart';

class TaskService {
  static final _supabase = Supabase.instance.client;

  /// Assign a task to a user
  static Future<bool> assignTask({
    required int taskId,
    required String assignedUserId,
    required String taskTitle,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Insert into task_assignments table
      await _supabase
          .from('task_assignments')
          .insert({
            'task_id': taskId,
            'user_id': assignedUserId,
            'assigned_by': currentUser.id,
            'assigned_at': DateTime.now().toIso8601String(),
            'status': 'pending',
          } as Map<String, Object>);

      // Update task status
      await _supabase
          .from('tasks')
          .update({
            'status': 'assigned',
            'assigned_user_id': assignedUserId,
            'assigned_at': DateTime.now().toIso8601String(),
          } as Map<String, Object>)
          .eq('id', taskId);

      // Send notification
      await NotificationService.sendTaskAssignmentNotification(
        taskId: taskId,
        assignedUserId: assignedUserId,
        assignedById: currentUser.id,
        taskTitle: taskTitle,
      );

      if (kDebugMode) {
        print('Task assigned successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error assigning task: $e');
      }
      return false;
    }
  }

  /// Complete a task
  static Future<bool> completeTask({
    required String taskId,
    required String taskTitle,
    String? completionNotes,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Update task status
      await _supabase
          .from('tasks')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'completion_notes': completionNotes,
          } as Map<String, Object>)
          .eq('id', taskId);

      // Update task assignment status
      await _supabase
          .from('task_assignments')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          } as Map<String, Object>)
          .eq('task_id', taskId)
          .eq('user_id', currentUser.id);

      // Get task details to notify admin/creator
      final taskData = await _supabase
          .from('tasks')
          .select('created_by, assigned_user_id')
          .eq('id', taskId)
          .single();

      if (taskData != null) {
        final createdBy = taskData['created_by'];
        if (createdBy != null && createdBy != currentUser.id) {
          await NotificationService.sendTaskUpdateNotification(
            taskId: taskId,
            taskTitle: taskTitle,
            assignedUserId: createdBy,
            updateType: 'completed',
            message: 'تم إكمال المهمة بنجاح',
          );
        }
      }

      if (kDebugMode) {
        print('Task completed successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error completing task: $e');
      }
      return false;
    }
  }

  /// Update task status
  static Future<bool> updateTaskStatus({
    required String taskId,
    required String taskTitle,
    required String newStatus,
    String? updateNotes,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Update task status
      await _supabase
          .from('tasks')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
            'update_notes': updateNotes,
          } as Map<String, Object>)
          .eq('id', taskId);

      // Get task details to notify relevant users
      final taskData = await _supabase
          .from('tasks')
          .select('created_by, assigned_user_id')
          .eq('id', taskId)
          .single();

      if (taskData != null) {
        final createdBy = taskData['created_by'];
        final assignedUserId = taskData['assigned_user_id'];
        
        // Notify creator if current user is not the creator
        if (createdBy != null && createdBy != currentUser.id) {
          await NotificationService.sendTaskUpdateNotification(
            taskId: taskId,
            taskTitle: taskTitle,
            assignedUserId: createdBy,
            updateType: 'updated',
            message: 'تم تحديث حالة المهمة إلى: $newStatus',
          );
        }
        
        // Notify assigned user if current user is not the assigned user
        if (assignedUserId != null && assignedUserId != currentUser.id) {
          await NotificationService.sendTaskUpdateNotification(
            taskId: taskId,
            taskTitle: taskTitle,
            assignedUserId: assignedUserId,
            updateType: 'updated',
            message: 'تم تحديث حالة المهمة إلى: $newStatus',
          );
        }
      }

      if (kDebugMode) {
        print('Task status updated successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating task status: $e');
      }
      return false;
    }
  }

  /// Get all tasks for the current user
  static Future<List<Map<String, dynamic>>> getUserTasks() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return [];
      }

      final response = await _supabase
          .from('tasks')
          .select('*, task_assignments!inner(*)')
          .eq('task_assignments.user_id', currentUser.id)
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print('Fetched ${response.length} tasks for user');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user tasks: $e');
      }
      return [];
    }
  }

  /// Get all tasks (admin view)
  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    try {
      final response = await _supabase
          .from('tasks')
          .select('*, task_assignments(*), profiles!tasks_created_by_fkey(*)')
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print('Fetched ${response.length} total tasks');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all tasks: $e');
      }
      return [];
    }
  }

  /// Create a new task
  static Future<bool> createTask({
    required String title,
    required String description,
    required DateTime dueDate,
    required String priority,
    String? assignedUserId,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Insert task
      final taskResponse = await _supabase
          .from('tasks')
          .insert({
            'title': title,
            'description': description,
            'due_date': dueDate.toIso8601String(),
            'priority': priority,
            'status': assignedUserId != null ? 'assigned' : 'pending',
            'created_by': currentUser.id,
            'assigned_user_id': assignedUserId,
            'created_at': DateTime.now().toIso8601String(),
          } as Map<String, Object>)
          .select()
          .single();

      final taskId = taskResponse['id'];

      // If task is assigned, create assignment record and send notification
      if (assignedUserId != null) {
        await _supabase
            .from('task_assignments')
            .insert({
              'task_id': taskId,
              'user_id': assignedUserId,
              'assigned_by': currentUser.id,
              'assigned_at': DateTime.now().toIso8601String(),
              'status': 'pending',
            } as Map<String, Object>);

        // Send notification
        await NotificationService.sendTaskAssignmentNotification(
          taskId: taskId,
          assignedUserId: assignedUserId,
          assignedById: currentUser.id,
          taskTitle: title,
        );
      }

      if (kDebugMode) {
        print('Task created successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating task: $e');
      }
      return false;
    }
  }

  /// Delete a task
  static Future<bool> deleteTask({required int taskId}) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Delete task assignments first
      await _supabase
          .from('task_assignments')
          .delete()
          .eq('task_id', taskId);

      // Delete the task
      await _supabase
          .from('tasks')
          .delete()
          .eq('id', taskId);

      if (kDebugMode) {
        print('Task deleted successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting task: $e');
      }
      return false;
    }
  }

  /// Check for due tasks and send notifications
  static Future<void> checkDueTasks() async {
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = tomorrow.toIso8601String().split('T')[0];

      // Get tasks due tomorrow
      final dueTasks = await _supabase
          .from('tasks')
          .select('*, task_assignments(*)')
          .eq('status', 'assigned')
          .gte('due_date', '${tomorrowStr}T00:00:00')
          .lt('due_date', '${tomorrowStr}T23:59:59');

      for (final task in dueTasks) {
        final assignments = task['task_assignments'] as List?;
        if (assignments != null && assignments.isNotEmpty) {
          for (final assignment in assignments) {
            if (assignment['status'] == 'pending') {
              await NotificationService.sendTaskUpdateNotification(
                taskId: task['id'].toString(),
                taskTitle: task['title'],
                assignedUserId: assignment['user_id'],
                updateType: 'due_soon',
                message: 'المهمة مستحقة غداً',
              );
            }
          }
        }
      }

      if (kDebugMode) {
        print('Due task notifications sent for ${dueTasks.length} tasks');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking due tasks: $e');
      }
    }
  }

  /// Get task statistics
  static Future<Map<String, int>> getTaskStatistics() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        return {};
      }

      final isAdmin = currentUser.userMetadata?['role'] == 'admin';
      String query = 'tasks';
      Map<String, Object> filter = {};

      if (!isAdmin) {
        query = 'task_assignments';
        filter = {'user_id': currentUser.id};
      }

      final response = await _supabase
          .from(query)
          .select('status')
          .match(filter);

      final stats = <String, int>{
        'total': 0,
        'pending': 0,
        'assigned': 0,
        'in_progress': 0,
        'completed': 0,
      };

      for (final item in response) {
        final status = item['status'] as String;
        stats['total'] = (stats['total'] ?? 0) + 1;
        stats[status] = (stats[status] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting task statistics: $e');
      }
      return {};
    }
  }

  /// Get user's task assignments
  static Future<List<Map<String, dynamic>>> getUserTaskAssignments() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        return [];
      }

      final response = await _supabase
          .from('task_assignments')
          .select('*, tasks(*)')
          .eq('user_id', currentUser.id)
          .order('assigned_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching task assignments: $e');
      }
      return [];
    }
  }

  /// Send reminder notifications for overdue tasks
  static Future<void> sendOverdueReminders() async {
    try {
      final now = DateTime.now();
      final todayStr = now.toIso8601String().split('T')[0];

      // Get overdue tasks
      final overdueTasks = await _supabase
          .from('tasks')
          .select('*, task_assignments(*)')
          .eq('status', 'assigned')
          .lt('due_date', '${todayStr}T00:00:00');

      for (final task in overdueTasks) {
        final assignments = task['task_assignments'] as List?;
        if (assignments != null && assignments.isNotEmpty) {
          for (final assignment in assignments) {
            if (assignment['status'] == 'pending') {
              await NotificationService.sendTaskUpdateNotification(
                taskId: task['id'].toString(),
                taskTitle: task['title'],
                assignedUserId: assignment['user_id'],
                updateType: 'overdue',
                message: 'المهمة متأخرة عن موعد التسليم',
              );
            }
          }
        }
      }

      if (kDebugMode) {
        print('Overdue reminders sent for ${overdueTasks.length} tasks');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending overdue reminders: $e');
      }
    }
  }

  /// Cancel recurring task
  static Future<bool> cancelRecurringTask({required int taskId}) async {
    try {
      print('🔧 TaskService: Starting cancelRecurringTask for taskId: $taskId');
      
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('❌ TaskService: No authenticated user');
        return false;
      }
      
      print('✅ TaskService: User authenticated: ${currentUser.id}');

      // First, check if the task exists and user has permission
      print('🔍 TaskService: Checking if task exists and user has permission...');
      final existingTask = await _supabase
          .from('tasks')
          .select('id, title, created_by, is_recurring')
          .eq('id', taskId)
          .maybeSingle();
          
      print('📋 TaskService: Existing task data: $existingTask');
      
      if (existingTask == null) {
        print('❌ TaskService: Task not found or no permission to access');
        return false;
      }
      
      if (existingTask['is_recurring'] == false) {
        print('⚠️ TaskService: Task is already not recurring');
        return true; // Consider it successful since it's already in desired state
      }

      // Update task to stop recurring
      print('📝 TaskService: Updating task $taskId in database...');
      final response = await _supabase
          .from('tasks')
          .update({
            'is_recurring': false,
            'recurrence_type': null,
          })
          .eq('id', taskId)
          .select(); // Add select to get the updated row back

      print('📊 TaskService: Database response: $response');
      
      if (response.isEmpty) {
        print('⚠️ TaskService: No rows were updated. Task might not exist or user has no permission.');
        return false;
      }

      print('✅ TaskService: Task recurring cancelled successfully');
      return true;
    } catch (e) {
      print('💥 TaskService: Error cancelling recurring task: $e');
      print('🔍 TaskService: Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        print('🔍 TaskService: Postgrest error details: ${e.details}');
        print('🔍 TaskService: Postgrest error message: ${e.message}');
      }
      return false;
    }
  }

  /// Get recurring tasks with detailed stats
  static Future<List<Map<String, dynamic>>> getRecurringTasks() async {
    try {
      final response = await _supabase
          .from('tasks')
          .select('*, profiles!tasks_created_by_fkey(*)')
          .eq('is_recurring', true)
          .order('created_at', ascending: false);

      // Get stats for each recurring task
      List<Map<String, dynamic>> tasksWithStats = [];
      
      for (var task in response) {
        final taskId = task['id'];
        
        // Count generated tasks
        final generatedTasks = await _supabase
            .from('tasks')
            .select('id')
            .eq('parent_task_id', taskId);
            
        // Get last generated task
        final lastGenerated = await _supabase
            .from('tasks')
            .select('created_at')
            .eq('parent_task_id', taskId)
            .order('created_at', ascending: false)
            .limit(1);
            
        // Calculate next occurrence
        final nextOccurrence = _calculateNextOccurrence(
          task['recurrence_type'],
          DateTime.parse(task['created_at']),
          lastGenerated.isNotEmpty 
              ? DateTime.parse(lastGenerated[0]['created_at'])
              : null,
        );
        
        // Add stats to task
        Map<String, dynamic> taskWithStats = Map<String, dynamic>.from(task);
        taskWithStats['generated_count'] = generatedTasks.length;
        taskWithStats['last_generated_at'] = lastGenerated.isNotEmpty 
            ? lastGenerated[0]['created_at'] 
            : null;
        taskWithStats['next_occurrence'] = nextOccurrence?.toIso8601String();
        
        tasksWithStats.add(taskWithStats);
      }

      if (kDebugMode) {
        print('Fetched ${tasksWithStats.length} recurring tasks with stats');
      }
      
      return tasksWithStats;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching recurring tasks: $e');
      }
      return [];
    }
  }
  
  /// Calculate next occurrence based on recurrence type
  static DateTime? _calculateNextOccurrence(
    String? recurrenceType,
    DateTime createdAt,
    DateTime? lastGenerated,
  ) {
    if (recurrenceType == null) return null;
    
    DateTime baseDate = lastGenerated ?? createdAt;
    DateTime now = DateTime.now();
    
    switch (recurrenceType) {
      case 'every_minute':
        DateTime next = baseDate.add(const Duration(minutes: 1));
        return next.isAfter(now) ? next : now.add(const Duration(minutes: 1));
        
      case 'daily':
        DateTime next = DateTime(baseDate.year, baseDate.month, baseDate.day + 1);
        while (next.isBefore(now)) {
          next = next.add(const Duration(days: 1));
        }
        return next;
        
      case 'weekly':
        DateTime next = baseDate.add(const Duration(days: 7));
        while (next.isBefore(now)) {
          next = next.add(const Duration(days: 7));
        }
        return next;
        
      case 'monthly':
        DateTime next = DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
        while (next.isBefore(now)) {
          next = DateTime(next.year, next.month + 1, next.day);
        }
        return next;
        
      default:
        return null;
    }
  }

  /// Update recurring task settings
  static Future<bool> updateRecurringTask({
    required int taskId,
    required String recurrenceType,
    DateTime? recurrenceEndDate,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('No authenticated user');
        }
        return false;
      }

      // Update task recurring settings
      await _supabase
          .from('tasks')
          .update({
            'recurrence_type': recurrenceType,
            'recurrence_end_date': recurrenceEndDate?.toIso8601String(),
          } as Map<String, Object>)
          .eq('id', taskId);

      if (kDebugMode) {
        print('Task recurring settings updated successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating recurring task: $e');
      }
      return false;
    }
  }
}