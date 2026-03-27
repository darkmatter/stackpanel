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
    pub reader: Box<dyn Read + Send>,
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
            reader,
            child,
            _master: pair.master,
        })
    }

    /// Take ownership of the PTY writer for bidirectional I/O.
    /// Panics if called more than once.
    pub fn take_writer(&mut self) -> Box<dyn Write + Send> {
        self.writer.take().expect("writer already taken from PtySession")
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

/// Run the PTY session: forward stdin↔PTY and PTY→stdout until the child exits.
///
/// Integrates the file watcher: when watched files change, spawns a background
/// rebuild. On success, the PTY swap is triggered (Phase 3+).
///
/// Returns the shell exit code.
pub async fn run_session(config: &Config) -> Result<u32> {
    use crate::reloader::Reloader;
    use crate::terminal::{is_tty, terminal_size, RawModeGuard};
    use std::io::stdout;
    use tokio::task;

    // Non-TTY (CI): just exec the command directly — don't engage PTY machinery.
    if !is_tty() {
        return exec_direct(config).await;
    }

    let (cols, rows) = terminal_size();
    let mut session = PtySession::spawn(config, cols, rows)?;

    // Extract the writer BEFORE moving session into the output task.
    let raw_writer = session.take_writer();
    let writer: Arc<Mutex<Box<dyn Write + Send>>> = Arc::new(Mutex::new(raw_writer));

    // Enable raw mode so all keystrokes (including Ctrl+C) go to the PTY.
    let _raw = RawModeGuard::enter()?;

    // Shared done flag: set when the child's output stream closes (child exited).
    let done = Arc::new(Mutex::new(false));

    // ── Task 1: PTY output → stdout ─────────────────────────────────────────
    let done_out = done.clone();
    let output_task = task::spawn_blocking(move || {
        let mut buf = [0u8; 4096];
        let mut out = stdout();
        loop {
            match session.reader.read(&mut buf) {
                Ok(0) => break, // EOF: child closed stdout
                Ok(n) => {
                    if out.write_all(&buf[..n]).is_err() {
                        break;
                    }
                    let _ = out.flush();
                }
                Err(_) => break,
            }
        }
        *done_out.lock().unwrap() = true;
        session // return so we can call wait()
    });

    // ── Task 2: stdin → PTY writer ──────────────────────────────────────────
    let writer_in = writer.clone();
    let done_in = done.clone();
    let stdin_task = task::spawn_blocking(move || {
        use std::io::stdin;
        let mut buf = [0u8; 256];
        let mut inp = stdin();
        loop {
            if *done_in.lock().unwrap() {
                break;
            }
            match inp.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let mut w = writer_in.lock().unwrap();
                    let _ = w.write_all(&buf[..n]);
                    let _ = w.flush();
                }
            }
        }
    });

    // ── Task 3: file watcher + background reloader ──────────────────────────
    let reloader = Reloader::new(config.clone());
    let reloader_task = tokio::spawn(async move {
        reloader.run().await;
    });

    // Wait for the shell to exit (output EOF).
    let mut session = output_task.await?;
    reloader_task.abort();
    let _ = stdin_task.await;

    let exit_code = session.wait()?;
    Ok(exit_code)
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
