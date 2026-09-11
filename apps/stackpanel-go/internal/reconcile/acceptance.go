package reconcile

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type AcceptanceCommand struct {
	ID    string   `json:"id"`
	Scope string   `json:"scope"`
	Dir   string   `json:"dir"`
	Argv  []string `json:"argv"`
}

func relativeAcceptancePath(path string) bool {
	return path != "" && filepath.IsLocal(path)
}

// acceptancePath checks symlinks as well as lexical traversal.
func acceptancePath(root, path string) (string, error) {
	if !relativeAcceptancePath(path) {
		return "", fmt.Errorf("acceptance path must be inside the repository: %q", path)
	}
	resolved, err := filepath.EvalSymlinks(filepath.Join(root, path))
	if err != nil {
		return "", err
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(canonicalRoot, resolved)
	if err != nil || !filepath.IsLocal(rel) {
		return "", fmt.Errorf("acceptance path escapes repository: %q", path)
	}
	return resolved, nil
}

// CheckAcceptance runs the commands accepted before generation, without a shell.
// Output is bounded and never interpreted as a successful verification report.
func CheckAcceptance(ctx *Context, expected Expectations) []CheckResult {
	var results []CheckResult
	selected := func(scope string) bool {
		if len(ctx.CheckScopes) == 0 {
			return true
		}
		for _, s := range ctx.CheckScopes {
			if s == scope {
				return true
			}
		}
		return false
	}
	if selected("repo") {
		for _, file := range expected.Files {
			result := CheckResult{ID: "file:" + file, Module: "onboarding", Scope: "repo", Status: "pass"}
			path, err := acceptancePath(ctx.ProjectRoot, file)
			if err == nil {
				var stat os.FileInfo
				stat, err = os.Stat(path)
				if err == nil && !stat.Mode().IsRegular() {
					err = fmt.Errorf("expected a regular file")
				}
			}
			if err != nil {
				result.Status = "fail"
				result.Message = err.Error()
			}
			results = append(results, result)
		}
	}
	for _, check := range expected.Commands {
		if !selected(check.Scope) {
			continue
		}
		result := CheckResult{ID: "acceptance:" + check.ID, Module: "onboarding", Scope: check.Scope, Status: "pass"}
		if !ctx.InDevshell() {
			result.Status = "skipped"
			result.Message = "evaluated devshell configuration unavailable"
			results = append(results, result)
			continue
		}
		if check.Scope == "build" && !ctx.Build {
			result.Status = "skipped"
			result.Message = "requires --build"
			results = append(results, result)
			continue
		}
		dir, err := acceptancePath(ctx.ProjectRoot, check.Dir)
		if err == nil {
			runCtx, cancel := context.WithTimeout(ctx.Ctx, 5*time.Minute)
			cmd := exec.CommandContext(runCtx, check.Argv[0], check.Argv[1:]...)
			cmd.Dir = dir
			cmd.WaitDelay = time.Second
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
			output := &acceptanceOutput{}
			cmd.Stdout, cmd.Stderr = output, output
			started := time.Now()
			err = cmd.Run()
			result.DurationMs = time.Since(started).Milliseconds()
			cancel()
			if err != nil {
				err = fmt.Errorf("%v: %s", err, output.text)
			}
		}
		if err != nil {
			result.Status = "fail"
			result.Message = err.Error()
		}
		results = append(results, result)
	}
	return results
}

type acceptanceOutput struct{ text string }

func (b *acceptanceOutput) Write(p []byte) (int, error) {
	b.text += string(p)
	if len(b.text) > 8192 {
		b.text = b.text[len(b.text)-8192:]
	}
	return len(p), nil
}

func validateAcceptance(expected Expectations) error {
	for _, file := range expected.Files {
		if !relativeAcceptancePath(file) {
			return fmt.Errorf("invalid required file %q", file)
		}
	}
	ids := map[string]bool{}
	for _, c := range expected.Commands {
		if strings.TrimSpace(c.ID) == "" || ids[c.ID] || !relativeAcceptancePath(c.Dir) || len(c.Argv) == 0 || strings.TrimSpace(c.Argv[0]) == "" {
			return fmt.Errorf("invalid acceptance command %q", c.ID)
		}
		if c.Scope != "repo" && c.Scope != "build" {
			return fmt.Errorf("acceptance scope must be repo or build")
		}
		ids[c.ID] = true
	}
	return nil
}
