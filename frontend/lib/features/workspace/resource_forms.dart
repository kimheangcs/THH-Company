import '../../core/network/workspace_api.dart';
import '../shared/editor.dart';
import 'access.dart';
import '../../core/design/app_theme.dart';

const priorities = {
  'LOW': 'Low',
  'MEDIUM': 'Medium',
  'HIGH': 'High',
  'URGENT': 'Urgent',
};
const projectStatuses = {
  'PLANNED': 'Planned',
  'IN_PROGRESS': 'In progress',
  'ON_HOLD': 'On hold',
  'COMPLETED': 'Completed',
  'CANCELLED': 'Cancelled',
};

Future<List<EditField>> resourceFields(
  String kind,
  WorkspaceApi api,
  Access access, {
  Record? existing,
}) async {
  final edit = existing != null;
  Map<String, String> departments = {}, people = {}, projects = {};
  if (['Projects', 'Tasks', 'People'].contains(kind)) {
    final result = await api.list('/api/departments');
    departments = {for (final d in result.items) '${d['id']}': '${d['name']}'};
  }
  if (['Projects', 'Tasks'].contains(kind)) {
    final result = await api.list('/api/users');
    people = {
      for (final u in result.items.where(
        (u) =>
            u['status'] == 'ACTIVE' &&
            u['emailVerifiedAt'] != null &&
            (kind == 'Projects'
                ? ['ADMIN', 'MANAGER'].contains(u['role'])
                : u['role'] == 'EMPLOYEE'),
      ))
        '${u['id']}': '${person(u)} · ${human(u['role'])}',
    };
    if (kind == 'Projects') {
      people['${access.user['id']}'] = '${person(access.user)} (you)';
    }
  }
  if (kind == 'Tasks') {
    final all = <Record>[];
    var page = 1;
    while (true) {
      final result = await api.list(
        '/api/projects',
        query: {'page': page, 'limit': 100},
      );
      all.addAll(result.items);
      if (page >= result.pages) break;
      page++;
    }
    projects = {
      for (final p in all.where(
        (p) =>
            access.managesProject(p) &&
            !['COMPLETED', 'CANCELLED'].contains(p['status']),
      ))
        '${p['id']}': '${p['name']}',
    };
  }
  return switch (kind) {
    'Projects' => [
      const EditField('name', 'Project name', required: true),
      const EditField('code', 'Project code', required: true),
      const EditField('description', 'Description', multiline: true),
      const EditField('priority', 'Priority', choices: priorities),
      const EditField('status', 'Status', choices: projectStatuses),
      const EditField('startDate', 'Start date', date: true),
      const EditField('dueDate', 'Due date', date: true),
      if (!edit || access.admin) ...[
        EditField(
          'ownerDepartmentId',
          'Owning department',
          required: true,
          numeric: true,
          choices: departments,
        ),
        EditField(
          'leadManagerId',
          'Project lead',
          required: true,
          numeric: true,
          choices: people,
        ),
        EditField(
          'departmentIds',
          'Participating departments',
          multiple: true,
          numeric: true,
          choices: departments,
        ),
      ],
    ],
    'Tasks' => [
      const EditField('title', 'Task title', required: true),
      const EditField('description', 'Description', multiline: true),
      EditField(
        'projectId',
        'Project',
        required: true,
        numeric: true,
        choices: projects,
      ),
      EditField(
        'departmentId',
        'Department',
        required: true,
        numeric: true,
        choices: departments,
      ),
      const EditField('priority', 'Priority', choices: priorities),
      const EditField('startDate', 'Start date', date: true),
      const EditField('dueDate', 'Due date', date: true),
      EditField(
        'assigneeIds',
        'Assign teammates',
        numeric: true,
        multiple: true,
        choices: people,
      ),
    ],
    'Requests' => [
      const EditField('title', 'Request title', required: true),
      const EditField(
        'type',
        'Request type',
        required: true,
        choices: {
          'LEAVE': 'Leave',
          'EXPENSE': 'Expense',
          'PURCHASE': 'Purchase',
          'IT_SUPPORT': 'IT support',
          'GENERAL': 'General',
        },
      ),
      const EditField('description', 'Details', multiline: true),
      const EditField('priority', 'Priority', choices: priorities),
      const EditField('amount', 'Amount'),
      const EditField('currency', 'Currency (USD, KHR…)'),
      const EditField('startDate', 'Start date', date: true),
      const EditField('endDate', 'End date', date: true),
    ],
    'People' => [
      const EditField('firstName', 'First name', required: true),
      const EditField('lastName', 'Last name', required: true),
      const EditField('email', 'Work email', required: true),
      const EditField('employeeCode', 'Employee code'),
      const EditField('phone', 'Phone'),
      const EditField('jobTitle', 'Job title'),
      if (!edit)
        EditField(
          'role',
          'Role',
          choices: access.admin
              ? {'ADMIN': 'Admin', 'MANAGER': 'Manager', 'EMPLOYEE': 'Employee'}
              : {'EMPLOYEE': 'Employee'},
        ),
      if (!edit || access.admin)
        EditField(
          'departmentId',
          'Department',
          required: true,
          numeric: true,
          choices: departments,
        ),
    ],
    'Departments' => [
      const EditField('name', 'Department name', required: true),
      const EditField('code', 'Department code', required: true),
      const EditField('description', 'Description', multiline: true),
      if (edit)
        const EditField(
          'isActive',
          'Availability',
          choices: {'true': 'Active', 'false': 'Inactive'},
        ),
    ],
    _ => [],
  };
}
