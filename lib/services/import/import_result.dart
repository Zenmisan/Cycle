/// Source-agnostic shape every importer maps its data into, so the import
/// screen can preview/commit generically regardless of where it came from.
class ImportedProject {
  final String name;
  final String color;
  ImportedProject({required this.name, this.color = '#009688'});
}

class ImportedTask {
  /// Index into the returned `ImportResult.projects` list — importers don't
  /// know final uuids yet (those get assigned on commit, never reuse a
  /// foreign source's own IDs directly, they might collide with existing
  /// local ones).
  final int projectIndex;
  final String title;
  final String notes;
  final DateTime? due;
  final List<String> tags;
  final String status;
  final int priority;

  ImportedTask({
    required this.projectIndex,
    required this.title,
    this.notes = '',
    this.due,
    this.tags = const [],
    this.status = 'open',
    this.priority = 0,
  });
}

class ImportResult {
  final List<ImportedProject> projects;
  final List<ImportedTask> tasks;
  ImportResult({required this.projects, required this.tasks});
}
