import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../rust_bridge/api.dart' as rust;
import '../rust_bridge/crdt.dart' as rust show TaskRecord;
import 'database.dart';

/// Glue between Drift (UI-facing relational store) and the Rust Automerge
/// core (conflict-free merge authority) — see PLAN.md's Drift<->Automerge
/// boundary. Every local edit goes through both; every incoming peer sync
/// comes back from Rust as plain tasks and gets upserted into Drift here.

/// Opens the Rust side's connection to the same SQLite file Drift manages.
/// Must be called after Drift has run its migrations (so `sync_changes`
/// exists) and after `RustLib.init()`.
Future<void> initCrdtCore(AppDatabase db) async {
  // Force the connection (and any pending migration) to complete before
  // Rust opens its own connection to the same file.
  await db.select(db.projects).get();
  final path = await AppDatabase.resolveDbFilePath();
  await rust.initCrdt(dbPath: path);
}

rust.TaskRecord _taskToRecord(Task task) {
  return rust.TaskRecord(
    id: task.id,
    projectId: task.projectId,
    title: task.title,
    notes: task.notes,
    dueMillis: task.due?.millisecondsSinceEpoch,
    tags: task.tags.isEmpty ? const [] : task.tags.split(','),
    status: task.status,
    priority: task.priority,
    createdAtMillis: task.createdAt.millisecondsSinceEpoch,
    updatedAtMillis: task.updatedAt.millisecondsSinceEpoch,
  );
}

TasksCompanion _recordToCompanion(rust.TaskRecord r) {
  return TasksCompanion(
    id: Value(r.id),
    projectId: Value(r.projectId),
    title: Value(r.title),
    notes: Value(r.notes),
    due: Value(
      r.dueMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r.dueMillis!),
    ),
    tags: Value(r.tags.join(',')),
    status: Value(r.status),
    priority: Value(r.priority),
    createdAt: Value(DateTime.fromMillisecondsSinceEpoch(r.createdAtMillis)),
    updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(r.updatedAtMillis)),
  );
}

/// Call this alongside every local Drift task write so the CRDT core picks
/// it up too — see PLAN.md, both stores must move together.
Future<void> applyLocalTaskEdit(Task task) {
  return rust.applyTaskEdit(task: _taskToRecord(task));
}

/// Feed a peer's sync message into the CRDT core (however the bytes
/// arrived — this function doesn't know or care) and reflect whatever
/// changed back into Drift's reactive tables.
Future<void> handleIncomingSyncMessage(
  AppDatabase db,
  String peerId,
  Uint8List bytes,
) async {
  final updated = await rust.mergeIncoming(peerId: peerId, bytes: bytes);
  for (final record in updated) {
    await db.upsertTask(_recordToCompanion(record));
  }
}

/// What to send next to the given peer, if anything. Callers must always
/// deliver a non-null result to the peer — see PLAN.md, generating and not
/// sending drops protocol state.
Future<Uint8List?> generateSyncMessageFor(String peerId) {
  return rust.generateSyncMessage(peerId: peerId);
}
