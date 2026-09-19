import 'package:flutter_test/flutter_test.dart';
import 'package:cycles/services/import/vikunja_importer.dart';
import 'package:cycles/services/import/todoist_importer.dart';
import 'package:cycles/services/import/super_productivity_importer.dart';

void main() {
  group('VikunjaImporter', () {
    test('parses Vikunja projects and tasks correctly', () {
      final projectsJson = [
        {'id': 101, 'title': 'Work Project', 'hex_color': '#ff5722'},
        {'id': 102, 'title': 'Home Chores', 'hex_color': '009688'},
      ];

      final tasksJson = [
        {
          'id': 1,
          'project_id': 101,
          'title': 'Ship Phase 7',
          'description': 'Finish platform polish and import',
          'done': false,
          'priority': 5, // High
          'due_date': '2026-09-20T14:30:00Z',
          'labels': [{'title': 'dev'}, {'title': 'cycles'}],
        },
        {
          'id': 2,
          'project_id': 102,
          'title': 'Buy groceries',
          'description': 'Milk, eggs, coffee',
          'done': true,
          'priority': 1, // Low
          'due_date': null,
          'labels': ['shopping'],
        },
      ];

      final result = VikunjaImporter.parseJson(
        projectsJson: projectsJson,
        tasksJson: tasksJson,
      );

      expect(result.projects.length, 2);
      expect(result.projects[0].name, 'Work Project');
      expect(result.projects[0].color, '#ff5722');
      expect(result.projects[1].name, 'Home Chores');
      expect(result.projects[1].color, '#009688');

      expect(result.tasks.length, 2);

      // Task 1
      final t1 = result.tasks[0];
      expect(t1.title, 'Ship Phase 7');
      expect(t1.notes, 'Finish platform polish and import');
      expect(t1.projectIndex, 0);
      expect(t1.status, 'open');
      expect(t1.priority, 3); // Mapped from 5 to High (3)
      expect(t1.due, isNotNull);
      expect(t1.tags, ['dev', 'cycles']);

      // Task 2
      final t2 = result.tasks[1];
      expect(t2.title, 'Buy groceries');
      expect(t2.notes, 'Milk, eggs, coffee');
      expect(t2.projectIndex, 1);
      expect(t2.status, 'completed');
      expect(t2.priority, 1); // Mapped from 1 to Low (1)
      expect(t2.due, isNull);
      expect(t2.tags, ['shopping']);
    });

    test('creates default Inbox project when projects list is empty', () {
      final result = VikunjaImporter.parseJson(
        projectsJson: [],
        tasksJson: [
          {'title': 'Orphan task', 'done': false}
        ],
      );

      expect(result.projects.length, 1);
      expect(result.projects[0].name, 'Inbox');
      expect(result.tasks.length, 1);
      expect(result.tasks[0].projectIndex, 0);
    });
  });

  group('TodoistImporter', () {
    test('parses Todoist projects and tasks correctly', () {
      final projectsJson = [
        {'id': 'proj_1', 'name': 'Todoist Work', 'color': 'charcoal'},
      ];

      final tasksJson = [
        {
          'id': 'task_1',
          'project_id': 'proj_1',
          'content': 'Write release notes',
          'description': 'Draft v1.0 notes',
          'is_completed': false,
          'priority': 4, // Urgent in Todoist -> High (3) in Cycles
          'due': {'datetime': '2026-09-21T09:00:00Z'},
          'labels': ['release', 'docs'],
        },
        {
          'id': 'task_2',
          'project_id': 'proj_1',
          'content': 'Fix minor typo',
          'description': '',
          'is_completed': true,
          'priority': 1, // Normal in Todoist -> None (0) in Cycles
          'due': null,
          'labels': [],
        },
      ];

      final result = TodoistImporter.parseJson(
        projectsJson: projectsJson,
        tasksJson: tasksJson,
      );

      expect(result.projects.length, 1);
      expect(result.projects[0].name, 'Todoist Work');

      expect(result.tasks.length, 2);
      expect(result.tasks[0].title, 'Write release notes');
      expect(result.tasks[0].priority, 3);
      expect(result.tasks[0].status, 'open');
      expect(result.tasks[0].tags, ['release', 'docs']);
      expect(result.tasks[0].due, isNotNull);

      expect(result.tasks[1].title, 'Fix minor typo');
      expect(result.tasks[1].priority, 0);
      expect(result.tasks[1].status, 'completed');
    });
  });

  group('SuperProductivityImporter', () {
    test('parses nested Super Productivity export data map', () {
      final data = {
        'project': {
          'projects': [
            {
              'id': 'sp_proj_1',
              'title': 'Sprint 4',
              'theme': {'primary': '#9c27b0'},
            }
          ]
        },
        'task': {
          'tasks': [
            {
              'id': 'sp_task_1',
              'projectId': 'sp_proj_1',
              'title': 'Implement offline sync',
              'notes': 'CRDT integration',
              'isDone': false,
              'priority': 2,
              'plannedAt': 1789885200000,
              'tagIds': ['offline', 'rust'],
            }
          ]
        }
      };

      final result = SuperProductivityImporter.parseDataMap(data);

      expect(result.projects.length, 1);
      expect(result.projects[0].name, 'Sprint 4');
      expect(result.projects[0].color, '#9c27b0');

      expect(result.tasks.length, 1);
      expect(result.tasks[0].title, 'Implement offline sync');
      expect(result.tasks[0].notes, 'CRDT integration');
      expect(result.tasks[0].status, 'open');
      expect(result.tasks[0].priority, 2);
      expect(result.tasks[0].due, isNotNull);
      expect(result.tasks[0].tags, ['offline', 'rust']);
    });

    test('parses Super Productivity export from JSON string', () {
      const jsonStr = '''
      {
        "projects": [
          {"id": "p1", "title": "Simple Project"}
        ],
        "tasks": [
          {"projectId": "p1", "title": "Simple Task", "isDone": true}
        ]
      }
      ''';

      final result = SuperProductivityImporter.parseJsonString(jsonStr);

      expect(result.projects.length, 1);
      expect(result.projects[0].name, 'Simple Project');
      expect(result.tasks.length, 1);
      expect(result.tasks[0].title, 'Simple Task');
      expect(result.tasks[0].status, 'completed');
    });
  });
}
