package reconcile

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Speculation is what evaluating the module system with accepted addon
// mutations overlaid would produce. Nothing is written or built to get it.
type Speculation struct {
	Files                    []PlanEntry         `json:"files"`
	Doctor                   []DoctorCheck       `json:"doctor"`
	Addons                   []nixeval.AddonSpec `json:"addons"`
	WriterDrvPath            string              `json:"writerDrvPath"`
	WriterOutPath            string              `json:"writerOutPath"`
	PreflightManifestDrvPath string              `json:"preflightManifestDrvPath"`
	PreflightManifestOutPath string              `json:"preflightManifestOutPath"`
}

// DefaultSpeculateTimeout bounds one full module-system evaluation.
const DefaultSpeculateTimeout = 10 * time.Minute

// Speculate evaluates the project's flake with `overlay` merged into the
// stackpanel config and returns the resulting file plan. One evaluation for
// the whole accepted set, not one per addon. Pure: `nix eval` writes nothing
// to the repository and realizes no derivations.
//
// The JSON payload is encoded as a single Nix string literal, not executable
// syntax; the evaluated function needs no access to a temp file or ambient env.
func Speculate(
	ctx context.Context,
	projectRoot string,
	overlay map[string]any,
	timeout time.Duration,
) (*Speculation, error) {
	if timeout <= 0 {
		timeout = DefaultSpeculateTimeout
	}
	overlayJSON, err := json.Marshal(overlay)
	if err != nil {
		return nil, fmt.Errorf("marshal overlay: %w", err)
	}
	literal, err := nix.Serialize(string(overlayJSON))
	if err != nil {
		return nil, fmt.Errorf("encode speculative overlay: %w", err)
	}
	data, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression:  ".#legacyPackages." + nixeval.CurrentSystem() + ".stackpanelSpeculate",
		Apply:       "f: f { config = builtins.fromJSON " + literal + "; }",
		ProjectRoot: projectRoot,
		Timeout:     timeout,
	})
	if err != nil {
		return nil, fmt.Errorf("speculative eval failed: %w", err)
	}

	var spec Speculation
	if err := json.Unmarshal(data, &spec); err != nil {
		return nil, fmt.Errorf("parse speculative eval: %w", err)
	}
	return &spec, nil
}

// RealizeOutputs builds derivations by drvPath and returns their output paths.
// Used by `stack setup` after a config mutation to materialize the new
// generation's writer and preflight manifest without re-entering the shell.
func RealizeOutputs(
	ctx context.Context,
	projectRoot string,
	drvPaths ...string,
) ([]string, error) {
	if len(drvPaths) == 0 {
		return nil, nil
	}
	args := []string{"build", "--no-link", "--print-out-paths"}
	for _, p := range drvPaths {
		args = append(args, p+"^*")
	}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Dir = projectRoot
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf(
			"nix build failed: %w\n%s",
			err,
			trimNixNoise(stderr.String()),
		)
	}
	var outs []string
	for _, line := range strings.Split(strings.TrimSpace(stdout.String()), "\n") {
		if line != "" {
			outs = append(outs, line)
		}
	}
	return outs, nil
}

// trimNixNoise drops the trusted-settings chatter nix prints on every run.
func trimNixNoise(s string) string {
	var kept []string
	for _, line := range strings.Split(s, "\n") {
		if strings.Contains(line, "trusted-settings") ||
			strings.Contains(line, "accept-flake-config") ||
			strings.HasPrefix(line, "warning: Git tree") {
			continue
		}
		kept = append(kept, line)
	}
	return strings.TrimSpace(strings.Join(kept, "\n"))
}
