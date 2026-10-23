import 'package:flutter/material.dart';

import '../workspace/workspace_list_screen.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkspaceListScreen(isProjects: false);
  }
}
