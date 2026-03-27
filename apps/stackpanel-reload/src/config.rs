/// Configuration for stackpanel-reload.
///
/// Holds the shell command to spawn, the list of files/dirs to watch,
/// and tuning knobs. Sourced from CLI args and env variables.
#[derive(Debug, Clone)]
pub struct Config {
    /// The shell command and arguments to run inside the PTY.
    /// e.g. ["nix", "develop", "--impure", "--command", "zsh"]
    pub shell_command: Vec<String>,

    /// Paths (files or directories) to watch for changes.
    pub watch_paths: Vec<std::path::PathBuf>,

    /// Debounce delay in milliseconds before triggering a rebuild.
    pub debounce_ms: u64,

    /// Project root directory. Defaults to cwd.
    pub project_root: std::path::PathBuf,
}

impl Config {
    /// Default watch paths relative to a project root.
    pub const DEFAULT_WATCH_NAMES: &'static [&'static str] = &[
        "flake.nix",
        "flake.lock",
        "devenv.nix",
        "devenv.yaml",
        ".stack",
        "nix",
    ];

    /// Build a Config from explicit parts. Used in tests and the CLI builder.
    pub fn new(
        shell_command: Vec<String>,
        watch_paths: Vec<std::path::PathBuf>,
        debounce_ms: u64,
        project_root: std::path::PathBuf,
    ) -> Self {
        Self {
            shell_command,
            watch_paths,
            debounce_ms,
            project_root,
        }
    }

    /// Build a Config with default watch paths rooted at `project_root`.
    pub fn with_defaults(
        shell_command: Vec<String>,
        project_root: std::path::PathBuf,
    ) -> Self {
        let watch_paths = Self::DEFAULT_WATCH_NAMES
            .iter()
            .map(|name| project_root.join(name))
            .collect();
        Self::new(shell_command, watch_paths, 500, project_root)
    }

    /// Resolve the shell binary to use when no explicit command is given.
    /// Prefers $SHELL, falls back to "bash".
    pub fn default_shell() -> String {
        std::env::var("SHELL").unwrap_or_else(|_| "bash".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn new_stores_fields() {
        let cmd = vec!["nix".to_string(), "develop".to_string()];
        let paths = vec![PathBuf::from("/tmp/flake.nix")];
        let root = PathBuf::from("/tmp");

        let cfg = Config::new(cmd.clone(), paths.clone(), 300, root.clone());

        assert_eq!(cfg.shell_command, cmd);
        assert_eq!(cfg.watch_paths, paths);
        assert_eq!(cfg.debounce_ms, 300);
        assert_eq!(cfg.project_root, root);
    }

    #[test]
    fn with_defaults_generates_watch_paths() {
        let root = PathBuf::from("/my/project");
        let cmd = vec!["bash".to_string()];
        let cfg = Config::with_defaults(cmd, root.clone());

        // Should contain all default names rooted at project_root
        for name in Config::DEFAULT_WATCH_NAMES {
            assert!(
                cfg.watch_paths.contains(&root.join(name)),
                "Missing default watch path: {name}"
            );
        }
        assert_eq!(cfg.debounce_ms, 500);
        assert_eq!(cfg.project_root, root);
    }

    #[test]
    fn with_defaults_includes_flake_nix() {
        let root = PathBuf::from("/repo");
        let cfg = Config::with_defaults(vec!["bash".to_string()], root.clone());
        assert!(cfg.watch_paths.contains(&root.join("flake.nix")));
        assert!(cfg.watch_paths.contains(&root.join("flake.lock")));
    }

    #[test]
    fn with_defaults_includes_stack_dir() {
        let root = PathBuf::from("/repo");
        let cfg = Config::with_defaults(vec!["bash".to_string()], root.clone());
        assert!(cfg.watch_paths.contains(&root.join(".stack")));
    }

    #[test]
    fn default_shell_returns_shell_env_or_bash() {
        // We can't assert exact value (depends on environment), but it
        // should be non-empty and not panic.
        let shell = Config::default_shell();
        assert!(!shell.is_empty());
    }

    #[test]
    fn default_watch_names_are_nonempty() {
        assert!(!Config::DEFAULT_WATCH_NAMES.is_empty());
    }
}
