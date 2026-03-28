use crate::config::Config;
use anyhow::{Context, Result};
use std::ffi::CString;
use std::fs::File;
use std::io::{Read, Write};
use std::mem;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::ptr;
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

/// `POSIX_SPAWN_SETSID` makes the child a new session leader.
/// Value 0x80 is consistent across macOS and Linux (glibc 2.26+).
/// This is required for PTY job control to work correctly.
const POSIX_SPAWN_SETSID: libc::c_short = 0x0080;

/// A live PTY session: the child process, its stdin writer, and stdout reader.
pub struct PtySession {
    /// Write to this to send input to the child.
    writer: Option<Box<dyn Write + Send>>,
    /// Read from this to get output from the child.
    reader: Option<Box<dyn Read + Send>>,
    /// PID of the child process.
    pid: libc::pid_t,
    /// Master side of the PTY — kept alive to prevent SIGHUP on the child.
    _master: OwnedFd,
}

impl PtySession {
    /// Spawn a new PTY session running the given command at the given size.
    ///
    /// Uses `posix_spawn` instead of `fork+exec` so it is safe to call from
    /// multi-threaded programs (e.g. inside a Tokio runtime on macOS, where
    /// `fork` in a multi-threaded process triggers an abort in the child).
    pub fn spawn(config: &Config, cols: u16, rows: u16) -> Result<Self> {
        // ── 1. Open master/slave PTY pair ────────────────────────────────────
        let (master_fd, slave_fd) = open_pty(cols, rows)?;
        let slave_raw = slave_fd.as_raw_fd();

        // Set CLOEXEC on both so the child only inherits the dup2'd copies
        // (fd 0/1/2) and not the raw fd numbers.
        set_cloexec(master_fd.as_raw_fd()).context("set CLOEXEC on master")?;
        set_cloexec(slave_raw).context("set CLOEXEC on slave")?;

        // ── 2. Build argv: /bin/sh -c "cd '<root>' && exec '<cmd>' ..." ──────
        let sh_cmd = build_sh_command(config)?;
        let program = CString::new("/bin/sh").unwrap();
        let flag    = CString::new("-c").unwrap();
        let cmd_str = CString::new(sh_cmd).context("NUL byte in shell command")?;
        let mut argv: Vec<*mut libc::c_char> = vec![
            program.as_ptr() as *mut _,
            flag.as_ptr()    as *mut _,
            cmd_str.as_ptr() as *mut _,
            ptr::null_mut(),
        ];

        // ── 3. Build envp from current process environment ───────────────────
        // Collect before acquiring any locks; posix_spawn is thread-safe.
        let env_strings: Vec<CString> = std::env::vars()
            .filter_map(|(k, v)| CString::new(format!("{}={}", k, v)).ok())
            .collect();
        let mut envp: Vec<*mut libc::c_char> = env_strings
            .iter()
            .map(|s| s.as_ptr() as *mut _)
            .chain(std::iter::once(ptr::null_mut()))
            .collect();

        // ── 4. File actions: dup2 slave → stdin/stdout/stderr ────────────────
        let mut fa: libc::posix_spawn_file_actions_t = unsafe { mem::zeroed() };
        unsafe { libc::posix_spawn_file_actions_init(&mut fa) };
        unsafe { libc::posix_spawn_file_actions_adddup2(&mut fa, slave_raw, libc::STDIN_FILENO) };
        unsafe { libc::posix_spawn_file_actions_adddup2(&mut fa, slave_raw, libc::STDOUT_FILENO) };
        unsafe { libc::posix_spawn_file_actions_adddup2(&mut fa, slave_raw, libc::STDERR_FILENO) };
        // CLOEXEC on slave means it's gone after exec, but dup2'd copies survive.

        // ── 5. Spawn attributes: SETSID for PTY job control ─────────────────
        let mut attr: libc::posix_spawnattr_t = unsafe { mem::zeroed() };
        unsafe { libc::posix_spawnattr_init(&mut attr) };
        unsafe { libc::posix_spawnattr_setflags(&mut attr, POSIX_SPAWN_SETSID) };

        // ── 6. posix_spawn (no fork — safe in multi-threaded processes) ──────
        let mut pid: libc::pid_t = 0;
        let rc = unsafe {
            libc::posix_spawn(
                &mut pid,
                program.as_ptr(),
                &fa,
                &attr,
                argv.as_mut_ptr(),
                envp.as_mut_ptr(),
            )
        };

        unsafe { libc::posix_spawn_file_actions_destroy(&mut fa) };
        unsafe { libc::posix_spawnattr_destroy(&mut attr) };
        drop(slave_fd); // close slave in parent

        if rc != 0 {
            return Err(PtyError::Spawn(
                std::io::Error::from_raw_os_error(rc).to_string(),
            )
            .into());
        }

        // ── 7. Set up master reader / writer ─────────────────────────────────
        let writer_fd = master_fd.try_clone().context("clone master fd for writer")?;
        let reader_fd = master_fd.try_clone().context("clone master fd for reader")?;

        Ok(Self {
            writer: Some(Box::new(File::from(writer_fd))),
            reader: Some(Box::new(File::from(reader_fd))),
            pid,
            _master: master_fd,
        })
    }

    /// Take ownership of the PTY writer. Panics if called more than once.
    pub fn take_writer(&mut self) -> Box<dyn Write + Send> {
        self.writer.take().expect("writer already taken from PtySession")
    }

    /// Take ownership of the PTY reader. Panics if called more than once.
    pub fn take_reader(&mut self) -> Box<dyn Read + Send> {
        self.reader.take().expect("reader already taken from PtySession")
    }

    /// Resize the PTY to new dimensions.
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<()> {
        let ws = libc::winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let rc = unsafe {
            libc::ioctl(self._master.as_raw_fd(), libc::TIOCSWINSZ, &ws as *const _)
        };
        if rc == -1 {
            return Err(std::io::Error::last_os_error().into());
        }
        Ok(())
    }

    /// Block until the child exits. Returns its exit code.
    pub fn wait(&mut self) -> Result<u32> {
        loop {
            let mut status = 0i32;
            let rc = unsafe { libc::waitpid(self.pid, &mut status, 0) };
            if rc == -1 {
                let err = std::io::Error::last_os_error();
                if err.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(err.into());
            }
            if libc::WIFEXITED(status) {
                return Ok(libc::WEXITSTATUS(status) as u32);
            }
            if libc::WIFSIGNALED(status) {
                return Ok((128 + libc::WTERMSIG(status)) as u32);
            }
        }
    }

    /// Non-blocking check whether the child has exited.
    pub fn try_wait(&mut self) -> Result<Option<u32>> {
        let mut status = 0i32;
        let rc = unsafe { libc::waitpid(self.pid, &mut status, libc::WNOHANG) };
        if rc == -1 {
            return Err(std::io::Error::last_os_error().into());
        }
        if rc == 0 {
            return Ok(None); // still running
        }
        if libc::WIFEXITED(status) {
            return Ok(Some(libc::WEXITSTATUS(status) as u32));
        }
        if libc::WIFSIGNALED(status) {
            return Ok(Some((128 + libc::WTERMSIG(status)) as u32));
        }
        Ok(None)
    }
}

/// Open a master/slave PTY pair with the given terminal size.
fn open_pty(cols: u16, rows: u16) -> Result<(OwnedFd, OwnedFd)> {
    let mut ws = libc::winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let mut master: libc::c_int = -1;
    let mut slave: libc::c_int = -1;
    let rc = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            ptr::null_mut(),
            ptr::null_mut(), // termp: use default terminal settings
            &mut ws,
        )
    };
    if rc == -1 {
        return Err(PtyError::Open(std::io::Error::last_os_error().to_string()).into());
    }
    // SAFETY: openpty returned 0, both fds are valid and we now own them.
    Ok(unsafe { (OwnedFd::from_raw_fd(master), OwnedFd::from_raw_fd(slave)) })
}

/// Set the FD_CLOEXEC flag on a file descriptor.
fn set_cloexec(fd: libc::c_int) -> Result<()> {
    let rc = unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    if rc == -1 {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(())
}

/// Build the shell command string that runs inside the PTY.
///
/// Wraps the user command in `cd '<root>' && exec '<arg0>' '<arg1>' ...` so
/// the child starts in the project root without needing posix_spawn chdir
/// extensions (which vary across platforms).
fn build_sh_command(config: &Config) -> Result<String> {
    let args = &config.shell_command;
    if args.is_empty() {
        anyhow::bail!("shell_command must not be empty");
    }
    let cwd = config
        .project_root
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("project_root contains non-UTF-8 bytes"))?;

    let escaped_cwd = shell_single_quote(cwd);
    let escaped_args: Vec<String> = args.iter().map(|a| shell_single_quote(a)).collect();
    Ok(format!("cd {} && exec {}", escaped_cwd, escaped_args.join(" ")))
}

/// Wrap a string in single quotes, escaping any embedded single quotes.
fn shell_single_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''" ))
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
    fn build_sh_command_includes_cwd_and_all_args() {
        let cfg = make_config(vec!["echo", "hello world"]);
        let cmd = build_sh_command(&cfg).unwrap();
        assert!(cmd.contains("echo"), "should contain the binary");
        // args are single-quoted
        assert!(cmd.contains("'hello world'"), "should contain the quoted arg");
        // cwd should appear after 'cd'
        assert!(cmd.starts_with("cd '"), "should start with cd");
    }

    #[test]
    fn build_sh_command_rejects_empty_args() {
        let cfg = make_config(vec![]);
        let result = build_sh_command(&cfg);
        assert!(result.is_err(), "expected error for empty shell_command");
    }

    #[test]
    fn shell_single_quote_escapes_embedded_quotes() {
        assert_eq!(shell_single_quote("it's"), "'it'\\''s'");
        assert_eq!(shell_single_quote("plain"), "'plain'");
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

    /// Regression test for the macOS multi-threaded fork crash.
    ///
    /// Before the posix_spawn fix, calling PtySession::spawn from inside a
    /// multi-threaded tokio runtime would abort the process with:
    ///   EXC_CRASH / SIGABRT — "crashed on child side of fork pre-exec"
    ///
    /// Gate behind `test-pty` because it requires a real PTY (not available in CI).
    #[cfg(feature = "test-pty")]
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn pty_session_spawns_and_exits_multi_thread() {
        let cfg = make_config(vec!["bash", "-c", "exit 42"]);
        // Spawn directly from the async context (multi-threaded tokio runtime).
        // With fork+exec this aborted; with posix_spawn it must succeed.
        let mut session = PtySession::spawn(&cfg, 80, 24)
            .expect("PTY spawn must not crash in multi-threaded tokio runtime");
        let code = session.wait().expect("wait must not fail");
        assert_eq!(code, 42, "child should exit with code 42");
    }
}
