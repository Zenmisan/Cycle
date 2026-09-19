import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/sync_bridge.dart';
import '../services/import/import_result.dart';
import '../services/import/super_productivity_importer.dart';
import '../services/import/todoist_importer.dart';
import '../services/import/vikunja_importer.dart';
import '../services/notification_service.dart';

enum ImportSource { vikunja, todoist, superProductivity }

class ImportScreen extends StatefulWidget {
  final AppDatabase db;

  const ImportScreen({super.key, required this.db});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportSource _source = ImportSource.vikunja;

  // Controllers
  final _vikunjaUrlController = TextEditingController();
  final _vikunjaTokenController = TextEditingController();
  final _todoistTokenController = TextEditingController();
  final _superProductivityJsonController = TextEditingController();

  String? _selectedFilePath;
  bool _isLoading = false;
  String? _errorMessage;
  ImportResult? _previewResult;

  @override
  void dispose() {
    _vikunjaUrlController.dispose();
    _vikunjaTokenController.dispose();
    _todoistTokenController.dispose();
    _superProductivityJsonController.dispose();
    super.dispose();
  }

  Future<void> _pickSuperProductivityFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isNotEmpty && files.first.path != null) {
        setState(() {
          _selectedFilePath = files.first.path;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to pick file: $e');
    }
  }

  Future<void> _runPreview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _previewResult = null;
    });

    try {
      ImportResult result;
      switch (_source) {
        case ImportSource.vikunja:
          final url = _vikunjaUrlController.text.trim();
          final token = _vikunjaTokenController.text.trim();
          if (url.isEmpty || token.isEmpty) {
            throw Exception('Vikunja Base URL and API Token are required');
          }
          final importer = VikunjaImporter();
          result = await importer.importFromApi(baseUrl: url, token: token);
          break;

        case ImportSource.todoist:
          final token = _todoistTokenController.text.trim();
          if (token.isEmpty) {
            throw Exception('Todoist API Token is required');
          }
          final importer = TodoistImporter();
          result = await importer.importFromApi(token: token);
          break;

        case ImportSource.superProductivity:
          final importer = SuperProductivityImporter();
          if (_selectedFilePath != null) {
            result = await importer.importFromFile(_selectedFilePath!);
          } else {
            final jsonStr = _superProductivityJsonController.text.trim();
            if (jsonStr.isEmpty) {
              throw Exception('Select an export JSON file or paste JSON content');
            }
            result = SuperProductivityImporter.parseJsonString(jsonStr);
          }
          break;
      }

      setState(() {
        _previewResult = result;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _commitImport() async {
    final preview = _previewResult;
    if (preview == null || (preview.projects.isEmpty && preview.tasks.isEmpty)) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Create projects and record their new IDs
      final projectIds = <String>[];
      for (final p in preview.projects) {
        final newId = const Uuid().v4();
        projectIds.add(newId);
        await widget.db.upsertProject(
          ProjectsCompanion.insert(
            id: newId,
            name: p.name,
            color: p.color,
          ),
        );
      }

      // Fallback if no project was generated
      if (projectIds.isEmpty) {
        final defaultId = const Uuid().v4();
        projectIds.add(defaultId);
        await widget.db.upsertProject(
          ProjectsCompanion.insert(
            id: defaultId,
            name: 'Imported',
            color: '#009688',
          ),
        );
      }

      // 2. Create tasks with generated UUIDs
      final now = DateTime.now();
      for (final t in preview.tasks) {
        final newTaskId = const Uuid().v4();
        final targetProjectId = (t.projectIndex >= 0 && t.projectIndex < projectIds.length)
            ? projectIds[t.projectIndex]
            : projectIds.first;

        final companion = TasksCompanion.insert(
          id: newTaskId,
          projectId: targetProjectId,
          title: t.title,
          notes: Value(t.notes),
          due: Value(t.due),
          tags: Value(t.tags.join(',')),
          status: Value(t.status),
          priority: Value(t.priority),
          createdAt: now,
          updatedAt: now,
        );

        await widget.db.upsertTask(companion);
        final row = await (widget.db.select(widget.db.tasks)
              ..where((tbl) => tbl.id.equals(newTaskId)))
            .getSingle();

        // Feed to CRDT engine
        await applyLocalTaskEdit(row);

        // Schedule notification if task has a due date
        await NotificationService.scheduleForTask(row);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully imported ${preview.tasks.length} task${preview.tasks.length == 1 ? '' : 's'} across ${preview.projects.length} project${preview.projects.length == 1 ? '' : 's'}!',
            ),
            backgroundColor: Colors.teal.shade700,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed during import: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Tasks'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source selector
            SegmentedButton<ImportSource>(
              segments: const [
                ButtonSegment(
                  value: ImportSource.vikunja,
                  label: Text('Vikunja'),
                  icon: Icon(Icons.cloud_download_outlined),
                ),
                ButtonSegment(
                  value: ImportSource.todoist,
                  label: Text('Todoist'),
                  icon: Icon(Icons.check_circle_outline),
                ),
                ButtonSegment(
                  value: ImportSource.superProductivity,
                  label: Text('Super Prod.'),
                  icon: Icon(Icons.file_present_outlined),
                ),
              ],
              selected: {_source},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _source = newSelection.first;
                  _errorMessage = null;
                  _previewResult = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // Source inputs
            if (_source == ImportSource.vikunja) ...[
              TextField(
                controller: _vikunjaUrlController,
                decoration: const InputDecoration(
                  labelText: 'Vikunja Base URL',
                  hintText: 'https://vikunja.example.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vikunjaTokenController,
                decoration: const InputDecoration(
                  labelText: 'API Token',
                  hintText: 'Generated in Settings > API Tokens',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                obscureText: true,
              ),
            ] else if (_source == ImportSource.todoist) ...[
              TextField(
                controller: _todoistTokenController,
                decoration: const InputDecoration(
                  labelText: 'Todoist API Token',
                  hintText: 'Settings > Integrations > Developer API Token',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Uses Todoist REST API v2 with your personal API token.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _pickSuperProductivityFile,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _selectedFilePath != null
                      ? 'Selected: ${_selectedFilePath!.split('/').last}'
                      : 'Choose Super Productivity Export JSON',
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text('— OR Paste Export JSON —', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _superProductivityJsonController,
                decoration: const InputDecoration(
                  labelText: 'JSON Content',
                  hintText: '{"project": {...}, "task": {...}}',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
            ],

            const SizedBox(height: 20),

            // Action: Preview button
            FilledButton.icon(
              onPressed: _isLoading ? null : _runPreview,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.visibility),
              label: Text(_isLoading ? 'Fetching...' : 'Preview Import'),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade900.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ],

            // Preview result section
            if (_previewResult != null) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(
                            'Ready to Import',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Found ${_previewResult!.tasks.length} task${_previewResult!.tasks.length == 1 ? '' : 's'} across ${_previewResult!.projects.length} project${_previewResult!.projects.length == 1 ? '' : 's'}.',
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Projects:',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _previewResult!.projects.map((p) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Color(int.parse(
                                p.color.replaceFirst('#', '0xff'),
                              )),
                              radius: 6,
                            ),
                            label: Text(p.name),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _commitImport,
                        icon: const Icon(Icons.download),
                        label: Text('Import ${_previewResult!.tasks.length} Tasks Now'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
