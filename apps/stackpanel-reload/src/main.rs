mod config;
mod pty_manager;
mod reloader;
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

    /// The shell command to run. Defaults to `nix develop --impure`.
    /// Separate with `--` to avoid flag confusion:
    ///   stackpanel-reload -- nix develop --impure
    #[arg(last = true)]
    command: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialise structured logging. RUST_LOG controls verbosity.
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn")),
        )
        .with_writer(std::io::stderr)
        .init();

    let cli = Cli::parse();

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
