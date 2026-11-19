package cmd

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func authorFile(t *testing.T, path, text string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

func authorRead(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func authorGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	b, err := setupGitCommand(t.Context(), dir, args...)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func authorCLI(t *testing.T, args ...string) (string, error) {
	t.Helper()
	cmd := newModuleCmd()
	var out, stderr bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&stderr)
	cmd.SetArgs(args)
	if err := cmd.ExecuteContext(t.Context()); err != nil {
		return out.String(), fmt.Errorf("%w\n%s", err, stderr.String())
	}
	return out.String(), nil
}

func TestModuleProjectRootUsesCanonicalDirectory(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	nested := filepath.Join(root, "nested")
	authorFile(t, filepath.Join(nested, ".stackpanel", "config.nix"), "{}", 0o644)
	t.Chdir(nested)
	if got, err := findProjectRoot(); err == nil {
		t.Fatalf("unsupported config directory selected a project: %s", got)
	}
	authorFile(t, filepath.Join(root, ".stack", "config.nix"), "{}", 0o644)
	got, err := findProjectRoot()
	if err != nil || got != root {
		t.Fatalf("findProjectRoot() = %q, %v; want %q", got, err, root)
	}
}

func TestModuleLinkKeepsOtherProjectOverrides(t *testing.T) {
	project, old, other, author := t.TempDir(), t.TempDir(), t.TempDir(), t.TempDir()
	for _, dir := range []string{project, old, other, author} {
		authorFile(t, filepath.Join(dir, "flake.nix"), `{ outputs = { self }: {}; }`, 0o644)
	}
	authorFile(
		t,
		filepath.Join(project, "flake.nix"),
		`{ inputs.demo.url = "path:/demo"; outputs = { self, stackpanel, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs self; }; }`,
		0o644,
	)
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	mgr, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	for id, path := range map[string]string{"demo": old, "other": other} {
		if err := mgr.SetLinkedModule(
			project,
			id,
			userconfig.LinkedModule{Path: path},
		); err != nil {
			t.Fatal(err)
		}
	}
	bin, argv := t.TempDir(), filepath.Join(t.TempDir(), "args")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("AUTHOR_TEST_ARGS", argv)
	authorFile(t, filepath.Join(bin, "nix"), `#!/bin/sh
if [ "$1" = eval ]; then
  case "$*" in
    *--apply*) echo true ;;
    *) echo '{"modulesListAll":[{"id":"demo"}]}' ;;
  esac
  exit 0
fi
printf '%s\n' "$@" >"$AUTHOR_TEST_ARGS"
echo '{"locks":{"root":"project","nodes":{"project":{"inputs":{"demo":"demo_2","other":"other"}}}}}'
`, 0o755)
	if _, err := authorCLI(
		t,
		"link",
		author,
		"--id",
		"demo",
		"--project-root",
		project,
	); err != nil {
		t.Fatal(err)
	}
	links, err := userconfig.LoadLinkedModules(project)
	if err != nil {
		t.Fatal(err)
	}
	for id, path := range map[string]string{"demo": author, "other": other} {
		path, err := filepath.EvalSymlinks(path)
		if err != nil || links[id].Path != path {
			t.Fatalf("unexpected link for %s: %+v (%v)", id, links[id], err)
		}
	}
	want := []string{
		"flake",
		"metadata",
		"--json",
		"--no-write-lock-file",
		"--override-input",
		"demo",
		modulePathRef(links["demo"].Path),
		"--override-input",
		"other",
		modulePathRef(links["other"].Path),
		".",
	}
	if got := authorRead(t, argv); got != strings.Join(want, "\n")+"\n" {
		t.Fatalf("validation didn't use the resulting input graph:\n%s", got)
	}
}

func TestModuleEjectPublishesIndependentWorkingCopy(t *testing.T) {
	for _, entry := range []string{"default.nix", "module.nix"} {
		t.Run(entry, func(t *testing.T) {
			root := t.TempDir()
			authorGit(t, root, "init", "--quiet")
			src := filepath.Join(root, ".stack", "modules", "sample")
			authorFile(
				t,
				filepath.Join(src, entry),
				`{ ... }: { text = builtins.readFile ./message; }`,
				0o644,
			)
			authorFile(t, filepath.Join(src, "message"), "staged version", 0o644)
			authorFile(t, filepath.Join(src, "bin", "report"), "#!/bin/sh\necho ok\n", 0o755)
			authorFile(t, filepath.Join(root, ".gitignore"), "private-token\n", 0o644)
			authorGit(t, root, "add", "-f", "--", ".stack/modules/sample/message")
			authorFile(t, filepath.Join(src, "message"), "working copy", 0o644)
			authorFile(t, filepath.Join(src, "private-token"), "must not be exported", 0o600)
			before := authorGit(t, root, "status", "--porcelain=v1", "--untracked-files=all")
			dest := filepath.Join(t.TempDir(), "standalone")
			t.Setenv("STACKPANEL_ROOT", t.TempDir())
			if _, err := authorCLI(
				t,
				"eject",
				"--project-root",
				root,
				"sample",
				dest,
			); err != nil {
				t.Fatal(err)
			}
			if got := authorGit(
				t,
				root,
				"status",
				"--porcelain=v1",
				"--untracked-files=all",
			); got != before {
				t.Fatalf("eject modified the source/index: %s -> %s", before, got)
			}
			if got := authorRead(t, filepath.Join(dest, "message")); got != "working copy" {
				t.Fatalf("ejected %q instead of working copy", got)
			}
			st, err := os.Stat(filepath.Join(dest, "bin", "report"))
			if err != nil || st.Mode()&0o111 == 0 {
				t.Fatalf("lost executable bit: %v %v", st, err)
			}
			if _, err := os.Lstat(
				filepath.Join(dest, "private-token"),
			); !errors.Is(
				err,
				os.ErrNotExist,
			) {
				t.Fatalf("copied ignored local data: %v", err)
			}
			if got := authorRead(
				t,
				filepath.Join(dest, "flake.nix"),
			); !strings.Contains(got, "stackpanelModules.default = import ./"+entry) ||
				strings.Contains(got, src) {
				t.Fatal(got)
			}
			authorGit(
				t,
				dest,
				"ls-files",
				"--error-unmatch",
				"--",
				"flake.nix",
				entry,
				"message",
				"bin/report",
			)
			authorFile(t, filepath.Join(src, "message"), "changed again", 0o644)
			if _, err := authorCLI(
				t,
				"eject",
				"--project-root",
				root,
				"sample",
				dest,
			); err == nil ||
				authorRead(t, filepath.Join(dest, "message")) != "working copy" {
				t.Fatal(
					"overwrote an existing destination or ejected a reference to the source",
				)
			}
		})
	}
}

func TestModuleEjectRejectsUnsafeCopies(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, ".stack", "modules", "demo")
	authorFile(t, filepath.Join(src, "module.nix"), `{ ... }: { }`, 0o644)
	outside := filepath.Join(t.TempDir(), "outside")
	authorFile(t, outside, "unchanged", 0o644)
	if err := os.Symlink(outside, filepath.Join(src, "token")); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(t.TempDir(), "alias")
	if err := os.Symlink(src, alias); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(
		filepath.Dir(outside),
		filepath.Join(root, ".stack", "modules", "linked"),
	); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ id, dest string }{
		{"demo", filepath.Join(t.TempDir(), "copy")}, // symlink among regular files
		{"demo", filepath.Join(src, "inside")},
		{"demo", filepath.Join(alias, "inside")},
		{"linked", filepath.Join(t.TempDir(), "copy")},
		{"../demo", filepath.Join(t.TempDir(), "copy")},
	} {
		if err := ejectLocalModule(t.Context(), root, tc.id, tc.dest); err == nil {
			t.Fatalf("allowed unsafe ejection %s -> %s", tc.id, tc.dest)
		}
		if _, err := os.Lstat(tc.dest); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("left a partial copy at %s", tc.dest)
		}
	}
	if got := authorRead(t, outside); got != "unchanged" {
		t.Fatal("modified symlink target")
	}
}

func TestModuleEjectRejectsRepoRelativeDependency(t *testing.T) {
	project := t.TempDir()
	dir := filepath.Join(project, ".stack", "modules", "sample")
	authorFile(
		t,
		filepath.Join(dir, "module.nix"),
		`{ imports = [ ./helpers/ui.nix ]; }`,
		0o644,
	)
	authorFile(
		t,
		filepath.Join(dir, "helpers", "ui.nix"),
		`import ../../repo-only.nix`,
		0o644,
	)
	dest := filepath.Join(t.TempDir(), "sample")
	if err := ejectLocalModule(
		t.Context(),
		project,
		"sample",
		dest,
	); err == nil ||
		!strings.Contains(err.Error(), "repo-only.nix") {
		t.Fatalf("expected an error identifying the non-portable dependency, got %v", err)
	}
	if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("failed ejection left a partial destination: %v", err)
	}
}

func TestModuleEjectRequiresCopiedSiblingDependencies(t *testing.T) {
	for _, state := range []string{"present", "ignored", "absent"} {
		t.Run(state, func(t *testing.T) {
			project := t.TempDir()
			authorGit(t, project, "init", "--quiet")
			src := filepath.Join(project, ".stack", "modules", "demo")
			authorFile(
				t,
				filepath.Join(src, "default.nix"),
				`import ./helpers/detail.nix`,
				0o644,
			)
			authorFile(
				t,
				filepath.Join(src, "helpers/detail.nix"),
				`{ text = builtins.readFile ../assets/message; }`,
				0o644,
			)
			if state != "absent" {
				authorFile(t, filepath.Join(src, "assets/message"), "hello", 0o644)
			}
			if state == "ignored" {
				// A slash-containing pattern is relative to the .gitignore that
				// declares it. Verify Git really excludes this dependency.
				authorFile(t, filepath.Join(src, ".gitignore"), "assets/message\n", 0o644)
				if got := authorGit(
					t,
					src,
					"ls-files",
					"--others",
					"--ignored",
					"--exclude-standard",
					"--",
					"assets/message",
				); strings.TrimSpace(
					got,
				) != "assets/message" {
					t.Fatalf("fixture must omit a real ignored dependency; git reported %q", got)
				}
			}
			dest := filepath.Join(t.TempDir(), "demo")
			err := ejectLocalModule(t.Context(), project, "demo", dest)
			if state != "present" {
				if err == nil || !strings.Contains(err.Error(), "assets/message") {
					t.Fatalf("expected missing module dependency error, got %v", err)
				}
				if _, err := os.Stat(dest); !errors.Is(err, os.ErrNotExist) {
					t.Fatalf("partial ejection left behind: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			authorGit(
				t,
				dest,
				"ls-files",
				"--error-unmatch",
				"--",
				"helpers/detail.nix",
				"assets/message",
			)
			if got := authorRead(
				t,
				filepath.Join(dest, "helpers/../assets/message"),
			); got != "hello" {
				t.Fatalf("wrong sibling content: %s", got)
			}
		})
	}
}

func TestModuleDevOpensSelectedScratchProject(t *testing.T) {
	cfg := filepath.Join(t.TempDir(), "user.yaml")
	cache, bin := t.TempDir(), t.TempDir()
	src := filepath.Join(t.TempDir(), "checkout")
	authorFile(
		t,
		filepath.Join(src, "flake.nix"),
		`{ outputs = { self }: { stackpanelModules.default = {}; }; }`,
		0o644,
	)
	t.Chdir(src)
	t.Setenv("STACKPANEL_USER_CONFIG", cfg)
	t.Setenv("STACKPANEL_ROOT", t.TempDir())
	t.Setenv("XDG_CACHE_HOME", cache)
	t.Setenv("STACKPANEL_FLAKE", "github:fixture/framework")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	authorFile(t, filepath.Join(bin, "nix"), `#!/bin/sh
set -eu
test "$*" = 'flake lock'
test ! -e flake.lock
git ls-files --error-unmatch -- flake.nix .stack/config.nix >/dev/null
printf '{}\n' >flake.lock
`, 0o755)
	opened := filepath.Join(t.TempDir(), "url")
	t.Setenv("AUTHOR_TEST_URL", opened)
	for _, launcher := range []string{"open", "xdg-open"} {
		authorFile(
			t,
			filepath.Join(bin, launcher),
			"#!/bin/sh\nprintf '%s' \"$1\" >\"$AUTHOR_TEST_URL\"\n",
			0o755,
		)
	}
	mgr, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	other := t.TempDir()
	if _, err := mgr.SetCurrentProject(other); err != nil {
		t.Fatal(err)
	}
	// A live agent can be reused only after it reports the expected root and
	// a ready devshell. Discover that root as an independent Studio client would.
	agent := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != "/health" {
				http.NotFound(w, r)
				return
			}
			current, err := userconfig.NewManager()
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			for _, p := range current.ListProjects() {
				if _, ok := p.LinkedModules["demo"]; ok {
					_ = json.NewEncoder(w).
						Encode(map[string]any{"project_root": p.Path, "status": "ok", "agent_id": "test-agent", "devshell_ready": true, "setup_version": 1})
					return
				}
			}
			http.NotFound(w, r)
		}),
	)
	defer agent.Close()
	agentURL, _ := url.Parse(agent.URL)
	if _, err := authorCLI(
		t,
		"dev",
		"--id",
		"demo",
		"--studio-url",
		"https://studio.example",
	); err == nil {
		t.Fatal("accepted an arbitrary remote Studio origin")
	}
	args := []string{
		"dev",
		"--id",
		"demo",
		"--ui-url",
		"http://localhost:5174",
		"--studio-url",
		"http://localhost:3000",
		"--agent-port",
		agentURL.Port(),
	}
	out, err := authorCLI(t, args...)
	if err != nil {
		t.Fatal(err)
	}
	link, err := url.Parse(strings.TrimSpace(out))
	if err != nil {
		t.Fatal(err)
	}
	if link.Path != "/studio/m/demo" || link.Host != "localhost:3000" ||
		link.Query().Get("agent") != agent.URL ||
		authorRead(t, opened) != link.String() {
		t.Fatalf("bad browser handoff: %s", link)
	}
	mgr, err = userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	p := mgr.ResolveProject(link.Query().Get("project"))
	if p == nil || p.Path == other || p.Path == src || mgr.CurrentProjectPath() != other {
		t.Fatalf("preview was not scoped to the scratch consumer: %+v", p)
	}
	realSource, err := filepath.EvalSymlinks(src)
	if err != nil {
		t.Fatal(err)
	}
	if got := p.LinkedModules["demo"]; got.Path != realSource ||
		got.UIDevURL != "http://localhost:5174" {
		t.Fatalf("incorrect module link: %+v", got)
	}
	authorGit(
		t,
		p.Path,
		"ls-files",
		"--error-unmatch",
		"--",
		"flake.lock",
		"flake.nix",
		".stack/config.nix",
	)
	if _, err := os.Stat(
		filepath.Join(src, "flake.lock"),
	); !errors.Is(
		err,
		os.ErrNotExist,
	) {
		t.Fatal("preview locked the author project")
	}
	if again, err := authorCLI(
		t,
		args...); err != nil ||
		strings.TrimSpace(again) != link.String() {
		t.Fatalf(
			"unable to reuse the same consumer without rewriting its lock: %s %v",
			again,
			err,
		)
	}
}

// Stand-in for the agent below nix develop. This subprocess must also die
// when the preview closes, not just the Nix wrapper that launched it.
func TestModuleDevHealthFixture(t *testing.T) {
	addr := os.Getenv("AUTHOR_TEST_SERVE_HEALTH")
	if addr == "" {
		return
	}
	root, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	s := &http.Server{
		Addr: addr,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_ = json.NewEncoder(w).
				Encode(map[string]any{"project_root": root, "status": "ok", "agent_id": "preview", "devshell_ready": true, "setup_version": 1})
		}),
	}
	time.AfterFunc(20*time.Second, func() { _ = s.Close() })
	if err := s.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		t.Fatal(err)
	}
}

func TestModuleDevCancellationStopsOwnedProcessGroup(t *testing.T) {
	bin, src := t.TempDir(), filepath.Join(t.TempDir(), "demo")
	authorFile(
		t,
		filepath.Join(src, "flake.nix"),
		`{ outputs = { self }: { stackpanelModules.default = {}; }; }`,
		0o644,
	)
	t.Chdir(src)
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := l.Addr().(*net.TCPAddr)
	l.Close()
	pids := filepath.Join(t.TempDir(), "pids")
	t.Setenv("AUTHOR_TEST_ADDR", addr.String())
	t.Setenv("AUTHOR_TEST_BIN", exe)
	t.Setenv("AUTHOR_TEST_PIDS", pids)
	authorFile(t, filepath.Join(bin, "nix"), `#!/bin/sh
set -eu
if [ "$1" = flake ]; then echo '{}' >flake.lock; exit; fi
test "$1" = develop
AUTHOR_TEST_SERVE_HEALTH="$AUTHOR_TEST_ADDR" "$AUTHOR_TEST_BIN" -test.run='^TestModuleDevHealthFixture$' &
agent=$!
trap 'wait "$agent" || :; exit 0' TERM
printf '%d %d\n' "$$" "$agent" >"$AUTHOR_TEST_PIDS"
wait "$agent"
`, 0o755)
	cmd := newModuleCmd()
	cmd.SilenceUsage, cmd.SilenceErrors = true, true
	r, w := io.Pipe()
	defer r.Close()
	cmd.SetOut(w)
	var stderr bytes.Buffer
	cmd.SetErr(&stderr)
	cmd.SetArgs([]string{"dev", "--no-browser", "--agent-port", strconv.Itoa(addr.Port)})
	ctx, cancel := context.WithTimeout(t.Context(), 12*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() {
		err := cmd.ExecuteContext(ctx)
		_ = w.CloseWithError(err)
		done <- err
	}()
	link, readErr := bufio.NewReader(r).ReadString('\n')
	cancel()
	err = <-done
	if readErr != nil || !strings.Contains(link, "/studio/m/demo?") ||
		!errors.Is(err, context.Canceled) {
		t.Fatalf(
			"preview handoff / cancellation: %q %v %v\n%s",
			link,
			readErr,
			err,
			stderr.String(),
		)
	}
	var wrapper, child int
	if _, err := fmt.Sscan(
		authorRead(t, pids),
		&wrapper,
		&child,
	); err != nil || wrapper <= 0 ||
		child <= 0 {
		t.Fatalf("bad fixture PIDs: %v", err)
	}
	for _, pid := range []int{wrapper, child} {
		if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
			t.Fatalf("preview process %d still exists after cancellation: %v", pid, err)
		}
	}
}

func TestModuleDevWaitsForStartupOutcome(t *testing.T) {
	for _, tc := range []struct{ name, command string }{
		{"child failure", "exit 37"},
		{"cancel while preparing", "exec sleep 30"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, bin := t.TempDir(), t.TempDir()
			t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
			t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
			authorFile(
				t,
				filepath.Join(bin, "nix"),
				"#!/bin/sh\necho $$ > launcher.pid\n"+tc.command+"\n",
				0o755,
			)
			l, err := net.Listen("tcp4", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			addr := l.Addr().(*net.TCPAddr)
			l.Close()
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			_, started, err := ensureLocalAgent(
				ctx,
				root,
				"stack",
				"http://"+addr.String(),
				"https://stackpanel.dev",
				addr.Port,
			)
			if started != nil || err == nil {
				t.Fatalf("claimed readiness before any health response: %v, %v", started, err)
			}
			if tc.command == "exit 37" {
				if !strings.Contains(err.Error(), "exit status 37") {
					t.Fatalf("lost child failure: %v", err)
				}
			} else if !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("did not honor caller context before readiness: %v", err)
			}
			pid, err := strconv.Atoi(
				strings.TrimSpace(authorRead(t, filepath.Join(root, "launcher.pid"))),
			)
			if err != nil || pid <= 0 {
				t.Fatalf("invalid launcher pid: %d %v", pid, err)
			}
			if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
				t.Fatalf("startup did not reap launcher %d: %v", pid, err)
			}
		})
	}
}

// Exercise Git filtering, pure evaluation of the ejected module, a live edit
// via the same evaluator flags used by the agent, and returning to the pin.
// No network inputs, external catalog, or pre-existing user config are needed.
func TestModuleEjectLinkUnlinkPureNix(t *testing.T) {
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("requires Nix")
	}
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "config.yaml"))
	t.Setenv("NIX_CONFIG", "experimental-features = nix-command flakes")
	t.Setenv("STACKPANEL_ROOT", t.TempDir())
	project := t.TempDir()
	src := filepath.Join(project, ".stack", "modules", "sample")
	authorFile(
		t,
		filepath.Join(src, "default.nix"),
		`{ ... }: { text = builtins.readFile ./message; }`,
		0o644,
	)
	authorFile(t, filepath.Join(src, "message"), "first", 0o644)
	dest := filepath.Join(t.TempDir(), "sample")
	if _, err := authorCLI(
		t,
		"eject",
		"sample",
		dest,
		"--project-root",
		project,
	); err != nil {
		t.Fatal(err)
	}
	// Deliberately tiny local framework: consumes exactly the public mkFlake
	// argument shape, the module flake output and the consumer config file.
	dep, framework := t.TempDir(), t.TempDir()
	authorFile(t, filepath.Join(dep, "flake.nix"), `{ outputs = { self }: {}; }`, 0o644)
	authorFile(t, filepath.Join(framework, "flake.nix"), fmt.Sprintf(`{
  inputs.nixpkgs.url = %q;
  inputs.flake-parts.follows = "nixpkgs";
  outputs = { self, ... }: {
    lib.mkFlake = { self, inputs }: {
      # self includes these outputs; force the consumer config only once its
      # message is requested, not while constructing the output set itself.
      message = assert (import (self + "/.stack/config.nix")).modules.sample.enable;
        (inputs.sample.stackpanelModules.default {}).text;
      legacyPackages.%q.stackpanelSerializable.modulesListAll = [ {
        id = (inputs.sample.stackpanelModules.default {}).id or "sample";
        readme = (inputs.sample.stackpanelModules.default {}).text;
      } ];
    };
  };
}`, modulePathRef(dep), nixeval.CurrentSystem()), 0o644)
	cmd := newModuleCmd()
	cmd.SetContext(t.Context())
	consumer, err := prepareModuleConsumer(
		cmd,
		filepath.Join(t.TempDir(), "consumer"),
		"sample",
		dest,
		modulePathRef(framework),
	)
	if err != nil {
		t.Fatal(err)
	}
	lock := authorRead(t, filepath.Join(consumer, "flake.lock"))
	eval := func() string {
		t.Helper()
		args, err := nixeval.ProjectFlakeArgs(consumer)
		if err != nil {
			t.Fatal(err)
		}
		args = append([]string{"eval", "--raw", ".#message"}, args...)
		c := exec.CommandContext(t.Context(), "nix", args...)
		c.Dir = consumer
		var stderr bytes.Buffer
		c.Stderr = &stderr
		out, err := c.Output()
		if err != nil {
			t.Fatalf("pure Nix evaluation failed: %v\n%s", err, stderr.String())
		}
		return string(out)
	}
	if got := eval(); got != "first" {
		t.Fatalf("scratch consumer evaluated %q", got)
	}
	// Override with a different checkout; leave the original pinned input
	// alone. Relative path and HMR state must stay scoped to this project.
	author := filepath.Join(t.TempDir(), "sample")
	if _, err := authorCLI(
		t,
		"eject",
		"sample",
		author,
		"--project-root",
		project,
	); err != nil {
		t.Fatal(err)
	}
	t.Chdir(filepath.Dir(author))
	if _, err := authorCLI(
		t,
		"link",
		"sample",
		"--project-root",
		consumer,
		"--ui-url",
		"https://not-local.example/ui",
	); err == nil {
		t.Fatal("accepted a non-local UI dev server")
	}
	if _, err := authorCLI(
		t,
		"link",
		"sample",
		"--id",
		"undeclared",
		"--project-root",
		consumer,
	); err == nil {
		t.Fatal("linked an input absent from the consumer")
	}
	if _, err := authorCLI(
		t,
		"link",
		"sample",
		"--project-root",
		consumer,
		"--ui-url",
		"http://localhost:5174",
	); err != nil {
		t.Fatal(err)
	}
	authorFile(t, filepath.Join(author, "message"), "edited", 0o644)
	if got := eval(); got != "edited" {
		t.Fatalf("live override evaluated %q", got)
	}
	// An input and even a placeholder module ID in consumer settings are
	// insufficient: the author checkout must supply the expected module.
	bogus := t.TempDir()
	authorFile(
		t,
		filepath.Join(bogus, "flake.nix"),
		`{ outputs = _: { unrelated = true; }; }`,
		0o644,
	)
	configBefore := authorRead(t, userconfig.GetConfigPath())
	if _, err := authorCLI(
		t,
		"link",
		bogus,
		"--id",
		"sample",
		"--project-root",
		consumer,
	); err == nil {
		t.Fatal("linked a non-module over the working input")
	}
	if got := authorRead(t, userconfig.GetConfigPath()); got != configBefore {
		t.Fatal("invalid candidate changed the active link")
	}
	if got := authorRead(t, filepath.Join(consumer, "flake.lock")); got != lock {
		t.Fatal("prospective validation wrote the lockfile")
	}
	authorFile(
		t,
		filepath.Join(bogus, "flake.nix"),
		`{ outputs = _: { stackpanelModules.default = _: { text = "ok"; id = "other"; }; }; }`,
		0o644,
	)
	if _, err := authorCLI(
		t,
		"link",
		bogus,
		"--id",
		"sample",
		"--project-root",
		consumer,
	); err == nil {
		t.Fatal("linked an export that does not register the requested module")
	}
	if got := authorRead(t, userconfig.GetConfigPath()); got != configBefore {
		t.Fatal("wrong module ID changed the active link")
	}
	if _, err := authorCLI(t, "unlink", "sample", "--project-root", project); err == nil {
		t.Fatal("unlinked from another project")
	}
	if _, err := authorCLI(
		t,
		"unlink",
		"sample",
		"--project-root",
		consumer,
	); err != nil {
		t.Fatal(err)
	}
	if got := eval(); got != "first" {
		t.Fatalf("unlink failed to restore locked input: %q", got)
	}
	if got := authorRead(t, filepath.Join(consumer, "flake.lock")); got != lock {
		t.Fatal("link, evaluation or unlink modified the consumer lockfile")
	}
}
