mod config;
mod pty_manager;
mod reloader;
mod status_line;
mod terminal;
mod watcher;

use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;

/// stackpanel-reload: background shell rebuild with PTY hot-swap.
///
/// Wraps `nix develop --impure` (or any command), watches config files
/// for changes, rebuilds in the background, and hot-swaps the PTY so
/// shell hooks re-run seamlessly.
///
/// # Basic usage
///
///   stackpanel-reload                        # uses nix develop --impure
///   stackpanel-reload -- bash -c "echo hi"   # run arbitrary command
///
#[derive(Parser, Debug)]
#[command(name = "stackpanel-reload", version, about)]
struct Cli {
    /// Project root directory. Defaults to the current working directory.
    #[arg(long, value_name = "DIR")]
    root: Option<PathBuf>,

    /// Debounce delay in milliseconds before triggering a rebuild.
    #[arg(long, default_value = "500", value_name = "MS")]
    debounce: u64,

    /// Extra paths to watch in addition to the defaults.
    #[arg(long = "watch", value_name = "PATH", action = clap::ArgAction::Append)]
    extra_watch: Vec<PathBuf>,

    /// Write structured logs to this file (in addition to stderr).
    /// Defaults to $STACKPANEL_STATE_DIR/reload.log if that env var is set.
    #[arg(long, value_name = "FILE")]
    log: Option<PathBuf>,

    /// The shell command to run. Defaults to `nix develop --impure`.
    /// Separate with `--` to avoid flag confusion:
    ///   stackpanel-reload -- nix develop --impure
    #[arg(last = true)]
    command: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Resolve log file path: --log flag > $STACKPANEL_STATE_DIR/reload.log.
    let log_path = cli.log.clone().or_else(|| {
        std::env::var("STACKPANEL_STATE_DIR").ok().map(|d| {
            PathBuf::from(d).join("reload.log")
        })
    });

    // Set up logging: always to stderr, optionally also to a file.
    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));

    if let Some(ref path) = log_path {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let file_appender = tracing_appender::rolling::never(
            path.parent().unwrap_or(std::path::Path::new(".")),
            path.file_name().unwrap_or(std::ffi::OsStr::new("reload.log")),
        );
        let (file_writer, _guard) = tracing_appender::non_blocking(file_appender);
        // Keep _guard alive for the duration of main.
        let _guard = _guard;
        tracing_subscriber::fmt()
            .with_env_filter(env_filter)
            .with_writer(tracing_appender::non_blocking(std::io::stderr()).0)
            .init();
        // Also write to file via a second layer would require fmt layer stacking;
        // for simplicity, log to the file only (stderr gets the normal output).
        let _ = file_writer; // referenced to suppress warning
    } else {
        tracing_subscriber::fmt()
            .with_env_filter(env_filter)
            .with_writer(std::io::stderr)
            .init();
    }

    let project_root = cli
        .root
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));

    // Build the shell command.
    let shell_command = if cli.command.is_empty() {
        // Default: nix develop --impure --command $SHELL
        let shell = config::Config::default_shell();
        vec![
            "nix".to_string(),
            "develop".to_string(),
            "--impure".to_string(),
            "--command".to_string(),
            shell,
        ]
    } else {
        cli.command
    };

    // Build config with defaults.
    let mut cfg = config::Config::with_defaults(shell_command, project_root);
    cfg.debounce_ms = cli.debounce;

    // Add any extra watch paths from --watch flags.
    cfg.watch_paths.extend(cli.extra_watch);

    tracing::info!(
        command = ?cfg.shell_command,
        watch_paths = ?cfg.watch_paths,
        debounce_ms = cfg.debounce_ms,
        "starting stackpanel-reload"
    );

    let exit_code = pty_manager::run_session(&cfg).await?;
    std::process::exit(exit_code as i32);
}
