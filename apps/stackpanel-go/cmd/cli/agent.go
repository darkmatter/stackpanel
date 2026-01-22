package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/server"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/envvars"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
)

var agentCmd = &cobra.Command{
	Use:   "agent",
	Short: "Run the local Stackpanel agent",
	Long: `Run the local Stackpanel agent server.

The agent runs on your machine and exposes a localhost API used by the Stackpanel web UI
to run commands, evaluate Nix, and read/write files in the project.

The agent auto-detects projects by looking for .stackpanel/config.nix in the current
directory or parent directories.`,
	RunE: runAgent,
}

var agentTestTokenCmd = &cobra.Command{
	Use:   "test-token",
	Short: "Generate a deterministic test pairing token",
	Long: `Generate a deterministic pairing token for testing and E2E automation.

This command requires STACKPANEL_TEST_PAIRING_TOKEN to be set. The generated token
will be valid as long as the agent is started with the same secret.

The token is deterministic - running this command with the same secret and origin
will always produce the same token, making it suitable for CI/CD pipelines.

Example:
  export STACKPANEL_TEST_PAIRING_TOKEN="my-e2e-test-secret"
  stackpanel agent test-token --origin "http://localhost:3000"

Then use the token in your tests:
  curl -H "X-Stackpanel-Token: <token>" http://localhost:9876/api/...`,
	RunE: runAgentTestToken,
}

func init() {
	agentCmd.Flags().Bool("debug", false, "Enable debug logging")
	agentCmd.Flags().StringP("project-root", "p", "", "Project root (defaults to auto-detect from current directory)")
	agentCmd.Flags().Int("port", 9876, "Port to listen on")
	agentCmd.Flags().Bool("remote", false, "Enable remote access (binds to 0.0.0.0 and allows Tailscale origins)")
	agentCmd.Flags().String("bind", "", "Bind address (default 127.0.0.1, or 0.0.0.0 with --remote)")
	agentCmd.Flags().StringArray("host", []string{}, "Allowed CORS origins (can be specified multiple times, e.g., --host https://myapp.example.com)")

	// test-token subcommand
	agentTestTokenCmd.Flags().String("origin", "", "Origin to bind the token to (e.g., http://localhost:3000)")
	agentTestTokenCmd.Flags().Bool("json", false, "Output in JSON format")
	agentCmd.AddCommand(agentTestTokenCmd)
}

func runAgent(cmd *cobra.Command, args []string) error {
	debug, _ := cmd.Flags().GetBool("debug")
	projectRoot, _ := cmd.Flags().GetString("project-root")
	port, _ := cmd.Flags().GetInt("port")
	remote, _ := cmd.Flags().GetBool("remote")
	bindAddr, _ := cmd.Flags().GetString("bind")
	allowedHosts, _ := cmd.Flags().GetStringArray("host")

	// Setup logging
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	if debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
		log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	} else {
		zerolog.SetGlobalLevel(zerolog.InfoLevel)
	}

	// Set project root env var if specified
	if projectRoot != "" {
		os.Setenv("STACKPANEL_PROJECT_ROOT", projectRoot)
	}

	// Load config
	cfg, err := config.Load("")
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Override port if specified
	if port != 9876 {
		cfg.Port = port
	}

	// Handle remote access mode
	if remote {
		cfg.RemoteAccess = true
		if bindAddr == "" {
			cfg.BindAddress = "0.0.0.0"
		}
		log.Info().Msg("Remote access enabled - binding to all interfaces and allowing Tailscale origins")
	}

	// Override bind address if explicitly specified
	if bindAddr != "" {
		cfg.BindAddress = bindAddr
	}

	// Add allowed origins from --host flags
	if len(allowedHosts) > 0 {
		cfg.AllowedOrigins = append(cfg.AllowedOrigins, allowedHosts...)
		log.Info().Strs("hosts", allowedHosts).Msg("Added allowed CORS origins")
	}

	// Print banner
	fmt.Print(tui.Banner)

	log.Info().
		Str("version", Version).
		Int("port", cfg.Port).
		Msg("Starting stackpanel agent")

	// Create and start server
	srv, err := server.New(cfg)
	if err != nil {
		return fmt.Errorf("failed to create server: %w", err)
	}

	// Handle shutdown gracefully
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.Start(); err != nil {
			log.Fatal().Err(err).Msg("Server failed")
		}
	}()

	<-quit
	log.Info().Msg("Shutting down agent...")
	srv.Stop()

	return nil
}

func runAgentTestToken(cmd *cobra.Command, args []string) error {
	origin, _ := cmd.Flags().GetString("origin")
	jsonOutput, _ := cmd.Flags().GetBool("json")

	// Get the test pairing token from environment
	secret := envvars.StackpanelTestPairingToken.Get()
	if secret == "" {
		return fmt.Errorf("STACKPANEL_TEST_PAIRING_TOKEN environment variable is not set\n\nSet it to a secret string that will be used to derive the token:\n  export STACKPANEL_TEST_PAIRING_TOKEN=\"my-test-secret\"")
	}

	// Generate the test token
	token, agentID, err := server.GenerateTestTokenStatic(secret, origin)
	if err != nil {
		return fmt.Errorf("failed to generate test token: %w", err)
	}

	if jsonOutput {
		output := map[string]string{
			"token":    token,
			"agent_id": agentID,
			"origin":   origin,
		}
		data, err := json.MarshalIndent(output, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal JSON: %w", err)
		}
		fmt.Println(string(data))
	} else {
		fmt.Printf("Test Pairing Token Generated\n")
		fmt.Printf("============================\n\n")
		fmt.Printf("Agent ID: %s\n", agentID)
		if origin != "" {
			fmt.Printf("Origin:   %s\n", origin)
		} else {
			fmt.Printf("Origin:   (any)\n")
		}
		fmt.Printf("\nToken:\n%s\n", token)
		fmt.Printf("\nUsage:\n")
		fmt.Printf("  1. Start the agent with the same secret:\n")
		fmt.Printf("     export STACKPANEL_TEST_PAIRING_TOKEN=\"%s\"\n", secret)
		fmt.Printf("     stackpanel agent\n\n")
		fmt.Printf("  2. Use the token in API requests:\n")
		fmt.Printf("     curl -H \"X-Stackpanel-Token: %s\" http://localhost:9876/api/...\n", token)
	}

	return nil
}
