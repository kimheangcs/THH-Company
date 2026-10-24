import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/design/app_theme.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'providers/auth_provider.dart';
import 'features/auth/auth_screen.dart';
import 'features/workspace/workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Poppins',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final storage = TokenStorage();
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          AuthProvider(api: ApiClient(storage), storage: storage)
            ..restoreSession(),
      child: const THHWorkflowApp(),
    ),
  );
}

class THHWorkflowApp extends StatelessWidget {
  const THHWorkflowApp({super.key});
  @override
  Widget build(BuildContext context) => Consumer<AuthProvider>(
    builder: (context, auth, _) => MaterialApp(
      key: ValueKey(auth.isAuthenticated),
      title: 'THH Workflow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: auth.isRestoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : auth.isAuthenticated
          ? const WorkspaceScreen()
          : const AuthScreen(),
    ),
  );
}
