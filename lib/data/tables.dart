import 'package:drift/drift.dart';

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get due => dateTime().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Automerge change bytes, written/read directly by the Rust core via a
/// separate SQLite connection to this same database file. Dart never parses
/// these bytes — see PLAN.md's Drift<->Automerge boundary.
class SyncChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  BlobColumn get changeBytes => blob()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Relay (phase 6, opt-in last-resort sync) configuration. Single row,
/// `id` always 0 — off by default, user must explicitly enable and supply
/// their own self-hosted relay's URL + shared-secret token.
class RelaySettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get relayUrl => text().withDefault(const Constant(''))();
  TextColumn get token => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}
