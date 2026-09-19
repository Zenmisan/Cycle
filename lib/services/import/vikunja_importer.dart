import 'dart:convert';
import 'package:http/http.dart' as http;
import 'import_result.dart';

/// Importer for Vikunja (self-hosted task manager).
/// Connects to Vikunja's REST API using a personal API token.
class VikunjaImporter {
  final http.Client _client;

  VikunjaImporter({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches projects and tasks from a Vikunja instance and returns an ImportResult.
  Future<ImportResult> importFromApi({
    required String baseUrl,
    required String token,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final headers = {
      'Authorization': 'Bearer ${token.trim()}',
      'Content-Type': 'application/json',
    };

    // 1. Fetch projects
    final projectsUri = Uri.parse('$cleanBase/api/v1/projects');
    final projectsResp = await _client.get(projectsUri, headers: headers);
    if (projectsResp.statusCode != 200) {
      throw Exception(
        'Failed to fetch Vikunja projects (${projectsResp.statusCode}): ${projectsResp.body}',
      );
    }

    final projectsData = jsonDecode(projectsResp.body);
    final projectsList = projectsData is List ? projectsData : [];

    // 2. Fetch all tasks
    // Vikunja provides /api/v1/tasks/all for fetching all tasks accessible by token
    final tasksUri = Uri.parse('$cleanBase/api/v1/tasks/all');
    final tasksResp = await _client.get(tasksUri, headers: headers);
    List<dynamic> tasksList = [];
    if (tasksResp.statusCode == 200) {
      final tasksData = jsonDecode(tasksResp.body);
      tasksList = tasksData is List ? tasksData : [];
    } else {
      // Fallback: fetch tasks per project if /tasks/all is unsupported by older version
      for (final p in projectsList) {
        if (p is Map && p['id'] != null) {
          final pTasksUri = Uri.parse('$cleanBase/api/v1/projects/${p['id']}/tasks');
          final pResp = await _client.get(pTasksUri, headers: headers);
          if (pResp.statusCode == 200) {
            final pData = jsonDecode(pResp.body);
            if (pData is List) tasksList.addAll(pData);
          }
        }
      }
    }

    return parseJson(projectsJson: projectsList, tasksJson: tasksList);
  }

  /// Parses raw JSON lists into an ImportResult. Separated for pure unit testability.
  static ImportResult parseJson({
    required List<dynamic> projectsJson,
    required List<dynamic> tasksJson,
  }) {
    final List<ImportedProject> projects = [];
    final Map<int, int> foreignIdToIndex = {};

    for (int i = 0; i < projectsJson.length; i++) {
      final p = projectsJson[i];
      if (p is! Map) continue;

      final id = p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}');
      final name = p['title'] as String? ?? p['name'] as String? ?? 'Untitled Project';
      final color = p['hex_color'] as String? ?? '#009688';

      foreignIdToIndex[id ?? i] = projects.length;
      projects.add(ImportedProject(
        name: name.trim().isEmpty ? 'Untitled Project' : name.trim(),
        color: color.startsWith('#') ? color : '#$color',
      ));
    }

    // If no projects exist, add a default Inbox
    if (projects.isEmpty) {
      projects.add(ImportedProject(name: 'Inbox', color: '#009688'));
    }

    final List<ImportedTask> tasks = [];
    for (final t in tasksJson) {
      if (t is! Map) continue;

      final title = t['title'] as String? ?? '';
      if (title.trim().isEmpty) continue;

      final pId = t['project_id'] is int
          ? t['project_id'] as int
          : int.tryParse('${t['project_id']}');
      final projectIndex = (pId != null && foreignIdToIndex.containsKey(pId))
          ? foreignIdToIndex[pId]!
          : 0;

      final notes = t['description'] as String? ?? '';
      final isDone = t['done'] as bool? ?? false;
      final status = isDone ? 'completed' : 'open';

      // Due date parsing
      DateTime? due;
      final dueStr = t['due_date'] as String?;
      if (dueStr != null && dueStr.isNotEmpty && !dueStr.startsWith('0001-01-01')) {
        due = DateTime.tryParse(dueStr)?.toLocal();
      }

      // Priority mapping (Vikunja: 0 to 5) -> (Cycles: 0 to 3)
      final rawPrio = t['priority'] is int ? t['priority'] as int : 0;
      final priority = _mapPriority(rawPrio);

      // Labels mapping to tags
      final List<String> tags = [];
      final rawLabels = t['labels'];
      if (rawLabels is List) {
        for (final l in rawLabels) {
          if (l is Map && l['title'] != null) {
            final tagTitle = '${l['title']}'.trim();
            if (tagTitle.isNotEmpty) tags.add(tagTitle);
          } else if (l is String && l.trim().isNotEmpty) {
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
    if (v >= 4) return 3; // High
    if (v >= 2) return 2; // Medium
    if (v == 1) return 1; // Low
    return 0; // None
  }
}
