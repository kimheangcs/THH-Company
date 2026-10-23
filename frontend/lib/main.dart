import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = TokenStorage();
  final api = ApiClient(storage);

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(api: api, storage: storage)..restoreSession(),
      child: const THHWorkflowApp(),
    ),
  );
}

class THHWorkflowApp extends StatelessWidget {
  const THHWorkflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THH Workflow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6155FF)),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (auth.isAuthenticated) {
            return const DashboardScreen();
          }

          if (auth.requiresEmailVerification) {
            return const EmailVerificationScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}
