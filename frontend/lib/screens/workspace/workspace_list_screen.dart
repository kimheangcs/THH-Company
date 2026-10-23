import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/token_storage.dart';

class WorkspaceListScreen extends StatefulWidget {
  final bool isProjects;

  const WorkspaceListScreen({super.key, required this.isProjects});

  @override
  State<WorkspaceListScreen> createState() => _WorkspaceListScreenState();
}

class _WorkspaceListScreenState extends State<WorkspaceListScreen> {
  static const primary = Color(0xFF6155FF);
  static const background = Color(0xFFF6F7FB);
  static const dark = Color(0xFF20243A);

  final _searchController = TextEditingController();
  final _storage = TokenStorage();
  final _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  final List<Map<String, dynamic>> _records = [];

  String _status = 'ALL';
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  int _requestVersion = 0;

  String get _endpoint => widget.isProjects ? '/api/projects' : '/api/tasks';

  List<String> get _statuses => widget.isProjects
      ? ['ALL', 'PLANNED', 'IN_PROGRESS', 'ON_HOLD', 'COMPLETED', 'CANCELLED']
      : [
          'ALL',
          'PENDING',
          'IN_PROGRESS',
          'IN_REVIEW',
          'COMPLETED',
          'CANCELLED',
        ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestVersion++;
    _searchController.dispose();
    _dio.close();
    super.dispose();
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return '${data['message']}';
      }
      if (error.response?.statusCode == 401) {
        return 'Session expired. Please log in again.';
      }
      return error.message ?? 'Network request failed.';
    }
    return error.toString();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _loadingMore || _page >= _totalPages)) {
      return;
    }

    final requestId = ++_requestVersion;
    final nextPage = more ? _page + 1 : 1;

    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      final token = await _storage.readToken();

      if (token == null || token.isEmpty) {
        throw Exception('Please log in again.');
      }

      final response = await _dio.get(
        _endpoint,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        queryParameters: {
          'page': nextPage,
          'limit': 20,
          if (_status != 'ALL') 'status': _status,
          if (_searchController.text.trim().isNotEmpty)
            'search': _searchController.text.trim(),
        },
      );

      final body = response.data;

      if (body is! Map || body['success'] != true) {
        throw Exception('Unexpected server response.');
      }

      final rawItems = body['data'];
      if (rawItems is! List) {
        throw Exception('Invalid list response.');
      }

      final items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final pagination = body['pagination'];
      final totalPages = pagination is Map
          ? int.tryParse('${pagination['totalPages']}') ?? 1
          : 1;

      if (!mounted || requestId != _requestVersion) return;

      setState(() {
        if (!more) _records.clear();
        _records.addAll(items);
        _page = nextPage;
        _totalPages = totalPages;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestVersion) return;

      setState(() {
        _error = _message(error);
      });
    } finally {
      if (mounted && requestId == _requestVersion) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map((word) {
        if (word.isEmpty) return word;
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return const Color(0xFF0F9D78);
      case 'IN_PROGRESS':
        return const Color(0xFF367BF5);
      case 'IN_REVIEW':
        return const Color(0xFF8959D9);
      case 'CANCELLED':
        return const Color(0xFFE05D65);
      default:
        return const Color(0xFFF09A28);
    }
  }

  String _date(dynamic value) {
    if (value == null) return 'No due date';
    final date = DateTime.tryParse('$value');
    if (date == null) return 'No due date';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _name(dynamic value) {
    if (value is! Map) return 'Not assigned';
    final first = '${value['firstName'] ?? ''}'.trim();
    final last = '${value['lastName'] ?? ''}'.trim();
    final result = '$first $last'.trim();
    return result.isEmpty ? 'Not assigned' : result;
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> item) {
    final isProject = widget.isProjects;
    final title = '${item[isProject ? 'name' : 'title'] ?? 'Untitled'}';
    final status = '${item['status'] ?? 'PENDING'}';
    final project = item['project'];
    final department = isProject ? item['ownerDepartment'] : item['department'];

    final subtitle = isProject
        ? '${item['code'] ?? ''}'
        : project is Map
        ? '${project['name'] ?? 'Project'}'
        : 'Task';

    final count = item['_count'];
    final taskCount = count is Map ? count['tasks'] : null;
    final progress = num.tryParse('${item['progress'] ?? 0}') ?? 0;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isProject
                          ? Icons.folder_outlined
                          : Icons.task_alt_rounded,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(_label(status), _statusColor(status)),
                  if (!isProject && item['priority'] != null)
                    _chip(
                      _label('${item['priority']}'),
                      const Color(0xFF8959D9),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (!isProject) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Progress',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '${progress.clamp(0, 100).round()}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.clamp(0, 100) / 100,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: const Color(0xFFEEEEF6),
                  color: primary,
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.apartment_rounded,
                    size: 15,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      department is Map
                          ? '${department['name'] ?? 'Department'}'
                          : 'Department',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    isProject
                        ? '${taskCount ?? 0} tasks'
                        : _date(item['dueDate']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> item) {
    final isProject = widget.isProjects;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        final department = isProject
            ? item['ownerDepartment']
            : item['department'];

        final assignments = item['assignments'];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item[isProject ? 'name' : 'title'] ?? 'Details'}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: dark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _detail('Status', _label('${item['status'] ?? ''}')),
                  _detail(
                    'Department',
                    department is Map ? '${department['name'] ?? '—'}' : '—',
                  ),
                  if (isProject) ...[
                    _detail('Code', '${item['code'] ?? '—'}'),
                    _detail('Lead Manager', _name(item['leadManager'])),
                  ] else ...[
                    _detail('Priority', _label('${item['priority'] ?? '—'}')),
                    _detail('Due date', _date(item['dueDate'])),
                    _detail('Progress', '${item['progress'] ?? 0}%'),
                    if (assignments is List)
                      _detail(
                        'Assignees',
                        assignments.isEmpty
                            ? 'Unassigned'
                            : assignments
                                  .map((entry) {
                                    if (entry is Map) {
                                      return _name(entry['user']);
                                    }
                                    return 'Unknown';
                                  })
                                  .join(', '),
                      ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Description',
                    style: TextStyle(fontWeight: FontWeight.bold, color: dark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item['description'] ?? 'No description provided.'}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(title, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, color: dark),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isProjects ? 'Projects' : 'Tasks';

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: dark,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : () => _load(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Search ${title.toLowerCase()}...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: () => _load(),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _statuses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final status = _statuses[index];
                  final selected = _status == status;

                  return ChoiceChip(
                    label: Text(_label(status)),
                    selected: selected,
                    selectedColor: primary.withValues(alpha: 0.14),
                    onSelected: (_) {
                      setState(() => _status = status);
                      _load();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: primary),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                  TextButton(
                                    onPressed: () => _load(),
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          if (_records.isEmpty && _error == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 100),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 60,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 12),
                                  Text('No records found'),
                                ],
                              ),
                            ),
                          ..._records.map(_recordCard),
                          if (_page < _totalPages)
                            Center(
                              child: TextButton(
                                onPressed: _loadingMore
                                    ? null
                                    : () => _load(more: true),
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : const Text('Load more'),
                              ),
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
}
