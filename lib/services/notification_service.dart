// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static SupabaseClient? _supabase;

  static SupabaseClient get supabase => _supabase ?? Supabase.instance.client;

  // Notification channels
  static const AndroidNotificationChannel _highImportanceChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _taskChannel =
      AndroidNotificationChannel(
    'task_notifications',
    'Task Notifications',
    description: 'Notifications for task assignments and updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize the notification service
  static Future<void> initialize() async {
    // Load environment variables
    try {
      await dotenv.load(fileName: "assets/.env");
      if (kDebugMode) print('Loaded .env from assets/.env');
    } catch (e) {
      if (kDebugMode)
        print('assets/.env not found, trying to load .env from root...');
      try {
        await dotenv.load(fileName: ".env");
        if (kDebugMode) print('Loaded .env from project root');
      } catch (e) {
        if (kDebugMode)
          print(
              '.env not found in project root, using system environment variables');
        // Optionally: dotenv.testLoad(fileInput: Platform.environment);
      }
    }

    // Initialize Supabase
    await _initializeSupabase();

    // Request permissions
    await _requestPermissions();

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Create notification channels
    await _createNotificationChannels();

    // Set up message handlers
    _setupMessageHandlers();
  }

  /// Initialize Supabase with environment variables
  static Future<void> _initializeSupabase() async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseApiKey = dotenv.env['SUPABASE_API_KEY'];

    if (supabaseUrl == null || supabaseApiKey == null) {
      throw Exception(
          'SUPABASE_URL or SUPABASE_API_KEY is missing in assets/.env');
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseApiKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    _supabase = Supabase.instance.client;
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    final NotificationSettings settings =
        await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      print('Notification permission status: ${settings.authorizationStatus}');
    }
  }

  /// Initialize local notifications
  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Create notification channels
  static Future<void> _createNotificationChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_highImportanceChannel);
      await androidPlugin.createNotificationChannel(_taskChannel);
    }
  }

  /// Setup message handlers
  static void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  /// Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Received foreground message: ${message.messageId}');

      // Handle notification content (from Firebase Console or proper notification structure)
      if (message.notification != null) {
        print('Notification Title: ${message.notification!.title}');
        print('Notification Body: ${message.notification!.body}');
        if (message.notification!.android != null) {
          print('Android notification data: ${message.notification!.android}');
        }
        if (message.notification!.apple != null) {
          print('Apple notification data: ${message.notification!.apple}');
        }
      }

      // Handle data payload (from programmatic sends or additional data)
      if (message.data.isNotEmpty) {
        print('Data payload: ${message.data}');
      } else {
        print(
            'No data payload (likely sent from Firebase Console without additional data)');
      }

      // Additional message properties
      print('Message from: ${message.from}');
      print('Message sent time: ${message.sentTime}');
      print('Message category: ${message.category}');
    }

    await showLocalNotification(message);
  }

  /// Handle notification tap
  static Future<void> _handleNotificationTap(RemoteMessage message) async {
    if (kDebugMode) {
      print('Notification tapped: ${message.messageId}');
    }

    // Handle navigation based on notification data
    // For Firebase Console notifications, check if there's any data payload
    Map<String, dynamic> navigationData = message.data;

    // If no data payload, try to extract from notification content
    if (navigationData.isEmpty && message.notification != null) {
      // Create a basic navigation data structure from notification
      navigationData = {
        'type': 'general',
        'title': message.notification!.title,
        'body': message.notification!.body,
      };
    }

    await _handleNotificationNavigation(navigationData);
  }

  /// Handle notification response when tapped
  static Future<void> _onNotificationTapped(
      NotificationResponse response) async {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        await _handleNotificationNavigation(data);
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing notification payload: $e');
        }
        // Handle as general notification if payload parsing fails
        await _handleNotificationNavigation({'type': 'general'});
      }
    }
  }

  /// Handle navigation based on notification data
  static Future<void> _handleNotificationNavigation(
      Map<String, dynamic> data) async {
    // Implement navigation logic based on notification type
    final String? notificationType = data['type'];
    final String? taskId = data['task_id'];

    switch (notificationType) {
      case 'task_assigned':
        // Navigate to task details
        print('Navigate to task: $taskId');
        break;
      case 'task_completed':
        // Navigate to completed tasks
        print('Navigate to completed tasks');
        break;
      case 'task_due_soon':
        // Navigate to task details
        print('Navigate to due task: $taskId');
        break;
      case 'general':
        // Handle general notifications (like from Firebase Console)
        print('General notification tapped');
        break;
      default:
        print('Unknown notification type: $notificationType');
    }
  }

  /// Show local notification
  static Future<void> showLocalNotification(RemoteMessage message) async {
    // Get notification type from data payload, fallback to general
    final String? notificationType = message.data['type'];
    final String channelId = _getChannelId(notificationType);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelId == 'task_notifications'
          ? 'Task Notifications'
          : 'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF2196F3),
      playSound: true,
      enableVibration: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidDetails,
    );

    // Create payload with both notification and data content
    final Map<String, dynamic> payload = {
      ...message.data,
      'type': notificationType ?? 'general',
    };

    // Add notification content to payload if available
    if (message.notification != null) {
      payload['notification_title'] = message.notification!.title;
      payload['notification_body'] = message.notification!.body;
    }

    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title ?? 'Taskaty',
      body: message.notification?.body ?? 'New notification',
      notificationDetails: platformChannelSpecifics,
      payload: jsonEncode(payload),
    );
  }

  /// Get appropriate channel ID based on notification type
  static String _getChannelId(String? notificationType) {
    switch (notificationType) {
      case 'task_assigned':
      case 'task_completed':
      case 'task_due_soon':
        return 'task_notifications';
      default:
        return 'high_importance_channel';
    }
  }

  /// Get and save FCM token
  static Future<void> getAndSaveFCMToken([String? userId]) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    // Get user id if not provided
    final uid = userId ?? supabase.auth.currentUser?.id;
    if (uid == null) return;

    // Save the token in the profiles table
    await supabase.from('profiles').update({'fcm_token': token}).eq('id', uid);
  }

  /// Check if user has FCM token, if not create and save a new one
  static Future<void> checkAndEnsureFCMToken([String? userId]) async {
    try {
      // Get user id if not provided
      final uid = userId ?? supabase.auth.currentUser?.id;
      if (uid == null) {
        if (kDebugMode) {
          print('No user logged in, cannot check FCM token');
        }
        return;
      }

      // Check if user already has an FCM token in the database
      final response = await supabase
          .from('profiles')
          .select('fcm_token')
          .eq('id', uid)
          .single();

      final existingToken = response['fcm_token'] as String?;

      if (existingToken != null && existingToken.isNotEmpty) {
        if (kDebugMode) {
          print(
              'User already has FCM token: ${existingToken.substring(0, 20)}...');
        }

        // Verify the token is still valid by getting current token
        final currentToken = await FirebaseMessaging.instance.getToken();

        // If tokens don't match, update with current token
        if (currentToken != null && currentToken != existingToken) {
          await supabase
              .from('profiles')
              .update({'fcm_token': currentToken}).eq('id', uid);

          if (kDebugMode) {
            print('Updated FCM token for user: $uid');
          }
        }
        return;
      }

      // No token exists, generate and save a new one
      if (kDebugMode) {
        print('No FCM token found for user: $uid, generating new token...');
      }

      final newToken = await FirebaseMessaging.instance.getToken();
      if (newToken != null) {
        await supabase
            .from('profiles')
            .update({'fcm_token': newToken}).eq('id', uid);

        if (kDebugMode) {
          print('New FCM token generated and saved for user: $uid');
          print('Token: ${newToken.substring(0, 20)}...');
        }
      } else {
        if (kDebugMode) {
          print('Failed to generate FCM token for user: $uid');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking/ensuring FCM token: $e');
      }

      // Fallback: try to generate and save token anyway
      try {
        final uid = userId ?? supabase.auth.currentUser?.id;
        if (uid != null) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await supabase
                .from('profiles')
                .update({'fcm_token': token}).eq('id', uid);

            if (kDebugMode) {
              print('Fallback: FCM token saved for user: $uid');
            }
          }
        }
      } catch (fallbackError) {
        if (kDebugMode) {
          print('Fallback FCM token generation also failed: $fallbackError');
        }
      }
    }
  }

  /// Save FCM token to Supabase
  static Future<void> _saveFCMToken(String token, String userId) async {
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': token}).eq('id', userId);

      if (kDebugMode) {
        print('FCM token saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving FCM token: $e');
      }
    }
  }

  /// Setup token refresh listener
  static void setupTokenRefreshListener() {
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        print('FCM Token refreshed: $newToken');
      }

      final String? currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await _saveFCMToken(newToken, currentUserId);
      }
    });
  }

  /// Delete FCM token on logout
  static Future<void> deleteFCMToken() async {
    try {
      final String? currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await supabase
            .from('profiles')
            .update({'fcm_token': null}).eq('id', currentUserId);

        if (kDebugMode) {
          print('FCM token deleted successfully');
        }
      }

      await _firebaseMessaging.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting FCM token: $e');
      }
    }
  }

  /// Send task assignment notification using Firebase HTTP v1 API
  static Future<bool> sendTaskAssignmentNotification({
    required int taskId,
    required String assignedUserId,
    required String assignedById,
    required String taskTitle,
  }) async {
    try {
      // Get recipient's FCM token
      final response = await supabase
          .from('profiles')
          .select('fcm_token, name, full_name')
          .eq('id', assignedUserId)
          .single();

      final fcmToken = response['fcm_token'] as String?;
      if (fcmToken == null) {
        if (kDebugMode) {
          print('No FCM token found for user: $assignedUserId');
        }
        return false;
      }

      // Get assigner's name from the name column first, then fallback to full_name
      final assignerResponse = await supabase
          .from('profiles')
          .select('name, full_name')
          .eq('id', assignedById)
          .single();

      final assignerName = assignerResponse['name'] as String? ??
          assignerResponse['full_name'] as String? ??
          'المدير';

      // Send notification using Firebase HTTP v1 API
      return await _sendFirebaseNotification(
        fcmToken: fcmToken,
        title: 'مهمة جديدة مُسندة إليك',
        body: 'تم تكليفك بمهمة: $taskTitle من قِبل $assignerName',
        data: {
          'type': 'task_assigned',
          'task_id': taskId.toString(),
          'task_title': taskTitle,
          'assigned_by': assignerName,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error sending task assignment notification: $e');
      }
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
      // Get recipient's FCM token
      final response = await supabase
          .from('profiles')
          .select('fcm_token, full_name')
          .eq('id', assignedUserId)
          .single();

      final fcmToken = response['fcm_token'] as String?;
      if (fcmToken == null) {
        if (kDebugMode) {
          print('No FCM token found for user: $assignedUserId');
        }
        return false;
      }

      String title = 'تحديث المهمة';
      String body = message ?? 'تم تحديث المهمة: $taskTitle';

      switch (updateType) {
        case 'completed':
          title = 'تم إكمال المهمة';
          body = 'تم إكمال المهمة: $taskTitle';
          break;
        case 'due_soon':
          title = 'موعد تسليم المهمة قريب';
          body = 'المهمة "$taskTitle" موعد تسليمها قريب';
          break;
      }

      return await _sendFirebaseNotification(
        fcmToken: fcmToken,
        title: title,
        body: body,
        data: {
          'type': updateType,
          'task_id': taskId,
          'task_title': taskTitle,
          'message': message ?? '',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error sending task update notification: $e');
      }
      return false;
    }
  }

  /// Send bulk notifications to multiple users
  static Future<bool> sendBulkNotifications({
    required List<String> userIds,
    required String title,
    required String body,
    String? notificationType,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get FCM tokens for all users
      final response = await supabase
          .from('profiles')
          .select('fcm_token')
          .inFilter('id', userIds);

      final fcmTokens = response
          .map((profile) => profile['fcm_token'] as String?)
          .where((token) => token != null)
          .cast<String>()
          .toList();

      if (fcmTokens.isEmpty) {
        if (kDebugMode) {
          print('No FCM tokens found for provided users');
        }
        return false;
      }

      // Send notifications to all tokens
      int successCount = 0;
      for (final token in fcmTokens) {
        final success = await _sendFirebaseNotification(
          fcmToken: token,
          title: title,
          body: body,
          data: {
            'type': notificationType ?? 'general',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            ...?data,
          },
        );
        if (success) successCount++;
      }

      if (kDebugMode) {
        print('Bulk notifications sent: $successCount/${fcmTokens.length}');
      }

      return successCount > 0;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending bulk notifications: $e');
      }
      return false;
    }
  }

  /// Send Firebase notification using HTTP v1 API
  static Future<bool> _sendFirebaseNotification({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final firebaseApiKey = dotenv.env['FIREBASE_API_KEY'];
      if (firebaseApiKey == null || firebaseApiKey.isEmpty) {
        if (kDebugMode) {
          print('Firebase API key not found or empty in .env file');
        }
        return false;
      }

      // Validate API key format (should start with AIza)
      if (!firebaseApiKey.startsWith('AIza')) {
        if (kDebugMode) {
          print('Invalid Firebase API key format. Should start with "AIza"');
        }
        return false;
      }

      final payload = {
        'to': fcmToken,
        'notification': {
          'title': title,
          'body': body,
          'sound': 'default',
          'badge': 1,
        },
        'data': data ?? {},
        'android': {
          'notification': {
            'channel_id': 'task_notifications',
            'priority': 'high',
            'default_sound': true,
            'default_vibrate_timings': true,
          }
        },
        'apns': {
          'payload': {
            'aps': {
              'sound': 'default',
              'badge': 1,
              'content_available': true,
            }
          }
        }
      };

      if (kDebugMode) {
        print(
            'Sending FCM notification to token: ${fcmToken.substring(0, 20)}...');
        print('Using API key: ${firebaseApiKey.substring(0, 10)}...');
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Authorization': 'key=$firebaseApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (kDebugMode) {
        print('FCM Response status: ${response.statusCode}');
        print('FCM Response headers: ${response.headers}');
      }

      // Check if response is JSON
      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.contains('application/json')) {
        if (kDebugMode) {
          print('Firebase returned non-JSON response');
          print('Response body: ${response.body.substring(0, 500)}');
        }
        return false;
      }

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (kDebugMode) {
          print('Firebase notification sent successfully');
          print('Response: $responseData');
        }

        // Check if there are any failures in the response
        if (responseData['failure'] != null && responseData['failure'] > 0) {
          if (kDebugMode) {
            print('FCM reported failures: ${responseData['results']}');
          }
          return false;
        }

        return true;
      } else {
        if (kDebugMode) {
          print('Failed to send Firebase notification: ${response.statusCode}');
          print('Response: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending Firebase notification: $e');
      }
      return false;
    }
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    final NotificationSettings settings =
        await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Get initial message (when app is opened from terminated state)
  static Future<RemoteMessage?> getInitialMessage() async {
    return await _firebaseMessaging.getInitialMessage();
  }

  /// Fetch the FCM token for the currently logged-in user from Supabase
  static Future<String?> fetchCurrentUserFCMToken() async {
    final String? userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final response = await supabase
          .from('profiles')
          .select('fcm_token')
          .eq('id', userId)
          .single();
      return response['fcm_token'] as String?;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching FCM token from Supabase: $e');
      }
      return null;
    }
  }
}

// Ensure NotificationService.initialize() is called at app startup (e.g., in main.dart).
// The onMessage handler already shows notifications immediately when a push is received.

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('Handling background message: ${message.messageId}');

    // Log both notification and data content
    if (message.notification != null) {
      print('Background notification - Title: ${message.notification!.title}');
      print('Background notification - Body: ${message.notification!.body}');
    }

    if (message.data.isNotEmpty) {
      print('Background data payload: ${message.data}');
    }
  }

  // You can handle background messages here
  // For example, update local database, show notification, etc.
  // Note: You can't update UI from background handler
}
