package cmd

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"strings"
	"text/tabwriter"

	"connectrpc.com/connect"
	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/server"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/spf13/cobra"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"
)

type moduleAPI interface {
	agentv1connect.ModuleServiceHandler
	ExecuteAction(
		context.Context,
		*agentv1.RunModuleActionRequest,
		func(*agentv1.RunModuleActionResponse) error,
	) error
}

type moduleCLI struct {
	open      func(context.Context, string) (context.Context, moduleAPI, error)
	reconcile func(context.Context, string) error
}

func newModuleCmd() *cobra.Command {
	cli := moduleCLI{
		open: func(ctx context.Context, root string) (context.Context, moduleAPI, error) {
			return server.NewLocalModules(ctx, root)
		},
		reconcile: reconcileModuleFiles,
	}
	cmd := cli.command()
	addModuleDevCommands(cmd)
	return cmd
}

func moduleProjectRoot(cmd *cobra.Command) (string, error) {
	flag, err := cmd.Flags().GetString("project-root")
	if err != nil {
		return "", err
	}
	if flag != "" {
		return filepath.Abs(flag)
	}
	// A caller may have cd'd to another project without leaving its old
	// devshell. Never adopt into that shell's project (or a saved active one).
	return findProjectRoot()
}

type moduleInvocation struct {
	ctx  context.Context
	cmd  *cobra.Command
	root string
	api  moduleAPI
}

func (cli moduleCLI) command() *cobra.Command {
	module := &cobra.Command{
		Use:   "module",
		Short: "Discover, adopt, and run project modules",
	}
	module.PersistentFlags().
		String("project-root", "", "Project directory (default: current stackpanel project)")
	add := func(use, short string, positional cobra.PositionalArgs, run func(moduleInvocation, []string) error) *cobra.Command {
		cmd := &cobra.Command{
			Use:   use,
			Short: short,
			Args:  positional,
			RunE: func(cmd *cobra.Command, args []string) error {
				root, err := moduleProjectRoot(cmd)
				if err != nil {
					return err
				}
				ctx, api, err := cli.open(cmd.Context(), root)
				if err != nil {
					return err
				}
				return run(moduleInvocation{ctx, cmd, root, api}, args)
			},
		}
		module.AddCommand(cmd)
		return cmd
	}
	var category, tag string
	search := add(
		"search [query]",
		"Search the module registry",
		cobra.MaximumNArgs(1),
		func(m moduleInvocation, args []string) error {
			req := &agentv1.ListRegistryModulesRequest{Category: category, Tag: tag}
			if len(args) > 0 {
				req.Query = args[0]
			}
			r, err := m.api.ListRegistryModules(m.ctx, connect.NewRequest(req))
			if err != nil {
				return err
			}
			w := tabwriter.NewWriter(m.cmd.OutOrStdout(), 0, 4, 2, ' ', 0)
			if _, err := fmt.Fprintln(w, "ID\tVERSION\tCATEGORY\tDESCRIPTION"); err != nil {
				return err
			}
			for _, mod := range r.Msg.Modules {
				if _, err := fmt.Fprintf(
					w,
					"%s\t%s\t%s\t%s\n",
					mod.GetId(),
					mod.GetLatestVersion(),
					mod.GetCategory(),
					mod.GetDescription(),
				); err != nil {
					return err
				}
			}
			return w.Flush()
		},
	)
	search.Flags().StringVar(&category, "category", "", "Filter by category")
	search.Flags().StringVar(&tag, "tag", "", "Filter by tag")

	var all bool
	list := add(
		"list",
		"List enabled project modules",
		cobra.NoArgs,
		func(m moduleInvocation, _ []string) error {
			r, err := m.api.ListModules(
				m.ctx,
				connect.NewRequest(&agentv1.ListModulesRequest{}),
			)
			if err != nil {
				return err
			}
			for _, mod := range r.Msg.Modules {
				status := "enabled"
				if !mod.GetEnabled() {
					if !all {
						continue
					}
					status = "disabled"
				}
				if _, err := fmt.Fprintf(
					m.cmd.OutOrStdout(),
					"%s\t%s\t%s\n",
					mod.GetId(),
					status,
					mod.GetMeta().GetDescription(),
				); err != nil {
					return err
				}
			}
			return nil
		},
	)
	list.Flags().BoolVar(&all, "all", false, "Include disabled modules")
	add(
		"info <id>",
		"Show module metadata, actions, and attributed outputs",
		cobra.ExactArgs(1),
		moduleInfo,
	)

	var adopt moduleAdoptionOptions
	install := add(
		"install <id[@version]>",
		"Install a registry module and offer to enable it",
		cobra.ExactArgs(1),
		func(m moduleInvocation, args []string) error {
			id, version, err := moduleVersion(args[0])
			if err != nil {
				return err
			}
			r, err := m.api.InstallModule(
				m.ctx,
				connect.NewRequest(
					&agentv1.InstallModuleRequest{ModuleId: id, Version: version},
				),
			)
			if err != nil {
				return err
			}
			if _, err := fmt.Fprintln(m.cmd.OutOrStdout(), r.Msg.GetMessage()); err != nil {
				return err
			}
			if r.Msg.GetModuleId() == "" {
				return errors.New("installed module has no canonical Nix module id")
			}
			return cli.enable(m, r.Msg.GetModuleId(), adopt)
		},
	)
	install.Long = "Install and lock the registry input first, then preview adoption. Declining the preview leaves the input installed but does not enable it or reconcile files."
	adopt.bind(install)
	var enableOptions moduleAdoptionOptions
	enable := add(
		"enable <id>",
		"Preview, enable, and reconcile a module",
		cobra.ExactArgs(1),
		func(m moduleInvocation, args []string) error {
			return cli.enable(m, args[0], enableOptions)
		},
	)
	enableOptions.bind(enable)
	add(
		"disable <id>",
		"Disable a module and reconcile files",
		cobra.ExactArgs(1),
		func(m moduleInvocation, args []string) error {
			r, err := m.api.DisableModule(
				m.ctx,
				connect.NewRequest(&agentv1.DisableModuleRequest{ModuleId: args[0]}),
			)
			if err != nil {
				return err
			}
			return cli.finishMutation(m, r.Msg.GetMessage())
		},
	)
	add(
		"uninstall <id>",
		"Remove a registry module from the project",
		cobra.ExactArgs(1),
		func(m moduleInvocation, args []string) error {
			r, err := m.api.UninstallModule(
				m.ctx,
				connect.NewRequest(&agentv1.UninstallModuleRequest{ModuleId: args[0]}),
			)
			if err != nil {
				return err
			}
			return cli.finishMutation(m, r.Msg.GetMessage())
		},
	)
	var updateAll bool
	update := add(
		"update [id[@version]]",
		"Update one or all installed registry modules",
		cobra.MaximumNArgs(1),
		func(m moduleInvocation, args []string) error {
			if updateAll && len(args) != 0 {
				return errors.New("use either a module id or --all")
			}
			if len(args) == 0 {
				r, err := m.api.ListRegistryModules(
					m.ctx,
					connect.NewRequest(&agentv1.ListRegistryModulesRequest{}),
				)
				if err != nil {
					return err
				}
				for _, mod := range r.Msg.Modules {
					if mod.GetInstalled() {
						args = append(args, mod.GetId())
					}
				}
				sort.Strings(args)
			}
			for _, arg := range args {
				id, version, err := moduleVersion(arg)
				if err != nil {
					return err
				}
				r, err := m.api.UpdateModule(
					m.ctx,
					connect.NewRequest(
						&agentv1.UpdateModuleRequest{ModuleId: id, Version: version},
					),
				)
				if err != nil {
					return fmt.Errorf("update %s: %w", id, err)
				}
				if _, err := fmt.Fprintln(m.cmd.OutOrStdout(), r.Msg.GetMessage()); err != nil {
					return err
				}
			}
			if len(args) == 0 {
				_, err := fmt.Fprintln(
					m.cmd.OutOrStdout(),
					"No installed registry modules to update.",
				)
				return err
			}
			return cli.reconcile(m.ctx, m.root)
		},
	)
	update.Flags().
		BoolVar(&updateAll, "all", false, "Update every installed registry module (default if no id is given)")
	var jsonArgs string
	var approve bool
	run := add(
		"run <id> <action> [-- --key=value ...]",
		"Run a declared module action",
		cobra.MinimumNArgs(2),
		func(m moduleInvocation, args []string) error {
			return runModuleAction(m, args, jsonArgs, approve)
		},
	)
	run.Example = `  stack module run db inspect -- --table=users --limit 5
  stack module run db inspect --json '{"table":"users","limit":5}'`
	run.Flags().
		StringVar(&jsonArgs, "json", "", "Action arguments as a JSON object instead of flags after --")
	run.Flags().
		BoolVarP(&approve, "yes", "y", false, "Approve the action's declared confirmation without prompting")
	return module
}

func moduleVersion(arg string) (string, string, error) {
	id, version, pin := strings.Cut(arg, "@")
	if id == "" || (pin && version == "") || strings.Contains(version, "@") ||
		strings.TrimSpace(arg) != arg {
		return "", "", errors.New("expected a module id or id@version")
	}
	return id, version, nil
}

func (cli moduleCLI) enable(
	m moduleInvocation,
	id string,
	opts moduleAdoptionOptions,
) error {
	r, err := m.api.PreviewModuleEnable(
		m.ctx,
		connect.NewRequest(&agentv1.PreviewModuleEnableRequest{ModuleId: id}),
	)
	if err != nil {
		return fmt.Errorf("preview %s before enabling: %w", id, err)
	}
	if r.Msg.GetPreview() == nil {
		return errors.New("missing module adoption preview")
	}
	input := bufio.NewScanner(m.cmd.InOrStdin())
	answers, err := opts.answers(
		id,
		r.Msg.GetPreview().GetOffers(),
		input,
		m.cmd.ErrOrStderr(),
	)
	if err != nil {
		return err
	}
	if len(answers) != 0 {
		r, err = m.api.PreviewModuleEnable(
			m.ctx,
			connect.NewRequest(
				&agentv1.PreviewModuleEnableRequest{ModuleId: id, Answers: answers},
			),
		)
		if err != nil {
			return fmt.Errorf("preview selected adoption answers: %w", err)
		}
		if r.Msg.GetPreview() == nil {
			return errors.New("missing answered adoption preview")
		}
	}
	if err := printModuleProto(m.cmd.OutOrStdout(), r.Msg.GetPreview()); err != nil {
		return err
	}
	if !opts.yes {
		ok, err := confirmModuleInput(
			m.cmd,
			input,
			fmt.Sprintf("Enable %s with the reviewed answers and reconcile files?", id),
		)
		if err != nil {
			return err
		}
		if !ok {
			_, err := fmt.Fprintln(
				m.cmd.OutOrStdout(),
				"Enable skipped; no adoption changes applied.",
			)
			return err
		}
	}
	enabled, err := m.api.EnableModule(
		m.ctx,
		connect.NewRequest(&agentv1.EnableModuleRequest{ModuleId: id, Answers: answers}),
	)
	if err != nil {
		return err
	}
	return cli.finishMutation(m, enabled.Msg.GetMessage())
}

func confirmModule(cmd *cobra.Command, question string) (bool, error) {
	return confirmModuleInput(cmd, bufio.NewScanner(cmd.InOrStdin()), question)
}

func confirmModuleInput(
	cmd *cobra.Command,
	r *bufio.Scanner,
	question string,
) (bool, error) {
	if _, err := fmt.Fprintf(cmd.ErrOrStderr(), "%s [y/N] ", question); err != nil {
		return false, err
	}
	if !r.Scan() {
		if err := r.Err(); err != nil {
			return false, err
		}
		return false, errors.New(
			"no confirmation received; use --yes to approve non-interactively",
		)
	}
	switch strings.ToLower(strings.TrimSpace(r.Text())) {
	case "y", "yes":
		return true, nil
	case "", "n", "no":
		return false, nil
	default:
		return false, errors.New("expected yes or no; no changes approved")
	}
}

func (cli moduleCLI) finishMutation(m moduleInvocation, message string) error {
	if _, err := fmt.Fprintln(m.cmd.OutOrStdout(), message); err != nil {
		return err
	}
	if err := cli.reconcile(m.ctx, m.root); err != nil {
		return fmt.Errorf("module change saved, file reconciliation failed: %w", err)
	}
	return nil
}

func reconcileModuleFiles(ctx context.Context, root string) error {
	rc, err := reconcile.NewContext(ctx, root)
	if err != nil {
		return err
	}
	// Evaluate the committed configuration rather than the old shell's manifest.
	spec, err := reconcile.Speculate(ctx, root, map[string]any{}, 0)
	if err != nil {
		return err
	}
	return reconcileAfterMutation(rc, spec)
}

func printModuleProto(w io.Writer, msg proto.Message) error {
	b, err := (protojson.MarshalOptions{Indent: "  "}).Marshal(msg)
	if err != nil {
		return err
	}
	_, err = w.Write(append(b, '\n'))
	return err
}

func moduleInfo(m moduleInvocation, args []string) error {
	id := args[0]
	r, err := m.api.GetModule(
		m.ctx,
		connect.NewRequest(&agentv1.GetModuleRequest{ModuleId: id}),
	)
	if err != nil {
		return err
	}
	out, err := m.api.GetModuleOutputs(
		m.ctx,
		connect.NewRequest(&agentv1.GetModuleOutputsRequest{ModuleId: id}),
	)
	if err != nil {
		return err
	}
	mod := r.Msg.GetModule()
	if mod == nil || out.Msg.GetOutputs() == nil {
		return errors.New("incomplete module metadata")
	}
	// Do not dump the full config: settings and app overrides may be private.
	w := m.cmd.OutOrStdout()
	if _, err := fmt.Fprintf(
		w,
		"%s (%s)\n%s\nCategory: %s\nEnabled: %t\nActions:\n",
		mod.GetMeta().GetName(),
		mod.GetId(),
		mod.GetMeta().GetDescription(),
		mod.GetMeta().GetCategory(),
		mod.GetEnabled(),
	); err != nil {
		return err
	}
	for _, name := range sortedKeys(mod.Actions) {
		a := mod.Actions[name]
		if _, err := fmt.Fprintf(
			w,
			"  %s\t%s\t%s\n",
			name,
			a.GetLabel(),
			a.GetDescription(),
		); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintln(w, "Outputs:"); err != nil {
		return err
	}
	return printModuleProto(w, out.Msg.GetOutputs())
}

func runModuleAction(m moduleInvocation, args []string, raw string, yes bool) error {
	if pos := m.cmd.ArgsLenAtDash(); pos >= 0 && pos != 2 {
		return errors.New("expected <id> <action> before --")
	}
	r, err := m.api.GetModule(
		m.ctx,
		connect.NewRequest(&agentv1.GetModuleRequest{ModuleId: args[0]}),
	)
	if err != nil {
		return err
	}
	action := r.Msg.GetModule().GetActions()[args[1]]
	if action == nil {
		return fmt.Errorf("module %q has no action %q", args[0], args[1])
	}
	if m.cmd.Flags().Changed("json") && raw == "" {
		return errors.New("--json requires a JSON object")
	}
	params, err := moduleActionArgs(raw, args[2:], action.GetArgsSchema())
	if err != nil {
		return err
	}
	if !yes && action.GetConfirm() != "" {
		ok, err := confirmModule(m.cmd, action.GetConfirm())
		if err != nil {
			return err
		}
		if !ok {
			return errors.New("action cancelled")
		}
	}
	req := &agentv1.RunModuleActionRequest{
		ModuleId: args[0],
		ActionId: args[1],
		Args:     params,
	}
	var exited bool
	var code int32
	err = m.api.ExecuteAction(
		m.ctx,
		req,
		func(ev *agentv1.RunModuleActionResponse) error {
			if exited {
				return errors.New("received event after action exit")
			}
			switch e := ev.GetEvent().(type) {
			case *agentv1.RunModuleActionResponse_Stdout:
				_, err := io.WriteString(m.cmd.OutOrStdout(), e.Stdout)
				return err
			case *agentv1.RunModuleActionResponse_Stderr:
				_, err := io.WriteString(m.cmd.ErrOrStderr(), e.Stderr)
				return err
			case *agentv1.RunModuleActionResponse_Json:
				return printModuleProto(m.cmd.OutOrStdout(), e.Json)
			case *agentv1.RunModuleActionResponse_ExitCode:
				exited, code = true, e.ExitCode
				return nil
			default:
				return errors.New("unknown module action event")
			}
		},
	)
	if err != nil {
		return err
	}
	if !exited {
		return errors.New("action ended without exit status")
	}
	if code != 0 {
		return fmt.Errorf("action exited with status %d", code)
	}
	return nil
}

func moduleActionArgs(
	raw string,
	flags []string,
	schema *structpb.Struct,
) (*structpb.Struct, error) {
	if raw == "" && len(flags) == 1 &&
		strings.HasPrefix(strings.TrimSpace(flags[0]), "{") {
		raw, flags = flags[0], nil
	}
	if raw != "" {
		if len(flags) > 0 {
			return nil, errors.New("provide a JSON object or -- flags, not both")
		}
		var args structpb.Struct
		if err := protojson.Unmarshal([]byte(raw), &args); err != nil {
			return nil, errors.New("action arguments must be a JSON object")
		}
		return &args, nil
	}
	values := map[string]any{}
	properties := schema.GetFields()["properties"].GetStructValue().GetFields()
	for len(flags) > 0 {
		flag, rest := flags[0], flags[1:]
		if !strings.HasPrefix(flag, "--") {
			return nil, errors.New("expected --key=value, --key value, or a JSON object")
		}
		key, val, explicit := strings.Cut(flag[2:], "=")
		if key == "" {
			return nil, errors.New("empty argument name")
		}
		if _, exists := values[key]; exists {
			return nil, fmt.Errorf("duplicate action argument %q", key)
		}
		typ := properties[key].GetStructValue().GetFields()["type"].GetStringValue()
		if !explicit && len(rest) > 0 && !strings.HasPrefix(rest[0], "--") {
			val, rest, explicit = rest[0], rest[1:], true
		}
		switch {
		case !explicit && (typ == "" || typ == "boolean"):
			values[key] = true
		case !explicit:
			return nil, fmt.Errorf("missing value for --%s", key)
		case typ == "string":
			values[key] = val
		default:
			var decoded any
			if err := json.Unmarshal([]byte(val), &decoded); err != nil {
				if typ != "" {
					return nil, fmt.Errorf("--%s expects a JSON %s", key, typ)
				}
				decoded = val
			}
			values[key] = decoded
		}
		flags = rest
	}
	return structpb.NewStruct(values)
}
