package nixeval

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// GetConfigWithEval returns the typed CLI state (distinct from the full module
// state). With links, cached shell output is stale by definition: evaluate the
// project's exported CLI config with the live input overrides instead.
func GetConfigWithEval(ctx context.Context, projectRoot string) (*Config, error) {
	if projectRoot == "" {
		projectRoot = findProjectRoot()
	}
	if projectRoot != "" {
		var err error
		projectRoot, err = filepath.Abs(projectRoot)
		if err != nil {
			return nil, err
		}
	}
	load := func(path string) (*Config, error) {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		return decodeConfig(data, projectRoot)
	}
	var linked bool
	if projectRoot != "" {
		links, err := userconfig.LoadLinkedModules(projectRoot)
		if err != nil {
			return nil, err
		}
		linked = len(links) != 0
	}
	if !linked {
		// Never pass a cache from the agent's shell to a different consumer.
		if projectRoot == "" || projectRoot == os.Getenv("STACKPANEL_ROOT") {
			if path := os.Getenv("STACKPANEL_CONFIG_JSON"); filepath.IsAbs(path) {
				if c, err := load(path); err == nil || !os.IsNotExist(err) {
					return c, err
				}
			}
			if dir := os.Getenv("STACKPANEL_STATE_DIR"); filepath.IsAbs(dir) {
				if c, err := load(
					filepath.Join(dir, "stackpanel.json"),
				); err == nil ||
					!os.IsNotExist(err) {
					return c, err
				}
			}
		}
		if projectRoot != "" {
			for _, dir := range []string{".stack/profile", ".stack/state"} {
				if c, err := load(
					filepath.Join(projectRoot, dir, "stackpanel.json"),
				); err == nil ||
					!os.IsNotExist(err) {
					return c, err
				}
			}
		}
	}
	if projectRoot == "" {
		return nil, fmt.Errorf("no Stackpanel project or shell configuration found")
	}
	data, err := EvalOnce(ctx, EvalOnceParams{
		ProjectRoot: projectRoot,
		Expression:  ".#devShells." + CurrentSystem() + ".default.passthru.env.STACKPANEL_CONFIG_JSON",
		Apply:       "path: builtins.fromJSON (builtins.readFile path)",
	})
	if err != nil {
		return nil, err
	}
	return decodeConfig(data, projectRoot)
}

func decodeConfig(data []byte, root string) (*Config, error) {
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parse CLI configuration: %w", err)
	}
	if c.Error != "" {
		return nil, fmt.Errorf("%s: %s", c.Error, c.Hint)
	}
	if root != "" {
		c.ProjectRoot = root
	}
	return &c, nil
}

// EvalOnceParams configures a generic one-shot nix eval invocation.
type EvalOnceParams struct {
	Expression  string            // Nix expression or flake installable (e.g. ".#foo")
	Args        map[string]string // Passed as --argstr key value pairs
	Apply       string            // Optional function applied to an installable via --apply
	ProjectRoot string
	Timeout     time.Duration
}

// EvalOnce loads overrides for the selected consumer, not for the agent's cwd.
// CLI commands using a relative .# attribute may discover their project root;
// agent callers must always pass the selected project explicitly.
func EvalOnce(ctx context.Context, opts EvalOnceParams) ([]byte, error) {
	root := opts.ProjectRoot
	if opts.Expression == "" && root == "" {
		return nil, fmt.Errorf("an expression or explicit project root is required")
	}
	if root == "" && strings.HasPrefix(opts.Expression, ".#") {
		root = findProjectRoot()
		if root == "" {
			return nil, fmt.Errorf("no project found for %q", opts.Expression)
		}
	}
	timeout := opts.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	nixArgs := []string{"eval", "--json"}
	if root != "" {
		var err error
		root, err = filepath.Abs(root)
		if err != nil {
			return nil, err
		}
		flags, err := ProjectFlakeArgs(root)
		if err != nil {
			return nil, err
		}
		nixArgs = append(nixArgs, flags...)
	} else {
		nixArgs = append(nixArgs, "--no-write-lock-file")
	}
	if opts.Expression != "" {
		expr := opts.Expression
		if root != "" &&
			(strings.HasPrefix(expr, "path:") || strings.HasPrefix(expr, "git+") || strings.HasPrefix(expr, "github:") || strings.HasPrefix(expr, "nixpkgs#")) {
			return nil, fmt.Errorf(
				"project evaluation requires a relative flake attribute, not %q",
				expr,
			)
		}
		if strings.HasPrefix(expr, ".#") || strings.HasPrefix(expr, "path:") ||
			strings.HasPrefix(expr, "git+") ||
			strings.HasPrefix(expr, "github:") ||
			strings.HasPrefix(expr, "nixpkgs#") {
			nixArgs = append(nixArgs, expr)
		} else {
			nixArgs = append(nixArgs, "--expr", expr)
		}
	}
	if opts.Apply != "" {
		nixArgs = append(nixArgs, "--apply", opts.Apply)
	}
	for k, v := range opts.Args {
		nixArgs = append(nixArgs, "--argstr", k, v)
	}
	return runEval(ctx, root, nixArgs)
}

func runEval(ctx context.Context, root string, args []string) ([]byte, error) {
	nix, err := findNixBin()
	if err != nil {
		return nil, err
	}
	cmd := exec.CommandContext(ctx, nix, args...)
	cmd.Dir = root
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.Output()
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("nix eval failed: %w\n%s", err, stderr.String())
	}
	return stdout, nil
}

// findProjectRoot walks up from cwd before consulting the shell root. A CLI
// opened in consumer B inside project A's devshell must not evaluate A's inputs.
func findProjectRoot() string {
	cwd, err := os.Getwd()
	if err == nil {
		for dir := cwd; ; dir = filepath.Dir(dir) {
			if _, err := os.Stat(filepath.Join(dir, "flake.nix")); err == nil {
				return dir
			}
			if filepath.Dir(dir) == dir {
				break
			}
		}
	}
	if root := os.Getenv("STACKPANEL_ROOT"); filepath.IsAbs(root) {
		return root
	}
	return ""
}
