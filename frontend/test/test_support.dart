import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:thh_company_frontend/core/network/api_client.dart';
import 'package:thh_company_frontend/core/network/workspace_api.dart';
import 'package:thh_company_frontend/core/storage/token_storage.dart';
import 'package:thh_company_frontend/providers/auth_provider.dart';

class MemoryStorage extends TokenStorage {
  String? token;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<void> deleteToken() async {
    token = null;
  }
}

class FakeAdapter implements HttpClientAdapter {
  final Future<Record> Function(RequestOptions) respond;
  final List<RequestOptions> calls = [];
  FakeAdapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final body = await respond(options);
    final status = body.remove('_status') as int? ?? 200;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Record userFor(String role) => {
  'id': 1,
  'firstName': 'Kim',
  'lastName': 'Heang',
  'email': 'kim@example.test',
  'role': role,
  'departmentId': 1,
  'canApproveManagerRequests': role == 'ADMIN',
  'department': {'name': 'Operations'},
};
AuthProvider signedIn(String role, {FakeAdapter? adapter}) {
  final storage = MemoryStorage()..token = 'session';
  final api = ApiClient(storage);
  api.dio.httpClientAdapter =
      adapter ??
      FakeAdapter(
        (options) async => options.path == '/api/auth/me'
            ? {'user': userFor(role)}
            : {
                'data': [],
                'pagination': {'total': 0, 'totalPages': 1},
              },
      );
  return AuthProvider(api: api, storage: storage)
    ..user = userFor(role)
    ..isAuthenticated = true;
}
