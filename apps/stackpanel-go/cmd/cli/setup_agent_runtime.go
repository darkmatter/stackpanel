package cmd

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"syscall"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func runSetupRuntime(ctx context.Context, root, executable string, selected []string, opts setupFlags, ui *tui.SetupUI, debug io.Writer) error {
	base := opts.studioURL
	if base == "" {
		base = setupsession.DefaultStudioURL
	}
	if _, err := setupsession.StudioURL(base, setupsession.Session{}); err != nil {
		return err
	}
	studio, _ := url.Parse(base)
	origin := studio.Scheme + "://" + studio.Host
	ui.Progress("Registering repository and checking the local Stackpanel agent…")
	mgr, err := userconfig.NewManager()
	if err != nil {
		return err
	}
	project, err := mgr.AddProject(root, filepath.Base(root))
	if err != nil {
		return err
	}
	port := opts.agentPort
	if port == 0 {
		port = config.DefaultConfig().Port
	}
	endpoint := "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	health, err := ensureSetupAgent(ctx, root, executable, endpoint, origin, port)
	if err != nil {
		return err
	}
	ui.Progress("Starting selected development services…")
	if err := startSetupServices(ctx, root, executable, selected, debug); err != nil {
		return err
	}
	session, err := setupsession.Create(setupsession.Session{Root: root, ProjectID: project.ID, AgentID: health.AgentID, Endpoint: endpoint, Origin: origin, RequireBrowser: !opts.noBrowser, Services: selected})
	if err != nil {
		return err
	}
	if !opts.noBrowser {
		link, err := setupsession.StudioURL(base, session)
		if err != nil {
			return err
		}
		ui.Progress("Open Studio and pair with your local agent:\n" + link)
		if err := openSetupStudio(ctx, link); err != nil {
			ui.Progress("Could not launch a browser. Open this link manually:\n" + link)
		}
		if err := waitForSetupStudio(ctx, session.ID); err != nil {
			return fmt.Errorf("%w; open Studio, pair, and retry setup (agent log: %s)", err, setupAgentLogPath())
		}
	}
	ui.Progress("Verifying runtime with stack doctor…")
	report, err := runFreshDoctorArgs(ctx, root, executable, debug,
		[]string{"--strict", "--scope", "runtime", "--setup-session", session.ID, "--json"},
		[]string{"checks", "runtime", "verification"})
	if err != nil {
		if report != nil {
			var rendered bytes.Buffer
			report.Render(&rendered, reconcile.RenderOptions{Title: "stack doctor · runtime verification", Verbose: true})
			return fmt.Errorf("%w\n%s", err, rendered.String())
		}
		return err
	}
	if opts.noBrowser {
		ui.ShowResult("Repository and runtime verified. Studio unverified (--no-browser).")
	} else {
		// Keep custom endpoints in the bookmark, without the expiring receipt.
		session.ID = ""
		link, err := setupsession.StudioURL(base, session)
		if err != nil {
			return err
		}
		ui.ShowResult("Repository, local agent, and Studio verified.\n" + link)
	}
	return nil
}

func setupAgentLogPath() string {
	return filepath.Join(filepath.Dir(userconfig.GetConfigPath()), "agent.log")
}

func ensureSetupAgent(ctx context.Context, root, executable, endpoint, origin string, port int) (setupsession.Health, error) {
	client := &http.Client{Timeout: time.Second}
	if health, err := setupsession.ReadHealth(client, endpoint); err == nil {
		if filepath.Clean(health.ProjectRoot) != filepath.Clean(root) {
			return health, fmt.Errorf("running agent serves %s; use --agent-port for a separate agent or restart it for %s", health.ProjectRoot, root)
		}
		if !health.DevshellReady {
			return health, fmt.Errorf("running agent has no devshell environment; restart it from this repository devshell")
		}
		if health.SetupVersion < 1 {
			return health, fmt.Errorf("running agent needs updating; restart it with %s agent --project-root %s", executable, root)
		}
		return health, nil
	}
	// Never start a second process over an occupied endpoint.
	u, _ := url.Parse(endpoint)
	if conn, err := net.DialTimeout("tcp", u.Host, time.Second); err == nil {
		conn.Close()
		return setupsession.Health{}, fmt.Errorf("%s is occupied but is not a healthy Stackpanel agent", endpoint)
	}
	path := setupAgentLogPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return setupsession.Health{}, err
	}
	log, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return setupsession.Health{}, err
	}
	defer log.Close()
	cmd := services.NewBackgroundProcess("nix", "develop", ".", "--no-update-lock-file", "--no-write-lock-file", "--command", executable, "agent", "--project-root", root, "--port", strconv.Itoa(port), "--host", origin)
	cmd.Dir = root
	cmd.Env = freshSetupEnvironment(os.Environ())
	cmd.Stdout, cmd.Stderr = log, log
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return setupsession.Health{}, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	ready := false
	defer func() {
		if !ready {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		}
	}()
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.NewTimer(2 * time.Minute)
	defer timeout.Stop()
	for {
		select {
		case <-ctx.Done():
			return setupsession.Health{}, ctx.Err()
		case err := <-done:
			return setupsession.Health{}, fmt.Errorf("local agent exited (%v); inspect %s", err, path)
		case <-timeout.C:
			return setupsession.Health{}, fmt.Errorf("local agent did not start; inspect %s", path)
		case <-ticker.C:
			if health, err := setupsession.ReadHealth(client, endpoint); err == nil && health.SetupVersion >= 1 && health.DevshellReady && filepath.Clean(health.ProjectRoot) == filepath.Clean(root) {
				ready = true
				return health, nil
			}
		}
	}
}

func startSetupServices(ctx context.Context, root, executable string, selected []string, out io.Writer) error {
	for _, name := range selected {
		if services.Get(name) == nil {
			return fmt.Errorf("unsupported local service %q", name)
		}
		if err := runSetupShell(ctx, root, out, executable, "services", "start", name, "--no-tui"); err != nil {
			return err
		}
	}
	return nil
}

func openSetupStudio(ctx context.Context, link string) error {
	launcher := "xdg-open"
	if runtime.GOOS == "darwin" {
		launcher = "open"
	}
	runCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return exec.CommandContext(runCtx, launcher, link).Run()
}
func waitForSetupStudio(ctx context.Context, id string) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		s, err := setupsession.Load(id)
		if err != nil {
			return err
		}
		if !s.ReadyAt.IsZero() && s.Connection != "" && time.Since(s.ConnectedAt) < 15*time.Second {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}
