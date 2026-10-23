import 'package:flutter/material.dart';

import '../workspace/workspace_list_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkspaceListScreen(isProjects: true);
  }
}
