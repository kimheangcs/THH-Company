import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:thh_company_frontend/core/network/api_client.dart';
import 'package:thh_company_frontend/core/network/workspace_api.dart';

import 'test_support.dart';

// Opt-in: a disposable database/server fixture supplies synthetic credentials.
// Never point this test at a shared or production database.
void main() {
  final fixturePath = Platform.environment['THH_API_FIXTURE'];
  test(
    'all workspace modules use real backend responses and enforce role boundaries',
    () async {
      final fixture =
          jsonDecode(await File(fixturePath!).readAsString()) as Map;
      WorkspaceApi connect(String role) {
        final storage = MemoryStorage()
          ..token = fixture['users'][role]['token'] as String;
        final client = ApiClient(storage);
        client.dio.options.baseUrl = fixture['url'] as String;
        client.dio.interceptors.add(
          InterceptorsWrapper(
            onError: (error, handler) {
              final body = error.response?.data;
              handler.next(
                error.copyWith(
                  message:
                      '${error.requestOptions.method} ${error.requestOptions.path}: ${body is Map ? body['message'] : error.response?.statusCode}',
                ),
              );
            },
          ),
        );
        return WorkspaceApi(client);
      }

      final admin = connect('ADMIN'),
          manager = connect('MANAGER'),
          employee = connect('EMPLOYEE');
      final department = fixture['departmentId'];
      final managerId = fixture['users']['MANAGER']['id'];
      final employeeId = fixture['users']['EMPLOYEE']['id'];
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      expect((await admin.request('/api/health'))['success'], true);
      expect((await admin.request('/api/health/database'))['success'], true);
      expect((await admin.request('/api/auth/admin-test'))['success'], true);
      expect(
        (await employee.request('/api/auth/me'))['user']['role'],
        'EMPLOYEE',
      );
      expect((await admin.list('/api/departments')).items, isNotEmpty);
      await admin.request(
        '/api/departments/$department',
        method: 'PATCH',
        body: {'description': 'Android workflow integration'},
      );
      await admin.request(
        '/api/departments/$department/manager',
        method: 'PATCH',
        body: {'managerId': managerId},
      );
      expect(
        (await admin.detail('/api/departments/$department'))['managerId'],
        managerId,
      );
      final emptyDept = (await admin.request(
        '/api/departments',
        method: 'POST',
        body: {'name': 'Temporary $stamp', 'code': 'T$stamp'},
      ))['department'];
      await admin.request(
        '/api/departments/${emptyDept['id']}',
        method: 'DELETE',
      );
      final created = (await admin.request(
        '/api/users',
        method: 'POST',
        body: {
          'firstName': 'API',
          'lastName': 'Teammate',
          'email': 'mobile-$stamp@example.test',
          'departmentId': department,
          'role': 'EMPLOYEE',
        },
      ))['user'];
      final personId = created['id'];
      expect(
        (await admin.list('/api/users')).items.any((u) => u['id'] == personId),
        true,
      );
      await manager.request(
        '/api/users/$personId',
        method: 'PATCH',
        body: {'jobTitle': 'Designer'},
      );
      expect(
        (await admin.detail('/api/users/$personId'))['jobTitle'],
        'Designer',
      );
      await admin.request(
        '/api/users/$personId/status',
        method: 'PATCH',
        body: {'status': 'INACTIVE'},
      );
      await admin.request(
        '/api/users/$personId/password',
        method: 'PATCH',
        body: {'password': 'ResetPassword@2026'},
      );
      final project = (await admin.request(
        '/api/projects',
        method: 'POST',
        body: {
          'name': 'Android delivery $stamp',
          'code': 'P$stamp',
          'ownerDepartmentId': department,
          'leadManagerId': managerId,
          'departmentIds': [department],
        },
      ))['data'];
      final projectId = project['id'];
      await manager.request(
        '/api/projects/$projectId',
        method: 'PATCH',
        body: {'description': 'Connected to Flutter'},
      );
      await manager.request(
        '/api/projects/$projectId/status',
        method: 'PATCH',
        body: {'status': 'IN_PROGRESS'},
      );
      expect(
        (await employee.detail('/api/projects/$projectId'))['status'],
        'IN_PROGRESS',
      );
      expect(
        (await employee.list('/api/projects', query: {'search': stamp})).items,
        isNotEmpty,
      );
      final task = (await manager.request(
        '/api/tasks',
        method: 'POST',
        body: {
          'title': 'Deliver mobile workspace',
          'projectId': projectId,
          'departmentId': department,
          'assigneeIds': [employeeId],
        },
      ))['data'];
      final taskId = task['id'];
      final taskPath = '/api/tasks/$taskId';
      await manager.request(
        taskPath,
        method: 'PATCH',
        body: {'description': 'Full API workflow'},
      );
      await manager.request(
        '$taskPath/assign',
        method: 'PATCH',
        body: {
          'assigneeIds': [employeeId],
        },
      );
      expect(
        (await employee.detail(taskPath))['description'],
        'Full API workflow',
      );
      expect(
        (await employee.list(
          '/api/tasks',
          query: {'projectId': projectId},
        )).items,
        isNotEmpty,
      );
      final comment = (await employee.request(
        '$taskPath/comments',
        method: 'POST',
        body: {'content': 'Ready to begin'},
      ))['data'];
      await employee.request(
        '$taskPath/comments/${comment['id']}',
        method: 'PATCH',
        body: {'content': 'In progress'},
      );
      expect(
        (await employee.list('$taskPath/comments')).items.single['content'],
        'In progress',
      );
      await employee.request(
        '$taskPath/comments/${comment['id']}',
        method: 'DELETE',
      );
      final item = (await manager.request(
        '$taskPath/checklist',
        method: 'POST',
        body: {'title': 'Check mobile layout'},
      ))['data'];
      await manager.request(
        '$taskPath/checklist/${item['id']}',
        method: 'PATCH',
        body: {'title': 'Check Android layout', 'position': 1},
      );
      await employee.request(
        '$taskPath/checklist/${item['id']}',
        method: 'PATCH',
        body: {'isCompleted': true},
      );
      expect(
        (await employee.list('$taskPath/checklist'))
            .items
            .single['isCompleted'],
        true,
      );
      await manager.request(
        '$taskPath/checklist/${item['id']}',
        method: 'DELETE',
      );
      final bytes = Uint8List.fromList(
        utf8.encode('Mobile integration attachment'),
      );
      await employee.upload(
        '$taskPath/attachments',
        bytes,
        'notes.txt',
        'text/plain',
      );
      final attachment = (await employee.list('$taskPath/attachments'))
          .items
          .single;
      expect(
        await employee.download(
          '$taskPath/attachments/${attachment['id']}/download',
        ),
        bytes,
      );
      await employee.request(
        '$taskPath/attachments/${attachment['id']}',
        method: 'DELETE',
      );
      await employee.request(
        '$taskPath/progress',
        method: 'PATCH',
        body: {'progress': 100},
      );
      await employee.request('$taskPath/submit-review', method: 'POST');
      await admin.request(
        '$taskPath/reviews',
        method: 'POST',
        body: {
          'decision': 'CHANGES_REQUESTED',
          'comment': 'One more mobile check',
        },
      );
      await employee.request('$taskPath/submit-review', method: 'POST');
      await admin.request(
        '$taskPath/reviews',
        method: 'POST',
        body: {'decision': 'APPROVED'},
      );
      expect((await employee.detail(taskPath))['status'], 'COMPLETED');
      expect((await employee.list('$taskPath/reviews')).items.length, 2);
      final request = (await employee.request(
        '/api/requests',
        method: 'POST',
        body: {'title': 'Mobile test request', 'type': 'GENERAL'},
      ))['data'];
      final requestPath = '/api/requests/${request['id']}';
      await employee.request(
        requestPath,
        method: 'PATCH',
        body: {'description': 'Please review'},
      );
      await employee.upload(
        '$requestPath/attachments',
        bytes,
        'notes.txt',
        'text/plain',
      );
      final file = (await employee.list('$requestPath/attachments'))
          .items
          .single;
      expect(
        await employee.download(
          '$requestPath/attachments/${file['id']}/download',
        ),
        bytes,
      );
      await employee.request(
        '$requestPath/attachments/${file['id']}',
        method: 'DELETE',
      );
      await employee.request('$requestPath/submit', method: 'POST');
      expect(
        (await manager.list('/api/requests/pending-approvals')).items
            .any((r) => r['id'] == request['id']),
        true,
      );
      await manager.request('$requestPath/approve', method: 'POST');
      expect((await employee.detail(requestPath))['status'], 'APPROVED');
      expect(
        (await employee.detail('$requestPath/history'))['approvalActions'],
        isNotEmpty,
      );
      for (final decision in ['reject', 'cancel']) {
        final draft = (await manager.request(
          '/api/requests',
          method: 'POST',
          body: {'title': 'Manager $decision', 'type': 'GENERAL'},
        ))['data'];
        final path = '/api/requests/${draft['id']}';
        await manager.request('$path/submit', method: 'POST');
        if (decision == 'cancel') {
          await manager.request('$path/cancel', method: 'POST');
        } else {
          await admin.request(
            '$path/reject',
            method: 'POST',
            body: {'comment': 'Not needed'},
          );
        }
        expect(
          (await manager.detail(path))['status'],
          decision == 'cancel' ? 'CANCELLED' : 'REJECTED',
        );
      }
      expect((await employee.list('/api/requests')).items, isNotEmpty);
      expect((await employee.list('/api/notifications')).items, isNotEmpty);
      final notification = (await employee.list('/api/notifications'))
          .items
          .first;
      await employee.request(
        '/api/notifications/${notification['id']}/read',
        method: 'PATCH',
      );
      await employee.request(
        '/api/notifications/${notification['id']}',
        method: 'DELETE',
      );
      await employee.request('/api/notifications/read-all', method: 'PATCH');
      expect(
        (await employee.request(
          '/api/notifications/unread-count',
        ))['data']['unreadCount'],
        0,
      );
      await employee.request('/api/notifications/read', method: 'DELETE');
      final history = await admin.list('/api/activity-logs');
      expect(history.items, isNotEmpty);
      expect(
        (await admin.detail(
          '/api/activity-logs/${history.items.first['id']}',
        ))['id'],
        history.items.first['id'],
      );
      expect(
        (await admin.list('/api/activity-logs/entity/TASK/$taskId')).items,
        isNotEmpty,
      );
      expect(
        (await employee.list('/api/activity-logs/my-activity')).items,
        isNotEmpty,
      );
      await expectLater(employee.list('/api/users'), throwsA(anything));
      await expectLater(
        employee.request('/api/projects', method: 'POST', body: {}),
        throwsA(anything),
      );
      await employee.request('/api/auth/logout', method: 'POST');
      await expectLater(employee.request('/api/auth/me'), throwsA(anything));
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
