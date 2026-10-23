import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/token_storage.dart';
import '../../providers/auth_provider.dart';
import '../projects/projects_screen.dart';
import '../tasks/tasks_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // =====================================================
  // THEME
  // =====================================================

  static const Color primary = Color(0xFF6155FF);
  static const Color accent = Color(0xFF938AFF);
  static const Color background = Color(0xFFF6F7FB);
  static const Color dark = Color(0xFF20243A);
  static const Color muted = Color(0xFF8990A5);
  static const Color success = Color(0xFF10A77A);
  static const Color warning = Color(0xFFF5A524);
  static const Color info = Color(0xFF3988FF);

  // =====================================================
  // STATE
  // =====================================================

  int selectedIndex = 0;

  bool isLoading = true;
  String? loadError;

  int totalProjects = 0;
  int totalTasks = 0;
  int pendingTasks = 0;
  int completedTasks = 0;
  int inProgressTasks = 0;
  int reviewTasks = 0;

  List<Map<String, dynamic>> recentTasks = [];

  final TokenStorage _storage = TokenStorage();

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  // =====================================================
  // API HELPERS
  // =====================================================

  Future<Map<String, dynamic>> _fetch(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final token = await _storage.readToken();

    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please log in again.');
    }

    final response = await _dio.get(
      path,
      queryParameters: query,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final body = response.data;

    if (body is! Map || body['success'] != true) {
      throw Exception('Unexpected API response');
    }

    return Map<String, dynamic>.from(body);
  }

  Future<int> _fetchCount(String path, {String? status}) async {
    final result = await _fetch(
      path,
      query: {'page': 1, 'limit': 1, if (status != null) 'status': status},
    );

    final pagination = result['pagination'];

    if (pagination is Map) {
      return int.tryParse('${pagination['total']}') ?? 0;
    }

    return 0;
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final results = await Future.wait([
        _fetchCount('/api/projects'),
        _fetchCount('/api/tasks'),
        _fetchCount('/api/tasks', status: 'PENDING'),
        _fetchCount('/api/tasks', status: 'IN_PROGRESS'),
        _fetchCount('/api/tasks', status: 'IN_REVIEW'),
        _fetchCount('/api/tasks', status: 'COMPLETED'),
        _fetch('/api/tasks', query: {'page': 1, 'limit': 5}),
      ]);

      if (!mounted) return;

      final recentResponse = results[6] as Map<String, dynamic>;
      final rawTasks = recentResponse['data'];

      setState(() {
        totalProjects = results[0] as int;
        totalTasks = results[1] as int;
        pendingTasks = results[2] as int;
        inProgressTasks = results[3] as int;
        reviewTasks = results[4] as int;
        completedTasks = results[5] as int;

        recentTasks = rawTasks is List
            ? rawTasks
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];

        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = _errorMessage(error);
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;

      if (data is Map && data['message'] != null) {
        return '${data['message']}';
      }

      return error.message ?? 'Unable to connect to the server';
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  // =====================================================
  // USER HELPERS
  // =====================================================

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;

    final result = '$value'.trim();

    return result.isEmpty ? fallback : result;
  }

  String _formatRole(String role) {
    return role
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;

          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'No due date';

    final date = DateTime.tryParse('$value');

    if (date == null) return 'No due date';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return success;

      case 'IN_PROGRESS':
        return info;

      case 'IN_REVIEW':
        return primary;

      case 'CANCELLED':
        return const Color(0xFFE35D6A);

      default:
        return warning;
    }
  }

  // =====================================================
  // MAIN BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};

    final firstName = _text(user['firstName'], 'Team Member');

    final lastName = _text(user['lastName']);

    final fullName = '$firstName $lastName'.trim();

    final role = _text(user['role'], 'EMPLOYEE');

    return Scaffold(
      backgroundColor: background,
      body: IndexedStack(
        index: selectedIndex,
        children: [
          _buildHome(fullName, role),
          const ProjectsScreen(),
          const TasksScreen(),
          _buildCalendar(),
          _buildProfile(user),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  // =====================================================
  // HOME
  // =====================================================

  Widget _buildHome(String name, String role) {
    return SafeArea(
      child: RefreshIndicator(
        color: primary,
        onRefresh: _loadDashboard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(name)),

            SliverToBoxAdapter(child: _buildWelcomeCard(role)),

            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: _SectionHeading(
                  title: 'Overview',
                  subtitle: 'Your workspace at a glance',
                ),
              ),
            ),

            if (isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: primary),
                  ),
                ),
              )
            else if (loadError != null)
              SliverToBoxAdapter(child: _buildError())
            else ...[
              SliverToBoxAdapter(child: _buildStats()),

              SliverToBoxAdapter(child: _buildProgressSection()),
            ],

            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 14),
                child: _SectionHeading(
                  title: 'Quick Actions',
                  subtitle: 'Access your workspace',
                ),
              ),
            ),

            SliverToBoxAdapter(child: _buildQuickActions()),

            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 14),
                child: _SectionHeading(
                  title: 'Recent Tasks',
                  subtitle: 'Latest tasks in your workspace',
                ),
              ),
            ),

            SliverToBoxAdapter(child: _buildRecentTasks()),

            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // HEADER
  // =====================================================

  Widget _buildHeader(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              'assets/images/thh_workflow_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                return const Icon(Icons.apps_rounded, color: primary, size: 28);
              },
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THH WORKFLOW',
                  style: TextStyle(
                    color: primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Hello, $name 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: dark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded, color: dark),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // WELCOME CARD
  // =====================================================

  Widget _buildWelcomeCard(String role) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatRole(role),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Your workspace,\nsimplified.',
            style: TextStyle(
              fontSize: 25,
              height: 1.2,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Manage projects, track tasks, and collaborate with your team.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // STATISTICS
  // =====================================================

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.28,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _StatCard(
            title: 'Projects',
            value: totalProjects,
            icon: Icons.folder_outlined,
            color: primary,
            onTap: () => _selectTab(1),
          ),

          _StatCard(
            title: 'Tasks',
            value: totalTasks,
            icon: Icons.task_alt_rounded,
            color: success,
            onTap: () => _selectTab(2),
          ),

          _StatCard(
            title: 'Pending',
            value: pendingTasks,
            icon: Icons.pending_actions_rounded,
            color: warning,
            onTap: () => _selectTab(2),
          ),

          _StatCard(
            title: 'Completed',
            value: completedTasks,
            icon: Icons.check_circle_outline_rounded,
            color: info,
            onTap: () => _selectTab(2),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TASK PROGRESS
  // =====================================================

  Widget _buildProgressSection() {
    final completionRate = totalTasks == 0
        ? 0.0
        : (completedTasks / totalTasks).clamp(0.0, 1.0).toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Task Completion',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: dark,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '$completedTasks of $totalTasks tasks completed',
            style: const TextStyle(fontSize: 12, color: muted),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: completionRate,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFEEEEF6),
                    color: primary,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Text(
                '${(completionRate * 100).round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusCount(
                label: 'In Progress',
                count: inProgressTasks,
                color: info,
              ),

              _StatusCount(
                label: 'In Review',
                count: reviewTasks,
                color: primary,
              ),

              _StatusCount(
                label: 'Pending',
                count: pendingTasks,
                color: warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // QUICK ACTIONS
  // =====================================================

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  title: 'Projects',
                  icon: Icons.folder_copy_outlined,
                  onTap: () => _selectTab(1),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _QuickAction(
                  title: 'Tasks',
                  icon: Icons.checklist_rounded,
                  onTap: () => _selectTab(2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  title: 'Requests',
                  icon: Icons.approval_outlined,
                  onTap: () => _showComingSoon('Requests'),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _QuickAction(
                  title: 'Calendar',
                  icon: Icons.calendar_month_outlined,
                  onTap: () => _selectTab(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // RECENT TASKS
  // =====================================================

  Widget _buildRecentTasks() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    if (loadError != null) {
      return const SizedBox.shrink();
    }

    if (recentTasks.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: muted),
            SizedBox(height: 12),
            Text(
              'No tasks available',
              style: TextStyle(fontWeight: FontWeight.w700, color: dark),
            ),
            SizedBox(height: 6),
            Text(
              'Your recent tasks will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: recentTasks.map((task) {
          final title = _text(task['title'], 'Untitled Task');

          final status = _text(task['status'], 'PENDING');

          final project = task['project'];

          final projectName = project is Map
              ? _text(project['name'], 'Project')
              : 'Project';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.task_alt_rounded, color: primary),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: dark,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        '$projectName • ${_formatDate(task['dueDate'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatRole(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // =====================================================
  // ERROR
  // =====================================================

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 40,
            ),

            const SizedBox(height: 12),

            Text(
              loadError ?? 'Unable to load dashboard',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 14),

            TextButton(
              onPressed: _loadDashboard,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // CALENDAR
  // =====================================================

  Widget _buildCalendar() {
    return const SafeArea(
      child: _EmptyFeatureScreen(
        icon: Icons.calendar_month_outlined,
        title: 'Calendar',
        subtitle: 'Calendar integration is coming next.',
      ),
    );
  }

  // =====================================================
  // PROFILE
  // =====================================================

  Widget _buildProfile(Map<String, dynamic> user) {
    final firstName = _text(user['firstName']);
    final lastName = _text(user['lastName']);
    final name = '$firstName $lastName'.trim();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'My Profile',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: dark,
            ),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: primary.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.person_rounded,
                    color: primary,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  name.isEmpty ? 'Team Member' : name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: dark,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  _text(user['email']),
                  style: const TextStyle(color: muted),
                ),

                const SizedBox(height: 10),

                _StatusCount(
                  label: _formatRole(_text(user['role'], 'EMPLOYEE')),
                  count: null,
                  color: primary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _profileRow(
                  Icons.badge_outlined,
                  'Employee Code',
                  _text(user['employeeCode'], '—'),
                ),

                const Divider(height: 26),

                _profileRow(
                  Icons.verified_user_outlined,
                  'Account Status',
                  _text(user['status'], '—'),
                ),

                const Divider(height: 26),

                _profileRow(
                  Icons.apartment_outlined,
                  'Department ID',
                  _text(user['departmentId'], '—'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => context.read<AuthProvider>().logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, color: dark),
          ),
        ),
      ],
    );
  }

  // =====================================================
  // NAVIGATION
  // =====================================================

  void _selectTab(int index) {
    setState(() {
      selectedIndex = index;
    });

    if (index == 0) {
      _loadDashboard();
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature integration is coming next.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: _selectTab,
      backgroundColor: Colors.white,
      indicatorColor: primary.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: primary),
          label: 'Home',
        ),

        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded, color: primary),
          label: 'Projects',
        ),

        NavigationDestination(
          icon: Icon(Icons.task_alt_outlined),
          selectedIcon: Icon(Icons.task_alt_rounded, color: primary),
          label: 'Tasks',
        ),

        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded, color: primary),
          label: 'Calendar',
        ),

        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: primary),
          label: 'Profile',
        ),
      ],
    );
  }
}

// =====================================================
// REUSABLE WIDGETS
// =====================================================

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF20243A),
          ),
        ),

        const SizedBox(height: 5),

        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8990A5)),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),

              const Spacer(),

              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF20243A),
                ),
              ),

              const SizedBox(height: 3),

              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8990A5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCount extends StatelessWidget {
  final String label;
  final int? count;
  final Color color;

  const _StatusCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        count == null ? label : '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 23, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: Color(0xFF6155FF), size: 29),

              const SizedBox(height: 11),

              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF20243A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeatureScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyFeatureScreen({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: const Color(0xFF6155FF)),

            const SizedBox(height: 20),

            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF20243A),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8990A5)),
            ),
          ],
        ),
      ),
    );
  }
}
