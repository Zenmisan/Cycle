import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/sync_bridge.dart';
import '../services/notification_service.dart';

const List<String> kPriorityLabels = ['None', 'Low', 'Medium', 'High'];

/// Full task editor — title, notes, due date/time, tags, priority, project.
/// Every field here already round-trips through CRDT sync (`TaskRecord`
/// carries all of them); this screen is what was missing to actually *set*
/// most of them from the UI.
class TaskDetailScreen extends StatefulWidget {
  final AppDatabase db;
  final String projectId;

  /// Null for a new task.
  final Task? existing;

  const TaskDetailScreen({
    super.key,
    required this.db,
    required this.projectId,
    this.existing,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  DateTime? _due;
  int _priority = 0;
  late String _projectId;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _titleController = TextEditingController(text: t?.title ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _tagsController = TextEditingController(text: t?.tags ?? '');
    _due = t?.due;
    _priority = t?.priority ?? 0;
    _projectId = t?.projectId ?? widget.projectId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    if (!mounted) return;
    setState(() {
      _due = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final id = widget.existing?.id ?? const Uuid().v4();
    final companion = TasksCompanion(
      id: Value(id),
      projectId: Value(_projectId),
      title: Value(_titleController.text.trim()),
      notes: Value(_notesController.text.trim()),
      due: Value(_due),
      tags: Value(_tagsController.text.trim()),
      status: Value(widget.existing?.status ?? 'open'),
      priority: Value(_priority),
      createdAt: Value(widget.existing?.createdAt ?? now),
      updatedAt: Value(now),
    );

    await widget.db.upsertTask(companion);
    final row = await (widget.db.select(
      widget.db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await applyLocalTaskEdit(row);
    await NotificationService.scheduleForTask(row);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New task' : 'Edit task'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: _isNew,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 8,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _due == null
                    ? 'No due date'
                    : DateFormat('EEE, MMM d · HH:mm').format(_due!),
              ),
              trailing: _due != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear due date',
                      onPressed: () => setState(() => _due = null),
                    )
                  : null,
              onTap: _pickDue,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'comma, separated, tags',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),
            Text('Priority', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < kPriorityLabels.length; i++)
                  ButtonSegment(value: i, label: Text(kPriorityLabels[i])),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Project>>(
              stream: widget.db.watchProjects(),
              builder: (context, snapshot) {
                final projects = snapshot.data ?? [];
                if (projects.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String>(
                  initialValue: projects.any((p) => p.id == _projectId)
                      ? _projectId
                      : projects.first.id,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _projectId = v);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
