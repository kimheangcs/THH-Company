import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

typedef Record = Map<String, dynamic>;

class PageResult {
  final List<Record> items;
  final int total;
  final int pages;
  const PageResult(this.items, {required this.total, required this.pages});
}

class WorkspaceApi {
  final ApiClient client;
  WorkspaceApi(this.client);
  Future<Record> request(
    String path, {
    String method = 'GET',
    Object? body,
    Record? query,
  }) async {
    final response = await client.dio.request(
      path,
      data: body,
      queryParameters: query,
      options: Options(method: method),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static PageResult parsePage(Record body) {
    final data = body['data'];
    final nested = data is Map ? data : <String, dynamic>{};
    final raw = data is List
        ? data
        : body['users'] ??
              body['departments'] ??
              nested['notifications'] ??
              nested['logs'] ??
              nested['tasks'] ??
              nested['projects'] ??
              nested['requests'] ??
              <dynamic>[];
    final items = (raw as List).map((e) => Record.from(e as Map)).toList();
    final pagination = body['pagination'] ?? nested['pagination'] ?? {};
    return PageResult(
      items,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
      pages: (pagination['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  Future<PageResult> list(String path, {Record? query}) async =>
      parsePage(await request(path, query: query));
  Future<Record> detail(String path) async {
    final body = await request(path);
    return Record.from(
      (body['data'] ?? body['user'] ?? body['department'] ?? body) as Map,
    );
  }

  Future<void> upload(
    String path,
    Uint8List bytes,
    String name,
    String mime,
  ) async {
    await client.dio.post(
      path,
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: name,
          contentType: DioMediaType.parse(mime),
        ),
      }),
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  Future<Uint8List> download(String path) async {
    final response = await client.dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }
}
