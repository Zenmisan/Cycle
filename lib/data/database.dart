import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Projects, Tasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Stream<List<Project>> watchProjects() => select(projects).watch();

  Stream<List<Task>> watchTasksForProject(String projectId) {
    return (select(tasks)..where((t) => t.projectId.equals(projectId)))
        .watch();
  }

  Future<void> upsertProject(ProjectsCompanion entry) =>
      into(projects).insertOnConflictUpdate(entry);

  Future<void> upsertTask(TasksCompanion entry) =>
      into(tasks).insertOnConflictUpdate(entry);

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  Future<void> deleteProject(String id) =>
      (delete(projects)..where((p) => p.id.equals(id))).go();
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'cycles');
}
