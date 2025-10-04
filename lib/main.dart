// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskaty/router/auth_router.dart';
import 'package:taskaty/pages/dashboard.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/user_Dashboard.dart';
import 'package:taskaty/auth/login.dart';

// Conditional imports for Firebase (only on mobile)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:taskaty/services/notification_service.dart';

// Global flag to track Supabase initialization
bool _supabaseInitialized = false;
bool _dotenvLoaded = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables with platform-specific handling
  if (kIsWeb) {
    // For web, skip dotenv loading - we'll use compile-time constants or platform env vars
    print('Running on web - skipping .env file loading');
  } else {
    // For mobile, load from assets/.env file
    try {
      await dotenv.load(fileName: "assets/.env");
      _dotenvLoaded = true;
      print('Successfully loaded .env file');
    } catch (e) {
      print('Failed to load .env file: $e');
      print('Will use fallback hardcoded values');
      _dotenvLoaded = false;
    }
  }

  // Initialize Firebase only on mobile platforms
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Initialize notification service
      await NotificationService.initialize();

      // Setup token refresh listener
      NotificationService.setupTokenRefreshListener();
    } catch (e) {
      print('Firebase initialization failed: $e');
    }
  }

  // Initialize Supabase
  await _initializeSupabase();

  // Listen for Supabase auth state changes and save FCM token for logged-in users
  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    final session = data.session;
    print('Auth state changed: ${data.event}');

    if (session?.user?.id != null) {
      print('User signed in: ${session!.user!.id}');

      // Wait a moment to ensure FCM token is available
      await Future.delayed(Duration(milliseconds: 500));

      // Check and ensure FCM token exists for the user
      if (!kIsWeb) {
        try {
          await NotificationService.checkAndEnsureFCMToken(session.user!.id);
          print('FCM token checked and ensured for user: ${session.user!.id}');
        } catch (e) {
          print('Failed to check/ensure FCM token: $e');
        }
      }
    } else {
      print('User signed out');
    }
  });

  runApp(MyApp());
}

// Background message handler (only used on mobile)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    // Only initialize Firebase if it hasn't been initialized yet
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Firebase might already be initialized, which is fine
      print('Firebase already initialized in background handler');
    }
    print('Handling a background message: ${message.messageId ?? "unknown"}');
  }
}

Future<void> _initializeSupabase() async {
  // Guard against multiple initializations
  if (_supabaseInitialized) {
    print('Supabase already initialized, skipping...');
    return;
  }

  String? supabaseUrl;
  String? supabaseApiKey;

  if (kIsWeb) {
    // For web builds, use compile-time constants or environment variables
    supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    supabaseApiKey = const String.fromEnvironment('SUPABASE_API_KEY');

    // Check if environment variables are provided
    if (supabaseUrl.isEmpty || supabaseApiKey.isEmpty) {
      print(
          'Environment variables not found, using hardcoded values for web...');

      // Use actual Supabase credentials for web deployment
      supabaseUrl = 'https://gbdhgvwtfbfjxoioyuiw.supabase.co';
      supabaseApiKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiZGhndnd0ZmJmanhvaW95dWl3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk1NjAyMjMsImV4cCI6MjA2NTEzNjIyM30.-al9ws0fvh5TydlKBy26pPKF6bE5oJQe_qZqj2r1X6I';
    }
  } else {
    // For mobile, try to use dotenv first, then fall back to hardcoded values
    if (_dotenvLoaded) {
      try {
        supabaseUrl = dotenv.env['SUPABASE_URL'];
        supabaseApiKey = dotenv.env['SUPABASE_API_KEY'];
        print('Using values from .env file');
      } catch (e) {
        print('Error accessing dotenv variables: $e');
        supabaseUrl = null;
        supabaseApiKey = null;
      }
    }

    // If dotenv wasn't loaded or values are null/empty, use hardcoded fallback values
    if (!_dotenvLoaded ||
        supabaseUrl == null ||
        supabaseUrl.isEmpty ||
        supabaseApiKey == null ||
        supabaseApiKey.isEmpty) {
      print('Using fallback hardcoded values for mobile...');
      supabaseUrl = 'https://gbdhgvwtfbfjxoioyuiw.supabase.co';
      supabaseApiKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiZGhndnd0ZmJmanhvaW95dWl3Iiwicm9zZSI6ImFub24iLCJpYXQiOjE3NDk1NjAyMjMsImV4cCI6MjA2NTEzNjIyM30.-al9ws0fvh5TydlKBy26pPKF6bE5oJQe_qZqj2r1X6I';
    }
  }

  if (supabaseUrl == null ||
      supabaseApiKey == null ||
      supabaseUrl.isEmpty ||
      supabaseApiKey.isEmpty) {
    throw Exception('SUPABASE_URL or SUPABASE_API_KEY is missing or empty');
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseApiKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    
    _supabaseInitialized = true;
    print('Supabase initialized successfully with URL: $supabaseUrl');
  } catch (e) {
    if (e.toString().contains('already initialized')) {
      print('Supabase was already initialized elsewhere');
      _supabaseInitialized = true;
    } else {
      print('Supabase initialization failed: $e');
      rethrow;
    }
  }
}

class FCMTokenNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Save FCM token when navigating to dashboard or user page
    final routeName = route.settings.name ?? '';
    if (routeName == '/admin/dashboard' ||
        routeName == '/admin/create-task' ||
        routeName == '/user/dashboard') {
      if (!kIsWeb) {
        try {
          NotificationService.getAndSaveFCMToken();
        } catch (e) {
          print('Failed to get and save FCM token: $e');
        }
      }
    }
    super.didPush(route, previousRoute);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taskaty',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            minimumSize: MaterialStatePropertyAll(Size(200, 40)),
          ),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      // Show LoginScreen as the home page
      home: const LoginScreen(),
      navigatorObservers: [FCMTokenNavigatorObserver()],
      routes: {
        '/login': (context) => const LoginScreen(),
        '/auth': (context) => const AuthRouter(),
        '/admin/dashboard': (context) => const DashboardPage(),
        '/admin/create-task': (context) => const AdminDashboard(),
        '/user/dashboard': (context) => const UserDashboard(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
