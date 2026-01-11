package cmd

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/server"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
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

func init() {
	agentCmd.Flags().Bool("debug", false, "Enable debug logging")
	agentCmd.Flags().StringP("project-root", "p", "", "Project root (defaults to auto-detect from current directory)")
	agentCmd.Flags().Int("port", 9876, "Port to listen on")
	agentCmd.Flags().Bool("remote", false, "Enable remote access (binds to 0.0.0.0 and allows Tailscale origins)")
	agentCmd.Flags().String("bind", "", "Bind address (default 127.0.0.1, or 0.0.0.0 with --remote)")
	agentCmd.Flags().StringArray("host", []string{}, "Allowed CORS origins (can be specified multiple times, e.g., --host https://myapp.example.com)")
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
