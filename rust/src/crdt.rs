use automerge::sync::{Message as SyncMessage, State as SyncState};
use automerge::transaction::Transactable;
use automerge::{AutoCommit, ObjType, ReadDoc, ScalarValue, Value, ROOT};

/// Plain-data view of a task, for handing across the FFI boundary to Dart.
#[derive(Debug, Clone, PartialEq)]
pub struct TaskRecord {
    pub id: String,
    pub project_id: String,
    pub title: String,
    pub notes: String,
    pub due_millis: Option<i64>,
    pub tags: Vec<String>,
    pub status: String,
    pub priority: i64,
    pub created_at_millis: i64,
    pub updated_at_millis: i64,
}

/// Wraps a single Automerge document holding tasks directly on the document
/// root, one nested map per task keyed `task:<id>`.
///
/// Deliberately NOT nested under an intermediate "tasks" container object:
/// `ROOT` is the one object guaranteed to have the same identity across every
/// independently-created device document, because Automerge allocates a fresh,
/// distinct object ID each time `put_object` creates a *new* container. Two
/// devices that each call `put_object(ROOT, "tasks", Map)` before ever syncing
/// end up with two different objects at that key — a genuine concurrent-write
/// conflict, where `get()` silently returns only one winner and the other
/// device's entire task list becomes unreadable post-merge. Keying tasks
/// directly under `ROOT` (unique-per-task key, so only the task's own creator
/// ever allocates its object) sidesteps this. See PLAN.md's Drift<->Automerge
/// boundary — this is the whole CRDT surface area, no networking here.
pub struct TaskDoc {
    doc: AutoCommit,
}

fn task_key(id: &str) -> String {
    format!("task:{id}")
}

impl TaskDoc {
    pub fn new() -> Self {
        Self {
            doc: AutoCommit::new(),
        }
    }

    /// Reconstruct a document from previously persisted change bytes
    /// (the concatenated contents of the `sync_changes` table).
    pub fn load(bytes: &[u8]) -> Result<Self, String> {
        if bytes.is_empty() {
            return Ok(Self::new());
        }
        AutoCommit::load(bytes)
            .map(|doc| Self { doc })
            .map_err(|e| e.to_string())
    }

    /// Insert or overwrite a task's fields (last-write-wins per field, which is
    /// what Automerge's map `put` gives us — good enough for scalar task fields).
    pub fn upsert_task(&mut self, task: &TaskRecord) -> Result<(), String> {
        let key = task_key(&task.id);
        let task_obj = match self.doc.get(ROOT, key.as_str()).map_err(|e| e.to_string())? {
            Some((_, id)) => id,
            None => self
                .doc
                .put_object(ROOT, key.as_str(), ObjType::Map)
                .map_err(|e| e.to_string())?,
        };

        self.doc
            .put(&task_obj, "project_id", task.project_id.clone())
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "title", task.title.clone())
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "notes", task.notes.clone())
            .map_err(|e| e.to_string())?;
        self.doc
            .put(
                &task_obj,
                "due_millis",
                match task.due_millis {
                    Some(v) => ScalarValue::Int(v),
                    None => ScalarValue::Null,
                },
            )
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "status", task.status.clone())
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "priority", task.priority)
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "created_at_millis", task.created_at_millis)
            .map_err(|e| e.to_string())?;
        self.doc
            .put(&task_obj, "updated_at_millis", task.updated_at_millis)
            .map_err(|e| e.to_string())?;

        let tags_obj = self
            .doc
            .put_object(&task_obj, "tags", ObjType::List)
            .map_err(|e| e.to_string())?;
        for (i, tag) in task.tags.iter().enumerate() {
            self.doc
                .insert(&tags_obj, i, tag.clone())
                .map_err(|e| e.to_string())?;
        }

        self.doc.commit();
        Ok(())
    }

    /// Read every task currently in the document.
    pub fn all_tasks(&self) -> Vec<TaskRecord> {
        let mut out = Vec::new();
        for item in self.doc.map_range(ROOT, "task:".to_string()..="task;".to_string()) {
            if let Some(id) = item.key.strip_prefix("task:") {
                let task_obj = item.id();
                out.push(self.read_task(id, &task_obj));
            }
        }
        out
    }

    fn read_task(&self, id: &str, task_obj: &automerge::ObjId) -> TaskRecord {
        let get_str = |key: &str| -> String {
            match self.doc.get(task_obj, key) {
                Ok(Some((Value::Scalar(v), _))) => match v.as_ref() {
                    ScalarValue::Str(s) => s.to_string(),
                    _ => String::new(),
                },
                _ => String::new(),
            }
        };
        let get_int = |key: &str| -> i64 {
            match self.doc.get(task_obj, key) {
                Ok(Some((Value::Scalar(v), _))) => match v.as_ref() {
                    ScalarValue::Int(i) => *i,
                    ScalarValue::Uint(u) => *u as i64,
                    _ => 0,
                },
                _ => 0,
            }
        };
        let get_opt_int = |key: &str| -> Option<i64> {
            match self.doc.get(task_obj, key) {
                Ok(Some((Value::Scalar(v), _))) => match v.as_ref() {
                    ScalarValue::Int(i) => Some(*i),
                    ScalarValue::Uint(u) => Some(*u as i64),
                    _ => None,
                },
                _ => None,
            }
        };
        let tags = match self.doc.get(task_obj, "tags") {
            Ok(Some((_, tags_obj))) => {
                let len = self.doc.length(&tags_obj);
                (0..len)
                    .filter_map(|i| match self.doc.get(&tags_obj, i) {
                        Ok(Some((Value::Scalar(v), _))) => match v.as_ref() {
                            ScalarValue::Str(s) => Some(s.to_string()),
                            _ => None,
                        },
                        _ => None,
                    })
                    .collect()
            }
            _ => Vec::new(),
        };

        TaskRecord {
            id: id.to_string(),
            project_id: get_str("project_id"),
            title: get_str("title"),
            notes: get_str("notes"),
            due_millis: get_opt_int("due_millis"),
            tags,
            status: get_str("status"),
            priority: get_int("priority"),
            created_at_millis: get_int("created_at_millis"),
            updated_at_millis: get_int("updated_at_millis"),
        }
    }

    /// Bytes representing every change since the document was loaded/created.
    /// Callers persist this to the `sync_changes` table.
    pub fn save_incremental(&mut self) -> Vec<u8> {
        self.doc.save_incremental()
    }
}

impl Default for TaskDoc {
    fn default() -> Self {
        Self::new()
    }
}

/// What changed locally as a result of merging a peer's message. Callers
/// decide separately (via `SyncSession::generate_message`) whether there's
/// anything to send back — never call `generate_message` and discard the
/// result, that silently drops protocol state the peer is waiting on.
pub struct MergeOutcome {
    pub updated_tasks: Vec<TaskRecord>,
}

/// Drives Automerge's built-in sync protocol for one peer. Callers keep one of
/// these per peer connection (see PLAN.md's tie-breaking / pairing model).
pub struct SyncSession {
    state: SyncState,
}

impl SyncSession {
    pub fn new() -> Self {
        Self {
            state: SyncState::new(),
        }
    }

    /// What this side should send next to make progress, if anything.
    pub fn generate_message(&mut self, doc: &mut TaskDoc) -> Option<Vec<u8>> {
        use automerge::sync::SyncDoc;
        doc.doc
            .sync()
            .generate_sync_message(&mut self.state)
            .map(|m| m.encode())
    }

    /// Apply a peer's sync message, returning the tasks that changed as a result.
    /// After calling this, callers should call `generate_message` to see if a
    /// reply is needed to keep the sync round going — don't skip that step.
    pub fn receive_message(
        &mut self,
        doc: &mut TaskDoc,
        bytes: Vec<u8>,
    ) -> Result<MergeOutcome, String> {
        use automerge::sync::SyncDoc;
        let message = SyncMessage::decode(&bytes).map_err(|e| e.to_string())?;
        doc.doc
            .sync()
            .receive_sync_message(&mut self.state, message)
            .map_err(|e| e.to_string())?;

        Ok(MergeOutcome {
            updated_tasks: doc.all_tasks(),
        })
    }
}

impl Default for SyncSession {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_task(id: &str, title: &str) -> TaskRecord {
        TaskRecord {
            id: id.to_string(),
            project_id: "proj-1".to_string(),
            title: title.to_string(),
            notes: String::new(),
            due_millis: None,
            tags: vec!["home".to_string()],
            status: "open".to_string(),
            priority: 0,
            created_at_millis: 0,
            updated_at_millis: 0,
        }
    }

    #[test]
    fn upsert_and_read_round_trips() {
        let mut doc = TaskDoc::new();
        doc.upsert_task(&sample_task("t1", "Buy milk")).unwrap();
        let tasks = doc.all_tasks();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].title, "Buy milk");
        assert_eq!(tasks[0].tags, vec!["home".to_string()]);
    }

    #[test]
    fn two_docs_converge_after_sync_exchange() {
        let mut doc_a = TaskDoc::new();
        let mut doc_b = TaskDoc::new();

        doc_a.upsert_task(&sample_task("t1", "From A")).unwrap();
        doc_b.upsert_task(&sample_task("t2", "From B")).unwrap();

        let mut session_a = SyncSession::new();
        let mut session_b = SyncSession::new();

        // Canonical Automerge sync loop: each side generates at most one
        // message per round and it always gets delivered — never generate
        // and discard, that drops protocol state the peer is waiting on.
        let mut rounds = 0;
        loop {
            rounds += 1;
            assert!(rounds < 20, "sync did not converge within 20 rounds");
            let mut quiet = true;
            if let Some(msg) = session_a.generate_message(&mut doc_a) {
                quiet = false;
                session_b.receive_message(&mut doc_b, msg).unwrap();
            }
            if let Some(msg) = session_b.generate_message(&mut doc_b) {
                quiet = false;
                session_a.receive_message(&mut doc_a, msg).unwrap();
            }
            if quiet {
                break;
            }
        }

        let mut a_tasks = doc_a.all_tasks();
        let mut b_tasks = doc_b.all_tasks();
        a_tasks.sort_by(|x, y| x.id.cmp(&y.id));
        b_tasks.sort_by(|x, y| x.id.cmp(&y.id));

        assert_eq!(a_tasks.len(), 2, "doc A should have both tasks after sync");
        assert_eq!(a_tasks, b_tasks, "both docs must converge to the same state");
    }

    #[test]
    fn incremental_save_can_be_reloaded() {
        let mut doc = TaskDoc::new();
        doc.upsert_task(&sample_task("t1", "Persisted")).unwrap();
        let bytes = doc.save_incremental();

        let reloaded = TaskDoc::load(&bytes).unwrap();
        let tasks = reloaded.all_tasks();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].title, "Persisted");
    }
}
