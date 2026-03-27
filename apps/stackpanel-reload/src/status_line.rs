//! Status line: a one-row bar at the bottom of the terminal that shows
//! the current rebuild state without interfering with the shell above it.
//!
//! # Implementation approach
//!
//! Rather than using a full TUI framework, we use a small set of ANSI escape
//! sequences to:
//!   1. Save the cursor position.
//!   2. Move to the last terminal row.
//!   3. Overwrite that row with our status text.
//!   4. Restore the cursor to its original position.
//!
//! This is the same technique used by tools like `git` progress bars and
//! `cargo`'s build progress. It requires no special terminal support beyond
//! basic VT100 (DECSC/DECRC), which every modern terminal implements.
//!
//! # Lifecycle
//!
//! `StatusLine::start()` spawns a background task that:
//!   - Watches the `SharedBuildState` for changes (via a polling loop).
//!   - Redraws the status row when the state changes.
//!   - Clears the status row on drop.
//!
//! The `StatusLineHandle` returned by `start()` keeps the task alive. Drop it
//! to clear and remove the status line.

use crate::reloader::{BuildState, SharedBuildState};
use std::io::{stderr, Write};
use std::time::Duration;
use tokio::task::JoinHandle;

/// Spinner frames for the "rebuilding" animation.
const SPINNER: &[&str] = &["⠋", "⠙", "⠸", "⠴", "⠦", "⠇"];
const POLL_INTERVAL: Duration = Duration::from_millis(80);

// ANSI escape helpers
const SAVE_CURSOR: &str = "\x1b7";      // DECSC
const RESTORE_CURSOR: &str = "\x1b8";  // DECRC
const CLEAR_LINE: &str = "\x1b[2K";    // erase entire line
const MOVE_LAST_ROW: &str = "\x1b[999B"; // move down 999 rows (clamps to last)
const COL1: &str = "\x1b[1G";          // move to column 1

// Colour codes
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";
const DIM: &str = "\x1b[2m";
const RESET: &str = "\x1b[0m";

/// Render the status line content for a given `BuildState` and spinner tick.
pub fn render(state: &BuildState, tick: usize) -> String {
    match state {
        BuildState::Idle => {
            format!("{DIM}  stackpanel-reload: watching for changes{RESET}")
        }
        BuildState::Rebuilding { .. } => {
            let frame = SPINNER[tick % SPINNER.len()];
            format!("{YELLOW}{frame} rebuilding shell…{RESET}")
        }
        BuildState::Succeeded => {
            format!("{GREEN}✓ shell reloaded — new environment active{RESET}")
        }
        BuildState::Failed { exit_code } => {
            format!("{RED}✗ rebuild failed (exit {exit_code}) — press Ctrl+Alt+R to retry{RESET}")
        }
    }
}

/// Write the status line to stderr without disturbing the shell's stdout.
///
/// Uses save/restore cursor so the prompt position is preserved.
fn draw(content: &str) {
    let mut err = stderr();
    // Save cursor → jump to last row → col 1 → clear → write → restore cursor
    let seq = format!(
        "{SAVE_CURSOR}{MOVE_LAST_ROW}{COL1}{CLEAR_LINE}{content}{RESTORE_CURSOR}"
    );
    let _ = err.write_all(seq.as_bytes());
    let _ = err.flush();
}

/// Erase the status line row (called on shutdown).
fn clear() {
    let mut err = stderr();
    let seq = format!("{SAVE_CURSOR}{MOVE_LAST_ROW}{COL1}{CLEAR_LINE}{RESTORE_CURSOR}");
    let _ = err.write_all(seq.as_bytes());
    let _ = err.flush();
}

/// A running status line. Drop to stop and clear.
pub struct StatusLineHandle {
    task: JoinHandle<()>,
}

impl StatusLineHandle {
    /// Start the status line, polling `state` and redrawing on changes.
    pub fn start(state: SharedBuildState) -> Self {
        let task = tokio::spawn(async move {
            let mut last_rendered = String::new();
            let mut tick: usize = 0;
            let mut interval = tokio::time::interval(POLL_INTERVAL);

            loop {
                interval.tick().await;

                let current = state.lock().unwrap().clone();
                let content = render(&current, tick);

                if content != last_rendered {
                    draw(&content);
                    last_rendered = content;
                }

                // Animate the spinner even when content text hasn't changed.
                if matches!(current, BuildState::Rebuilding { .. }) {
                    tick = tick.wrapping_add(1);
                    // Force redraw on next tick so spinner advances visually.
                    last_rendered.clear();
                }

                // After a successful swap we keep showing "✓" briefly, then
                // transition back to watching.
                if matches!(current, BuildState::Succeeded) {
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    *state.lock().unwrap() = BuildState::Idle;
                }
            }
        });

        Self { task }
    }
}

impl Drop for StatusLineHandle {
    fn drop(&mut self) {
        self.task.abort();
        clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    // ── render() tests ────────────────────────────────────────────────────────

    #[test]
    fn render_idle_contains_watching() {
        let s = render(&BuildState::Idle, 0);
        assert!(s.contains("watching"), "idle state should mention watching, got: {s}");
    }

    #[test]
    fn render_rebuilding_contains_spinner_frame() {
        for tick in 0..SPINNER.len() {
            let s = render(
                &BuildState::Rebuilding {
                    changed_files: vec![PathBuf::from("flake.nix")],
                },
                tick,
            );
            assert!(
                SPINNER.iter().any(|f| s.contains(f)),
                "rebuilding state at tick {tick} should contain a spinner frame, got: {s}"
            );
        }
    }

    #[test]
    fn render_rebuilding_contains_rebuilding_text() {
        let s = render(
            &BuildState::Rebuilding { changed_files: vec![] },
            0,
        );
        assert!(s.contains("rebuilding"), "got: {s}");
    }

    #[test]
    fn render_succeeded_contains_check_mark() {
        let s = render(&BuildState::Succeeded, 0);
        assert!(s.contains('✓'), "got: {s}");
    }

    #[test]
    fn render_failed_contains_exit_code() {
        let s = render(&BuildState::Failed { exit_code: 127 }, 0);
        assert!(s.contains("127"), "got: {s}");
        assert!(s.contains('✗'), "got: {s}");
    }

    #[test]
    fn render_failed_mentions_retry() {
        let s = render(&BuildState::Failed { exit_code: 1 }, 0);
        assert!(s.to_lowercase().contains("retry"), "got: {s}");
    }

    #[test]
    fn spinner_wraps_at_frame_count() {
        // tick >= SPINNER.len() should not panic (wrapping_add + modulo)
        let s = render(
            &BuildState::Rebuilding { changed_files: vec![] },
            usize::MAX,
        );
        assert!(!s.is_empty());
    }

    // ── ANSI escape sequence sanity ───────────────────────────────────────────

    #[test]
    fn render_idle_contains_ansi_reset() {
        let s = render(&BuildState::Idle, 0);
        assert!(s.contains('\x1b'), "should contain escape sequences");
    }

    // ── StatusLineHandle is Send + 'static (compile-time check) ──────────────

    fn assert_send<T: Send>() {}
    #[test]
    fn status_line_handle_is_send() {
        assert_send::<StatusLineHandle>();
    }
}
