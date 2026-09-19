import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/database.dart';
import 'rust_bridge/api.dart' as rust;
import 'rust_bridge/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    await RustLib.init();
  }
  runApp(CyclesApp(db: AppDatabase()));
}

class CyclesApp extends StatelessWidget {
  final AppDatabase db;
  const CyclesApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cycles',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: ProjectListScreen(db: db),
    );
  }
}

class ProjectListScreen extends StatelessWidget {
  final AppDatabase db;
  const ProjectListScreen({super.key, required this.db});

  Future<void> _addProject(BuildContext context) async {
    final name = await _promptText(context, title: 'New project');
    if (name == null || name.trim().isEmpty) return;
    await db.upsertProject(ProjectsCompanion.insert(
      id: const Uuid().v4(),
      name: name.trim(),
      color: '#009688',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cycles')),
      body: StreamBuilder<List<Project>>(
        stream: db.watchProjects(),
        builder: (context, snapshot) {
          final projects = snapshot.data ?? [];
          if (projects.isEmpty) {
            return const Center(child: Text('No projects yet. Tap + to add one.'));
          }
          return ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, i) {
              final p = projects[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(int.parse(p.color.replaceFirst('#', '0xff'))),
                ),
                title: Text(p.name),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TaskListScreen(db: db, project: p),
                )),
                onLongPress: () async {
                  await db.deleteProject(p.id);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kDebugMode)
            FloatingActionButton.small(
              heroTag: 'ffi-ping',
              onPressed: () async {
                final result = await rust.ping(name: 'cycles');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('FFI: $result')),
                  );
                }
              },
              child: const Icon(Icons.bolt),
            ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: () => _addProject(context),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class TaskListScreen extends StatelessWidget {
  final AppDatabase db;
  final Project project;
  const TaskListScreen({super.key, required this.db, required this.project});

  Future<void> _addTask(BuildContext context) async {
    final title = await _promptText(context, title: 'New task');
    if (title == null || title.trim().isEmpty) return;
    final now = DateTime.now();
    await db.upsertTask(TasksCompanion.insert(
      id: const Uuid().v4(),
      projectId: project.id,
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> _editTask(BuildContext context, Task task) async {
    final title = await _promptText(context, title: 'Edit task', initial: task.title);
    if (title == null || title.trim().isEmpty) return;
    await db.upsertTask(TasksCompanion(
      id: Value(task.id),
      projectId: Value(task.projectId),
      title: Value(title.trim()),
      notes: Value(task.notes),
      due: Value(task.due),
      tags: Value(task.tags),
      status: Value(task.status),
      priority: Value(task.priority),
      createdAt: Value(task.createdAt),
      updatedAt: Value(DateTime.now()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: StreamBuilder<List<Task>>(
        stream: db.watchTasksForProject(project.id),
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks yet. Tap + to add one.'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, i) {
              final t = tasks[i];
              final done = t.status == 'done';
              return ListTile(
                leading: Checkbox(
                  value: done,
                  onChanged: (_) async {
                    await db.upsertTask(TasksCompanion(
                      id: Value(t.id),
                      projectId: Value(t.projectId),
                      title: Value(t.title),
                      notes: Value(t.notes),
                      due: Value(t.due),
                      tags: Value(t.tags),
                      status: Value(done ? 'open' : 'done'),
                      priority: Value(t.priority),
                      createdAt: Value(t.createdAt),
                      updatedAt: Value(DateTime.now()),
                    ));
                  },
                ),
                title: Text(
                  t.title,
                  style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                onTap: () => _editTask(context, t),
                onLongPress: () async {
                  await db.deleteTask(t.id);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTask(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

Future<String?> _promptText(BuildContext context, {required String title, String? initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
