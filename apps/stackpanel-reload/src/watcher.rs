//! Debounced file watcher.
//!
//! Wraps the `notify` crate with a debounce window so that rapid successive
//! writes (e.g. editor atomic-save: write tmp → rename → delete) only produce
//! one event rather than a burst.
//!
//! Events are delivered on a tokio channel as `Vec<PathBuf>` (the batch of
//! changed paths). Paths that no longer exist at delivery time are included
//! as-is — the reloader decides what to do with them.

use anyhow::Result;
use notify::event::ModifyKind;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::PathBuf;
use std::sync::mpsc as std_mpsc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

/// A running file watcher. Dropping it stops the watch.
pub struct FileWatcher {
    // Keep the notify watcher alive. Dropping it stops watching.
    _watcher: RecommendedWatcher,
}

impl FileWatcher {
    /// Start watching `paths` (files or directories, recursively).
    ///
    /// `debounce_ms` is the quiet period after the last event before the
    /// accumulated batch is flushed to `tx`.
    ///
    /// Paths that don't exist yet are silently skipped (they may appear later).
    pub fn start(
        paths: &[PathBuf],
        debounce_ms: u64,
        tx: mpsc::Sender<Vec<PathBuf>>,
    ) -> Result<Self> {
        let (raw_tx, raw_rx) = std_mpsc::channel::<notify::Result<Event>>();

        let mut watcher = notify::recommended_watcher(raw_tx)?;

        let mut watched = 0usize;
        for path in paths {
            if path.exists() {
                watcher.watch(path, RecursiveMode::Recursive)?;
                watched += 1;
            } else {
                tracing::debug!(?path, "watch path does not exist yet, skipping");
            }
        }
        tracing::debug!(watched, "FileWatcher started");

        let debounce = Duration::from_millis(debounce_ms);

        // Debounce loop runs in a dedicated OS thread (notify uses std channels).
        std::thread::spawn(move || {
            debounce_loop(raw_rx, debounce, tx);
        });

        Ok(Self { _watcher: watcher })
    }
}

/// Collect raw notify events and flush them as batches after `debounce` quiet time.
fn debounce_loop(
    rx: std_mpsc::Receiver<notify::Result<Event>>,
    debounce: Duration,
    tx: mpsc::Sender<Vec<PathBuf>>,
) {
    let mut pending: Vec<PathBuf> = Vec::new();
    let mut deadline: Option<Instant> = None;

    loop {
        // How long until the current debounce window expires?
        let timeout = match deadline {
            Some(d) => d.saturating_duration_since(Instant::now()),
            None => Duration::from_secs(3600), // block indefinitely
        };

        match rx.recv_timeout(timeout) {
            Ok(Ok(event)) => {
                // Only react to create/modify/remove events, not metadata-only.
                if is_content_change(&event.kind) {
                    for path in event.paths {
                        if !pending.contains(&path) {
                            pending.push(path);
                        }
                    }
                    // (Re)arm the debounce window.
                    deadline = Some(Instant::now() + debounce);
                }
            }
            Ok(Err(e)) => {
                tracing::warn!("watch error: {e}");
            }
            Err(std_mpsc::RecvTimeoutError::Timeout) => {
                // Debounce window expired — flush the batch.
                if !pending.is_empty() {
                    let batch = std::mem::take(&mut pending);
                    deadline = None;
                    tracing::debug!(files = batch.len(), "file change batch ready");
                    if tx.blocking_send(batch).is_err() {
                        break; // Receiver dropped; stop the thread.
                    }
                }
            }
            Err(std_mpsc::RecvTimeoutError::Disconnected) => {
                break; // Watcher dropped; stop the thread.
            }
        }
    }
}

/// Returns true for events that represent actual content changes.
///
/// Excludes metadata-only modifications (chmod, timestamps) to avoid false
/// positives from tools that touch file metadata without changing content.
fn is_content_change(kind: &EventKind) -> bool {
    match kind {
        EventKind::Create(_) | EventKind::Remove(_) => true,
        // Modify: include data changes and renames, exclude metadata-only.
        EventKind::Modify(modify_kind) => !matches!(
            modify_kind,
            ModifyKind::Metadata(_)
        ),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tempfile::tempdir;
    use tokio::sync::mpsc;

    /// Verify the watcher can be constructed with a mix of existing and
    /// non-existing paths without panicking.
    #[test]
    fn start_with_mixed_paths_does_not_error() {
        let dir = tempdir().unwrap();
        let paths = vec![
            dir.path().to_path_buf(),          // exists
            dir.path().join("does_not_exist"),  // missing — should be skipped
        ];
        let (tx, _rx) = mpsc::channel(16);
        FileWatcher::start(&paths, 100, tx).expect("should succeed with missing paths");
    }

    /// Verify is_content_change filters correctly.
    #[test]
    fn is_content_change_filters_metadata_events() {
        use notify::event::{CreateKind, MetadataKind, ModifyKind};

        assert!(is_content_change(&EventKind::Create(CreateKind::File)));
        assert!(is_content_change(&EventKind::Modify(ModifyKind::Data(
            notify::event::DataChange::Content
        ))));
        assert!(is_content_change(&EventKind::Remove(
            notify::event::RemoveKind::File
        )));
        assert!(!is_content_change(&EventKind::Modify(
            ModifyKind::Metadata(MetadataKind::Any)
        )));
        assert!(!is_content_change(&EventKind::Access(
            notify::event::AccessKind::Any
        )));
    }

    /// Write a file and verify a change event arrives within a reasonable timeout.
    #[tokio::test]
    async fn detects_file_write() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("flake.nix");
        std::fs::write(&file, "initial").unwrap();

        let (tx, mut rx) = mpsc::channel(16);
        let _watcher = FileWatcher::start(&[dir.path().to_path_buf()], 50, tx).unwrap();

        // Write to the file to trigger a change event.
        std::fs::write(&file, "changed").unwrap();

        // Expect the event within 2 seconds.
        let batch = tokio::time::timeout(Duration::from_secs(2), rx.recv())
            .await
            .expect("timed out waiting for file change event")
            .expect("channel closed");

        assert!(!batch.is_empty(), "batch should contain changed paths");
    }

    /// Multiple rapid writes within the debounce window should produce one batch.
    #[tokio::test]
    async fn debounces_rapid_writes_into_one_batch() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("flake.lock");
        std::fs::write(&file, "v0").unwrap();

        let debounce_ms = 150u64;
        let (tx, mut rx) = mpsc::channel(16);
        let _watcher =
            FileWatcher::start(&[dir.path().to_path_buf()], debounce_ms, tx).unwrap();

        // Fire several writes rapidly.
        for i in 1..=5 {
            std::fs::write(&file, format!("v{i}")).unwrap();
            std::thread::sleep(Duration::from_millis(10));
        }

        // One batch should arrive after debounce window.
        let batch = tokio::time::timeout(Duration::from_secs(3), rx.recv())
            .await
            .expect("timed out waiting for debounced batch")
            .expect("channel closed");

        assert!(!batch.is_empty());

        // A second batch should NOT arrive within the debounce window.
        let second = tokio::time::timeout(Duration::from_millis(200), rx.recv()).await;
        assert!(second.is_err(), "expected no second batch within debounce window");
    }
}
