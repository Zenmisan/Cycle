use rusqlite::Connection;

/// Raw access to the `sync_changes` table, which Drift creates and manages
/// the schema for (see `lib/data/tables.dart`) — this module only ever does
/// plain INSERT/SELECT against a table it doesn't own the schema of, opening
/// its own connection to the same SQLite file Drift uses.
pub struct ChangeStore {
    conn: Connection,
}

impl ChangeStore {
    pub fn open(db_path: &str) -> Result<Self, String> {
        let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
        Ok(Self { conn })
    }

    /// All change bytes recorded so far, in insertion order, concatenated —
    /// suitable for `TaskDoc::load`.
    pub fn load_all_changes(&self) -> Result<Vec<u8>, String> {
        let mut stmt = self
            .conn
            .prepare("SELECT change_bytes FROM sync_changes ORDER BY id ASC")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| row.get::<_, Vec<u8>>(0))
            .map_err(|e| e.to_string())?;

        let mut all = Vec::new();
        for row in rows {
            all.extend(row.map_err(|e| e.to_string())?);
        }
        Ok(all)
    }

    /// Persist a batch of new change bytes (from `TaskDoc::save_incremental`).
    pub fn append_change(&self, bytes: &[u8]) -> Result<(), String> {
        if bytes.is_empty() {
            return Ok(());
        }
        self.conn
            .execute(
                "INSERT INTO sync_changes (change_bytes, created_at) VALUES (?1, ?2)",
                rusqlite::params![bytes, millis_since_epoch()],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }
}

fn millis_since_epoch() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crdt::{TaskDoc, TaskRecord};

    fn sample_task(id: &str) -> TaskRecord {
        TaskRecord {
            id: id.to_string(),
            project_id: "p1".to_string(),
            title: "Test".to_string(),
            notes: String::new(),
            due_millis: None,
            tags: vec![],
            status: "open".to_string(),
            priority: 0,
            created_at_millis: 0,
            updated_at_millis: 0,
        }
    }

    #[test]
    fn append_and_reload_round_trips_through_taskdoc() {
        let tmp = tempfile_path();
        {
            let conn = Connection::open(&tmp).unwrap();
            conn.execute(
                "CREATE TABLE sync_changes (id INTEGER PRIMARY KEY AUTOINCREMENT, change_bytes BLOB NOT NULL, created_at INTEGER NOT NULL)",
                [],
            )
            .unwrap();
        }

        let store = ChangeStore::open(&tmp).unwrap();
        let mut doc = TaskDoc::new();
        doc.upsert_task(&sample_task("t1")).unwrap();
        let bytes = doc.save_incremental();
        store.append_change(&bytes).unwrap();

        let loaded_bytes = store.load_all_changes().unwrap();
        let reloaded = TaskDoc::load(&loaded_bytes).unwrap();
        assert_eq!(reloaded.all_tasks().len(), 1);

        std::fs::remove_file(&tmp).ok();
    }

    fn tempfile_path() -> String {
        let mut path = std::env::temp_dir();
        path.push(format!("cycles_store_test_{}.sqlite", uuid::Uuid::new_v4()));
        path.to_string_lossy().to_string()
    }
}
