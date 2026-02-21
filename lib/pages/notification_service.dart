// lib/services/notification_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _supabase = Supabase.instance.client;

  /// Send task assignment notification
  static Future<bool> sendTaskAssignmentNotification({
    required int taskId,
    required String assignedUserId,
    required String assignedById,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'notify-task-assignment',
        body: {
          'task_id': taskId,
          'user_id': assignedUserId,
          'assigned_by_id': assignedById,
        },
      );

      if (response.status == 200) {
        print('Notification sent successfully');
        return true;
      } else {
        print('Failed to send notification: ${response.data}');
        return false;
      }
    } catch (e) {
      print('Error sending notification: $e');
      return false;
    }
  }

  /// Send task update notification
  static Future<bool> sendTaskUpdateNotification({
    required String taskId,
    required String taskTitle,
    required String assignedUserId,
    required String updateType, // 'completed', 'updated', 'due_soon'
    String? message,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'notify-task-update',
        body: {
          'task_id': taskId,
          'task_title': taskTitle,
          'assigned_user_id': assignedUserId,
          'update_type': updateType,
          'message': message,
        },
      );

      if (response.status == 200) {
        print('Update notification sent successfully');
        return true;
      } else {
        print('Failed to send update notification: ${response.data}');
        return false;
      }
    } catch (e) {
      print('Error sending update notification: $e');
      return false;
    }
  }

  /// Send bulk notifications to multiple users
  static Future<bool> sendBulkNotifications({
    required List<String> userIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-bulk-notifications',
        body: {
          'user_ids': userIds,
          'title': title,
          'body': body,
          'data': data ?? {},
        },
      );

      if (response.status == 200) {
        print('Bulk notifications sent successfully');
        return true;
      } else {
        print('Failed to send bulk notifications: ${response.data}');
        return false;
      }
    } catch (e) {
      print('Error sending bulk notifications: $e');
      return false;
    }
  }
}

// Usage example in your task assignment code:
class TaskService {
  static final _supabase = Supabase.instance.client;

  /// Assign a task to a user
  static Future<bool> assignTask({
    required int taskId,
    required String assignedUserId,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('No authenticated user');
        return false;
      }

      // Insert into task_assignments table
      final assignmentResponse = await _supabase
          .from('task_assignments')
          .insert({
            'task_id': taskId,
            'user_id': assignedUserId,
            'assigned_at': DateTime.now().toIso8601String(),
          });

      if (assignmentResponse.error != null) {
        print('Error creating task assignment: ${assignmentResponse.error}');
        return false;
      }

      // Update task status if you have a status column
      await _supabase
          .from('tasks')
          .update({
            'status': 'assigned',
            'assigned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);

      // Send notification
      await NotificationService.sendTaskAssignmentNotification(
        taskId: taskId,
        assignedUserId: assignedUserId,
        assignedById: currentUser.id,
      );

      return true;
    } catch (e) {
      print('Error assigning task: $e');
      return false;
    }
  }

  /// Complete a task
  static Future<bool> completeTask({
    required String taskId,
    required String taskTitle,
  }) async {
    try {
      // Update task status
      final response = await _supabase
          .from('tasks')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);

      if (response.error != null) {
        print('Error completing task: ${response.error}');
        return false;
      }

      // Get task details to notify admin
      final taskData = await _supabase
          .from('tasks')
          .select('assigned_user_id, created_by')
          .eq('id', taskId)
          .single();

      if (taskData != null) {
        final createdBy = taskData['created_by'];
        if (createdBy != null) {
          await NotificationService.sendTaskUpdateNotification(
            taskId: taskId,
            taskTitle: taskTitle,
            assignedUserId: createdBy,
            updateType: 'completed',
            message: 'تم إكمال المهمة بنجاح',
          );
        }
      }

      return true;
    } catch (e) {
      print('Error completing task: $e');
      return false;
    }
  }
}