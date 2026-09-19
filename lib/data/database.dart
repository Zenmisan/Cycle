import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Projects, Tasks, SyncChanges, RelaySettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(syncChanges);
      }
      if (from < 3) {
        await m.createTable(relaySettings);
      }
    },
  );

  /// The single relay settings row, creating a disabled default if absent.
  Future<RelaySetting> getRelaySettings() async {
    final existing = await (select(
      relaySettings,
    )..where((r) => r.id.equals(0))).getSingleOrNull();
    if (existing != null) return existing;
    final defaults = RelaySettingsCompanion.insert(id: const Value(0));
    await into(relaySettings).insertOnConflictUpdate(defaults);
    return (select(
      relaySettings,
    )..where((r) => r.id.equals(0))).getSingle();
  }

  Future<void> setRelaySettings({
    required bool enabled,
    required String relayUrl,
    required String token,
  }) {
    return into(relaySettings).insertOnConflictUpdate(
      RelaySettingsCompanion(
        id: const Value(0),
        enabled: Value(enabled),
        relayUrl: Value(relayUrl),
        token: Value(token),
      ),
    );
  }

  /// Absolute path to the underlying SQLite file, for handing to the Rust
  /// core so it can open its own connection (see PLAN.md's Drift<->Automerge
  /// boundary — Rust reads/writes `sync_changes` directly). Mirrors the path
  /// logic `driftDatabase(name: 'cycles')` uses internally — there's no public
  /// API to ask it for the resolved path directly.
  static Future<String> resolveDbFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'cycles.sqlite');
  }

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
