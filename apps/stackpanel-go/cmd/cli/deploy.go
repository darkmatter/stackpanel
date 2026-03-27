// deploy.go implements multi-backend deployment for stackpanel apps.
//
// Supported backends: colmena (NixOS multi-host), nixos-rebuild (single-host),
// alchemy (Cloudflare Workers), and fly (Fly.io). The deploy config is loaded
// live from the Nix flake via nix eval, not from the state file, so it always
// reflects the current flake.
package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/common"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/spf13/cobra"
)

// ---------------------------------------------------------------------------
// Config structs (deserialized from .#stackpanelConfig via nix eval)
// ---------------------------------------------------------------------------

type DeployMachineConfig struct {
	Host           string   `json:"host"`
	User           string   `json:"user"`
	System         string   `json:"system"`
	SSHPort        int      `json:"sshPort"`
	ProxyJump      string   `json:"proxyJump"`
	AuthorizedKeys []string `json:"authorizedKeys"`
}

type AppDeploymentOptions struct {
	Enable     bool     `json:"enable"`
	Host       string   `json:"host"`
	Backend    string   `json:"backend"`
	Targets    []string `json:"targets"`
	DefaultEnv string   `json:"defaultEnv"`
}

type DeployAppConfig struct {
	Deployment AppDeploymentOptions `json:"deployment"`
}

type DeployStackpanelConfig struct {
	Apps       map[string]DeployAppConfig `json:"apps"`
	Deployment struct {
		Machines map[string]DeployMachineConfig `json:"machines"`
	} `json:"deployment"`
}

// ---------------------------------------------------------------------------
// State file structs (.stack/state/deployments.json)
// ---------------------------------------------------------------------------

// DeploymentsState tracks the last deployment per app per environment.
// Keyed as map[appName]map[envName]DeploymentRecord. Persisted to
// .stack/state/deployments.json so `deploy status` can report history
// without re-evaluating the flake.
type DeploymentsState map[string]map[string]DeploymentRecord

type DeploymentRecord struct {
	Timestamp   string `json:"timestamp"`
	Backend     string `json:"backend"`
	Target      string `json:"target"`
	NixRevision string `json:"nixRevision"`
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

var deployCmd = &cobra.Command{
	Use:   "deploy [app]",
	Short: "Deploy apps to configured targets",
	Long: `Deploy apps to configured targets.

Without arguments, lists configured deployments.
With an app name, deploys that app to its configured targets.

Backends:
  colmena       - NixOS via colmena (multi-host)
  nixos-rebuild - NixOS via nixos-rebuild switch (single-host)
  alchemy       - Cloudflare Workers via Alchemy
  fly           - Fly.io containers

Examples:
  stackpanel deploy                     # List configured deployments
  stackpanel deploy my-api              # Deploy my-api to all targets
  stackpanel deploy my-api --dry-run    # Print command without executing it`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		cfg, err := loadDeployConfig(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load deploy config: %v", err))
			os.Exit(1)
		}

		if len(args) == 0 {
			listDeployments(cfg)
			return
		}

		appName := args[0]
		dryRun, _ := cmd.Flags().GetBool("dry-run")

		if err := runDeploy(ctx, cfg, appName, dryRun); err != nil {
			output.Error(fmt.Sprintf("Deploy failed: %v", err))
			os.Exit(1)
		}
	},
}

var deployStatusCmd = &cobra.Command{
	Use:   "status [app]",
	Short: "Show deployment status",
	Long: `Show the last recorded deployment status.

Without arguments, shows status for all apps.
With an app name, shows status for that specific app.

Status is read from .stack/state/deployments.json`,
	Run: func(cmd *cobra.Command, args []string) {
		appFilter := ""
		if len(args) > 0 {
			appFilter = args[0]
		}

		if err := showDeployStatus(appFilter); err != nil {
			output.Error(fmt.Sprintf("Failed to read deploy status: %v", err))
			os.Exit(1)
		}
	},
}

func init() {
	deployCmd.AddCommand(deployStatusCmd)

	deployCmd.Flags().Bool("dry-run", false, "Print the command that would be run without executing it")
}

// ---------------------------------------------------------------------------
// Config loading
// ---------------------------------------------------------------------------

// deployConfigExpr evaluates only the fields the deploy/provision commands
// need, avoiding the full filterSerializable traversal that forces expensive
// derivation instantiation (e.g. bun.nix with ~5000 fetchurl calls).
const deployConfigExpr = `
let
  flake = builtins.getFlake (toString ./.);
  sys = builtins.currentSystem;
  sp = flake.legacyPackages.${sys}.stackpanelFullConfig;
  serializeApp = name: app: {
    deployment = {
      enable = app.deployment.enable or false;
      host = app.deployment.host or "";
      backend = app.deployment.backend or "colmena";
      targets = app.deployment.targets or [];
      defaultEnv = app.deployment.defaultEnv or "prod";
    };
  };
in builtins.toJSON {
  apps = builtins.mapAttrs serializeApp (sp.apps or {});
  deployment = {
    machines = builtins.mapAttrs (name: m: {
      host = m.host or "";
      user = m.user or "root";
      system = m.system or "x86_64-linux";
      sshPort = m.sshPort or 22;
      proxyJump = m.proxyJump or null;
      authorizedKeys = m.authorizedKeys or [];
    }) (sp.deployment.machines or {});
  };
}
`

func loadDeployConfig(ctx context.Context) (*DeployStackpanelConfig, error) {
	root := detectStackpanelProject()
	if root == "" {
		return nil, fmt.Errorf("could not find stackpanel project root (look for .stack/config.nix or flake.nix under cwd); try running from the repo root or set STACKPANEL_ROOT")
	}
	result, err := nixeval.EvalOnce(ctx, nixeval.EvalOnceParams{
		Expression:  deployConfigExpr,
		ProjectRoot: root,
		// Flake eval can exceed the default 10s on cold cache or large trees.
		Timeout: 10 * time.Minute,
	})
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %w", err)
	}

	// The expression returns a JSON string via builtins.toJSON, so the
	// outer result is a JSON-encoded string that we need to unwrap.
	var jsonStr string
	if err := json.Unmarshal(result, &jsonStr); err != nil {
		// If it's not a wrapped string, try parsing directly
		var cfg DeployStackpanelConfig
		if err2 := json.Unmarshal(result, &cfg); err2 != nil {
			return nil, fmt.Errorf("failed to parse deploy config: %w", err)
		}
		return &cfg, nil
	}

	common.L().Debug("using deploy config", "jsonStr", jsonStr)

	var cfg DeployStackpanelConfig
	if err := json.Unmarshal([]byte(jsonStr), &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse deploy config: %w", err)
	}

	return &cfg, nil
}

// ---------------------------------------------------------------------------
// Deploy operations
// ---------------------------------------------------------------------------

func listDeployments(cfg *DeployStackpanelConfig) {
	if len(cfg.Deployment.Machines) > 0 {
		machineState, _ := readMachineState()
		if machineState == nil {
			machineState = make(MachinesState)
		}

		machineNames := make([]string, 0, len(cfg.Deployment.Machines))
		for name := range cfg.Deployment.Machines {
			machineNames = append(machineNames, name)
		}
		sort.Strings(machineNames)

		fmt.Println("Machines:")
		for _, name := range machineNames {
			machine := cfg.Deployment.Machines[name]
			rec, provisioned := machineState[name]

			hwIndicator := "✗"
			provisionedStr := "not provisioned"
			if provisioned {
				provisionedStr = "provisioned " + rec.ProvisionedAt[:10]
				if rec.HardwareConfigGenerated {
					hwIndicator = "✓"
				}
			}
			fmt.Printf("  %-20s  %-20s  %-32s  hw-config %s\n",
				output.Purple.Sprint(name), machine.Host, provisionedStr, hwIndicator)
		}
		fmt.Println()
	}

	deployableApps := []string{}
	for name, app := range cfg.Apps {
		if app.Deployment.Enable {
			deployableApps = append(deployableApps, name)
		}
	}

	if len(deployableApps) == 0 {
		output.Warning("No apps have deployment enabled.")
		output.Dimmed("Set deployment.enable = true in your app config to enable deployment.")
		return
	}

	sort.Strings(deployableApps)
	fmt.Println("Deployments:")
	for _, name := range deployableApps {
		app := cfg.Apps[name]
		backend := resolveBackend(app.Deployment)
		fmt.Printf("  %s\n", output.Purple.Sprint(name))
		output.Dimmed(fmt.Sprintf("    backend: %s", backend))
		if len(app.Deployment.Targets) > 0 {
			output.Dimmed(fmt.Sprintf("    targets: %v", app.Deployment.Targets))
		}
		output.Dimmed(fmt.Sprintf("    env:     %s", app.Deployment.DefaultEnv))
	}
}

func runDeploy(ctx context.Context, cfg *DeployStackpanelConfig, appName string, dryRun bool) error {
	app, ok := cfg.Apps[appName]
	if !ok {
		return fmt.Errorf("app %q not found in config", appName)
	}
	if !app.Deployment.Enable {
		return fmt.Errorf("app %q does not have deployment.enable = true", appName)
	}

	backend := resolveBackend(app.Deployment)
	env := app.Deployment.DefaultEnv
	if env == "" {
		env = "prod"
	}

	output.Info(fmt.Sprintf("Deploying %s (backend: %s, env: %s)", appName, backend, env))

	var target string
	var deployErr error

	switch backend {
	case "colmena":
		target = joinTargets(app.Deployment.Targets)
		deployErr = deployColmena(ctx, cfg, appName, app, dryRun, env)
	case "nixos-rebuild":
		target = joinTargets(app.Deployment.Targets)
		deployErr = deployNixosRebuild(ctx, cfg, appName, app, dryRun)
	case "alchemy":
		target = env
		deployErr = deployAlchemy(ctx, appName, app, dryRun)
	default:
		return fmt.Errorf("backend %q is not supported by the CLI; run the deploy manually", backend)
	}

	if deployErr != nil {
		return deployErr
	}

	if !dryRun {
		if err := recordDeployment(appName, env, backend, target); err != nil {
			output.Warning(fmt.Sprintf("Failed to record deployment state: %v", err))
		}
		output.Success(fmt.Sprintf("Deployed %s (%s → %s)", appName, backend, target))
	}
	return nil
}

func joinTargets(targets []string) string {
	result := ""
	for i, t := range targets {
		if i > 0 {
			result += ","
		}
		result += t
	}
	return result
}

// resolveBackend derives the effective backend from the app's config.
// New: uses deployment.backend directly.
// Legacy fallback: maps deployment.host (cloudflare -> alchemy, fly -> fly).
func resolveBackend(d AppDeploymentOptions) string {
	if d.Backend != "" {
		return d.Backend
	}
	switch d.Host {
	case "cloudflare":
		return "alchemy"
	case "fly":
		return "fly"
	}
	return "colmena"
}

func deployColmena(ctx context.Context, cfg *DeployStackpanelConfig, appName string, app DeployAppConfig, dryRun bool, env string) error {
	if len(app.Deployment.Targets) == 0 {
		return fmt.Errorf("app %q has no deployment.targets configured", appName)
	}

	targetList := ""
	for i, t := range app.Deployment.Targets {
		if i > 0 {
			targetList += ","
		}
		targetList += t
	}

	var args []string
	if dryRun {
		args = []string{"--impure", "build", "--on", targetList}
	} else {
		args = []string{"--impure", "apply", "--on", targetList}
	}

	return runExternalCommand(ctx, "colmena", args, dryRun)
}

func deployNixosRebuild(ctx context.Context, cfg *DeployStackpanelConfig, appName string, app DeployAppConfig, dryRun bool) error {
	if len(app.Deployment.Targets) == 0 {
		return fmt.Errorf("app %q has no deployment.targets configured", appName)
	}

	for _, machineName := range app.Deployment.Targets {
		machine, ok := cfg.Deployment.Machines[machineName]
		if !ok {
			return fmt.Errorf("machine %q not found in deployment.machines config", machineName)
		}

		targetHost := fmt.Sprintf("%s@%s", machine.User, machine.Host)
		args := []string{
			"switch",
			"--flake", fmt.Sprintf(".#%s", machineName),
			"--target-host", targetHost,
		}
		if dryRun {
			args[0] = "dry-activate"
		}

		output.Info(fmt.Sprintf("  → %s (%s)", machineName, targetHost))
		if err := runExternalCommand(ctx, "nixos-rebuild", args, dryRun); err != nil {
			return err
		}
	}
	return nil
}

func deployAlchemy(ctx context.Context, appName string, app DeployAppConfig, dryRun bool) error {
	env := app.Deployment.DefaultEnv
	if env == "" {
		env = "prod"
	}

	entrypoint := findAlchemyEntrypoint(appName)

	args := []string{"run", entrypoint}
	if dryRun {
		output.Info(fmt.Sprintf("dry-run: STAGE=%s bun %s", env, entrypoint))
		return nil
	}

	cmd := exec.CommandContext(ctx, "bun", args...)
	cmd.Env = append(os.Environ(), fmt.Sprintf("STAGE=%s", env))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	output.Info(fmt.Sprintf("Running: STAGE=%s bun run %s", env, entrypoint))
	return cmd.Run()
}

// findAlchemyEntrypoint searches common locations for the Alchemy deploy
// script. Projects may place it at the repo root, in an infra/ subdirectory,
// or nested under apps/<name>/. Falls back to "alchemy.run.ts" so the error
// message from bun is clear about what's missing.
func findAlchemyEntrypoint(appName string) string {
	candidates := []string{
		"alchemy.run.ts",
		"infra/alchemy.ts",
		fmt.Sprintf("apps/%s/alchemy.run.ts", appName),
		fmt.Sprintf("apps/%s/infra/alchemy.ts", appName),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return "alchemy.run.ts"
}

func runExternalCommand(ctx context.Context, name string, args []string, dryRun bool) error {
	if dryRun {
		output.Info(fmt.Sprintf("dry-run: %s %v", name, args))
		return nil
	}

	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	output.Info(fmt.Sprintf("Running: %s %v", name, args))
	return cmd.Run()
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

func showDeployStatus(appFilter string) error {
	state, err := readDeployState()
	if err != nil {
		if os.IsNotExist(err) {
			output.Dimmed("No deployments recorded.")
			output.Dimmed("Run `stackpanel deploy <app>` to deploy an app.")
			return nil
		}
		return err
	}

	if len(state) == 0 {
		output.Dimmed("No deployments recorded.")
		return nil
	}

	apps := make([]string, 0, len(state))
	for name := range state {
		if appFilter == "" || name == appFilter {
			apps = append(apps, name)
		}
	}
	sort.Strings(apps)

	if len(apps) == 0 && appFilter != "" {
		output.Warning(fmt.Sprintf("No deployment records found for app %q", appFilter))
		return nil
	}

	for _, appName := range apps {
		fmt.Printf("\n%s %s\n", output.Purple.Sprint("==>"), appName)
		envRecords := state[appName]
		envs := make([]string, 0, len(envRecords))
		for env := range envRecords {
			envs = append(envs, env)
		}
		sort.Strings(envs)
		for _, env := range envs {
			rec := envRecords[env]
			output.Dimmed(fmt.Sprintf("  env:     %s", env))
			output.Dimmed(fmt.Sprintf("  backend: %s", rec.Backend))
			output.Dimmed(fmt.Sprintf("  target:  %s", rec.Target))
			output.Dimmed(fmt.Sprintf("  time:    %s", rec.Timestamp))
			if rec.NixRevision != "" {
				output.Dimmed(fmt.Sprintf("  rev:     %s", rec.NixRevision))
			}
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// State file helpers
// ---------------------------------------------------------------------------

func deployStateFile() string {
	root := os.Getenv("STACKPANEL_ROOT")
	if root == "" {
		root = detectStackpanelProject()
	}
	if root == "" {
		root = "."
	}
	return filepath.Join(root, ".stack", "state", "deployments.json")
}

func readDeployState() (DeploymentsState, error) {
	data, err := os.ReadFile(deployStateFile())
	if err != nil {
		return nil, err
	}
	var state DeploymentsState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("failed to parse deployments.json: %w", err)
	}
	return state, nil
}

func writeDeployState(state DeploymentsState) error {
	stateFile := deployStateFile()
	if err := os.MkdirAll(filepath.Dir(stateFile), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(stateFile, data, 0o644)
}

func recordDeployment(appName, env, backend, target string) error {
	state, err := readDeployState()
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if state == nil {
		state = make(DeploymentsState)
	}
	if state[appName] == nil {
		state[appName] = make(map[string]DeploymentRecord)
	}

	rev := gitRevision()
	state[appName][env] = DeploymentRecord{
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		Backend:     backend,
		Target:      target,
		NixRevision: rev,
	}
	return writeDeployState(state)
}

func gitRevision() string {
	cmd := exec.Command("git", "rev-parse", "--short", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return string(out[:len(out)-1])
}
