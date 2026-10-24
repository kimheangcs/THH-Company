import '../../core/network/workspace_api.dart';

class Access {
  final Record user;
  const Access(this.user);
  String get role => user['role'] as String? ?? 'EMPLOYEE';
  bool get admin => role == 'ADMIN';
  bool get manager => role == 'MANAGER';
  bool get managesPeople => admin || manager;
  bool managesProject(Record project) =>
      admin ||
      (manager &&
          project['leadManagerId'] == user['id'] &&
          project['ownerDepartmentId'] == user['departmentId']);
  bool managesTask(Record task) =>
      managesProject(Record.from(task['project'] as Map? ?? {}));
  bool assigned(Record task) => (task['assignments'] as List? ?? []).any(
    (a) => a['userId'] == user['id'],
  );
  bool worksOn(Record task) => managesTask(task) || assigned(task);
  bool reviews(Record task) =>
      managesTask(task) && task['createdById'] != user['id'] && !assigned(task);
  bool decides(Record request) =>
      request['assignedApproverId'] == user['id'] &&
      request['submittedById'] != user['id'] &&
      (manager || (admin && user['canApproveManagerRequests'] == true));
  List<String> get destinations => [
    'Overview',
    'Projects',
    'Tasks',
    'Requests',
    if (managesPeople) 'Approvals',
    if (managesPeople) 'People',
    if (managesPeople) 'Departments',
    'Inbox',
    'Activity',
  ];
}
