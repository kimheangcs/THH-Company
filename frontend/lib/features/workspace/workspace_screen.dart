import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/brand_widgets.dart';
import 'profile_sheet.dart';
import '../../core/network/workspace_api.dart';
import '../../providers/auth_provider.dart';
import '../shared/editor.dart';
import 'access.dart';
import 'resource_forms.dart';
import 'record_screen.dart';

String resourcePath(String kind) => switch (kind) {
  'People' => '/api/users',
  'Departments' => '/api/departments',
  'Approvals' => '/api/requests/pending-approvals',
  'Inbox' => '/api/notifications',
  'Activity' => '/api/activity-logs',
  _ => '/api/${kind.toLowerCase()}',
};
IconData destinationIcon(String name) => switch (name) {
  'Overview' => Icons.space_dashboard_outlined,
  'Projects' => Icons.folder_open_rounded,
  'Tasks' => Icons.check_circle_outline,
  'Requests' => Icons.description_outlined,
  'Approvals' => Icons.fact_check_outlined,
  'People' => Icons.people_outline,
  'Departments' => Icons.account_tree_outlined,
  'Inbox' => Icons.notifications_none_rounded,
  _ => Icons.history_rounded,
};

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String selected = 'Overview';
  int revision = 0;
  final _scaffold = GlobalKey<ScaffoldState>();
  Future<void> select(String value) async {
    await context.read<AuthProvider>().refreshProfile();
    if (mounted) setState(() => selected = value);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final access = Access(auth.user!);
    final api = WorkspaceApi(auth.api);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final content = selected == 'Overview'
            ? OverviewPanel(api: api, access: access, onSelect: select)
            : ResourcePanel(
                key: ValueKey('$selected-$revision'),
                kind: selected,
                api: api,
                access: access,
              );
        return Scaffold(
          key: _scaffold,
          drawer: wide ? null : Drawer(child: _navigation(access, auth)),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  SizedBox(width: 244, child: _navigation(access, auth)),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 32 : 8,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: AppTheme.line),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (!wide)
                              IconButton(
                                tooltip: 'Open menu',
                                onPressed: () =>
                                    _scaffold.currentState?.openDrawer(),
                                icon: const Icon(Icons.menu_rounded),
                              ),
                            Expanded(
                              child: wide
                                  ? Text(
                                      'Workspace  /  $selected',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    )
                                  : const WorkflowBrand(compact: true),
                            ),
                            IconButton(
                              tooltip: 'Notifications',
                              onPressed: () => select('Inbox'),
                              icon: FutureBuilder<Record>(
                                future: api.request(
                                  '/api/notifications/unread-count',
                                ),
                                builder: (context, snapshot) {
                                  final data = snapshot.data?['data'];
                                  final count = data is Map
                                      ? (data['unreadCount'] as num?)
                                                ?.toInt() ??
                                            0
                                      : 0;
                                  return Badge.count(
                                    count: count,
                                    isLabelVisible: count > 0,
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 2),
                            InkWell(
                              onTap: () => showWorkflowProfile(
                                context,
                                auth,
                                onNotifications: () => select('Inbox'),
                              ),
                              borderRadius: BorderRadius.circular(24),
                              child: CircleAvatar(
                                radius: 19,
                                backgroundColor: AppTheme.teal.withValues(
                                  alpha: .12,
                                ),
                                child: Text(
                                  '${auth.user?['firstName'] ?? 'U'}'
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.teal,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            if (wide) ...[
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person(auth.user),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    human(access.role),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                            ],
                            IconButton(
                              tooltip: 'Account',
                              onPressed: () => showWorkflowProfile(
                                context,
                                auth,
                                onNotifications: () => select('Inbox'),
                              ),
                              icon: const Icon(Icons.more_vert_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: WaveBackdrop(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: content,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex:
                      ['Overview', 'Tasks', 'Requests'].contains(selected)
                      ? ['Overview', 'Tasks', 'Requests'].indexOf(selected)
                      : 3,
                  onDestinationSelected: (index) {
                    if (index == 3) {
                      _scaffold.currentState?.openDrawer();
                    } else {
                      select(['Overview', 'Tasks', 'Requests'][index]);
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.check_circle_outline),
                      label: 'Tasks',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.description_outlined),
                      label: 'Requests',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      label: 'More',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _navigation(Access access, AuthProvider auth) => Material(
    color: const Color(0xFF202039),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/thh_workflow_logo.png',
                    width: 48,
                    height: 48,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${human(access.role).toUpperCase()} WORKSPACE',
              style: const TextStyle(
                color: Color(0xFFAAA4BF),
                fontSize: 10,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final name in access.destinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selected == name,
                      selectedTileColor: AppTheme.teal,
                      selectedColor: Colors.white,
                      iconColor: const Color(0xFFB9B5CF),
                      textColor: const Color(0xFFD4D0E3),
                      leading: Icon(destinationIcon(name), size: 21),
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      onTap: () {
                        select(name);
                        if (_scaffold.currentState?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: Color(0xFFBDB0FF),
                    size: 20,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'A little progress, every day.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your next great idea starts here.',
                    style: TextStyle(color: Color(0xFFAAA4BF), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class OverviewPanel extends StatefulWidget {
  final WorkspaceApi api;
  final Access access;
  final ValueChanged<String> onSelect;
  const OverviewPanel({
    super.key,
    required this.api,
    required this.access,
    required this.onSelect,
  });
  @override
  State<OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends State<OverviewPanel> {
  late Future<List<PageResult>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = Future.wait([
      widget.api.list('/api/tasks', query: {'limit': 5}),
      widget.api.list('/api/projects', query: {'limit': 1}),
      widget.api.list(
        '/api/tasks',
        query: {'status': 'IN_PROGRESS', 'limit': 1},
      ),
      widget.api.list('/api/tasks', query: {'status': 'COMPLETED', 'limit': 1}),
      widget.api.list('/api/activity-logs/my-activity', query: {'limit': 4}),
    ]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PageResult>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return FailureView(
          message: widget.api.client.errorMessage(snapshot.error!),
          retry: () => setState(load),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!, access = widget.access;
      return RefreshIndicator(
        onRefresh: () async {
          setState(load);
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final intro = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'LET’S MAKE THINGS HAPPEN',
                      style: TextStyle(
                        color: AppTheme.teal,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hello, ${access.user['firstName'] ?? 'there'}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 25, height: 1.25),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      access.admin
                          ? 'Here’s what’s moving across your company.'
                          : access.manager
                          ? 'Your team’s progress, all in one place.'
                          : 'Your work, your progress, your next step.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                        height: 1.65,
                      ),
                    ),
                  ],
                );
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: largeText
                          ? intro
                          : Row(
                              children: [
                                Expanded(flex: 6, child: intro),
                                const Expanded(
                                  flex: 4,
                                  child: BrandIllustration(
                                    'checklist',
                                    size: 144,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        tooltip: 'Refresh overview',
                        onPressed: () => setState(load),
                        icon: const Icon(Icons.refresh_rounded, size: 23),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth < 650 ? 2 : 4;
                final items = [
                  (
                    data[1].total,
                    'Projects',
                    Icons.folder_open_rounded,
                    const Color(0xFFDCCCFF),
                  ),
                  (
                    data[0].total,
                    'Tasks',
                    Icons.check_circle_outline,
                    const Color(0xFFD7E7FF),
                  ),
                  (
                    data[2].total,
                    'In progress',
                    Icons.trending_up_rounded,
                    const Color(0xFFFFE7B4),
                  ),
                  (
                    data[3].total,
                    'Completed',
                    Icons.verified_outlined,
                    const Color(0xFFCDF2E1),
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: (c.maxWidth - 12 * (columns - 1)) / columns,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0B7850CB),
                                blurRadius: 15,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Material(
                              color: Colors.white,
                              child: InkWell(
                                onTap: () => widget.onSelect(
                                  item.$2 == 'Projects' ? 'Projects' : 'Tasks',
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      right: -42,
                                      bottom: -70,
                                      child: Container(
                                        width: 140,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          color: item.$4,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  7,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: item.$4.withValues(
                                                    alpha: .4,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                ),
                                                child: Icon(
                                                  item.$3,
                                                  color: AppTheme.teal,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  item.$2,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right,
                                                size: 17,
                                                color: AppTheme.muted,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            '${item.$1}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(fontSize: 29),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            WaveBackdrop(
              strong: true,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final compact = c.maxWidth < 500;
                    final illustration = BrandIllustration(
                      'checklist',
                      size: compact ? 120 : 150,
                    );
                    final words = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Small steps.\nReal momentum.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 21 : 25,
                            fontWeight: FontWeight.w700,
                            height: 1.24,
                            letterSpacing: -.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          access.managesPeople
                              ? 'Keep your team aligned. Review work, clear approvals, and celebrate progress.'
                              : 'Focus on your next task. Share an update and keep your team moving.',
                          style: const TextStyle(
                            color: Color(0xFFF0E9FF),
                            fontSize: 10,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.teal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => widget.onSelect(
                            access.managesPeople ? 'Approvals' : 'Tasks',
                          ),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                          ),
                          iconAlignment: IconAlignment.end,
                          label: Text(
                            access.managesPeople
                                ? 'Review approvals'
                                : 'Explore my tasks',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                    return MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? words
                        : Row(
                            children: [
                              Expanded(flex: 6, child: words),
                              Expanded(flex: 4, child: illustration),
                            ],
                          );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your latest work',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onSelect('Tasks'),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (data[0].items.isEmpty)
              const EmptyView(
                title: 'A fresh start',
                message: 'Your tasks will appear here once work is assigned.',
                illustration: 'checklist',
              )
            else
              for (final task in data[0].items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RecordTile(
                    kind: 'Tasks',
                    record: task,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RecordScreen(
                            kind: 'Tasks',
                            id: task['id'],
                            api: widget.api,
                            access: access,
                          ),
                        ),
                      );
                      if (mounted) setState(load);
                    },
                  ),
                ),
            const SizedBox(height: 22),
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  if (data[4].items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Your activity will appear as you work.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ),
                  for (final log in data[4].items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, color: AppTheme.teal),
                      title: Text(
                        human(log['action']),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        dateLabel(log['createdAt']),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class ResourcePanel extends StatefulWidget {
  final String kind;
  final WorkspaceApi api;
  final Access access;
  const ResourcePanel({
    super.key,
    required this.kind,
    required this.api,
    required this.access,
  });
  @override
  State<ResourcePanel> createState() => _ResourcePanelState();
}

class _ResourcePanelState extends State<ResourcePanel> {
  late Future<PageResult> future;
  int page = 1;
  String filter = '', search = '';
  final searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String get path => widget.kind == 'Activity' && !widget.access.admin
      ? '/api/activity-logs/my-activity'
      : resourcePath(widget.kind);
  void load() {
    final paginated = !['People', 'Departments'].contains(widget.kind);
    future = widget.api.list(
      path,
      query: {
        if (paginated) 'page': page,
        if (paginated) 'limit': 20,
        if (filter.isNotEmpty)
          (widget.kind == 'Inbox' ? 'isRead' : 'status'): filter,
        if (search.isNotEmpty &&
            ['Projects', 'Tasks', 'People'].contains(widget.kind))
          'search': search,
      },
    );
  }

  Future<void> create() async {
    try {
      final fields = await resourceFields(
        widget.kind,
        widget.api,
        widget.access,
      );
      if (!mounted) return;
      final result = await showEditor(
        context,
        title: 'New ${singular(widget.kind)}',
        fields: fields,
        initial: {'priority': 'MEDIUM', 'role': 'EMPLOYEE', 'currency': 'USD'},
        save: (body) async {
          try {
            await widget.api.request(path, method: 'POST', body: body);
          } catch (e) {
            throw Exception(widget.api.client.errorMessage(e));
          }
        },
      );
      if (result != null && mounted) setState(load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.api.client.errorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ['Projects', 'Tasks', 'People'].contains(widget.kind)
        ? widget.access.managesPeople
        : widget.kind == 'Departments'
        ? widget.access.admin
        : widget.kind == 'Requests';
    final statuses = widget.kind == 'Projects'
        ? projectStatuses
        : widget.kind == 'Tasks'
        ? {
            'PENDING': 'Pending',
            'IN_PROGRESS': 'In progress',
            'IN_REVIEW': 'In review',
            'COMPLETED': 'Completed',
            'CANCELLED': 'Cancelled',
          }
        : widget.kind == 'Requests'
        ? {
            'DRAFT': 'Draft',
            'PENDING': 'Pending',
            'APPROVED': 'Approved',
            'REJECTED': 'Rejected',
            'CANCELLED': 'Cancelled',
          }
        : widget.kind == 'Inbox'
        ? {'false': 'Unread', 'true': 'Read'}
        : <String, String>{};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.kind,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          switch (widget.kind) {
                            'Projects' => 'Big ideas, moving forward.',
                            'Tasks' => 'A clear path from to-do to done.',
                            'Requests' => 'Ask, track, and keep things moving.',
                            'Approvals' =>
                              'Decisions that keep your team moving.',
                            'People' => 'Good work starts with great people.',
                            'Departments' => 'Your company, connected.',
                            'Inbox' => 'Stay in the loop.',
                            _ => 'A clear history of your workspace.',
                          },
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canCreate)
                    IconButton.filled(
                      tooltip: 'New ${singular(widget.kind)}',
                      onPressed: create,
                      icon: const Icon(Icons.add),
                    ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => setState(load),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if ([
                'Projects',
                'Tasks',
                'Requests',
                'People',
                'Departments',
              ].contains(widget.kind))
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: ['Departments', 'Requests'].contains(widget.kind)
                        ? 'Search this page'
                        : 'Search ${widget.kind.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () => setState(() {
                        search = searchController.text;
                        page = 1;
                        load();
                      }),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                  onSubmitted: (value) => setState(() {
                    search = value;
                    page = 1;
                    load();
                  }),
                ),
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in {'': 'All', ...statuses}.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: filter == entry.key,
                            onSelected: (_) => setState(() {
                              filter = entry.key;
                              page = 1;
                              load();
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (widget.kind == 'Inbox')
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => bulk(
                        'PATCH',
                        '/api/notifications/read-all',
                        'Mark all notifications read?',
                      ),
                      child: const Text('Mark all read'),
                    ),
                    TextButton(
                      onPressed: () => bulk(
                        'DELETE',
                        '/api/notifications/read',
                        'Delete all read notifications?',
                      ),
                      child: const Text('Clear read'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<PageResult>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return FailureView(
                  message: widget.api.client.errorMessage(snapshot.error!),
                  retry: () => setState(load),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final result = snapshot.data!;
              final items =
                  ['Departments', 'Requests'].contains(widget.kind) &&
                      search.isNotEmpty
                  ? result.items
                        .where(
                          (d) =>
                              '${d['name'] ?? d['title']} ${d['code'] ?? d['description'] ?? ''}'
                                  .toLowerCase()
                                  .contains(search.toLowerCase()),
                        )
                        .toList()
                  : result.items;
              return RefreshIndicator(
                onRefresh: () async {
                  setState(load);
                  await future;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Text(
                      '${result.total} ${widget.kind == 'Approvals' ? 'pending approvals' : widget.kind.toLowerCase()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      EmptyView(
                        illustration:
                            [
                              'Tasks',
                              'Projects',
                              'Departments',
                              'Approvals',
                            ].contains(widget.kind)
                            ? 'checklist'
                            : 'inbox',
                        actionLabel: canCreate
                            ? 'New ${human(singular(widget.kind))}'
                            : null,
                        onAction: canCreate ? create : null,
                        title: filter.isNotEmpty || search.isNotEmpty
                            ? 'No matches'
                            : 'You’re all caught up',
                        message: canCreate
                            ? 'Create a ${singular(widget.kind)} to get started.'
                            : 'Items will appear here when there’s something for you.',
                      ),
                    for (final record in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RecordTile(
                          kind: widget.kind,
                          record: record,
                          onTap: () async {
                            final detailKind = widget.kind == 'Approvals'
                                ? 'Requests'
                                : widget.kind;
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => RecordScreen(
                                  kind: detailKind,
                                  id: record['id'],
                                  api: widget.api,
                                  access: widget.access,
                                  initial: record,
                                ),
                              ),
                            );
                            if (mounted) setState(load);
                          },
                        ),
                      ),
                    if (result.pages > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed: page > 1
                                ? () => setState(() {
                                    page--;
                                    load();
                                  })
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('Page $page of ${result.pages}'),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: page < result.pages
                                ? () => setState(() {
                                    page++;
                                    load();
                                  })
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> bulk(String method, String path, String title) async {
    if (!await confirmAction(
      context,
      title,
      'This updates your notification inbox.',
    )) {
      return;
    }
    try {
      await widget.api.request(path, method: method);
      if (mounted) setState(load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.api.client.errorMessage(e))),
        );
      }
    }
  }
}

String singular(String kind) => switch (kind) {
  'People' => 'teammate',
  'Departments' => 'department',
  'Projects' => 'project',
  'Tasks' => 'task',
  _ => 'request',
};

class RecordTile extends StatelessWidget {
  final String kind;
  final Record record;
  final VoidCallback onTap;
  const RecordTile({
    super.key,
    required this.kind,
    required this.record,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final title =
        record['title'] ??
        record['name'] ??
        (kind == 'People' ? person(record) : human(record['action']));
    final subtitle = kind == 'Tasks'
        ? '${record['project']?['name'] ?? 'Task'} · ${dateLabel(record['dueDate'])}'
        : kind == 'People'
        ? '${human(record['role'])} · ${record['department']?['name'] ?? 'No department'}'
        : kind == 'Projects'
        ? '${record['code']} · ${record['ownerDepartment']?['name'] ?? ''}'
        : kind == 'Inbox'
        ? '${record['message']}'
        : kind == 'Activity'
        ? '${human(record['entityType'])} · ${dateLabel(record['createdAt'])}'
        : kind == 'Departments'
        ? '${record['code']} · ${record['manager'] != null ? person(record['manager'] as Map) : 'No manager'}'
        : '${human(record['type'])} · ${dateLabel(record['createdAt'])}';
    return Material(
      color: const Color(0xFFFEFCFF),
      elevation: 2,
      shadowColor: const Color(0x177850CB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.teal.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      destinationIcon(kind),
                      color: AppTheme.teal,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$title',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: AppTheme.muted,
                    size: 20,
                  ),
                ],
              ),
              if (record['status'] != null || kind == 'Tasks')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      if (record['status'] != null)
                        StatusPill('${record['status']}'),
                      const Spacer(),
                      if (record['priority'] != null)
                        Text(
                          human(record['priority']),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      if (kind == 'Tasks') ...[
                        const SizedBox(width: 12),
                        Text(
                          '${record['progress'] ?? 0}%',
                          style: const TextStyle(
                            color: AppTheme.teal,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (kind == 'Tasks')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(
                    value: ((record['progress'] as num? ?? 0) / 100).clamp(
                      0,
                      1,
                    ),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: AppTheme.line,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String title, message, illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyView({
    super.key,
    required this.title,
    required this.message,
    this.illustration = 'inbox',
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Surface(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
    child: Column(
      children: [
        BrandIllustration(illustration, size: 132),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        if (onAction != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              actionLabel ?? 'Create',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    ),
  );
}

class FailureView extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const FailureView({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42, color: AppTheme.muted),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
