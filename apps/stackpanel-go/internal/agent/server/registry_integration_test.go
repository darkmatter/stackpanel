package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/cgi"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/project"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/registry"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

const registryFixtureID = "local.probe" // deliberately distinct from the input and Nix ID

func TestProjectRegistryLifecycle(t *testing.T) {
	f := newRegistryIntegration(t)

	t.Run(
		"install, preview, adopt, update and uninstall in one project",
		func(t *testing.T) {
			userDep := fmt.Sprintf("userTool.url = %q;", f.gitURL+"?dir=foreign&ref=one")
			p := f.project(t, "primary.json", userDep)
			other := f.project(t, "other.json", "")
			otherFiles := other.files(t)
			f.assertCatalog(t, p, "Primary catalog", false, "")
			f.assertCatalog(t, other, "Other catalog", false, "")

			ctx := t.Context()
			installed, err := f.client.InstallModule(
				ctx,
				registryRequest(
					p,
					&agentv1.InstallModuleRequest{ModuleId: registryFixtureID, Version: "1.0"},
				),
			)
			require.NoError(t, err)
			require.Equal(t, "probe", installed.Msg.GetModuleId())
			revs := p.lockedRevs(t)
			require.Equal(t, f.v1, revs["probe"])
			require.Equal(t, f.v1, revs["support"])
			f.assertCatalog(t, p, "Primary catalog", true, "1.0") // not enabled, not latest
			f.assertCatalog(t, other, "Other catalog", false, "")
			_, err = f.client.GetModule(
				ctx,
				registryRequest(other, &agentv1.GetModuleRequest{ModuleId: "probe"}),
			)
			require.Equal(t, connect.CodeNotFound, connect.CodeOf(err), "%v", err)

			m := f.module(t, p)
			require.False(t, m.GetEnabled())
			require.Equal(t, "1.0", m.GetMeta().GetVersion())
			beforePreview := p.files(t)
			preview, err := f.client.PreviewModuleEnable(
				ctx,
				registryRequest(p, &agentv1.PreviewModuleEnableRequest{ModuleId: "probe"}),
			)
			require.NoError(t, err)
			require.Equal(
				t,
				[]string{"probe.conf"},
				preview.Msg.GetPreview().GetFiles().GetAdded(),
			)
			require.Equal(
				t,
				[]string{"probe-tool"},
				preview.Msg.GetPreview().GetPackages().GetAdded(),
			)
			require.Equal(
				t,
				[]string{"probe-worker"},
				preview.Msg.GetPreview().GetServices().GetAdded(),
			)
			require.Equal(
				t,
				beforePreview,
				p.files(t),
				"preview must not adopt or relock the module",
			)

			_, err = f.client.EnableModule(
				ctx,
				registryRequest(p, &agentv1.EnableModuleRequest{ModuleId: "probe"}),
			)
			require.NoError(t, err)
			settings, err := structpb.NewStruct(map[string]any{"color": "blue"})
			require.NoError(t, err)
			_, err = f.client.UpdateModuleConfig(
				ctx,
				registryRequest(
					p,
					&agentv1.UpdateModuleConfigRequest{ModuleId: "probe", Settings: settings},
				),
			)
			require.NoError(t, err)
			m = f.module(t, p)
			require.True(t, m.GetEnabled())
			require.Equal(t, "blue", m.GetSettings().GetFields()["color"].GetStringValue())

			// This release exists in the catalog, but not in Git. A real failed
			// lock must leave the installed release (and its config) intact.
			beforeUpdate := p.files(t)
			_, err = f.client.UpdateModule(
				ctx,
				registryRequest(
					p,
					&agentv1.UpdateModuleRequest{ModuleId: "probe", Version: "broken"},
				),
			)
			require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
			require.Equal(t, beforeUpdate, p.files(t))
			f.assertCatalog(t, p, "Primary catalog", true, "1.0")

			_, err = f.client.UpdateModule(
				ctx,
				registryRequest(
					p,
					&agentv1.UpdateModuleRequest{ModuleId: "probe", Version: "2.0"},
				),
			)
			require.NoError(t, err)
			revs = p.lockedRevs(t)
			require.Equal(t, f.v2, revs["probe"])
			require.Equal(t, f.v2, revs["support"])
			require.Equal(t, f.v1, revs["userTool"])
			require.Contains(t, p.files(t)["flake.nix"], userDep)
			f.assertCatalog(t, p, "Primary catalog", true, "2.0")
			m = f.module(t, p)
			require.Equal(t, "2.0", m.GetMeta().GetVersion())
			require.True(t, m.GetEnabled())
			require.Equal(t, "blue", m.GetSettings().GetFields()["color"].GetStringValue())

			links := f.manager.UserConfigManager()
			require.NoError(
				t,
				links.SetLinkedModule(
					p.root,
					"probe",
					userconfig.LinkedModule{Path: f.localProbe},
				),
			)
			beforeUninstall := p.files(t)
			_, err = f.client.UninstallModule(
				ctx,
				registryRequest(
					p,
					&agentv1.UninstallModuleRequest{ModuleId: registryFixtureID},
				),
			)
			require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
			require.ErrorContains(t, err, "stack module unlink probe")
			require.Equal(t, beforeUninstall, p.files(t))
			require.NoError(t, links.UnlinkModule(p.root, "probe"))

			_, err = f.client.UninstallModule(
				ctx,
				registryRequest(
					p,
					&agentv1.UninstallModuleRequest{ModuleId: registryFixtureID},
				),
			)
			require.NoError(t, err)
			require.NotContains(t, p.lockedRevs(t), "probe")
			// mkFlake rejects dangling enable *or* options after the input is
			// removed. This read also forces the unrelated sibling config value.
			f.assertCatalog(t, p, "Primary catalog", false, "")
			_, err = f.client.GetModule(
				ctx,
				registryRequest(p, &agentv1.GetModuleRequest{ModuleId: "probe"}),
			)
			require.Equal(t, connect.CodeNotFound, connect.CodeOf(err), "%v", err)
			require.Equal(t, otherFiles, other.files(t))
		},
	)

	t.Run(
		"catalog omitting a required input cannot report a successful install",
		func(t *testing.T) {
			p := f.project(t, "primary.json", "")
			cfg := p.files(t)[".stack/config.nix"]
			registryWrite(
				t,
				p.root,
				".stack/config.nix",
				strings.Replace(cfg, "{", "{ requireHelper = true;", 1),
			)
			before := p.files(t)
			_, err := f.client.InstallModule(
				t.Context(),
				registryRequest(p, &agentv1.InstallModuleRequest{ModuleId: "probe"}),
			)
			require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
			require.Equal(t, before, p.files(t))
		},
	)

	t.Run("matching user dependency cannot be migrated", func(t *testing.T) {
		p := f.project(
			t,
			"primary.json",
			fmt.Sprintf("support.url = %q;", f.gitURL+"?dir=support&ref=one"),
		)
		_, err := f.client.InstallModule(
			t.Context(),
			registryRequest(
				p,
				&agentv1.InstallModuleRequest{ModuleId: "probe", Version: "1.0"},
			),
		)
		require.NoError(t, err)
		before := p.files(t)
		_, err = f.client.UpdateModule(
			t.Context(),
			registryRequest(
				p,
				&agentv1.UpdateModuleRequest{ModuleId: "probe", Version: "2.0"},
			),
		)
		require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
		require.Equal(t, before, p.files(t))
	})

	t.Run(
		"same source at an unpublished commit has no installed version",
		func(t *testing.T) {
			p := f.project(t, "primary.json", "")
			_, err := f.client.InstallModule(
				t.Context(),
				registryRequest(
					p,
					&agentv1.InstallModuleRequest{ModuleId: "probe", Ref: "main"},
				),
			)
			require.NoError(t, err)
			require.Equal(t, f.dev, p.lockedRevs(t)["probe"])
			f.assertCatalog(t, p, "Primary catalog", true, "")
		},
	)

	t.Run(
		"concurrent installs and a failed removal preserve project config",
		func(t *testing.T) {
			p := f.project(t, "primary.json", "")
			start, results := make(chan struct{}), make(chan error, 2)
			for range 2 {
				go func() {
					<-start
					_, err := f.client.InstallModule(
						t.Context(),
						registryRequest(p, &agentv1.InstallModuleRequest{ModuleId: "probe"}),
					)
					results <- err
				}()
			}
			close(start)
			a, b := <-results, <-results
			if a != nil {
				a, b = b, a
			}
			require.NoError(t, a)
			require.Equal(t, connect.CodeAlreadyExists, connect.CodeOf(b), "%v", b)
			_, err := f.client.EnableModule(
				t.Context(),
				registryRequest(p, &agentv1.EnableModuleRequest{ModuleId: "probe"}),
			)
			require.NoError(t, err)
			// This independently declared project option also needs probe. It
			// isn't owned by the module and the agent must not silently delete it.
			config := p.files(t)[".stack/config.nix"]
			registryWrite(
				t,
				p.root,
				".stack/config.nix",
				strings.Replace(config, "{", "{\n  requireProbe = true;", 1),
			)
			before := p.files(t)
			_, err = f.client.UninstallModule(
				t.Context(),
				registryRequest(p, &agentv1.UninstallModuleRequest{ModuleId: "probe"}),
			)
			require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
			require.Equal(
				t,
				before,
				p.files(t),
				"failed validation must restore both config and flake files",
			)
			require.True(t, f.module(t, p).GetEnabled())
		},
	)

	for _, name := range []string{"probe", "support"} {
		t.Run("unrelated input named "+name, func(t *testing.T) {
			// Same repository as the catalog; only ?dir differs. A name or
			// repository-only match would steal this user-owned input.
			p := f.project(
				t,
				"primary.json",
				fmt.Sprintf("%s.url = %q;", name, f.gitURL+"?dir=foreign&ref=one"),
			)
			f.assertCatalog(t, p, "Primary catalog", false, "")
			before := p.files(t)
			_, err := f.client.InstallModule(
				t.Context(),
				registryRequest(p, &agentv1.InstallModuleRequest{ModuleId: registryFixtureID}),
			)
			want := connect.CodeFailedPrecondition
			if name == "probe" {
				want = connect.CodeAlreadyExists
			}
			require.Equal(t, want, connect.CodeOf(err), "%v", err)
			require.Equal(t, before, p.files(t))
			if name == "probe" {
				_, err = f.client.UpdateModule(
					t.Context(),
					registryRequest(p, &agentv1.UpdateModuleRequest{ModuleId: registryFixtureID}),
				)
				require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
				require.Equal(t, before, p.files(t))
				_, err = f.client.UninstallModule(
					t.Context(),
					registryRequest(
						p,
						&agentv1.UninstallModuleRequest{ModuleId: registryFixtureID},
					),
				)
				require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
				require.Equal(t, before, p.files(t))
			}
		})
	}

	t.Run("unresolvable version, lock and catalog", func(t *testing.T) {
		p := f.project(t, "primary.json", "")
		before := p.files(t)
		_, err := f.client.InstallModule(
			t.Context(),
			registryRequest(
				p,
				&agentv1.InstallModuleRequest{ModuleId: "probe", Version: "does-not-exist"},
			),
		)
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err), "%v", err)
		require.Equal(t, before, p.files(t))

		// A valid flake that locks successfully but doesn't export the catalog
		// module is not a successful install. Roll back both input additions.
		_, err = f.client.InstallModule(
			t.Context(),
			registryRequest(
				p,
				&agentv1.InstallModuleRequest{ModuleId: "probe", Version: "no-export"},
			),
		)
		require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
		require.Equal(t, before, p.files(t))

		// This release exports probe but remains enabled even after the agent
		// writes false to its declared enable path.
		_, err = f.client.InstallModule(
			t.Context(),
			registryRequest(
				p,
				&agentv1.InstallModuleRequest{ModuleId: "probe", Version: "always-on"},
			),
		)
		require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err), "%v", err)
		require.Equal(t, before, p.files(t))

		registryWrite(t, p.root, "flake.lock", `{"invalid":`)
		brokenLock := p.files(t)
		_, err = f.client.GetRegistryModule(
			t.Context(),
			registryRequest(p, &agentv1.GetRegistryModuleRequest{ModuleId: "probe"}),
		)
		require.Equal(
			t,
			connect.CodeFailedPrecondition,
			connect.CodeOf(err),
			"invalid lock is not an empty project: %v",
			err,
		)
		require.Equal(t, brokenLock, p.files(t))

		bad := f.project(t, "unavailable.json", "") // never cached; HTTP 404
		before = bad.files(t)
		_, err = f.client.ListRegistryModules(
			t.Context(),
			registryRequest(bad, &agentv1.ListRegistryModulesRequest{}),
		)
		require.Equal(t, connect.CodeUnavailable, connect.CodeOf(err), "%v", err)
		_, err = f.client.InstallModule(
			t.Context(),
			registryRequest(bad, &agentv1.InstallModuleRequest{ModuleId: "probe"}),
		)
		require.Equal(t, connect.CodeUnavailable, connect.CodeOf(err), "%v", err)
		require.Equal(t, before, bad.files(t))
	})
}

type registryIntegration struct {
	client                       agentv1connect.ModuleServiceClient
	manager                      *project.Manager
	projects, framework, catalog string
	gitURL, v1, v2, dev          string
	localProbe                   string
}

type registryProject struct{ root, id string }

func registryRequest[T any](p registryProject, msg *T) *connect.Request[T] {
	r := connect.NewRequest(msg)
	r.Header().Set(projectHeader, p.id)
	return r
}

func (f *registryIntegration) assertCatalog(
	t *testing.T,
	p registryProject,
	name string,
	installed bool,
	version string,
) {
	t.Helper()
	list, err := f.client.ListRegistryModules(
		t.Context(),
		registryRequest(
			p,
			&agentv1.ListRegistryModulesRequest{
				Query:    "probe",
				Category: "tools",
				Tag:      "offline",
			},
		),
	)
	require.NoError(t, err)
	require.Len(t, list.Msg.GetModules(), 1)
	get, err := f.client.GetRegistryModule(
		t.Context(),
		registryRequest(p, &agentv1.GetRegistryModuleRequest{ModuleId: registryFixtureID}),
	)
	require.NoError(t, err)
	m := get.Msg.GetModule()
	require.True(
		t,
		proto.Equal(list.Msg.GetModules()[0], m),
		"list and detail disagree: %v vs %v",
		list.Msg.GetModules()[0],
		m,
	)
	require.Equal(t, registryFixtureID, m.GetId())
	require.Equal(t, "probe", m.GetSlug())
	require.Equal(t, name, m.GetName())
	require.Equal(t, "2.0", m.GetLatestVersion())
	require.Equal(t, installed, m.GetInstalled())
	if version == "" {
		require.Nil(t, m.InstalledVersion, "unknown version must be absent")
	} else {
		require.Equal(t, version, m.GetInstalledVersion())
	}
	require.Equal(t, "# Local probe\n", get.Msg.GetReadme())
}

func (f *registryIntegration) module(t *testing.T, p registryProject) *agentv1.Module {
	t.Helper()
	r, err := f.client.GetModule(
		t.Context(),
		registryRequest(p, &agentv1.GetModuleRequest{ModuleId: "probe"}),
	)
	require.NoError(t, err)
	require.Equal(t, "probe", r.Msg.GetModule().GetId())
	return r.Msg.GetModule()
}

func (p registryProject) files(t *testing.T) map[string]string {
	t.Helper()
	files := map[string]string{}
	for _, name := range []string{"flake.nix", "flake.lock", ".stack/config.nix"} {
		data, err := os.ReadFile(filepath.Join(p.root, name))
		require.NoError(t, err)
		files[name] = string(data)
	}
	return files
}

// Follow the root edges rather than assuming node keys are input names.
func (p registryProject) lockedRevs(t *testing.T) map[string]string {
	t.Helper()
	var lock struct {
		Root  string
		Nodes map[string]struct {
			Inputs map[string]string
			Locked struct{ Rev, NarHash string }
		}
	}
	data, err := os.ReadFile(filepath.Join(p.root, "flake.lock"))
	require.NoError(t, err)
	require.NoError(t, json.Unmarshal(data, &lock))
	revs := map[string]string{}
	for input, node := range lock.Nodes[lock.Root].Inputs {
		locked := lock.Nodes[node].Locked
		require.NotEmpty(t, locked.NarHash, "unlocked input %s", input)
		revs[input] = locked.Rev
	}
	return revs
}

func (f *registryIntegration) project(
	t *testing.T,
	catalog, extraInputs string,
) registryProject {
	t.Helper()
	root, err := os.MkdirTemp(f.projects, "consumer-")
	require.NoError(t, err)
	registryWrite(t, root, "flake.nix", fmt.Sprintf(`{
  inputs = {
    stackpanel.url = %q;
    %s
  };
  outputs = { self, stackpanel, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs self; };
}
`, f.framework, extraInputs))
	registryWrite(t, root, ".stack/config.nix", fmt.Sprintf(`{
  registries = [ %q ];
  tooling.keep = "user value";
}
`, f.catalog+"/"+catalog))
	registryCommand(t, root, "git", "init", "-q", "-b", "main")
	registryCommand(t, root, "git", "add", "-f", "flake.nix", ".stack/config.nix")
	registryGitCommit(t, root, "consumer")
	registryCommand(t, root, "nix", "flake", "lock")
	registryCommand(t, root, "git", "add", "-f", "flake.lock")
	registryGitCommit(t, root, "lock local framework and initial inputs")
	registered, err := f.manager.UserConfigManager().AddProject(root, "")
	require.NoError(t, err)
	return registryProject{root: root, id: registered.ID}
}

func newRegistryIntegration(t *testing.T) *registryIntegration {
	t.Helper()
	if _, err := exec.LookPath("nix"); err != nil {
		t.Skip("registry lifecycle integration requires Nix with flakes")
	}
	f := &registryIntegration{projects: t.TempDir()}
	// Production project resolution deliberately rejects projects under /tmp
	// and /var (including macOS TMPDIR). Use disposable Git worktrees in a
	// valid location, not a stubbed project resolver or a real saved project.
	if errors.Is(project.QuickValidate(f.projects), project.ErrSuspiciousPath) {
		home, err := os.UserHomeDir()
		require.NoError(t, err)
		f.projects, err = os.MkdirTemp(home, ".stackpanel-test-projects-")
		require.NoError(t, err)
		t.Cleanup(func() { require.NoError(t, os.RemoveAll(f.projects)) })
	}
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv(
		"IN_NIX_SHELL",
		"1",
	) // the tiny framework doesn't provide a devshell to hydrate
	t.Setenv(
		"NIX_CONFIG",
		os.Getenv(
			"NIX_CONFIG",
		)+"\nexperimental-features = nix-command flakes\nsubstituters =\nflake-registry =\n",
	)

	pack := t.TempDir()
	registryCommand(t, pack, "git", "init", "-q", "-b", "main")
	registryWrite(
		t,
		pack,
		"framework/flake.nix",
		fmt.Sprintf(registryFixtureFramework, nixeval.CurrentSystem()),
	)
	registryWrite(
		t,
		pack,
		"support/flake.nix",
		`{ outputs = { self }: { token = "support"; }; }`,
	)
	registryWrite(
		t,
		pack,
		"foreign/flake.nix",
		`{ outputs = { self }: { token = "foreign"; }; }`,
	)
	f.localProbe = filepath.Join(pack, "probe")
	release := func(version, enabled string) string {
		registryWrite(
			t,
			pack,
			"probe/flake.nix",
			fmt.Sprintf(registryFixtureModule, version, enabled),
		)
		registryCommand(
			t,
			pack,
			"git",
			"add",
			"-f",
			"framework",
			"support",
			"foreign",
			"probe",
		)
		registryGitCommit(t, pack, version)
		return registryCommand(t, pack, "git", "rev-parse", "HEAD")
	}
	const configurable = "cfg.tooling.probe.enable or true"
	f.v1 = release("1.0", configurable)
	registryCommand(t, pack, "git", "branch", "one")
	f.v2 = release("2.0", configurable)
	registryCommand(t, pack, "git", "branch", "two")
	alwaysOn := release("always-on", "true")
	registryCommand(t, pack, "git", "branch", "always-on")
	f.dev = release("development", configurable)
	f.framework = (&url.URL{Scheme: "git+file", Path: pack, RawQuery: "dir=framework&ref=one&rev=" + f.v1}).String()

	// Catalogs accept remote-style flake URLs, not arbitrary filesystem
	// paths. Serve the same local Git history over loopback with Git itself.
	repos := t.TempDir()
	registryCommand(t, repos, "git", "clone", "-q", "--bare", pack, "pack.git")
	backend := filepath.Join(
		registryCommand(t, repos, "git", "--exec-path"),
		"git-http-backend",
	)
	gitHTTP := httptest.NewServer(
		&cgi.Handler{
			Path: backend,
			Env:  []string{"GIT_PROJECT_ROOT=" + repos, "GIT_HTTP_EXPORT_ALL=1"},
		},
	)
	t.Cleanup(gitHTTP.Close)
	f.gitURL = "git+" + gitHTTP.URL + "/pack.git"

	catalogDir := t.TempDir()
	catalogHTTP := httptest.NewServer(http.FileServer(http.Dir(catalogDir)))
	t.Cleanup(catalogHTTP.Close)
	f.catalog = catalogHTTP.URL
	registryWrite(t, catalogDir, "README.md", "# Local probe\n")
	version := func(v, ref, rev string) registry.Version {
		return registry.Version{
			Version:  v,
			Ref:      ref,
			Rev:      rev,
			FlakeURL: f.gitURL + "?dir=probe",
			FlakeInputs: []registry.FlakeInput{
				{Name: "support", URL: f.gitURL + "?dir=support", Ref: "one"},
			},
		}
	}
	noExport := version("no-export", "one", f.v1)
	noExport.FlakeURL = f.gitURL + "?dir=support"
	v2 := version("2.0", "two", f.v2)
	v2.FlakeInputs[0].Ref = "two"
	m := registry.Module{
		ID:            registryFixtureID,
		Slug:          "probe",
		Description:   "Local registry integration probe",
		Category:      "tools",
		Icon:          "box",
		Author:        "local",
		Tier:          "community",
		LatestVersion: "2.0",
		ReadmeURL:     f.catalog + "/README.md",
		Features:      []string{"files"},
		UISlots:       []string{},
		Tags:          []string{"offline"},
		Versions: []registry.Version{
			version("1.0", "one", f.v1),
			v2,
			version("broken", "missing-branch", ""),
			noExport,
			version("always-on", "always-on", alwaysOn),
		},
	}
	for file, name := range map[string]string{"primary.json": "Primary catalog", "other.json": "Other catalog"} {
		m.Name = name
		data, err := json.Marshal(
			registry.Catalog{SchemaVersion: 1, Modules: []registry.Module{m}},
		)
		require.NoError(t, err)
		registryWrite(t, catalogDir, file, string(data))
	}

	var err error
	f.manager, err = project.NewManager(t.TempDir())
	require.NoError(t, err)
	s := &Server{config: &config.Config{}, projectMgr: f.manager}
	s.runtimes = newRuntimeRegistry(s)
	scope := projectInterceptor{resolve: s.resolveProjectRoot, runtimes: s.runtimes}
	mux := http.NewServeMux()
	mux.Handle(
		agentv1connect.NewModuleServiceHandler(
			&moduleService{s: s},
			connect.WithInterceptors(scope),
		),
	)
	rpc := httptest.NewServer(mux)
	t.Cleanup(rpc.Close)
	f.client = agentv1connect.NewModuleServiceClient(rpc.Client(), rpc.URL)
	return f
}

func registryCommand(t *testing.T, dir, program string, args ...string) string {
	t.Helper()
	cmd := exec.CommandContext(t.Context(), program, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, "%s %v: %s", program, args, out)
	return strings.TrimSpace(string(out))
}

func registryWrite(t *testing.T, dir, name, body string) {
	t.Helper()
	file := filepath.Join(dir, name)
	require.NoError(t, os.MkdirAll(filepath.Dir(file), 0o755))
	require.NoError(t, os.WriteFile(file, []byte(body), 0o644))
}

func registryGitCommit(t *testing.T, dir, message string) {
	t.Helper()
	registryCommand(
		t,
		dir,
		"git",
		"-c",
		"user.name=Fixture",
		"-c",
		"user.email=fixture@example.invalid",
		"commit",
		"-qm",
		message,
	)
}

// Only the framework is miniature. Its exported function discovers real
// locked outputs, reads real project config and computes both sides of a
// preview without depending on nixpkgs, a derivation, or the host project.
const registryFixtureFramework = `{
  outputs = { self }: {
    lib.mkFlake = { self, inputs }:
      let
        cfg = import (self.outPath + "/.stack/config.nix");
        names = builtins.attrNames (builtins.removeAttrs inputs [ "self" "stackpanel" ]);
        discovered = builtins.filter (n: inputs.${n} ? stackpanelModules) names;
        modules = map (n: inputs.${n}.stackpanelModules.default { inherit cfg inputs; }) discovered;
        installed = builtins.any (m: m.id == "probe") modules;
        plan = enabled: {
          files = if enabled then [ { path = "probe.conf"; type = "text"; } ] else [];
          packages = if enabled then [ "probe-tool" ] else [];
          services = if enabled then [ "probe-worker" ] else [];
          packageFingerprints = if enabled then {
            probe-tool = builtins.hashString "sha256" inputs.probe.rev;
          } else {};
          serviceFingerprints = if enabled then {
            probe-worker = builtins.hashString "sha256" (builtins.toJSON (cfg.tooling.probe.options or {}));
          } else {};
          addons = [];
        };
        enabled = builtins.any (m: m.enabled) modules;
        state = assert cfg.tooling.keep == "user value";
                assert !(cfg.requireProbe or false) || installed;
                assert installed || (cfg.tooling.probe or {}) == {};
          { inherit (cfg) registries; modulesListAll = modules; };
      in { legacyPackages.%s = {
        stackpanelConfig = state;
        stackpanelSerializable = state;
        stackpanelSpeculate = { enablePath ? null, ... }:
          plan (installed && (enabled || enablePath == [ "tooling" "probe" "enable" ]));
      }; };
  };
}`

const registryFixtureModule = `{
  outputs = { self }: {
    stackpanelModules.default = { cfg, inputs }:
      assert inputs.support.token == "support";
      {
        id = "probe";
        meta = { name = "Probe"; category = "tools"; version = %q; };
        missingFlakeInputs = if cfg.requireHelper or false && !(inputs ? helper) then [ { name = "helper"; } ] else [];
        source = { type = "flake-input"; flakeInput = "probe"; };
        enablePath = "tooling.probe.enable";
        configPath = "tooling.probe.options";
        enabled = %s;
        settings = cfg.tooling.probe.options or {};
      };
  };
}`
