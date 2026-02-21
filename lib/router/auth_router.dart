import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/auth/login.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/user_Dashboard.dart';
import 'package:taskaty/pages/dashboard.dart';

class AuthRouter extends StatelessWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // Show loading while waiting for auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // If not authenticated, show login
          if (!snapshot.hasData ||
              snapshot.data?.event == AuthChangeEvent.signedOut) {
            return const LoginScreen();
          }

          // If authenticated, check role
          return FutureBuilder<String?>(
            future: _getUserRole(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Handle error state
              if (roleSnapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Error loading user role'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Supabase.instance.client.auth.signOut();
                        },
                        child: const Text('Back to Login'),
                      ),
                    ],
                  ),
                );
              }

              // Default to user dashboard if no specific role is found
              final role = roleSnapshot.data ?? 'user';
              return role == 'admin'
                  ? const DashboardPage() // Changed from AdminDashboard
                  : const UserDashboard();
            },
          );
        },
      ),
    );
  }

  Future<String?> _getUserRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('No user session found');
        return 'user';
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) {
        // Create profile if it doesn't exist
        await Supabase.instance.client.from('profiles').insert({
          'id': user.id,
          'email': user.email,
          'name': user.userMetadata?['full_name'] ?? user.email?.split('@')[0],
          'role': 'user',
          'avatar_url': user.userMetadata?['avatar_url'],
        });
        return 'user';
      }

      debugPrint('User Role Response: $response');
      return response['role'] as String? ?? 'user';
    } catch (e) {
      debugPrint('Error fetching user role: $e');
      return 'user';
    }
  }
}
