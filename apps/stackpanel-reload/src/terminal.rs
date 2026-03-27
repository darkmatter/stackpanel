use crossterm::terminal;
use std::io;

/// RAII guard that restores the terminal to its original mode on drop.
///
/// Entering raw mode intercepts all input (including Ctrl+C) and disables
/// line buffering. We MUST restore on exit, even on panic.
pub struct RawModeGuard;

impl RawModeGuard {
    /// Enable raw mode and return a guard that will disable it on drop.
    pub fn enter() -> io::Result<Self> {
        terminal::enable_raw_mode()?;
        Ok(Self)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        // Best-effort: ignore errors during cleanup (we may be panicking).
        let _ = terminal::disable_raw_mode();
    }
}

/// Returns true if stdout is connected to a real terminal (not a pipe or CI).
pub fn is_tty() -> bool {
    crossterm::tty::IsTty::is_tty(&std::io::stdout())
}

/// Query the current terminal dimensions (cols, rows).
/// Returns (80, 24) as a safe fallback if the query fails.
pub fn terminal_size() -> (u16, u16) {
    terminal::size().unwrap_or((80, 24))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_size_returns_positive_dimensions() {
        let (cols, rows) = terminal_size();
        // Even on CI / no-terminal, our fallback is (80, 24)
        assert!(cols > 0, "cols should be > 0, got {cols}");
        assert!(rows > 0, "rows should be > 0, got {rows}");
    }

    #[test]
    fn is_tty_does_not_panic() {
        // Just verify it returns without panicking.
        let _ = is_tty();
    }
}
