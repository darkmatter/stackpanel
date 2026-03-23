package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/fileops"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var preflightCmd = &cobra.Command{
	Use:   "preflight",
	Short: "Run shell-entry preparation tasks",
	Long: `Run shell-entry preparation tasks and explicit environment imports.

Use 'stackpanel preflight run' for safe entry tasks like host-side code generation.
Use 'stackpanel preflight import-env' to explicitly materialize environment values
into .stack/config.local.nix for pure-mode evaluation.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var (
	preflightProjectRoot  string
	preflightQuiet        bool
	preflightCodegenForce bool

	preflightImportEnvDryRun bool
	preflightImportEnvForce  bool
)

var preflightRunCmd = &cobra.Command{
	Use:   "run [module...]",
	Short: "Run safe shell-entry tasks",
	Long: `Run safe shell-entry tasks.

This is the entrypoint that shell startup should use. It performs idempotent,
host-side preparation such as code generation without materializing ambient
environment variables into tracked config files.

When module names are provided, only those codegen modules are built.`,
	RunE: runPreflightRun,
}

var preflightImportEnvCmd = &cobra.Command{
	Use:   "import-env",
	Short: "Generate config.local.nix from environment variables for pure mode",
	Long: `Generate config.local.nix from environment variables.

The purpose of this command is to allow pure evaluation while still providing a
way to configure modules using environment variables.

We add a preflight stage before the actual evaluation where all relevant environment
variables are collected into ` + "`" + `config.initial-env = { KEY = VALUE; ... }` + "`" + `

It simply represents the environment variables that were defined at eval time, except
as an attribute set so that it can be read by nix. This file can be gitignored but
that would require impure eval to read, so we recommend checking it in as a blank file
with changes untracked.

In pure mode, all environment variables are cleaned except those in ` + "`" + `devshell.clean.keep` + "`" + `

After running this, you can use 'nix develop' (without --impure) and direnv
will work in pure mode, making evaluation fully reproducible.`,
	RunE: runPreflightImportEnv,
}

func init() {
	rootCmd.AddCommand(preflightCmd)

	preflightCmd.AddCommand(preflightRunCmd)
	preflightCmd.AddCommand(preflightImportEnvCmd)

	preflightRunCmd.Flags().StringVar(&preflightProjectRoot, "project-root", "", "Project root (defaults to the current stackpanel project)")
	preflightRunCmd.Flags().BoolVar(&preflightQuiet, "quiet", false, "Suppress codegen summary output")
	preflightRunCmd.Flags().BoolVar(&preflightCodegenForce, "force", false, "Rewrite generated files even when contents are unchanged")

	preflightImportEnvCmd.Flags().BoolVar(&preflightImportEnvDryRun, "dry-run", false, "Show what would be generated without writing files")
	preflightImportEnvCmd.Flags().BoolVar(&preflightImportEnvForce, "force", false, "Overwrite existing config.local.nix")
}

func runPreflightRun(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolvePreflightProjectRoot(preflightProjectRoot)
	if err != nil {
		return err
	}

	if err := writeProjectRootMarker(projectRoot); err != nil {
		return err
	}

	verbose, _ := cmd.Flags().GetBool("verbose")
	summary, err := buildCodegenModules(cmd.Context(), projectRoot, args, preflightCodegenForce, verbose)
	if err != nil {
		return err
	}

	fileSummary, err := runPreflightFileOps(projectRoot)
	if err != nil {
		return err
	}

	if !preflightQuiet {
		printCodegenSummary(summary, verbose)
		printFileOpsSummary(projectRoot, fileSummary)
		output.Success(fmt.Sprintf("Preflight completed with %d codegen module(s)", len(summary.Results)))
	}

	return nil
}

func runPreflightFileOps(projectRoot string) (*fileops.Summary, error) {
	manifestPath := os.Getenv("STACKPANEL_FILES_PREFLIGHT_MANIFEST")
	if manifestPath == "" {
		return &fileops.Summary{}, nil
	}

	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read preflight files manifest: %w", err)
	}

	var manifest fileops.Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("failed to parse preflight files manifest: %w", err)
	}

	stateDir := os.Getenv("STACKPANEL_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(projectRoot, ".stack", "profile")
	}

	summary, err := fileops.ApplyManifest(projectRoot, stateDir, manifest)
	if err != nil {
		return nil, err
	}
	return &summary, nil
}

func printFileOpsSummary(projectRoot string, summary *fileops.Summary) {
	if summary == nil {
		return
	}

	for _, backup := range summary.Backups {
		rel := relativeDisplayPath(projectRoot, backup)
		output.Warning(fmt.Sprintf("Backed up %s", rel))
	}
	for _, path := range summary.Writes {
		output.Dimmed(fmt.Sprintf("  wrote %s", relativeDisplayPath(projectRoot, path)))
	}
	for _, path := range summary.Restored {
		if strings.Contains(path, ":") {
			output.Dimmed(fmt.Sprintf("  restored %s", path))
			continue
		}
		output.Dimmed(fmt.Sprintf("  restored %s", relativeDisplayPath(projectRoot, path)))
	}
	for _, path := range summary.Removed {
		output.Dimmed(fmt.Sprintf("  removed %s", relativeDisplayPath(projectRoot, path)))
	}
}

func runPreflightImportEnv(cmd *cobra.Command, args []string) error {
	projectRoot, err := resolvePreflightProjectRoot("")
	if err != nil {
		return fmt.Errorf("could not find project root: %w", err)
	}

	envConfig := collectEnvConfig()
	nixExpr := generateNixConfig(envConfig)

	if preflightImportEnvDryRun {
		fmt.Println("# Would generate the following config.local.nix:")
		fmt.Println(nixExpr)
		fmt.Printf("\n# Project root: %s\n", projectRoot)
		return nil
	}

	if err := writeProjectRootMarker(projectRoot); err != nil {
		return err
	}

	configPath := filepath.Join(projectRoot, ".stack", "config.local.nix")
	if !preflightImportEnvForce {
		if _, statErr := os.Stat(configPath); statErr == nil {
			return fmt.Errorf("config.local.nix already exists (use --force to overwrite)")
		}
	}

	if err := os.WriteFile(configPath, []byte(nixExpr), 0644); err != nil {
		return fmt.Errorf("failed to write config.local.nix: %w", err)
	}

	fmt.Printf("✅ Generated config.local.nix\n")
	fmt.Printf("   Project root: %s\n", projectRoot)
	fmt.Printf("   Config file: %s\n", configPath)
	fmt.Printf("\n💡 You can now use pure mode:\n")
	fmt.Printf("   nix develop  # (without --impure)\n")
	fmt.Printf("   direnv allow # (will use pure mode)\n")

	return nil
}

func resolvePreflightProjectRoot(flagValue string) (string, error) {
	if flagValue != "" {
		return flagValue, nil
	}
	if envRoot := os.Getenv("STACKPANEL_ROOT"); envRoot != "" {
		return envRoot, nil
	}
	return findProjectRoot()
}

func writeProjectRootMarker(projectRoot string) error {
	markerPath := filepath.Join(projectRoot, ".stackpanel-root")
	if err := os.WriteFile(markerPath, []byte(projectRoot+"\n"), 0644); err != nil {
		return fmt.Errorf("failed to write .stackpanel-root marker: %w", err)
	}
	return nil
}

// envConfig holds environment variable configuration.
type envConfig struct {
	AWSProfileARN      string
	AWSRoleARN         string
	AWSTrustAnchorARN  string
	AWSRegion          string
	AWSAccessKeyID     string
	AWSSecretAccessKey string
	AWSSessionToken    string

	StepCAURL         string
	StepCAFingerprint string
	StepCACert        string

	StackpanelRoot       string
	StackpanelConfigJSON string
	StackpanelStateDir   string
}

func collectEnvConfig() envConfig {
	return envConfig{
		AWSProfileARN:        os.Getenv("AWS_PROFILE_ARN"),
		AWSRoleARN:           os.Getenv("AWS_ROLE_ARN"),
		AWSTrustAnchorARN:    os.Getenv("AWS_TRUST_ANCHOR_ARN"),
		AWSRegion:            getAWSRegion(),
		AWSAccessKeyID:       os.Getenv("AWS_ACCESS_KEY_ID"),
		AWSSecretAccessKey:   os.Getenv("AWS_SECRET_ACCESS_KEY"),
		AWSSessionToken:      os.Getenv("AWS_SESSION_TOKEN"),
		StepCAURL:            os.Getenv("STEP_CA_URL"),
		StepCAFingerprint:    os.Getenv("STEP_CA_FINGERPRINT"),
		StepCACert:           os.Getenv("STEP_CA_CERT"),
		StackpanelRoot:       os.Getenv("STACKPANEL_ROOT"),
		StackpanelConfigJSON: os.Getenv("STACKPANEL_CONFIG_JSON"),
		StackpanelStateDir:   os.Getenv("STACKPANEL_STATE_DIR"),
	}
}

func getAWSRegion() string {
	if region := os.Getenv("AWS_REGION"); region != "" {
		return region
	}
	return os.Getenv("AWS_DEFAULT_REGION")
}

func generateNixConfig(cfg envConfig) string {
	var sb strings.Builder

	sb.WriteString("# config.local.nix\n")
	sb.WriteString("# Generated by: stackpanel preflight import-env\n")
	sb.WriteString("#\n")
	sb.WriteString("# This file materializes environment variables into Nix configuration,\n")
	sb.WriteString("# enabling pure mode evaluation (nix develop without --impure).\n")
	sb.WriteString("#\n")
	sb.WriteString("# To regenerate: stackpanel preflight import-env --force\n")
	sb.WriteString("# To remove: rm .stack/config.local.nix && use impure mode again\n")
	sb.WriteString("{\n")

	hasAnyConfig := false

	if hasAWSConfig(cfg) {
		hasAnyConfig = true
		sb.WriteString("  # AWS Configuration\n")
		sb.WriteString("  aws = {\n")

		if cfg.AWSProfileARN != "" {
			sb.WriteString(fmt.Sprintf("    profileArn = %s;\n", nixString(cfg.AWSProfileARN)))
		}
		if cfg.AWSRoleARN != "" {
			sb.WriteString(fmt.Sprintf("    roleArn = %s;\n", nixString(cfg.AWSRoleARN)))
		}
		if cfg.AWSTrustAnchorARN != "" {
			sb.WriteString(fmt.Sprintf("    trustAnchorArn = %s;\n", nixString(cfg.AWSTrustAnchorARN)))
		}
		if cfg.AWSRegion != "" {
			sb.WriteString(fmt.Sprintf("    region = %s;\n", nixString(cfg.AWSRegion)))
		}

		sb.WriteString("  };\n\n")
	}

	if hasStepCAConfig(cfg) {
		hasAnyConfig = true
		sb.WriteString("  # Step CA Configuration\n")
		sb.WriteString("  stepCA = {\n")

		if cfg.StepCAURL != "" {
			sb.WriteString(fmt.Sprintf("    url = %s;\n", nixString(cfg.StepCAURL)))
		}
		if cfg.StepCAFingerprint != "" {
			sb.WriteString(fmt.Sprintf("    fingerprint = %s;\n", nixString(cfg.StepCAFingerprint)))
		}
		if cfg.StepCACert != "" {
			sb.WriteString(fmt.Sprintf("    cert = %s;\n", nixString(cfg.StepCACert)))
		}

		sb.WriteString("  };\n\n")
	}

	if cfg.AWSAccessKeyID != "" || cfg.AWSSecretAccessKey != "" || cfg.AWSSessionToken != "" {
		sb.WriteString("  # Note: AWS credentials are NOT included in config.local.nix for security.\n")
		sb.WriteString("  # Use secrets management (vals/sops) or shell environment for credentials.\n")
		sb.WriteString("  # The following are available via environment only:\n")
		sb.WriteString("  #   - AWS_ACCESS_KEY_ID\n")
		sb.WriteString("  #   - AWS_SECRET_ACCESS_KEY\n")
		sb.WriteString("  #   - AWS_SESSION_TOKEN\n\n")
	}

	if !hasAnyConfig {
		sb.WriteString("  # No configuration found in environment variables.\n")
		sb.WriteString("  # This file can be deleted if not needed.\n")
	}

	sb.WriteString("}\n")
	return sb.String()
}

func nixString(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "${", "\\${")
	return fmt.Sprintf(`"%s"`, s)
}

func hasAWSConfig(cfg envConfig) bool {
	return cfg.AWSProfileARN != "" ||
		cfg.AWSRoleARN != "" ||
		cfg.AWSTrustAnchorARN != "" ||
		cfg.AWSRegion != ""
}

func hasStepCAConfig(cfg envConfig) bool {
	return cfg.StepCAURL != "" ||
		cfg.StepCAFingerprint != "" ||
		cfg.StepCACert != ""
}
