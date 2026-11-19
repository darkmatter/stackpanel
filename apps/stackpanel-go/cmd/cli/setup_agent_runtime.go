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
	"slices"
	"strconv"
	"syscall"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func runSetupRuntime(
	ctx context.Context,
	root, executable string,
	selected []string,
	opts setupFlags,
	ui *tui.SetupUI,
	debug io.Writer,
	state *setupManifest,
) (string, error) {
	base := opts.studioURL
	if base == "" {
		base = setupsession.DefaultStudioURL
	}
	if _, err := setupsession.StudioURL(base, setupsession.Session{}); err != nil {
		return "", err
	}
	studio, _ := url.Parse(base)
	origin := studio.Scheme + "://" + studio.Host
	ui.Stage(tui.SetupConnect, "Starting your local agent and connecting Studio…")
	mgr, err := userconfig.NewManager()
	if err != nil {
		return "", err
	}
	project, err := mgr.AddProject(root, filepath.Base(root))
	if err != nil {
		return "", err
	}
	port := opts.agentPort
	if port == 0 {
		port = config.DefaultConfig().Port
	}
	endpoint := "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	// Setup intentionally leaves its agent running after the browser handoff.
	startCtx, cancelStart := context.WithTimeoutCause(
		ctx,
		2*time.Minute,
		fmt.Errorf("local agent did not start; inspect %s", setupAgentLogPath()),
	)
	health, _, err := ensureLocalAgent(startCtx, root, executable, endpoint, origin, port)
	cancelStart()
	if err != nil {
		return "", err
	}
	ui.Progress("Starting selected development services…")
	if err := startSetupServices(ctx, root, executable, selected, debug); err != nil {
		return "", err
	}
	session, err := resumeSetupStudioSession(
		state,
		setupsession.Session{
			Root:           root,
			ProjectID:      project.ID,
			AgentID:        health.AgentID,
			Endpoint:       endpoint,
			Origin:         origin,
			RequireBrowser: !opts.noBrowser,
			Services:       selected,
		},
	)
	if err != nil {
		return "", err
	}
	if !opts.noBrowser {
		link, err := setupsession.StudioURL(base, session)
		if err != nil {
			return "", err
		}
		ui.Progress("Open Studio and pair with your local agent:\n" + link)
		if err := openSetupStudio(ctx, link); err != nil {
			ui.Progress("Could not launch a browser. Open this link manually:\n" + link)
		}
		if err := waitForSetupStudio(ctx, session.ID); err != nil {
			return "", fmt.Errorf(
				"%w; open Studio, pair, and retry setup (agent log: %s)",
				err,
				setupAgentLogPath(),
			)
		}
	}
	ui.Progress("Verifying runtime with stack doctor…")
	report, err := runFreshDoctorArgs(ctx, root, executable, debug,
		[]string{"--strict", "--scope", "runtime", "--setup-session", session.ID, "--json"},
		[]string{"checks", "runtime", "verification"})
	if err != nil {
		if report != nil {
			var rendered bytes.Buffer
			report.Render(
				&rendered,
				reconcile.RenderOptions{
					Title:   "stack doctor · runtime verification",
					Verbose: true,
				},
			)
			return "", fmt.Errorf("%w\n%s", err, rendered.String())
		}
		return "", err
	}
	ui.Verified("Local agent and services · runtime doctor passed")
	if opts.noBrowser {
		return "Repository and runtime verified. Studio unverified (--no-browser).", nil
	} else {
		// Keep custom endpoints in the bookmark, without the expiring receipt.
		session.ID = ""
		link, err := setupsession.StudioURL(base, session)
		if err != nil {
			return "", err
		}
		ui.Verified("Studio · browser connection confirmed")
		return "Repository, local agent, and Studio verified.\n" + link, nil
	}
}

// Reuse a live browser handoff after interruption, but never stale readiness
// evidence or a receipt bound to a different agent, origin, or runtime scope.
func resumeSetupStudioSession(
	state *setupManifest,
	want setupsession.Session,
) (setupsession.Session, error) {
	if state.StudioSession != "" {
		if old, err := setupsession.Load(
			state.StudioSession,
		); err == nil && old.Root == want.Root &&
			old.ProjectID == want.ProjectID && old.AgentID == want.AgentID && old.Endpoint == want.Endpoint &&
			old.Origin == want.Origin && old.RequireBrowser == want.RequireBrowser &&
			slices.Equal(old.Services, want.Services) {
			return old, nil
		}
	}
	session, err := setupsession.Create(want)
	if err != nil {
		return session, err
	}
	state.StudioSession = session.ID
	return session, state.save()
}

func setupAgentLogPath() string {
	return filepath.Join(filepath.Dir(userconfig.GetConfigPath()), "agent.log")
}

// Only created after starting our own session leader; never derive a PID or
// process group from a reused agent's health endpoint or listening port.
type startedLocalAgent struct {
	pgid int
	done chan struct{}
	err  error // written by the sole waiter before closing done
}

func (p *startedLocalAgent) stop() {
	if err := syscall.Kill(-p.pgid, syscall.SIGTERM); err == nil {
		select {
		case <-p.done:
		case <-time.After(3 * time.Second):
		}
		// A wrapper can exit before its descendants, or ignore SIGTERM.
		_ = syscall.Kill(-p.pgid, syscall.SIGKILL)
	}
	<-p.done // reap nix develop before allowing the foreground CLI to exit
}

func ensureLocalAgent(
	ctx context.Context,
	root, executable, endpoint, origin string,
	port int,
) (setupsession.Health, *startedLocalAgent, error) {
	client := &http.Client{Timeout: time.Second}
	validate := func(health setupsession.Health) error {
		if filepath.Clean(health.ProjectRoot) != filepath.Clean(root) {
			return fmt.Errorf(
				"running agent serves %s; use --agent-port for a separate agent or restart it for %s",
				health.ProjectRoot,
				root,
			)
		}
		if !health.DevshellReady {
			return fmt.Errorf(
				"running agent has no devshell environment; restart it from this repository devshell",
			)
		}
		if health.SetupVersion < 1 {
			return fmt.Errorf(
				"running agent needs updating; restart it with %s agent --project-root %s",
				executable,
				root,
			)
		}
		return nil
	}
	if health, err := setupsession.ReadHealth(client, endpoint); err == nil {
		return health, nil, validate(health)
	}
	// Never start a second process over an occupied endpoint.
	u, _ := url.Parse(endpoint)
	if conn, err := net.DialTimeout("tcp", u.Host, time.Second); err == nil {
		conn.Close()
		return setupsession.Health{}, nil, fmt.Errorf(
			"%s is occupied but is not a healthy Stackpanel agent",
			endpoint,
		)
	}
	path := setupAgentLogPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return setupsession.Health{}, nil, err
	}
	log, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return setupsession.Health{}, nil, err
	}
	defer log.Close()
	flags, err := nixeval.SetupFlakeArgs(root)
	if err != nil {
		return setupsession.Health{}, nil, err
	}
	args := append([]string{"develop", "."}, flags...)
	args = append(
		args,
		"--command",
		executable,
		"agent",
		"--project-root",
		root,
		"--port",
		strconv.Itoa(port),
		"--host",
		origin,
	)
	cmd := services.NewBackgroundProcess("nix", args...)
	cmd.Dir = root
	cmd.Env = freshSetupEnvironment(os.Environ())
	cmd.Stdout, cmd.Stderr = log, log
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return setupsession.Health{}, nil, err
	}
	process := &startedLocalAgent{pgid: cmd.Process.Pid, done: make(chan struct{})}
	go func() {
		process.err = cmd.Wait()
		close(process.done)
	}()
	ready := false
	defer func() {
		if !ready {
			process.stop()
		}
	}()
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return setupsession.Health{}, nil, context.Cause(ctx)
		case <-process.done:
			return setupsession.Health{}, nil, fmt.Errorf(
				"local agent exited (%v); inspect %s",
				process.err,
				path,
			)
		case <-ticker.C:
			if health, err := setupsession.ReadHealth(client, endpoint); err == nil {
				if err := validate(health); err != nil {
					return health, nil, err
				}
				ready = true
				return health, process, nil
			}
		}
	}
}

func startSetupServices(
	ctx context.Context,
	root, executable string,
	selected []string,
	out io.Writer,
) error {
	for _, name := range selected {
		if services.Get(name) == nil {
			return fmt.Errorf("unsupported local service %q", name)
		}
		if err := runSetupShell(
			ctx,
			root,
			out,
			executable,
			"services",
			"start",
			name,
			"--no-tui",
		); err != nil {
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
		if !s.ReadyAt.IsZero() && s.Connection != "" &&
			time.Since(s.ConnectedAt) < 15*time.Second {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}
