import 'dart:convert';
import 'package:http/http.dart' as http;
import 'import_result.dart';

/// Importer for Todoist tasks and projects using Todoist REST API v2.
class TodoistImporter {
  final http.Client _client;

  TodoistImporter({http.Client? client}) : _client = client ?? http.Client();

  static const String _defaultApiBase = 'https://api.todoist.com/rest/v2';

  /// Fetches projects and tasks from Todoist using a personal API token.
  Future<ImportResult> importFromApi({
    required String token,
    String apiBase = _defaultApiBase,
  }) async {
    final headers = {
      'Authorization': 'Bearer ${token.trim()}',
      'Content-Type': 'application/json',
    };

    // 1. Fetch projects
    final projectsUri = Uri.parse('$apiBase/projects');
    final projectsResp = await _client.get(projectsUri, headers: headers);
    if (projectsResp.statusCode != 200) {
      throw Exception(
        'Failed to fetch Todoist projects (${projectsResp.statusCode}): ${projectsResp.body}',
      );
    }
    final projectsData = jsonDecode(projectsResp.body);
    final projectsList = projectsData is List ? projectsData : [];

    // 2. Fetch tasks
    final tasksUri = Uri.parse('$apiBase/tasks');
    final tasksResp = await _client.get(tasksUri, headers: headers);
    if (tasksResp.statusCode != 200) {
      throw Exception(
        'Failed to fetch Todoist tasks (${tasksResp.statusCode}): ${tasksResp.body}',
      );
    }
    final tasksData = jsonDecode(tasksResp.body);
    final tasksList = tasksData is List ? tasksData : [];

    return parseJson(projectsJson: projectsList, tasksJson: tasksList);
  }

  /// Parses raw JSON lists into an ImportResult. Pure function for unit testing.
  static ImportResult parseJson({
    required List<dynamic> projectsJson,
    required List<dynamic> tasksJson,
  }) {
    final List<ImportedProject> projects = [];
    final Map<String, int> foreignIdToIndex = {};

    for (int i = 0; i < projectsJson.length; i++) {
      final p = projectsJson[i];
      if (p is! Map) continue;

      final id = '${p['id'] ?? i}';
      final name = p['name'] as String? ?? 'Untitled Project';

      foreignIdToIndex[id] = projects.length;
      projects.add(ImportedProject(
        name: name.trim().isEmpty ? 'Untitled Project' : name.trim(),
        color: '#009688',
      ));
    }

    if (projects.isEmpty) {
      projects.add(ImportedProject(name: 'Inbox', color: '#009688'));
    }

    final List<ImportedTask> tasks = [];
    for (final t in tasksJson) {
      if (t is! Map) continue;

      final title = t['content'] as String? ?? t['title'] as String? ?? '';
      if (title.trim().isEmpty) continue;

      final pId = '${t['project_id'] ?? ''}';
      final projectIndex = foreignIdToIndex[pId] ?? 0;

      final notes = t['description'] as String? ?? '';
      final isDone = t['is_completed'] as bool? ?? false;
      final status = isDone ? 'completed' : 'open';

      // Due date parsing: Todoist provides due object with date or datetime
      DateTime? due;
      if (t['due'] is Map) {
        final dueMap = t['due'] as Map;
        final dtStr = dueMap['datetime'] as String? ?? dueMap['date'] as String?;
        if (dtStr != null && dtStr.isNotEmpty) {
          due = DateTime.tryParse(dtStr)?.toLocal();
        }
      }

      // Priority mapping: Todoist uses 1 (normal) to 4 (urgent)
      // Cycles uses 0 (None), 1 (Low), 2 (Medium), 3 (High)
      final rawPrio = t['priority'] is int ? t['priority'] as int : 1;
      final priority = _mapPriority(rawPrio);

      // Labels mapping to tags
      final List<String> tags = [];
      if (t['labels'] is List) {
        for (final l in t['labels'] as List) {
          if (l is String && l.trim().isNotEmpty) {
            tags.add(l.trim());
          }
        }
      }

      tasks.add(ImportedTask(
        projectIndex: projectIndex,
        title: title.trim(),
        notes: notes.trim(),
        due: due,
        tags: tags,
        status: status,
        priority: priority,
      ));
    }

    return ImportResult(projects: projects, tasks: tasks);
  }

  static int _mapPriority(int v) {
    switch (v) {
      case 4:
        return 3; // Urgent -> High
      case 3:
        return 2; // High -> Medium
      case 2:
        return 1; // Medium -> Low
      default:
        return 0; // Normal (1) -> None
    }
  }
}
