import 'dart:convert';
import 'dart:io';
import 'import_result.dart';

/// Importer for Super Productivity JSON exports.
/// Parses the export file and maps its projects and tasks into an ImportResult.
class SuperProductivityImporter {
  /// Reads and parses an export file from a local filesystem path.
  Future<ImportResult> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Super Productivity export file not found at: $filePath');
    }
    final content = await file.readAsString();
    return parseJsonString(content);
  }

  /// Parses a raw JSON string from a Super Productivity export.
  static ImportResult parseJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw Exception('Invalid Super Productivity export: root must be a JSON object');
    }
    return parseDataMap(decoded as Map<String, dynamic>);
  }

  /// Parses the decoded map from a Super Productivity export.
  static ImportResult parseDataMap(Map<String, dynamic> data) {
    // 1. Extract projects
    List<dynamic> rawProjects = [];
    if (data['project'] is Map && data['project']['projects'] is List) {
      rawProjects = data['project']['projects'] as List;
    } else if (data['projects'] is List) {
      rawProjects = data['projects'] as List;
    }

    final List<ImportedProject> projects = [];
    final Map<String, int> foreignIdToIndex = {};

    for (int i = 0; i < rawProjects.length; i++) {
      final p = rawProjects[i];
      if (p is! Map) continue;

      final id = '${p['id'] ?? i}';
      final title = p['title'] as String? ?? p['name'] as String? ?? 'Untitled Project';

      String color = '#009688';
      if (p['theme'] is Map && p['theme']['primary'] is String) {
        color = p['theme']['primary'] as String;
      }

      foreignIdToIndex[id] = projects.length;
      projects.add(ImportedProject(
        name: title.trim().isEmpty ? 'Untitled Project' : title.trim(),
        color: color.startsWith('#') ? color : '#$color',
      ));
    }

    if (projects.isEmpty) {
      projects.add(ImportedProject(name: 'Super Productivity Inbox', color: '#009688'));
    }

    // 2. Extract tasks
    List<dynamic> rawTasks = [];
    if (data['task'] is Map && data['task']['tasks'] is List) {
      rawTasks = data['task']['tasks'] as List;
    } else if (data['tasks'] is List) {
      rawTasks = data['tasks'] as List;
    }

    final List<ImportedTask> tasks = [];
    for (final t in rawTasks) {
      if (t is! Map) continue;

      final title = t['title'] as String? ?? '';
      if (title.trim().isEmpty) continue;

      final pId = '${t['projectId'] ?? ''}';
      final projectIndex = foreignIdToIndex[pId] ?? 0;

      final notes = t['notes'] as String? ?? '';
      final isDone = t['isDone'] as bool? ?? false;
      final status = isDone ? 'completed' : 'open';

      // Due date parsing: check plannedAt, remindAt, or due
      DateTime? due;
      if (t['plannedAt'] is int) {
        due = DateTime.fromMillisecondsSinceEpoch(t['plannedAt'] as int).toLocal();
      } else if (t['remindAt'] is int) {
        due = DateTime.fromMillisecondsSinceEpoch(t['remindAt'] as int).toLocal();
      } else if (t['due'] is String) {
        due = DateTime.tryParse(t['due'] as String)?.toLocal();
      }

      // Priority mapping
      final rawPrio = t['priority'] is int ? t['priority'] as int : 0;
      final priority = rawPrio.clamp(0, 3);

      // Tags mapping
      final List<String> tags = [];
      if (t['tagIds'] is List) {
        for (final tag in t['tagIds'] as List) {
          if (tag is String && tag.trim().isNotEmpty) {
            tags.add(tag.trim());
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
}
