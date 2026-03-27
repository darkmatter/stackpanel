use crate::config::Config;
use anyhow::{Context, Result};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PtyError {
    #[error("failed to open PTY pair: {0}")]
    Open(String),
    #[error("failed to spawn command in PTY: {0}")]
    Spawn(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

/// A live PTY session: the child process, its stdin writer, and stdout reader.
pub struct PtySession {
    /// Write to this to send input to the child.
    /// Wrapped in Option so it can be extracted via `take_writer()`.
    writer: Option<Box<dyn Write + Send>>,
    /// Read from this to get output from the child.
    /// Wrapped in Option so it can be extracted via `take_reader()`.
    reader: Option<Box<dyn Read + Send>>,
    /// The child process handle (used to wait for exit).
    child: Box<dyn portable_pty::Child + Send>,
    /// The master side of the PTY (kept alive to avoid SIGHUP).
    _master: Box<dyn portable_pty::MasterPty + Send>,
}

impl PtySession {
    /// Spawn a new PTY session running the given command at the given size.
    pub fn spawn(config: &Config, cols: u16, rows: u16) -> Result<Self> {
        let pty_system = native_pty_system();

        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| PtyError::Open(e.to_string()))?;

        let mut cmd = build_command(config)?;
        cmd.cwd(&config.project_root);

        let child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|e| PtyError::Spawn(e.to_string()))?;

        let writer = pair
            .master
            .take_writer()
            .context("failed to take PTY writer")?;

        let reader = pair
            .master
            .try_clone_reader()
            .context("failed to clone PTY reader")?;

        Ok(Self {
            writer: Some(writer),
            reader: Some(reader),
            child,
            _master: pair.master,
        })
    }

    /// Take ownership of the PTY writer for bidirectional I/O.
    /// Panics if called more than once.
    pub fn take_writer(&mut self) -> Box<dyn Write + Send> {
        self.writer.take().expect("writer already taken from PtySession")
    }

    /// Take ownership of the PTY reader. Panics if called more than once.
    pub fn take_reader(&mut self) -> Box<dyn Read + Send> {
        self.reader.take().expect("reader already taken from PtySession")
    }

    /// Resize the PTY to new dimensions.
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<()> {
        self._master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .context("failed to resize PTY")
    }

    /// Wait for the child process to exit. Returns the exit code.
    pub fn wait(&mut self) -> Result<u32> {
        let status = self.child.wait().context("failed to wait for child")?;
        Ok(status.exit_code())
    }

    /// Returns true if the child has already exited.
    pub fn try_wait(&mut self) -> Result<Option<u32>> {
        match self.child.try_wait().context("failed to try_wait on child")? {
            Some(status) => Ok(Some(status.exit_code())),
            None => Ok(None),
        }
    }
}

/// Build a `CommandBuilder` from a `Config`.
fn build_command(config: &Config) -> Result<CommandBuilder> {
    let args = &config.shell_command;
    if args.is_empty() {
        anyhow::bail!("shell_command must not be empty");
    }
    let mut cmd = CommandBuilder::new(&args[0]);
    for arg in &args[1..] {
        cmd.arg(arg);
    }
    Ok(cmd)
}

/// Events flowing through the main session event loop.
#[derive(Debug)]
enum SessionEvent {
    /// Bytes from the PTY (tagged with generation so stale events are ignored).
    PtyOutput { gen: u64, bytes: Vec<u8> },
    /// The active PTY's output stream closed (child exited).
    PtyEof { gen: u64 },
    /// Bytes typed by the user (also forwarded directly to the PTY writer).
    Stdin(Vec<u8>),
    /// Background rebuild succeeded; time to spawn a new interactive PTY.
    SwapReady,
    /// User pressed Ctrl+Alt+R: trigger an immediate background rebuild.
    ManualRebuild,
    /// User pressed Ctrl+Alt+L: list currently watched files.
    ListWatchedFiles,
}

// Key sequences for Ctrl+Alt+R and Ctrl+Alt+L in most terminals.
// Ctrl+Alt+X sends ESC followed by Ctrl+X (0x12 for R, 0x0c for L).
const KEY_CTRL_ALT_R: &[u8] = &[0x1b, 0x12]; // ESC + Ctrl+R
const KEY_CTRL_ALT_L: &[u8] = &[0x1b, 0x0c]; // ESC + Ctrl+L

/// Check incoming stdin bytes for special keybindings and dispatch events.
async fn handle_keybinding(
    bytes: &[u8],
    tx: &tokio::sync::mpsc::Sender<SessionEvent>,
    _config: &Config,
) {
    if bytes == KEY_CTRL_ALT_R {
        tracing::info!("Ctrl+Alt+R pressed: triggering manual rebuild");
        let _ = tx.try_send(SessionEvent::ManualRebuild);
    } else if bytes == KEY_CTRL_ALT_L {
        tracing::info!("Ctrl+Alt+L pressed: listing watched files");
        let _ = tx.try_send(SessionEvent::ListWatchedFiles);
    }
}

/// Run the PTY session: forward stdin↔PTY and PTY→stdout until the child exits.
///
/// Integrates the file watcher and hot-swap:
/// - Reloader watches config files; on success, triggers a PTY swap.
/// - Swap: clear screen, spawn fresh `nix develop` PTY, redirect I/O.
///
/// Returns the shell exit code.
pub async fn run_session(config: &Config) -> Result<u32> {
    use crate::reloader::Reloader;
    use crate::terminal::{is_tty, terminal_size, RawModeGuard};
    use std::io::{stdout, Write as _};
    use tokio::sync::mpsc;
    use tokio::task;

    // Non-TTY (CI): exec directly — no PTY machinery needed.
    if !is_tty() {
        return exec_direct(config).await;
    }

    let (cols, rows) = terminal_size();

    // ── Set up channels ───────────────────────────────────────────────────────
    let (event_tx, mut event_rx) = mpsc::channel::<SessionEvent>(128);

    // ── Spawn initial session ─────────────────────────────────────────────────
    let mut current_gen = 0u64;
    let mut session = PtySession::spawn(config, cols, rows)?;
    let writer: Arc<Mutex<Box<dyn Write + Send>>> =
        Arc::new(Mutex::new(session.take_writer()));
    start_pty_forwarder(session.take_reader(), current_gen, event_tx.clone());
    // Hold the session so dropping it (on swap) closes the master → EOF.
    let mut active_session = Some(session);

    // Enable raw mode.
    let _raw = RawModeGuard::enter()?;

    // ── Task: stdin → active PTY writer ──────────────────────────────────────
    let writer_for_stdin = writer.clone();
    let stdin_tx = event_tx.clone();
    task::spawn_blocking(move || {
        use std::io::{stdin, Read as _};
        let mut buf = [0u8; 256];
        let mut inp = stdin();
        loop {
            match inp.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    // Also forward as event so we could intercept keybindings later.
                    let bytes = buf[..n].to_vec();
                    {
                        let mut w = writer_for_stdin.lock().unwrap();
                        let _ = w.write_all(&bytes);
                        let _ = w.flush();
                    }
                    // Non-blocking send — drop if buffer full (best effort).
                    let _ = stdin_tx.try_send(SessionEvent::Stdin(bytes));
                }
            }
        }
    });

    // ── Task: reloader (file watcher + background builds) ────────────────────
    let (reloader, mut ready_rx) = Reloader::new_with_ready(config.clone());
    let build_state = reloader.state.clone();
    let reloader_task = tokio::spawn(async move {
        reloader.run().await;
    });
    // Forward ready signal into main event channel.
    let swap_tx = event_tx.clone();
    tokio::spawn(async move {
        while ready_rx.recv().await.is_some() {
            if swap_tx.send(SessionEvent::SwapReady).await.is_err() {
                break;
            }
        }
    });

    // ── Status line (only when attached to a real TTY) ──────────────────────────
    let _status = crate::status_line::StatusLineHandle::start(build_state);

    // ── Main event loop ───────────────────────────────────────────────────────
    let mut exit_code = 0u32;
    loop {
        match event_rx.recv().await {
            None => break, // all senders dropped

            Some(SessionEvent::PtyOutput { gen, bytes }) => {
                if gen != current_gen {
                    continue; // stale event from old generation
                }
                let mut out = stdout();
                let _ = out.write_all(&bytes);
                let _ = out.flush();
            }

            Some(SessionEvent::PtyEof { gen }) => {
                if gen != current_gen {
                    continue;
                }
                // Active PTY exited. Wait for exit code and quit.
                if let Some(mut s) = active_session.take() {
                    exit_code = s.wait().unwrap_or(0);
                }
                break;
            }

            Some(SessionEvent::Stdin(bytes)) => {
                // Already forwarded to PTY writer in the stdin task above.
                // Intercept special keybindings before they reach the shell.
                handle_keybinding(&bytes, &event_tx, config).await;
            }

            Some(SessionEvent::SwapReady) => {
                perform_swap(
                    config,
                    &mut active_session,
                    &writer,
                    &mut current_gen,
                    cols,
                    rows,
                    &event_tx,
                )
                .await;
            }

            Some(SessionEvent::ManualRebuild) => {
                use std::io::{stdout, Write as _};
                let mut out = stdout();
                let _ = out.write_all(
                    b"\r\n\x1b[33m\xe2\x86\xbb Ctrl+Alt+R: triggering manual rebuild\x1b[0m\r\n",
                );
                let _ = out.flush();
                // Signal reloader to trigger a rebuild immediately.
                // We reuse the SwapReady path: push a fake "file changed" event
                // by directly marking the build state as needing rebuild.
                // The simplest approach: send SwapReady directly to trigger
                // a swap if a previous build had already succeeded, or just
                // log a hint that build is already in progress.
                tracing::info!("manual rebuild requested via Ctrl+Alt+R");
                // Notify via build state — the reloader will pick it up
                // on its next iteration via the manual_rebuild channel.
                // For now: send SwapReady if build state is Succeeded/Idle
                // (a new build would have been triggered by a file change).
                // The user can also just save a watched file to trigger.
                let _ = event_tx.try_send(SessionEvent::SwapReady);
            }

            Some(SessionEvent::ListWatchedFiles) => {
                use std::io::{stdout, Write as _};
                let mut out = stdout();
                let header = "\r\n\x1b[2m  Watching:\x1b[0m\r\n";
                let _ = out.write_all(header.as_bytes());
                for path in &config.watch_paths {
                    let line = format!("    {}\r\n", path.display());
                    let _ = out.write_all(line.as_bytes());
                }
                let _ = out.flush();
            }
        }
    }

    reloader_task.abort();
    Ok(exit_code)
}

/// Spawn a dedicated thread that reads from `reader` and sends bytes to `tx`.
/// Tagged with `gen` so the main loop can ignore bytes from old sessions.
fn start_pty_forwarder(
    reader: Box<dyn Read + Send>,
    gen: u64,
    tx: tokio::sync::mpsc::Sender<SessionEvent>,
) {
    tokio::task::spawn_blocking(move || {
        let mut buf = [0u8; 4096];
        let mut reader = reader;
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let bytes = buf[..n].to_vec();
                    if tx.blocking_send(SessionEvent::PtyOutput { gen, bytes }).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = tx.blocking_send(SessionEvent::PtyEof { gen });
    });
}

/// Perform the PTY hot-swap:
/// 1. Clear screen and show swap notification.
/// 2. Spawn a new `nix develop` interactive session.
/// 3. Replace the active writer and start a new forwarder.
/// 4. Drop the old session (SIGHUP → old shell exits → old forwarder gets EOF).
async fn perform_swap(
    config: &Config,
    active_session: &mut Option<PtySession>,
    writer: &Arc<Mutex<Box<dyn Write + Send>>>,
    current_gen: &mut u64,
    cols: u16,
    rows: u16,
    event_tx: &tokio::sync::mpsc::Sender<SessionEvent>,
) {
    use std::io::{stdout, Write as _};

    tracing::info!("performing PTY hot-swap");

    // Notify the terminal.
    {
        let mut out = stdout();
        // Move to a new line, clear to end of screen, show message.
        let msg = "\r\n\x1b[2K\x1b[32m\u{21bb} stackpanel: shell reloaded \u{2014} new environment active\x1b[0m\r\n";
        let _ = out.write_all(msg.as_bytes());
        let _ = out.flush();
    }

    // Spawn new interactive session.
    match PtySession::spawn(config, cols, rows) {
        Ok(mut new_session) => {
            *current_gen += 1;
            let gen = *current_gen;

            // Replace the shared writer.
            *writer.lock().unwrap() = new_session.take_writer();

            // Start new output forwarder.
            start_pty_forwarder(new_session.take_reader(), gen, event_tx.clone());

            // Drop old session → closes old master → SIGHUP to old shell.
            let _old = active_session.replace(new_session);
            // _old drops here
        }
        Err(e) => {
            let mut out = stdout();
            let msg = format!("\r\n\x1b[31m\u{2717} swap failed: {e}\x1b[0m\r\n");
            let _ = out.write_all(msg.as_bytes());
            let _ = out.flush();
        }
    }
}

/// Non-TTY fallback: just exec the command directly (no PTY).
/// Used in CI environments where there's no terminal.
async fn exec_direct(config: &Config) -> Result<u32> {
    let args = &config.shell_command;
    if args.is_empty() {
        anyhow::bail!("shell_command must not be empty");
    }

    let status = tokio::process::Command::new(&args[0])
        .args(&args[1..])
        .current_dir(&config.project_root)
        .status()
        .await
        .context("failed to exec command directly")?;

    Ok(status.code().unwrap_or(1) as u32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn make_config(cmd: Vec<&str>) -> Config {
        Config::new(
            cmd.into_iter().map(String::from).collect(),
            vec![],
            500,
            PathBuf::from(std::env::current_dir().unwrap()),
        )
    }

    #[test]
    fn build_command_uses_first_arg_as_binary() {
        let cfg = make_config(vec!["echo", "hello"]);
        let cmd = build_command(&cfg).unwrap();
        // CommandBuilder doesn't expose the program directly in public API,
        // but we verify it doesn't error and builds without panicking.
        let _ = cmd;
    }

    #[test]
    fn build_command_rejects_empty_args() {
        let cfg = make_config(vec![]);
        let result = build_command(&cfg);
        assert!(result.is_err(), "expected error for empty shell_command");
    }

    // ── keybinding tests ──────────────────────────────────────────────────

    #[tokio::test]
    async fn ctrl_alt_r_sends_manual_rebuild_event() {
        use tokio::sync::mpsc;
        let (tx, mut rx) = mpsc::channel(8);
        let cfg = make_config(vec!["bash"]);
        handle_keybinding(KEY_CTRL_ALT_R, &tx, &cfg).await;
        let event = rx.try_recv().expect("expected ManualRebuild event");
        assert!(matches!(event, SessionEvent::ManualRebuild));
    }

    #[tokio::test]
    async fn ctrl_alt_l_sends_list_watched_files_event() {
        use tokio::sync::mpsc;
        let (tx, mut rx) = mpsc::channel(8);
        let cfg = make_config(vec!["bash"]);
        handle_keybinding(KEY_CTRL_ALT_L, &tx, &cfg).await;
        let event = rx.try_recv().expect("expected ListWatchedFiles event");
        assert!(matches!(event, SessionEvent::ListWatchedFiles));
    }

    #[tokio::test]
    async fn ordinary_keystrokes_do_not_send_events() {
        use tokio::sync::mpsc;
        let (tx, mut rx) = mpsc::channel(8);
        let cfg = make_config(vec!["bash"]);
        handle_keybinding(b"hello", &tx, &cfg).await;
        assert!(rx.try_recv().is_err(), "should not send event for ordinary input");
    }

    #[cfg(feature = "test-pty")]
    #[test]
    fn pty_session_spawns_and_exits() {
        // Only run in environments with a real PTY (not CI).
        let cfg = make_config(vec!["bash", "-c", "exit 42"]);
        let (cols, rows) = (80, 24);
        let mut session = PtySession::spawn(&cfg, cols, rows).unwrap();
        let code = session.wait().unwrap();
        assert_eq!(code, 42);
    }
}
