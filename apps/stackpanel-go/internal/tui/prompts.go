package tui

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
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

// Select prompts the user to choose exactly one option. It shells out to
// `gum choose` when available, otherwise falls back to a numbered stdin prompt.
// defaultOpt (if non-empty and present in options) is pre-selected; on abort
// the default is returned.
func Select(prompt string, options []string, defaultOpt string) (string, error) {
	if len(options) == 0 {
		return "", fmt.Errorf("Select: no options provided")
	}
	if path, err := exec.LookPath("gum"); err == nil {
		args := []string{"choose", "--header", prompt}
		if defaultOpt != "" {
			args = append(args, "--selected", defaultOpt)
		}
		args = append(args, options...)
		cmd := exec.Command(path, args...)
		cmd.Stdin = os.Stdin
		cmd.Stderr = os.Stderr
		var out strings.Builder
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				// User aborted (esc) — fall back to the default.
				return fallbackOption(options, defaultOpt), nil
			}
			return "", fmt.Errorf("gum choose failed: %w", err)
		}
		chosen := strings.TrimSpace(out.String())
		if chosen == "" {
			return fallbackOption(options, defaultOpt), nil
		}
		return chosen, nil
	}
	return StdinSelect(os.Stdin, os.Stderr, prompt, options, defaultOpt)
}

// MultiSelect prompts the user to choose zero or more options. It shells out to
// `gum choose --no-limit` when available, otherwise falls back to a numbered
// stdin prompt accepting comma-separated indices. On abort the defaults are
// returned.
func MultiSelect(
	prompt string,
	options []string,
	defaults []string,
) ([]string, error) {
	if path, err := exec.LookPath("gum"); err == nil {
		args := []string{"choose", "--no-limit", "--header", prompt}
		if len(defaults) > 0 {
			args = append(args, "--selected", strings.Join(defaults, ","))
		}
		args = append(args, options...)
		cmd := exec.Command(path, args...)
		cmd.Stdin = os.Stdin
		cmd.Stderr = os.Stderr
		var out strings.Builder
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				return defaults, nil
			}
			return nil, fmt.Errorf("gum choose failed: %w", err)
		}
		return splitNonEmptyLines(out.String()), nil
	}
	return StdinMultiSelect(os.Stdin, os.Stderr, prompt, options, defaults)
}

// StdinSelect is the gum-less single-select fallback. Exposed for testing.
func StdinSelect(
	in io.Reader,
	out io.Writer,
	prompt string,
	options []string,
	defaultOpt string,
) (string, error) {
	defIdx := indexOf(options, defaultOpt)
	if defIdx < 0 {
		defIdx = 0
	}
	fmt.Fprintf(out, "? %s\n", prompt)
	for i, o := range options {
		marker := "  "
		if i == defIdx {
			marker = "* "
		}
		fmt.Fprintf(out, "  %s%d) %s\n", marker, i+1, o)
	}
	fmt.Fprintf(out, "Select [%d]: ", defIdx+1)
	r := bufio.NewReader(in)
	line, err := r.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	s := strings.TrimSpace(line)
	if s == "" {
		return options[defIdx], nil
	}
	if n, convErr := strconv.Atoi(s); convErr == nil && n >= 1 && n <= len(options) {
		return options[n-1], nil
	}
	if idx := indexOf(options, s); idx >= 0 {
		return options[idx], nil
	}
	return options[defIdx], nil
}

// StdinMultiSelect is the gum-less multi-select fallback. It accepts
// comma-separated indices (e.g. "1,3"). Empty input returns the defaults.
// Exposed for testing.
func StdinMultiSelect(
	in io.Reader,
	out io.Writer,
	prompt string,
	options []string,
	defaults []string,
) ([]string, error) {
	fmt.Fprintf(out, "? %s (comma-separated, empty = default)\n", prompt)
	for i, o := range options {
		marker := "  "
		if indexOf(defaults, o) >= 0 {
			marker = "* "
		}
		fmt.Fprintf(out, "  %s%d) %s\n", marker, i+1, o)
	}
	fmt.Fprint(out, "Select: ")
	r := bufio.NewReader(in)
	line, err := r.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	s := strings.TrimSpace(line)
	if s == "" {
		return defaults, nil
	}
	var selected []string
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if n, convErr := strconv.Atoi(part); convErr == nil && n >= 1 && n <= len(options) {
			selected = append(selected, options[n-1])
		}
	}
	return selected, nil
}

func indexOf(list []string, target string) int {
	for i, s := range list {
		if s == target {
			return i
		}
	}
	return -1
}

func fallbackOption(options []string, defaultOpt string) string {
	if indexOf(options, defaultOpt) >= 0 {
		return defaultOpt
	}
	return options[0]
}

func splitNonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(strings.TrimSpace(s), "\n") {
		l = strings.TrimSpace(l)
		if l != "" {
			out = append(out, l)
		}
	}
	return out
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
