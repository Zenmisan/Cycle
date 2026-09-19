# Cycles: Data Import & Migration Guide

Cycles makes it seamless to migrate your projects, tasks, notes, tags, and priorities from existing task management tools. Because Cycles is completely local-first and account-free, your imported data remains strictly on your device.

---

## 1. Supported Import Sources

| Source Platform | Method | Supported Entities | Requirements |
|---|---|---|---|
| **Vikunja** | Live REST API | Projects, Tasks, Due Dates, Notes, Priorities, Done status | Self-hosted or cloud Vikunja URL + API Token |
| **Todoist** | REST API v2 | Projects, Tasks, Due Dates, Descriptions, Priorities (1..4) | Personal API Token (Integrations settings) |
| **Super Productivity** | JSON File Export | Projects, Tasks, Subtasks, Notes, Done status | Export file from Super Productivity desktop or web |

---

## 2. Vikunja Migration

[Vikunja](https://vikunja.io/) is an open-source task manager.

### 2.1. Obtaining an API Token
1. Open your Vikunja web interface.
2. Navigate to **Settings** → **API Tokens**.
3. Create a token with **Read** access to Projects and Tasks.

### 2.2. Importing into Cycles
1. In Cycles, open the menu and tap **Import Tasks**.
2. Select **Vikunja**.
3. Enter your **Vikunja Instance URL** (e.g. `https://tasks.example.com` or `https://app.vikunja.io`).
4. Paste your **API Token**.
5. Tap **Preview Import** to review task and project counts.
6. Tap **Import Now** to commit records into Cycles's local database and CRDT log.

---

## 3. Todoist Migration

### 3.1. Obtaining an API Token
1. Open [Todoist Web](https://todoist.com/).
2. Navigate to **Settings** → **Integrations** → **Developer**.
3. Scroll down to find your **API Token** and copy it.

### 3.2. Priority Translation
Todoist uses inverse priority numbering compared to standard systems:
- Priority 4 (p1, Urgent / Red) → Cycles Priority 3 (High)
- Priority 3 (p2, Medium / Orange) → Cycles Priority 2 (Medium)
- Priority 2 (p3, Low / Blue) → Cycles Priority 1 (Low)
- Priority 1 (p4, Normal / Grey) → Cycles Priority 0 (None)

### 3.3. Importing into Cycles
1. Open **Import Tasks** in Cycles.
2. Select **Todoist**.
3. Paste your API token and tap **Preview Import**.
4. Confirm to import all active projects and uncompleted/completed tasks.

---

## 4. Super Productivity Migration

[Super Productivity](https://super-productivity.com/) is a popular local-first productivity tool.

### 4.1. Exporting Your Data
1. Open Super Productivity on your computer or phone.
2. Navigate to **Settings** → **Import/Export**.
3. Select **Export to File** and save the `.json` file to your device.

### 4.2. Importing into Cycles
1. Open **Import Tasks** in Cycles.
2. Select **Super Productivity**.
3. Tap **Browse File** to pick the exported JSON file.
4. Preview the discovered projects and task tree.
5. Tap **Import Now**.

---

## 5. Privacy & Conflict Guarantees During Import

1. **New UUID Assignment**: All imported projects and tasks are assigned fresh UUIDv4 identifiers. This prevents any possibility of foreign ID collisions with existing tasks in Cycles.
2. **Deterministic CRDT Seeding**: Each imported record is committed through `db.upsertProject` and `applyLocalTaskEdit`. This generates Automerge binary change vectors into `sync_changes`, ensuring the newly imported items immediately replicate to your other paired devices during the next proximity sync.
3. **Notification Scheduling**: Any imported tasks with future due dates automatically schedule local notifications on your device.
