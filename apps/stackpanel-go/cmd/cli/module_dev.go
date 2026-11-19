package cmd

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	nixgrammar "github.com/darkmatter/stackpanel/stackpanel-go/internal/treesitter/nix"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nix"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
	"github.com/spf13/cobra"
	treesitter "github.com/tree-sitter/go-tree-sitter"
)

func addModuleDevCommands(module *cobra.Command) {
	var linkID, linkUI string
	link := &cobra.Command{
		Use:   "link <path>",
		Short: "Override an installed flake input with a local module checkout",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			root, err := moduleProjectRoot(cmd)
			if err != nil {
				return err
			}
			id, local, err := moduleCheckout(args[0], linkID, linkUI)
			if err != nil {
				return err
			}
			// Nix only warns about an unknown --override-input. Do not persist
			// an override that evaluation will ignore. Ask Nix rather than
			// guessing the flake's inputs from its source or a stale lock.
			if err := checkModuleInput(cmd, root, id, local.Path); err != nil {
				return err
			}
			mgr, err := userconfig.NewManager()
			if err != nil {
				return err
			}
			if err := mgr.SetLinkedModule(root, id, local); err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Linked %s to %s in %s\n", id, local.Path, root)
			return nil
		},
	}
	link.Flags().
		StringVar(&linkID, "id", "", "Module ID / flake input name (defaults to checkout directory name)")
	link.Flags().
		StringVar(&linkUI, "ui-url", "", "Loopback URL of the module's custom UI dev server")
	unlink := &cobra.Command{
		Use:   "unlink <id>",
		Short: "Remove a project's local module override",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			root, err := moduleProjectRoot(cmd)
			if err != nil {
				return err
			}
			mgr, err := userconfig.NewManager()
			if err != nil {
				return err
			}
			if err := mgr.UnlinkModule(root, args[0]); err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Unlinked %s in %s\n", args[0], root)
			return nil
		},
	}
	var dev moduleDevOptions
	preview := &cobra.Command{
		Use:   "dev",
		Short: "Preview this module in Studio using an isolated scratch consumer",
		Args:  cobra.NoArgs,
		Long:  "Open this module in Studio using an isolated scratch consumer. If dev starts a local agent, it stays in the foreground until you press Ctrl-C. A previously running agent and any UI dev server remain under their original owner's control.",
		RunE:  func(cmd *cobra.Command, _ []string) error { return runModuleDev(cmd, dev) },
	}
	preview.Flags().
		StringVar(&dev.id, "id", "", "Module ID / flake input name (defaults to checkout directory name)")
	preview.Flags().
		StringVar(&dev.uiURL, "ui-url", "", "Loopback URL of the module's custom UI dev server")
	preview.Flags().
		StringVar(&dev.flake, "flake", "", "Stackpanel framework flake ref (default $STACKPANEL_FLAKE or github:darkmatter/stackpanel)")
	preview.Flags().
		StringVar(&dev.studio, "studio-url", setupsession.DefaultStudioURL, "Official Studio URL or a loopback Studio dev server")
	preview.Flags().
		IntVar(&dev.port, "agent-port", 0, "Local agent port (defaults to a per-consumer port)")
	preview.Flags().
		BoolVar(&dev.noBrowser, "no-browser", false, "Print the Studio link without launching a browser")
	eject := &cobra.Command{
		Use:   "eject <id> <dir>",
		Short: "Copy a project-local module into a new standalone Git flake",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			root, err := moduleProjectRoot(cmd)
			if err != nil {
				return err
			}
			if err := ejectLocalModule(cmd.Context(), root, args[0], args[1]); err != nil {
				return err
			}
			fmt.Fprintf(
				cmd.OutOrStdout(),
				"Created %s. Review the staged files before committing; the original module is unchanged.\n",
				args[1],
			)
			return nil
		},
	}
	module.AddCommand(link, unlink, preview, eject)
}

func moduleCheckout(path, id, uiURL string) (string, userconfig.LinkedModule, error) {
	var link userconfig.LinkedModule
	path, err := filepath.Abs(path)
	if err != nil {
		return "", link, err
	}
	path, err = filepath.EvalSymlinks(path)
	if err != nil {
		return "", link, err
	}
	if id == "" {
		id = filepath.Base(path)
	}
	if !userconfig.ValidModuleID(id) {
		return "", link, fmt.Errorf(
			"invalid module ID %q; specify the module's input name with --id",
			id,
		)
	}
	if err := userconfig.ValidateUIDevURL(uiURL); err != nil {
		return "", link, err
	}
	if err := moduleRegularFile(filepath.Join(path, "flake.nix")); err != nil {
		return "", link, fmt.Errorf("module checkout: %w", err)
	}
	return id, userconfig.LinkedModule{Path: path, UIDevURL: uiURL}, nil
}

func moduleRegularFile(path string) error {
	st, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !st.Mode().IsRegular() {
		return fmt.Errorf("expected a regular file at %s", path)
	}
	return nil
}

func modulePathRef(path string) string {
	return "path:" + (&url.URL{Path: path}).EscapedPath()
}

func checkModuleInput(cmd *cobra.Command, root, id, path string) error {
	links, err := userconfig.LoadLinkedModules(root)
	if err != nil {
		return err
	}
	if links == nil {
		links = make(map[string]userconfig.LinkedModule)
	}
	links[id] = userconfig.LinkedModule{Path: path}
	args := []string{"flake", "metadata", "--json", "--no-write-lock-file"}
	for _, name := range sortedKeys(links) {
		args = append(args, "--override-input", name, modulePathRef(links[name].Path))
	}
	probe := exec.CommandContext(cmd.Context(), "nix", append(args, ".")...)
	probe.Dir, probe.Stderr = root, cmd.ErrOrStderr()
	data, err := probe.Output()
	if err != nil {
		return fmt.Errorf("resolve inputs of %s: %w", root, err)
	}
	var metadata struct {
		Locks struct {
			Root  string
			Nodes map[string]struct{ Inputs map[string]json.RawMessage }
		}
	}
	if err := json.Unmarshal(data, &metadata); err != nil {
		return fmt.Errorf("read Nix input graph: %w", err)
	}
	if _, ok := metadata.Locks.Nodes[metadata.Locks.Root].Inputs[id]; !ok {
		return fmt.Errorf(
			"%s has no input %q; install the module first or use --id to select its input",
			root,
			id,
		)
	}
	// An enabled modules.<id> setting can itself produce a placeholder row
	// even when the input exports nothing. Check the actual import selected
	// by this consumer, then evaluate the whole proposed graph before saving.
	source, err := os.ReadFile(filepath.Join(root, "flake.nix"))
	if err != nil {
		return err
	}
	editor, err := flakeedit.NewFlakeEditor(source)
	if err != nil {
		return err
	}
	defer editor.Close()
	export, err := editor.ModuleImportPath(id)
	if err != nil {
		return fmt.Errorf("determine module import for %s: %w", id, err)
	}
	shape, err := nixeval.EvalOnce(cmd.Context(), nixeval.EvalOnceParams{
		Expression: modulePathRef(path) + "#" + export,
		Apply:      "m: builtins.isFunction m || builtins.isAttrs m || builtins.isPath m",
	})
	if err != nil {
		return fmt.Errorf("read module export %s in %s: %w", export, path, err)
	}
	if string(bytes.TrimSpace(shape)) != "true" {
		return fmt.Errorf("%s in %s is not a Nix module", export, path)
	}
	state, err := nixeval.EvalProspectiveModuleState(cmd.Context(), root, links)
	if err != nil {
		return fmt.Errorf("evaluate proposed link in %s: %w", root, err)
	}
	var result struct {
		Modules []struct {
			ID string `json:"id"`
		} `json:"modulesListAll"`
	}
	if err := json.Unmarshal(state, &result); err != nil {
		return fmt.Errorf("read module list: %w", err)
	}
	for _, mod := range result.Modules {
		if mod.ID == id {
			return nil
		}
	}
	return fmt.Errorf("proposed input does not register module %q in %s", id, root)
}

type moduleDevOptions struct {
	id, uiURL, flake, studio string
	port                     int
	noBrowser                bool
}

func runModuleDev(cmd *cobra.Command, opts moduleDevOptions) error {
	if cmd.Flags().Changed("project-root") {
		return errors.New(
			"module dev creates its own scratch project; use module link to preview in an existing project",
		)
	}
	parent := cmd.Context()
	ctx, cancel := signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
	defer cancel()
	cmd.SetContext(ctx)
	defer cmd.SetContext(parent)
	id, local, err := moduleCheckout(".", opts.id, opts.uiURL)
	if err != nil {
		return err
	}
	if id == "self" || id == "nixpkgs" || id == "stackpanel" || id == "flake-parts" {
		return fmt.Errorf("module ID %q collides with a framework input", id)
	}
	if opts.port < 0 || opts.port > 65535 {
		return errors.New("agent port must be between 1 and 65535 (or 0 for automatic)")
	}
	cache := os.Getenv("XDG_CACHE_HOME")
	if !filepath.IsAbs(cache) {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		cache = filepath.Join(home, ".cache")
	}
	framework := resolveFlakeRef(opts.flake)
	if filepath.IsAbs(framework) || strings.HasPrefix(framework, "./") ||
		strings.HasPrefix(framework, "../") ||
		framework == "." {
		abs, err := filepath.Abs(framework)
		if err != nil {
			return err
		}
		framework = modulePathRef(abs)
	}
	studio, err := url.Parse(opts.studio)
	official, _ := url.Parse(setupsession.DefaultStudioURL)
	if err != nil || studio.Host == "" || studio.User != nil ||
		!(studio.Scheme == official.Scheme && studio.Host == official.Host || userconfig.ValidateUIDevURL(opts.studio) == nil) {
		return errors.New(
			"Studio must use the official Studio origin or a loopback HTTP(S) dev server",
		)
	}
	origin := studio.Scheme + "://" + studio.Host
	// Checkouts of two modules with the same basename must not share a
	// lockfile, project ID, settings, or running agent.
	hash := sha256.Sum256([]byte(local.Path + "\x00" + framework + "\x00" + origin))
	root := filepath.Join(
		cache,
		"stackpanel",
		"dev-harness",
		id,
		fmt.Sprintf("%x", hash[:8]),
	)
	if opts.port == 0 {
		opts.port = 20000 + int(binary.BigEndian.Uint16(hash[:2]))%20000
	}
	endpoint := "http://127.0.0.1:" + strconv.Itoa(opts.port)
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	root, err = prepareModuleConsumer(cmd, root, id, local.Path, framework)
	if err != nil {
		return err
	}
	mgr, err := userconfig.NewManager()
	if err != nil {
		return err
	}
	if err := mgr.SetLinkedModule(root, id, local); err != nil {
		return err
	}
	fmt.Fprintf(
		cmd.ErrOrStderr(),
		"Preparing the Nix devshell and local agent for %s. Ctrl+C to cancel. Log: %s\n",
		id,
		setupAgentLogPath(),
	)
	_, started, err := ensureLocalAgent(
		ctx,
		root,
		executable,
		endpoint,
		origin,
		opts.port,
	)
	if err != nil {
		return err
	}
	if started != nil {
		defer started.stop()
	}
	studio = &url.URL{Scheme: studio.Scheme, Host: studio.Host, Path: "/studio/m/" + id}
	link, err := setupsession.StudioURL(
		studio.String(),
		setupsession.Session{
			ProjectID: userconfig.GenerateProjectID(root),
			Endpoint:  endpoint,
		},
	)
	if err != nil {
		return err
	}
	fmt.Fprintln(cmd.OutOrStdout(), link)
	if !opts.noBrowser {
		if err := openSetupStudio(ctx, link); err != nil {
			return fmt.Errorf(
				"could not launch a browser; open the printed Studio URL: %w",
				err,
			)
		}
	}
	if started == nil {
		return nil // Reused agent; its existing owner controls its lifetime.
	}
	fmt.Fprintln(cmd.ErrOrStderr(), "Press Ctrl-C to stop the preview agent.")
	select {
	case <-ctx.Done():
		return parent.Err() // Ctrl-C/TERM is an orderly shutdown; preserve caller cancellation.
	case <-started.done:
		if started.err != nil {
			return fmt.Errorf(
				"preview agent exited: %w; inspect %s",
				started.err,
				setupAgentLogPath(),
			)
		}
		return nil
	}
}

func prepareModuleConsumer(
	cmd *cobra.Command,
	root, id, path, framework string,
) (string, error) {
	if err := os.MkdirAll(filepath.Dir(root), 0o700); err != nil {
		return "", err
	}
	parent, err := filepath.EvalSymlinks(filepath.Dir(root))
	if err != nil {
		return "", err
	}
	root = filepath.Join(parent, filepath.Base(root))
	if rel, err := filepath.Rel(path, root); err != nil || filepath.IsLocal(rel) {
		return "", fmt.Errorf("scratch consumer cannot be inside module checkout %s", path)
	}
	// Follows keep the consumer on the framework's actual pins. The path
	// input makes the initial locked nix develop work without an override;
	// userconfig supplies the live override on subsequent agent evaluations.
	ref, err := nix.Serialize(framework)
	if err != nil {
		return "", err
	}
	input, err := nix.Serialize(modulePathRef(path))
	if err != nil {
		return "", err
	}
	flake := fmt.Sprintf(`{
  description = "Stackpanel module development consumer";
  inputs = {
    stackpanel.url = %s;
    nixpkgs.follows = "stackpanel/nixpkgs";
    flake-parts.follows = "stackpanel/flake-parts";
    "%s".url = %s;
  };
  outputs = { self, stackpanel, ... }@inputs:
    assert inputs."%s" ? stackpanelModules.default;
    stackpanel.lib.mkFlake { inherit inputs self; };
}
`, ref, id, input, id)
	if err := os.Mkdir(root, 0o700); err == nil {
		if err := initModuleConsumer(
			cmd.Context(),
			root,
			id,
			flake,
			cmd.ErrOrStderr(),
		); err != nil {
			_ = os.RemoveAll(
				root,
			) // Created exclusively above; never remove a reused project.
			return "", err
		}
	} else if !errors.Is(err, os.ErrExist) {
		return "", err
	} else {
		// Keep the author's changes to the preview config on the next run.
		real, err := filepath.EvalSymlinks(root)
		if err != nil || real != root {
			return "", fmt.Errorf("unsafe scratch project path: %s", root)
		}
		top, err := setupGitCommand(cmd.Context(), root, "rev-parse", "--show-toplevel")
		if err != nil || strings.TrimSuffix(string(top), "\n") != root {
			return "", fmt.Errorf("not a scratch Git repository: %s", root)
		}
		old, err := os.ReadFile(filepath.Join(root, "flake.nix"))
		if err != nil || string(old) != flake {
			return "", fmt.Errorf("scratch flake changed; refusing to overwrite %s", root)
		}
		for _, rel := range []string{"flake.lock", ".stack/config.nix"} {
			if err := moduleRegularFile(filepath.Join(root, rel)); err != nil {
				return "", fmt.Errorf("incomplete scratch consumer: %w", err)
			}
		}
		if _, err := setupGitCommand(
			cmd.Context(),
			root,
			"ls-files",
			"--error-unmatch",
			"--",
			"flake.nix",
			"flake.lock",
			".stack/config.nix",
		); err != nil {
			return "", fmt.Errorf("scratch flake inputs are not tracked: %w", err)
		}
	}
	return root, nil
}

func initModuleConsumer(
	ctx context.Context,
	root, id, flake string,
	out io.Writer,
) error {
	if _, err := setupGitCommand(ctx, root, "init", "--quiet"); err != nil {
		return err
	}
	if err := os.Mkdir(filepath.Join(root, ".stack"), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(
		filepath.Join(root, "flake.nix"),
		[]byte(flake),
		0o644,
	); err != nil {
		return err
	}
	cfg := fmt.Sprintf(
		"{\n  name = \"%s-dev\";\n  enable = true;\n  cli.enable = true;\n  modules.\"%s\".enable = true;\n}\n",
		id,
		id,
	)
	if err := os.WriteFile(
		filepath.Join(root, ".stack", "config.nix"),
		[]byte(cfg),
		0o644,
	); err != nil {
		return err
	}
	if _, err := setupGitCommand(
		ctx,
		root,
		"add",
		"-f",
		"--",
		"flake.nix",
		".stack/config.nix",
	); err != nil {
		return err
	}
	if err := runSetupProcess(ctx, root, out, "nix", "flake", "lock"); err != nil {
		return fmt.Errorf("lock scratch flake: %w", err)
	}
	_, err := setupGitCommand(ctx, root, "add", "-f", "--", "flake.lock")
	return err
}

func ejectLocalModule(ctx context.Context, project, id, dest string) error {
	if !userconfig.ValidModuleID(id) {
		return fmt.Errorf("invalid module ID %q", id)
	}
	project, err := filepath.EvalSymlinks(project)
	if err != nil {
		return err
	}
	src := filepath.Join(project, ".stack", "modules", id)
	real, err := filepath.EvalSymlinks(src)
	if err != nil {
		return err
	}
	if real != src {
		return fmt.Errorf("refusing to eject a symlinked module: %s", src)
	}
	dest, err = filepath.Abs(dest)
	if err != nil {
		return err
	}
	parent, err := filepath.EvalSymlinks(filepath.Dir(dest))
	if err != nil {
		return fmt.Errorf("destination parent must exist: %w", err)
	}
	dest = filepath.Join(parent, filepath.Base(dest))
	for _, part := range strings.Split(dest, string(filepath.Separator)) {
		if strings.EqualFold(part, ".git") {
			return fmt.Errorf("refusing to eject into Git metadata: %s", dest)
		}
	}
	if rel, err := filepath.Rel(src, dest); err != nil || filepath.IsLocal(rel) {
		return fmt.Errorf("destination %s is inside the source module", dest)
	}
	if err := os.Mkdir(dest, 0o755); err != nil {
		return fmt.Errorf("destination must be a new directory: %w", err)
	}
	success := false
	defer func() {
		if !success {
			_ = os.RemoveAll(dest)
		}
	}()
	if _, err := setupGitCommand(ctx, dest, "init", "--quiet"); err != nil {
		return err
	}
	if err := copyModuleSources(ctx, src, dest); err != nil {
		return err
	}
	entry := "default.nix"
	if err := moduleRegularFile(filepath.Join(dest, entry)); err != nil {
		entry = "module.nix"
		if err := moduleRegularFile(filepath.Join(dest, entry)); err != nil {
			return fmt.Errorf("module %s needs a regular default.nix or module.nix", id)
		}
	}
	flake := fmt.Sprintf(`{
  description = "Stackpanel module: %s";
  outputs = { self }: {
    stackpanelModules.default = import ./%s;
  };
}
`, id, entry)
	if err := writeEjectedFile(
		filepath.Join(dest, "flake.nix"),
		strings.NewReader(flake),
		0o644,
	); err != nil {
		return err
	}
	// The source Git file list has already applied the author's ignores;
	// keep deliberately tracked files even if they match a global ignore.
	if _, err := setupGitCommand(ctx, dest, "add", "-f", "--", "."); err != nil {
		return err
	}
	success = true
	return nil
}

func copyModuleSources(ctx context.Context, src, dest string) error {
	// Respect ignores in the containing project, including private local
	// files. For a prototype not yet in Git, use the new (empty) index
	// with the source as the work tree so module-local ignores still work.
	var opts []string
	for dir := src; ; dir = filepath.Dir(dir) {
		if _, err := os.Lstat(filepath.Join(dir, ".git")); err == nil {
			break
		} else if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if filepath.Dir(dir) == dir {
			opts = []string{"--git-dir=" + filepath.Join(dest, ".git"), "--work-tree=" + src}
			break
		}
	}
	files, err := setupGitCommand(
		ctx,
		src,
		append(
			opts,
			"ls-files",
			"--cached",
			"--others",
			"--exclude-standard",
			"-z",
			"--",
			".",
		)...)
	if err != nil {
		return err
	}
	source, err := os.OpenRoot(src)
	if err != nil {
		return err
	}
	defer source.Close()
	parser := treesitter.NewParser()
	defer parser.Close()
	if err := parser.SetLanguage(
		treesitter.NewLanguage(nixgrammar.Language()),
	); err != nil {
		return err
	}
	var deps []ejectedDependency
	for _, rel := range setupGitPaths(files) {
		if !filepath.IsLocal(rel) || filepath.Clean(rel) != rel {
			return fmt.Errorf("cannot eject nested repository or non-local path %q", rel)
		}
		for _, part := range strings.Split(rel, string(filepath.Separator)) {
			if strings.EqualFold(part, ".git") {
				return fmt.Errorf("refusing to copy Git metadata %q", rel)
			}
		}
		switch rel {
		case "flake.nix", "flake.lock":
			return fmt.Errorf(
				"module already contains %s; refusing to replace an existing flake",
				rel,
			)
		}
		if err := copyModuleFile(source, rel, dest, parser, &deps); err != nil {
			return err
		}
	}
	// Validate against the finished copy, not the checkout: Git ignores,
	// deletions, and empty directories affect what will actually be published.
	for _, dep := range deps {
		target := filepath.Join(dest, dep.target)
		info, err := os.Stat(target)
		if err == nil && dep.isImport && info.IsDir() {
			err = moduleRegularFile(filepath.Join(target, "default.nix"))
		}
		if err != nil {
			return fmt.Errorf(
				"%s: required module path %q is missing from the ejected flake: %w",
				dep.from,
				dep.target,
				err,
			)
		}
	}
	return nil
}

type ejectedDependency struct {
	from, target string
	isImport     bool
}

func copyModuleFile(
	source *os.Root,
	rel, dest string,
	parser *treesitter.Parser,
	deps *[]ejectedDependency,
) error {
	info, err := source.Lstat(rel)
	if errors.Is(err, os.ErrNotExist) {
		return nil // A tracked file deleted from the working tree.
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("refusing to copy non-regular module source %s", rel)
	}
	in, err := source.Open(rel)
	if err != nil {
		return err
	}
	defer in.Close()
	var r io.Reader = in
	if strings.HasSuffix(rel, ".nix") {
		data, err := io.ReadAll(in)
		if err != nil {
			return err
		}
		if err := checkModuleNixPaths(parser, rel, data, deps); err != nil {
			return err
		}
		r = bytes.NewReader(data)
	}
	return writeEjectedFile(filepath.Join(dest, rel), r, info.Mode().Perm())
}

func writeEjectedFile(path string, r io.Reader, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, r)
	return errors.Join(err, out.Close())
}

// A prototype that imports ../../nix/... isn't standalone. Catch literal
// paths that won't survive extraction, including those in helper modules,
// without interpreting comments or shell strings as dependencies. Computed
// dependencies still need the author's normal consumer evaluation/CI.
func checkModuleNixPaths(
	parser *treesitter.Parser,
	rel string,
	data []byte,
	deps *[]ejectedDependency,
) error {
	tree := parser.Parse(data, nil)
	if tree == nil {
		return fmt.Errorf("cannot parse %s", rel)
	}
	defer tree.Close()
	root := tree.RootNode()
	if root.HasError() {
		return fmt.Errorf("invalid Nix syntax in %s", rel)
	}
	var visit func(*treesitter.Node) error
	visit = func(n *treesitter.Node) error {
		switch n.Kind() {
		case "hpath_expression", "spath_expression":
			return fmt.Errorf(
				"%s uses a host-dependent Nix path: %s",
				rel,
				data[n.StartByte():n.EndByte()],
			)
		case "path_expression":
			path := string(data[n.StartByte():n.EndByte()])
			prefix, _, dynamic := strings.Cut(path, "${")
			target := filepath.Join(filepath.Dir(rel), prefix)
			first, _, _ := strings.Cut(target, string(filepath.Separator))
			if filepath.IsAbs(prefix) || !filepath.IsLocal(target) ||
				strings.EqualFold(first, ".git") {
				return fmt.Errorf(
					"%s: %s is outside the module; move the dependency into the module before ejecting",
					rel,
					path,
				)
			}
			if !dynamic {
				callee := nixPathCallee(n, data)
				if callee != "builtins.pathExists" {
					*deps = append(
						*deps,
						ejectedDependency{
							from:     rel,
							target:   target,
							isImport: callee == "import" || callee == "builtins.import",
						},
					)
				}
			}
		}
		for i := uint(0); i < n.NamedChildCount(); i++ {
			if err := visit(n.NamedChild(i)); err != nil {
				return err
			}
		}
		return nil
	}
	return visit(root)
}

func nixPathCallee(path *treesitter.Node, data []byte) string {
	parent := path.Parent()
	for parent != nil && parent.Kind() == "parenthesized_expression" {
		path, parent = parent, parent.Parent()
	}
	if parent != nil && parent.Kind() == "apply_expression" {
		fn, arg := parent.ChildByFieldName("function"), parent.ChildByFieldName("argument")
		if fn != nil && arg != nil && arg.StartByte() == path.StartByte() {
			return string(data[fn.StartByte():fn.EndByte()])
		}
	}
	return ""
}
