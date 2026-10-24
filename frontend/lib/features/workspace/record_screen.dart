import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter/material.dart';

import '../../core/design/app_theme.dart';
import '../../core/network/workspace_api.dart';
import '../shared/editor.dart';
import 'access.dart';
import 'resource_forms.dart';
import 'workspace_screen.dart';

class RecordScreen extends StatefulWidget {
  final String kind;
  final int id;
  final WorkspaceApi api;
  final Access access;
  final Record? initial;
  const RecordScreen({
    super.key,
    required this.kind,
    required this.id,
    required this.api,
    required this.access,
    this.initial,
  });
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late Future<Record> future;
  bool busy = false;
  String get path => '${resourcePath(widget.kind)}/${widget.id}';
  WorkspaceApi get api => widget.api;
  Access get access => widget.access;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future =
        widget.kind == 'Inbox' || (widget.kind == 'Activity' && !access.admin)
        ? Future.value(widget.initial ?? {})
        : api.detail(path);
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> action(
    String url, {
    String method = 'POST',
    Record? body,
    String? confirmation,
    bool close = false,
  }) async {
    if (busy) return;
    if (confirmation != null &&
        !await confirmAction(
          context,
          confirmation,
          'This change will be saved to your workspace.',
        )) {
      return;
    }
    setState(() => busy = true);
    try {
      await api.request(url, method: method, body: body ?? {});
      if (mounted) {
        if (close) {
          Navigator.pop(context);
        } else {
          setState(load);
          message('Changes saved');
        }
      }
    } catch (e) {
      message(api.client.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Record record) async {
    try {
      final initial = Record.from(record);
      if (widget.kind == 'Tasks') {
        initial['assigneeIds'] = (record['assignments'] as List? ?? [])
            .map((a) => a['userId'])
            .toList();
      }
      if (widget.kind == 'Projects') {
        initial['departmentIds'] = (record['departments'] as List? ?? [])
            .map((a) => a['departmentId'])
            .toList();
      }
      final fields = await resourceFields(
        widget.kind,
        api,
        access,
        existing: record,
      );
      if (!mounted) return;
      final result = await showEditor(
        context,
        title: 'Edit ${singular(widget.kind)}',
        fields: fields,
        initial: initial,
        save: (body) async {
          try {
            await api.request(path, method: 'PATCH', body: body);
          } catch (e) {
            throw Exception(api.client.errorMessage(e));
          }
        },
      );
      if (result != null && mounted) setState(load);
    } catch (e) {
      message(api.client.errorMessage(e));
    }
  }

  Future<void> form(
    String title,
    String url,
    List<EditField> fields, {
    String method = 'POST',
    Record initial = const {},
  }) async {
    final result = await showEditor(
      context,
      title: title,
      fields: fields,
      initial: initial,
      save: (body) async {
        try {
          await api.request(url, method: method, body: body);
        } catch (e) {
          throw Exception(api.client.errorMessage(e));
        }
      },
    );
    if (result != null && mounted) setState(load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.kind) {
        'People' => 'Teammate',
        'Activity' => 'Activity details',
        'Inbox' => 'Notification',
        _ => '${human(singular(widget.kind))} details',
      }),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Record>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FailureView(
            message: api.client.errorMessage(snapshot.error!),
            retry: () => setState(load),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final record = snapshot.data!;
        final kind = widget.kind;
        final title =
            record['title'] ??
            record['name'] ??
            (kind == 'People' ? person(record) : human(record['action']));
        final canEdit = switch (kind) {
          'Tasks' => access.managesTask(record),
          'Projects' => access.managesProject(record),
          'People' =>
            access.admin ||
                (access.manager &&
                    record['role'] == 'EMPLOYEE' &&
                    record['departmentId'] == access.user['departmentId']),
          'Departments' => access.admin,
          'Requests' =>
            record['submittedById'] == access.user['id'] &&
                record['status'] == 'DRAFT',
          _ => false,
        };
        return RefreshIndicator(
          onRefresh: () async {
            setState(load);
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            kind == 'People'
                                ? human(record['role'])
                                : record['code']?.toString() ??
                                      human(record['type'] ?? kind),
                            style: const TextStyle(
                              color: AppTheme.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (record['status'] != null)
                          StatusPill('${record['status']}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$title',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    if (record['description'] != null)
                      Text('${record['description']}'),
                    if (kind == 'Inbox') Text('${record['message']}'),
                    if (kind == 'People') ...[
                      Text('${record['email']}'),
                      Text('${record['jobTitle'] ?? ''}'),
                      if (record['phone'] != null) Text('${record['phone']}'),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      children: [
                        if (record['priority'] != null)
                          _meta(Icons.flag_outlined, human(record['priority'])),
                        if (record['dueDate'] != null)
                          _meta(
                            Icons.calendar_today_outlined,
                            dateLabel(record['dueDate']),
                          ),
                        if (record['department'] != null)
                          _meta(
                            Icons.account_tree_outlined,
                            '${record['department']['name']}',
                          ),
                        if (record['ownerDepartment'] != null)
                          _meta(
                            Icons.account_tree_outlined,
                            '${record['ownerDepartment']['name']}',
                          ),
                        if (record['leadManager'] != null)
                          _meta(
                            Icons.person_outline,
                            person(record['leadManager'] as Map),
                          ),
                        if (record['amount'] != null)
                          _meta(
                            Icons.payments_outlined,
                            '${record['amount']} ${record['currency']}',
                          ),
                      ],
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => edit(record),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit details'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (kind == 'Tasks') ..._task(record),
              if (kind == 'Projects') ...[
                if (access.managesProject(record))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: OutlinedButton.icon(
                      onPressed: () => form(
                        'Change project status',
                        '$path/status',
                        [
                          const EditField(
                            'status',
                            'Status',
                            required: true,
                            choices: projectStatuses,
                          ),
                        ],
                        method: 'PATCH',
                        initial: {'status': record['status']},
                      ),
                      icon: const Icon(Icons.sync),
                      label: const Text('Change status'),
                    ),
                  ),
                _section(
                  'Project tasks',
                  future: api.list(
                    '/api/tasks',
                    query: {'projectId': widget.id, 'limit': 100},
                  ),
                  builder: (task) => RecordTile(
                    kind: 'Tasks',
                    record: task,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RecordScreen(
                          kind: 'Tasks',
                          id: task['id'],
                          api: api,
                          access: access,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (kind == 'Requests') ..._request(record),
              if (kind == 'People' && canEdit) ..._people(record),
              if (kind == 'Departments' && access.admin) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final people = await api.list(
                        '/api/users',
                        query: {
                          'role': 'MANAGER',
                          'departmentId': record['id'],
                          'status': 'ACTIVE',
                        },
                      );
                      if (!mounted) return;
                      await form(
                        'Assign department manager',
                        '$path/manager',
                        [
                          EditField(
                            'managerId',
                            'Manager',
                            required: true,
                            numeric: true,
                            choices: {
                              for (final p in people.items)
                                '${p['id']}': person(p),
                            },
                          ),
                        ],
                        method: 'PATCH',
                        initial: {'managerId': record['managerId']},
                      );
                    } catch (e) {
                      message(api.client.errorMessage(e));
                    }
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Assign manager'),
                ),
                if (record['managerId'] != null)
                  TextButton(
                    onPressed: () => action(
                      '$path/manager',
                      method: 'PATCH',
                      body: {'managerId': null},
                      confirmation: 'Remove department manager?',
                    ),
                    child: const Text('Remove manager'),
                  ),
                TextButton(
                  onPressed: () => action(
                    path,
                    method: 'DELETE',
                    confirmation: 'Delete department?',
                    close: true,
                  ),
                  child: const Text('Delete department'),
                ),
              ],
              if (kind == 'Inbox')
                Wrap(
                  spacing: 10,
                  children: [
                    if (record['isRead'] != true)
                      FilledButton.icon(
                        onPressed: () =>
                            action('$path/read', method: 'PATCH', close: true),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Mark as read'),
                      ),
                    OutlinedButton(
                      onPressed: () => action(
                        path,
                        method: 'DELETE',
                        confirmation: 'Delete notification?',
                        close: true,
                      ),
                      child: const Text('Delete'),
                    ),
                    if (record['targetUrl'] is String)
                      TextButton(
                        onPressed: () =>
                            openTarget(record['targetUrl'] as String),
                        child: const Text('View related item →'),
                      ),
                  ],
                ),
              if (kind == 'Activity')
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        human(record['action']),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text('When: ${dateLabel(record['createdAt'])}'),
                      Text('Related to: ${human(record['entityType'])}'),
                      if (record['user'] != null)
                        Text('By: ${person(record['user'] as Map)}'),
                      if (record['details'] is Map) ...[
                        const SizedBox(height: 16),
                        ..._activityDetails(
                          Record.from(record['details'] as Map),
                        ),
                      ],
                    ],
                  ),
                ),
              if (access.admin &&
                  [
                    'Projects',
                    'Tasks',
                    'Requests',
                    'People',
                    'Departments',
                  ].contains(kind))
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _section(
                    'Audit history',
                    future: api.list(
                      '/api/activity-logs/entity/${switch (kind) {
                        'People' => 'USER',
                        'Departments' => 'DEPARTMENT',
                        'Requests' => 'REQUEST',
                        'Projects' => 'PROJECT',
                        _ => 'TASK',
                      }}/${widget.id}',
                      query: {'limit': 100},
                    ),
                    builder: (log) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(human(log['action'])),
                      subtitle: Text(dateLabel(log['createdAt'])),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RecordScreen(
                            kind: 'Activity',
                            id: log['id'],
                            api: api,
                            access: access,
                            initial: log,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppTheme.muted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ),
    ],
  );
  List<Widget> _task(Record task) {
    final closed =
        ['COMPLETED', 'CANCELLED'].contains(task['project']?['status']) ||
        ['COMPLETED', 'CANCELLED'].contains(task['status']);
    final mutable =
        !closed &&
        !['COMPLETED', 'CANCELLED', 'IN_REVIEW'].contains(task['status']);
    return [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progress',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${task['progress']}%',
                  style: const TextStyle(
                    color: AppTheme.teal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: ((task['progress'] as num? ?? 0) / 100).clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (access.worksOn(task) && mutable) ...[
                  OutlinedButton(
                    onPressed: () => form(
                      'Update progress',
                      '$path/progress',
                      [
                        const EditField(
                          'progress',
                          'Progress (0–100)',
                          numeric: true,
                          required: true,
                        ),
                      ],
                      method: 'PATCH',
                      initial: {'progress': task['progress']},
                    ),
                    child: const Text('Update progress'),
                  ),
                  FilledButton(
                    onPressed: () => action(
                      '$path/submit-review',
                      confirmation: 'Submit task for review?',
                    ),
                    child: const Text('Submit for review'),
                  ),
                ],
                if (access.reviews(task) &&
                    task['status'] == 'IN_REVIEW' &&
                    !closed) ...[
                  FilledButton(
                    onPressed: () => review('APPROVED'),
                    child: const Text('Approve task'),
                  ),
                  OutlinedButton(
                    onPressed: () => review('CHANGES_REQUESTED'),
                    child: const Text('Request changes'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Assigned to: ${(task['assignments'] as List? ?? []).map((a) => person(a['user'] as Map?)).join(', ')}',
              style: const TextStyle(color: AppTheme.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (access.managesTask(task) && !closed)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                final users = await api.list(
                  '/api/users',
                  query: {
                    'role': 'EMPLOYEE',
                    'departmentId': task['departmentId'],
                    'status': 'ACTIVE',
                  },
                );
                if (!mounted) return;
                await form(
                  'Assign teammates',
                  '$path/assign',
                  [
                    EditField(
                      'assigneeIds',
                      'Teammates',
                      multiple: true,
                      numeric: true,
                      choices: {
                        for (final user in users.items.where(
                          (u) => u['emailVerifiedAt'] != null,
                        ))
                          '${user['id']}': person(user),
                      },
                    ),
                  ],
                  method: 'PATCH',
                  initial: {
                    'assigneeIds': (task['assignments'] as List)
                        .map((a) => a['userId'])
                        .toList(),
                  },
                );
              } catch (e) {
                message(api.client.errorMessage(e));
              }
            },
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Manage assignments'),
          ),
        ),
      _section(
        'Checklist',
        future: api.list('$path/checklist'),
        add: access.managesTask(task) && !closed
            ? () => form('Add checklist item', '$path/checklist', [
                const EditField('title', 'Item title', required: true),
              ])
            : null,
        builder: (item) => CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${item['title']}'),
          value: item['isCompleted'] == true,
          onChanged: access.worksOn(task) && !closed
              ? (value) => action(
                  '$path/checklist/${item['id']}',
                  method: 'PATCH',
                  body: {'isCompleted': value},
                )
              : null,
          secondary: access.managesTask(task) && !closed
              ? PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      action(
                        '$path/checklist/${item['id']}',
                        method: 'DELETE',
                        confirmation: 'Delete checklist item?',
                      );
                    } else {
                      form(
                        'Edit checklist item',
                        '$path/checklist/${item['id']}',
                        [
                          const EditField(
                            'title',
                            'Item title',
                            required: true,
                          ),
                          const EditField(
                            'position',
                            'Position',
                            numeric: true,
                          ),
                        ],
                        method: 'PATCH',
                        initial: item,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                )
              : null,
        ),
      ),
      const SizedBox(height: 18),
      _section(
        'Conversation',
        future: api.list('$path/comments'),
        add: !closed && access.worksOn(task)
            ? () => form('Add a comment', '$path/comments', [
                const EditField(
                  'content',
                  'Your comment',
                  required: true,
                  multiline: true,
                ),
              ])
            : null,
        builder: (comment) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppTheme.canvas,
                child: Icon(Icons.chat_bubble_outline, size: 18),
              ),
              title: Text(person(comment['user'] as Map?)),
              subtitle: Text(dateLabel(comment['createdAt'])),
              trailing:
                  !closed &&
                      (comment['userId'] == access.user['id'] || access.admin)
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          action(
                            '$path/comments/${comment['id']}',
                            method: 'DELETE',
                            confirmation: 'Delete comment?',
                          );
                        } else {
                          form(
                            'Edit comment',
                            '$path/comments/${comment['id']}',
                            [
                              const EditField(
                                'content',
                                'Comment',
                                required: true,
                                multiline: true,
                              ),
                            ],
                            method: 'PATCH',
                            initial: comment,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        if (comment['userId'] == access.user['id'])
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    )
                  : null,
            ),
            Text('${comment['content']}'),
            const Divider(height: 28),
          ],
        ),
      ),
      const SizedBox(height: 18),
      attachments(task, task: true),
      const SizedBox(height: 18),
      _section(
        'Review history',
        future: api.list('$path/reviews'),
        builder: (review) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            review['decision'] == 'APPROVED'
                ? Icons.verified_outlined
                : Icons.rate_review_outlined,
            color: AppTheme.teal,
          ),
          title: Text(human(review['decision'])),
          subtitle: Text(
            '${person(review['reviewer'] as Map?)} · ${dateLabel(review['reviewedAt'])}\n${review['comment'] ?? ''}',
          ),
        ),
      ),
    ];
  }

  Future<void> review(String decision) => form(
    decision == 'APPROVED' ? 'Approve task' : 'Request changes',
    '$path/reviews',
    [
      const EditField(
        'decision',
        'Decision',
        required: true,
        choices: {
          'APPROVED': 'Approved',
          'CHANGES_REQUESTED': 'Changes requested',
        },
      ),
      EditField(
        'comment',
        'Feedback',
        required: decision != 'APPROVED',
        multiline: true,
      ),
    ],
    initial: {'decision': decision},
  );
  List<Widget> _request(Record record) {
    final owner = record['submittedById'] == access.user['id'];
    final pending = ['PENDING', 'IN_REVIEW'].contains(record['status']);
    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (owner && record['status'] == 'DRAFT')
            FilledButton.icon(
              onPressed: () =>
                  action('$path/submit', confirmation: 'Submit this request?'),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Submit request'),
            ),
          if (owner &&
              ['DRAFT', 'PENDING', 'IN_REVIEW'].contains(record['status']))
            OutlinedButton(
              onPressed: () =>
                  action('$path/cancel', confirmation: 'Cancel this request?'),
              child: const Text('Cancel request'),
            ),
          if (pending && access.decides(record)) ...[
            FilledButton(
              onPressed: () => action(
                '$path/approve',
                confirmation: 'Approve this request?',
              ),
              child: const Text('Approve'),
            ),
            OutlinedButton(
              onPressed: () => form('Reject request', '$path/reject', [
                const EditField(
                  'comment',
                  'Reason for rejection',
                  required: true,
                  multiline: true,
                ),
              ]),
              child: const Text('Reject'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      attachments(record, task: false),
      const SizedBox(height: 18),
      FutureBuilder<Record>(
        future: api.detail('$path/history'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FailureView(
              message: api.client.errorMessage(snapshot.error!),
              retry: () => setState(load),
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final data = snapshot.data!;
          final actions = data['approvalActions'] ?? data['actions'] ?? [];
          final steps = data['approvalSteps'] ?? data['steps'] ?? [];
          return Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approval history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if ((steps as List).isEmpty)
                  const Text(
                    'No approval step yet. Submit your draft to begin.',
                  ),
                for (final step in steps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.fact_check_outlined,
                      color: AppTheme.teal,
                    ),
                    title: Text(human(step['status'])),
                    subtitle: Text(
                      step['approver'] != null
                          ? person(step['approver'] as Map)
                          : human(step['approverType']),
                    ),
                  ),
                for (final item in actions as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(human(item['action'])),
                    subtitle: Text(
                      '${item['comment'] ?? ''}\n${dateLabel(item['createdAt'])}',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _people(Record record) => [
    Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (record['id'] != access.user['id'])
                OutlinedButton(
                  onPressed: () => form(
                    'Change account status',
                    '$path/status',
                    [
                      const EditField(
                        'status',
                        'Account status',
                        required: true,
                        choices: {
                          'ACTIVE': 'Active',
                          'INACTIVE': 'Inactive',
                          'SUSPENDED': 'Suspended',
                        },
                      ),
                    ],
                    method: 'PATCH',
                    initial: {'status': record['status']},
                  ),
                  child: const Text('Change status'),
                ),
              if (access.admin &&
                  (record['role'] != 'ADMIN' ||
                      record['id'] == access.user['id']))
                OutlinedButton(
                  onPressed: () => form('Reset password', '$path/password', [
                    const EditField(
                      'password',
                      'Temporary password',
                      required: true,
                      secret: true,
                    ),
                  ], method: 'PATCH'),
                  child: const Text('Reset password'),
                ),
            ],
          ),
          if (access.admin && record['role'] == 'ADMIN')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Approve manager requests'),
              subtitle: const Text(
                'Allow this admin to receive and decide approval requests.',
              ),
              value: record['canApproveManagerRequests'] == true,
              onChanged: busy
                  ? null
                  : (value) => action(
                      path,
                      method: 'PATCH',
                      body: {'canApproveManagerRequests': value},
                      confirmation: value
                          ? 'Grant approval permission?'
                          : 'Revoke approval permission?',
                    ),
            ),
        ],
      ),
    ),
  ];
  Widget attachments(Record record, {required bool task}) {
    final canUpload = task
        ? access.worksOn(record) &&
              ![
                'COMPLETED',
                'CANCELLED',
              ].contains(record['project']?['status']) &&
              !['COMPLETED', 'CANCELLED'].contains(record['status'])
        : record['submittedById'] == access.user['id'] &&
              record['status'] == 'DRAFT';
    return _section(
      'Files',
      future: api.list('$path/attachments'),
      add: canUpload ? () => upload() : null,
      builder: (file) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.attach_file, color: AppTheme.teal),
        title: Text(
          '${file['fileName']}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${((num.tryParse('${file['fileSize']}') ?? 0) / 1024).toStringAsFixed(1)} KB',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Save file',
              onPressed: () => download(file),
              icon: const Icon(Icons.download_outlined),
            ),
            if (canUpload &&
                (record['submittedById'] == access.user['id'] ||
                    file['uploadedById'] == access.user['id'] ||
                    access.managesTask(record)))
              IconButton(
                tooltip: 'Delete file',
                onPressed: () => action(
                  '$path/attachments/${file['id']}',
                  method: 'DELETE',
                  confirmation: 'Delete attachment?',
                ),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> upload() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Documents and images',
            extensions: ['pdf', 'jpg', 'jpeg', 'png', 'txt'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        message('Choose a file smaller than 10 MB.');
        return;
      }
      final ext = file.name.split('.').last.toLowerCase();
      final mime = {
        'pdf': 'application/pdf',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'txt': 'text/plain',
      }[ext];
      if (mime == null) {
        message('Choose a PDF, JPG, PNG, or TXT file.');
        return;
      }
      setState(() => busy = true);
      await api.upload(
        '$path/attachments',
        await file.readAsBytes(),
        file.name,
        mime,
      );
      if (mounted) {
        setState(load);
        message('File uploaded');
      }
    } catch (e) {
      message(api.client.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download(Record file) async {
    try {
      final bytes = await api.download(
        '$path/attachments/${file['id']}/download',
      );
      final name = '${file['fileName']}'.replaceAll(RegExp(r'[/\\]'), '_');
      if (kIsWeb) {
        await XFile.fromData(
          bytes,
          name: name,
          mimeType: file['mimeType'] as String?,
        ).saveTo(name);
      } else if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        final saved = await FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(
            data: bytes,
            fileName: name,
            mimeTypesFilter: [
              file['mimeType'] as String? ?? 'application/octet-stream',
            ],
          ),
        );
        if (saved == null) return;
      } else {
        final location = await getSaveLocation(suggestedName: name);
        if (location == null) return;
        await XFile.fromData(bytes, name: name).saveTo(location.path);
      }
      message('File saved');
    } catch (e) {
      message(api.client.errorMessage(e));
    }
  }

  Widget _section(
    String title, {
    required Future<PageResult> future,
    required Widget Function(Record) builder,
    VoidCallback? add,
  }) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (add != null)
              IconButton(
                tooltip: 'Add to $title',
                onPressed: busy ? null : add,
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: AppTheme.teal,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<PageResult>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  Text(api.client.errorMessage(snapshot.error!)),
                  TextButton(
                    onPressed: () => setState(load),
                    child: const Text('Try again'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.items.isEmpty) {
              return Text(
                'Nothing here yet.',
                style: Theme.of(context).textTheme.bodySmall,
              );
            }
            return Column(
              children: [
                for (final record in snapshot.data!.items) builder(record),
              ],
            );
          },
        ),
      ],
    ),
  );
  List<Widget> _activityDetails(Record details) => [
    for (final entry in details.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            entry.value is Map &&
                !(entry.value as Map).containsKey('before') &&
                !(entry.value as Map).containsKey('after')
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    human(entry.key),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ..._activityDetails(Record.from(entry.value as Map)),
                ],
              )
            : Text(
                '${human(entry.key.replaceAllMapped(RegExp(r"[A-Z]"), (m) => " ${m[0]}"))}: ${entry.value is Map
                    ? "${(entry.value as Map)["before"] ?? "—"} → ${(entry.value as Map)["after"] ?? "—"}"
                    : entry.value is List
                    ? (entry.value as List).join(", ")
                    : entry.value}',
              ),
      ),
  ];
  void openTarget(String target) {
    final match = RegExp(r'^/(tasks|requests|projects)/(\d+)$')
        .firstMatch(target);
    if (match == null) {
      message('This notification has no available destination.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordScreen(
          kind: human(match[1]),
          id: int.parse(match[2]!),
          api: api,
          access: access,
        ),
      ),
    );
  }
}
