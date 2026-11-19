package nixeval

import (
	"context"
	"fmt"
	"maps"
	"net/url"
	"os"
	"runtime"
	"slices"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

// ProjectFlakeArgs is the shared boundary for evaluating a consumer flake.
// Pass the returned argv to Nix directly, with its working directory set to
// projectRoot. Lock updates remain permitted in memory (required by overrides)
// but never written. A caller intentionally editing the lock must not use this.
func ProjectFlakeArgs(projectRoot string) ([]string, error) {
	links, err := userconfig.LoadLinkedModules(projectRoot)
	if err != nil {
		return nil, err
	}
	return linkFlags(links), nil
}

func linkFlags(links map[string]userconfig.LinkedModule) []string {
	args := make([]string, 1, 1+3*len(links))
	args[0] = "--no-write-lock-file"
	for _, id := range slices.Sorted(maps.Keys(links)) {
		path := (&url.URL{Path: links[id].Path}).EscapedPath()
		args = append(args, "--override-input", id, "path:"+path)
	}
	return args
}

// SetupFlakeArgs retains setup's frozen-lock requirement unless local links
// explicitly require resolving a different input graph in memory.
func SetupFlakeArgs(root string) ([]string, error) {
	flags, err := ProjectFlakeArgs(root)
	if err == nil && !slices.Contains(flags, "--override-input") {
		flags = append([]string{"--no-update-lock-file"}, flags...)
	}
	return flags, err
}

// CurrentSystem resolves host-dependent output names outside the pure Nix
// evaluator, where builtins.currentSystem does not exist.
func CurrentSystem() string {
	if sys := os.Getenv("NIX_SYSTEM"); sys != "" {
		return sys
	}
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		arch = "x86_64"
	case "arm64":
		arch = "aarch64"
	}
	return arch + "-" + runtime.GOOS
}

// ProjectAttr selects the canonical per-system output of a Stackpanel flake.
func ProjectAttr(name string) string {
	return ".#legacyPackages." + CurrentSystem() + "." + name
}

// EvalModuleState returns live serialized state for exactly one project. It
// never consults the global active project, shell state, or a generated cache.
func EvalModuleState(ctx context.Context, projectRoot string) ([]byte, error) {
	if projectRoot == "" {
		return nil, fmt.Errorf("module state requires an explicit project root")
	}
	return EvalOnce(ctx, EvalOnceParams{
		ProjectRoot: projectRoot,
		Expression:  ProjectAttr("stackpanelSerializable"),
		Timeout:     5 * time.Minute,
	})
}

// EvalProspectiveModuleState evaluates a proposed link graph without writing
// either user configuration or the consumer's lock. The caller has validated
// the selected input names, absolute paths, and URL policy before this probe.
func EvalProspectiveModuleState(
	ctx context.Context,
	root string,
	links map[string]userconfig.LinkedModule,
) ([]byte, error) {
	if root == "" {
		return nil, fmt.Errorf("module state requires an explicit project root")
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	return evalProjectOutput(ctx, root, "stackpanelSerializable", linkFlags(links))
}

// EvalLockedModuleState validates the unmodified lock after a registry
// mutation. A linked author checkout cannot conceal a broken installed pin.
// This is intentionally not an option on the ordinary module read API.
func EvalLockedModuleState(ctx context.Context, root string) ([]byte, error) {
	if root == "" {
		return nil, fmt.Errorf("lock validation requires an explicit project root")
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	return evalProjectOutput(
		ctx,
		root,
		"stackpanelSerializable",
		[]string{"--no-update-lock-file", "--no-write-lock-file"},
	)
}
