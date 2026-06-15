package tui

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/mattn/go-isatty"
)

// Confirm prompts the user for yes/no. It shells out to `gum confirm` when the
// binary is available; otherwise it falls back to a minimal stdin read so the
// command doesn't hard-fail on systems without gum.
func Confirm(prompt string, defaultYes bool) (bool, error) {
	if path, err := exec.LookPath("gum"); err == nil {
		args := []string{"confirm", prompt}
		if !defaultYes {
			args = append(args, "--default=false")
		}
		cmd := exec.Command(path, args...)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stderr
		cmd.Stderr = os.Stderr
		err := cmd.Run()
		if err == nil {
			return true, nil
		}
		// gum confirm exits 1 on "No" — not a real error.
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return false, nil
		}
		return false, fmt.Errorf("gum confirm failed: %w", err)
	}
	return StdinConfirm(os.Stdin, os.Stderr, prompt, defaultYes)
}

// StdinConfirm is the gum-less fallback. Exposed as an exported helper so
// tests can exercise it without running a real terminal.
func StdinConfirm(
	in io.Reader,
	out io.Writer,
	prompt string,
	defaultYes bool,
) (bool, error) {
	hint := "[Y/n]"
	if !defaultYes {
		hint = "[y/N]"
	}
	fmt.Fprintf(out, "? %s %s ", prompt, hint)
	r := bufio.NewReader(in)
	line, err := r.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return false, err
	}
	ans := strings.TrimSpace(strings.ToLower(line))
	if ans == "" {
		return defaultYes, nil
	}
	return ans == "y" || ans == "yes", nil
}

// IsInteractiveStdio reports whether we can safely prompt the user via
// external tools like gum. Requires both stdin and stderr to be terminals —
// stderr because gum draws prompts on stderr.
//
// Note: This differs from IsInteractive() (which checks stdin+stdout) because
// different tools use different file descriptors for their TUI.
func IsInteractiveStdio() bool {
	return isatty.IsTerminal(os.Stdin.Fd()) && isatty.IsTerminal(os.Stderr.Fd())
}
