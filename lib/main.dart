import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data/database.dart';
import 'data/sync_bridge.dart';
import 'rust_bridge/api.dart' as rust;
import 'rust_bridge/frb_generated.dart';
import 'services/ble_sync_service.dart';
import 'services/notification_service.dart';
import 'services/recurrence_service.dart';
import 'ui/import_screen.dart';
import 'ui/peers_screen.dart';
import 'ui/relay_settings_screen.dart';
import 'ui/task_detail_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Always init — the CRDT core is real functionality, not just the debug
  // ping demo (that button below stays kDebugMode-gated on its own).
  await RustLib.init();
  final db = AppDatabase();
  await initCrdtCore(db);
  await NotificationService.init();
  runApp(CyclesApp(db: db));
}

class CyclesApp extends StatelessWidget {
  final AppDatabase db;
  final BleSyncService bleService;

  CyclesApp({
    super.key,
    required this.db,
    BleSyncService? bleService,
  }) : bleService = bleService ?? BleSyncService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cycles',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: ProjectListScreen(db: db, bleService: bleService),
    );
  }
}

class ProjectListScreen extends StatelessWidget {
  final AppDatabase db;
  final BleSyncService bleService;

  const ProjectListScreen({
    super.key,
    required this.db,
    required this.bleService,
  });

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
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Image.asset('assets/icon/logo.png'),
        ),
        title: const Text('Cycles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Nearby Sync',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PeersScreen(
                  db: db,
                  bleService: bleService,
                ),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Remote Sync (Relay)',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RelaySettingsScreen(db: db),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Import tasks',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ImportScreen(db: db),
              ));
            },
          ),
        ],
      ),
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

  Future<void> _upsertAndSync(TasksCompanion companion, String id) async {
    await db.upsertTask(companion);
    final row = await (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
    await applyLocalTaskEdit(row);
    await NotificationService.scheduleForTask(row);
  }

  void _openTaskDetail(BuildContext context, {Task? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskDetailScreen(
        db: db,
        projectId: project.id,
        existing: existing,
      ),
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
                    final newStatus = done ? 'open' : 'done';
                    await _upsertAndSync(
                      TasksCompanion(
                        id: Value(t.id),
                        projectId: Value(t.projectId),
                        title: Value(t.title),
                        notes: Value(t.notes),
                        due: Value(t.due),
                        tags: Value(t.tags),
                        status: Value(newStatus),
                        priority: Value(t.priority),
                        createdAt: Value(t.createdAt),
                        updatedAt: Value(DateTime.now()),
                      ),
                      t.id,
                    );
                    if (newStatus == 'done') {
                      await NotificationService.cancelForTask(t.id);
                      await RecurrenceService.spawnNextOccurrence(
                        completedTask: t,
                        db: db,
                      );
                    }
                  },
                ),
                title: Text(
                  t.title,
                  style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                subtitle: (t.due != null || t.priority > 0 || RecurrenceService.extractRule(t.tags) != 'None')
                    ? Text([
                        if (t.due != null)
                          DateFormat('MMM d, HH:mm').format(t.due!),
                        if (t.priority > 0) kPriorityLabels[t.priority],
                        if (RecurrenceService.extractRule(t.tags) != 'None')
                          'Repeat: ${RecurrenceService.extractRule(t.tags)}',
                      ].join(' · '))
                    : null,
                onTap: () => _openTaskDetail(context, existing: t),
                onLongPress: () async {
                  await NotificationService.cancelForTask(t.id);
                  await db.deleteTask(t.id);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskDetail(context),
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
