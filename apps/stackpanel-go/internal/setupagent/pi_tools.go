package setupagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	piagent "github.com/sky-valley/pi/agent"
	"github.com/sky-valley/pi/coding"
)

// Reuse Pi's coding tools, with an application policy around each execution.
// Shell, recursive search, hooks, and automatic resource discovery are excluded
// from this experiment. Nix, installation and verification remain host actions.
func piTools(root string, readOnly bool, protected []string) ([]piagent.AgentTool, error) {
	root, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	names := []string{"read", "ls"}
	if !readOnly {
		names = append(names, "write", "edit")
	}
	var tools []piagent.AgentTool
	for _, name := range names {
		tool, err := coding.CreateTool(name, root)
		if err != nil {
			return nil, err
		}
		execute := tool.Execute
		tool.Execute = func(ctx context.Context, id string, args map[string]any, update piagent.ToolUpdateFunc) (piagent.AgentToolResult, error) {
			if err := ctx.Err(); err != nil {
				return piagent.AgentToolResult{}, err
			}
			path, _ := args["path"].(string)
			if path == "" && name == "ls" {
				path = "."
			}
			writable := name == "write" || name == "edit"
			absolute, err := piToolPath(root, path, writable, protected)
			if err != nil {
				return piagent.AgentToolResult{}, err
			}
			// Pi normalizes @, tilde, file:// and Unicode spaces. Supply the
			// already validated absolute path to avoid a second interpretation.
			args["path"] = absolute
			return execute(ctx, id, args, update)
		}
		tools = append(tools, tool)
	}
	return tools, nil
}

func piToolPath(root, path string, write bool, protected []string) (string, error) {
	if path == "" || strings.ContainsAny(path, "\x00\u00a0\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000") {
		return "", errors.New("tool requires an ordinary repository path")
	}
	abs := path
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(root, abs)
	}
	abs = filepath.Clean(abs)
	rel, err := filepath.Rel(root, abs)
	if err != nil || !filepath.IsLocal(rel) {
		return "", errors.New("tool path must stay inside the repository")
	}
	parts := strings.Split(filepath.ToSlash(rel), "/")
	for _, part := range parts {
		if part == ".git" || part == ".direnv" || part == "node_modules" ||
			part == ".aws" || part == ".ssh" || part == ".codex" || part == ".claude" || part == ".pi" ||
			part == ".env" || strings.HasPrefix(part, ".env.") || strings.HasSuffix(part, ".pem") || strings.HasSuffix(part, ".key") {
			return "", errors.New("tool path is private or managed state")
		}
	}
	for _, prefix := range []string{".stack/state", ".stack/secrets", ".stack/profile", ".stack/gen", ".stack/bin", "packages/gen/env"} {
		if piPathWithin(filepath.ToSlash(rel), prefix) {
			return "", errors.New("tool path is private or generated state")
		}
	}
	if write {
		for _, path := range protected {
			if piPathWithin(rel, filepath.Clean(path)) {
				return "", fmt.Errorf("preserve existing user file: %s", rel)
			}
		}
	}
	// No tool can create a symlink. Reject existing links (including ancestors)
	// before invoking Pi, so a repository link cannot redirect file operations.
	current := root
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			if write {
				break
			}
			return "", err
		}
		if err != nil {
			return "", err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return "", errors.New("Pi setup tools do not follow repository symlinks")
		}
		if !info.IsDir() && !info.Mode().IsRegular() {
			return "", errors.New("Pi setup tools only access ordinary files and directories")
		}
		if info.Mode().IsRegular() && info.Size() > 1<<20 {
			return "", errors.New("Pi setup file exceeds 1 MiB")
		}
	}
	return abs, nil
}

func piPathWithin(path, prefix string) bool {
	return path == prefix || strings.HasPrefix(path, prefix+"/")
}
