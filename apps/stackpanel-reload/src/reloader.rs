//! Background rebuild orchestrator.
//!
//! Listens for file change events from the `FileWatcher` and spawns
//! `nix develop --impure --command true` in the background to rebuild the
//! shell derivation. The PTY hot-swap (Phase 3) hooks into `on_success`.
//!
//! Only one background build runs at a time: if a new change arrives while
//! a build is in progress, the in-flight build is cancelled and restarted.

use crate::config::Config;
use crate::watcher::FileWatcher;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

/// Current state of the background rebuild.
#[derive(Debug, Clone, PartialEq)]
pub enum BuildState {
    /// No rebuild in progress; shell is current.
    Idle,
    /// A rebuild is running in the background.
    Rebuilding { changed_files: Vec<PathBuf> },
    /// Last rebuild succeeded.
    Succeeded,
    /// Last rebuild failed with the given exit code.
    Failed { exit_code: u32 },
}

/// Shared build state, readable by the status line (Phase 4).
pub type SharedBuildState = Arc<Mutex<BuildState>>;

/// The rebuild orchestrator.
pub struct Reloader {
    config: Config,
    /// Externally observable build state.
    pub state: SharedBuildState,
    /// Optional channel to signal when a build succeeds (for PTY swap).
    ready_tx: Option<mpsc::Sender<()>>,
}

impl Reloader {
    /// Create a Reloader without a swap signal channel.
    pub fn new(config: Config) -> Self {
        Self {
            config,
            state: Arc::new(Mutex::new(BuildState::Idle)),
            ready_tx: None,
        }
    }

    /// Create a Reloader that signals on `ready_rx` whenever a build succeeds.
    /// The receiver drives the PTY hot-swap in `run_session`.
    pub fn new_with_ready(config: Config) -> (Self, mpsc::Receiver<()>) {
        let (tx, rx) = mpsc::channel(4);
        let reloader = Self {
            config,
            state: Arc::new(Mutex::new(BuildState::Idle)),
            ready_tx: Some(tx),
        };
        (reloader, rx)
    }

    /// Run the reloader event loop. Blocks until the channel is closed or an
    /// unrecoverable error occurs. Designed to be run in a `tokio::spawn` task.
    pub async fn run(&self) {
        let (tx, mut rx) = mpsc::channel::<Vec<PathBuf>>(8);

        // Start the file watcher; if it fails, log and exit gracefully.
        let _watcher = match FileWatcher::start(&self.config.watch_paths, self.config.debounce_ms, tx) {
            Ok(w) => w,
            Err(e) => {
                tracing::warn!("FileWatcher failed to start: {e}. Hot-reload disabled.");
                return;
            }
        };

        tracing::info!(
            watch_paths = ?self.config.watch_paths,
            debounce_ms = self.config.debounce_ms,
            "reloader running"
        );

        // Handle is Some while a build is running, None when idle.
        let mut current_build: Option<tokio::task::JoinHandle<u32>> = None;

        while let Some(changed_files) = rx.recv().await {
            tracing::info!(?changed_files, "files changed, triggering rebuild");

            // Cancel any in-flight build.
            if let Some(handle) = current_build.take() {
                handle.abort();
                tracing::debug!("cancelled in-flight rebuild");
            }

            *self.state.lock().unwrap() = BuildState::Rebuilding {
                changed_files: changed_files.clone(),
            };

            let build_cmd = build_command(&self.config);
            let project_root = self.config.project_root.clone();
            let state = self.state.clone();
            // Clone the optional sender so the spawned task owns it.
            let ready_tx = self.ready_tx.clone();

            current_build = Some(tokio::spawn(async move {
                let exit_code = run_background_build(build_cmd, project_root).await;

                let succeeded = exit_code == 0;
                *state.lock().unwrap() = if succeeded {
                    tracing::info!("background rebuild succeeded");
                    BuildState::Succeeded
                } else {
                    tracing::warn!(exit_code, "background rebuild failed");
                    BuildState::Failed { exit_code }
                };

                // Signal PTY swap if configured and build succeeded.
                if succeeded {
                    if let Some(ref tx) = ready_tx {
                        let _ = tx.try_send(());
                    }
                }

                exit_code
            }));
        }
    }
}

/// Build the command that rebuilds the shell derivation in the background.
///
/// We use `nix develop --impure --command true` which:
/// 1. Evaluates the flake (same as entering the shell)
/// 2. Builds the devShell derivation if needed
/// 3. Runs the shell hook
/// 4. Executes `true` and exits
///
/// This exercises the full hook chain without keeping a PTY open.
fn build_command(config: &Config) -> Vec<String> {
    // If the user's shell command starts with "nix develop", reuse it but
    // replace the trailing shell program with `true`.
    // Otherwise, fall back to the canonical rebuild command.
    let cmd = &config.shell_command;
    if cmd.len() >= 2 && cmd[0] == "nix" && cmd[1] == "develop" {
        // e.g. ["nix", "develop", "--impure", "--command", "zsh"]
        //   → ["nix", "develop", "--impure", "--command", "true"]
        let mut rebuild = cmd.clone();
        if let Some(pos) = rebuild.iter().position(|a| a == "--command") {
            if pos + 1 < rebuild.len() {
                rebuild[pos + 1] = "true".to_string();
                return rebuild;
            }
        }
        // No --command flag: append one.
        rebuild.extend(["--command".to_string(), "true".to_string()]);
        rebuild
    } else {
        // Unknown command pattern; use the canonical form.
        vec![
            "nix".to_string(),
            "develop".to_string(),
            "--impure".to_string(),
            "--command".to_string(),
            "true".to_string(),
        ]
    }
}

/// Spawn the rebuild command as a regular child process (no PTY needed) and
/// wait for it to finish. Returns the exit code.
async fn run_background_build(cmd: Vec<String>, cwd: PathBuf) -> u32 {
    if cmd.is_empty() {
        return 1;
    }
    tracing::debug!(?cmd, ?cwd, "spawning background build");

    match tokio::process::Command::new(&cmd[0])
        .args(&cmd[1..])
        .current_dir(&cwd)
        // Silence the nix build output — the status line shows progress.
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .await
    {
        Ok(status) => status.code().unwrap_or(1) as u32,
        Err(e) => {
            tracing::error!("failed to spawn rebuild: {e}");
            1
        }
    }
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

    // ── build_command tests ───────────────────────────────────────────────────

    #[test]
    fn build_command_replaces_shell_with_true() {
        let cfg = make_config(vec!["nix", "develop", "--impure", "--command", "zsh"]);
        let cmd = build_command(&cfg);
        assert_eq!(cmd, vec!["nix", "develop", "--impure", "--command", "true"]);
    }

    #[test]
    fn build_command_appends_command_true_when_missing() {
        let cfg = make_config(vec!["nix", "develop", "--impure"]);
        let cmd = build_command(&cfg);
        assert_eq!(cmd, vec!["nix", "develop", "--impure", "--command", "true"]);
    }

    #[test]
    fn build_command_falls_back_for_non_nix_commands() {
        let cfg = make_config(vec!["bash", "-c", "echo hi"]);
        let cmd = build_command(&cfg);
        assert_eq!(
            cmd,
            vec!["nix", "develop", "--impure", "--command", "true"]
        );
    }

    #[test]
    fn build_command_handles_nix_develop_with_bash() {
        let cfg = make_config(vec!["nix", "develop", "--impure", "--command", "bash"]);
        let cmd = build_command(&cfg);
        assert_eq!(cmd, vec!["nix", "develop", "--impure", "--command", "true"]);
    }

    // ── BuildState tests ──────────────────────────────────────────────────────

    #[test]
    fn build_state_starts_idle() {
        let reloader = Reloader::new(make_config(vec!["bash"]));
        let state = reloader.state.lock().unwrap().clone();
        assert_eq!(state, BuildState::Idle);
    }

    #[test]
    fn new_with_ready_returns_receiver() {
        let (reloader, _rx) = Reloader::new_with_ready(make_config(vec!["bash"]));
        assert!(reloader.ready_tx.is_some());
        let state = reloader.state.lock().unwrap().clone();
        assert_eq!(state, BuildState::Idle);
    }

    #[tokio::test]
    async fn ready_signal_fires_on_successful_build() {
        use std::time::Duration;

        let cfg = Config::new(
            // Use `true` as the "nix develop" substitute so it succeeds instantly.
            vec!["true".to_string()],
            vec![], // no watch paths
            50,
            std::env::current_dir().unwrap(),
        );
        let (tx, rx) = mpsc::channel(1);

        // Simulate what run() does: run a background build, check it signals ready.
        let state = Arc::new(Mutex::new(BuildState::Idle));
        let ready_tx: Option<mpsc::Sender<()>> = Some(tx);
        let state_clone = state.clone();
        let exit_code = run_background_build(
            vec!["true".to_string()],
            cfg.project_root.clone(),
        )
        .await;

        let succeeded = exit_code == 0;
        *state_clone.lock().unwrap() = if succeeded {
            BuildState::Succeeded
        } else {
            BuildState::Failed { exit_code }
        };
        if succeeded {
            if let Some(ref t) = ready_tx {
                let _ = t.try_send(());
            }
        }

        let mut rx = rx;
        let signal = tokio::time::timeout(Duration::from_millis(200), rx.recv()).await;
        assert!(signal.is_ok(), "ready signal should fire on successful build");
        assert_eq!(*state.lock().unwrap(), BuildState::Succeeded);
    }

    // ── run_background_build tests ────────────────────────────────────────────

    #[tokio::test]
    async fn run_background_build_succeeds_for_true() {
        let exit = run_background_build(
            vec!["true".to_string()],
            std::env::current_dir().unwrap(),
        )
        .await;
        assert_eq!(exit, 0);
    }

    #[tokio::test]
    async fn run_background_build_fails_for_false() {
        let exit = run_background_build(
            vec!["false".to_string()],
            std::env::current_dir().unwrap(),
        )
        .await;
        assert_ne!(exit, 0);
    }

    #[tokio::test]
    async fn run_background_build_handles_missing_binary() {
        let exit = run_background_build(
            vec!["__nonexistent_binary_xyz__".to_string()],
            std::env::current_dir().unwrap(),
        )
        .await;
        assert_ne!(exit, 0);
    }

    #[tokio::test]
    async fn run_background_build_returns_nonzero_exit_code() {
        let exit = run_background_build(
            // `sh -c "exit 42"` returns 42
            vec!["sh".to_string(), "-c".to_string(), "exit 42".to_string()],
            std::env::current_dir().unwrap(),
        )
        .await;
        assert_eq!(exit, 42);
    }
}
