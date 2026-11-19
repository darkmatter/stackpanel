package cmd

import (
	"bytes"
	"context"
	"errors"
	"slices"
	"strings"
	"testing"

	"connectrpc.com/connect"
	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"
)

type moduleFixture struct {
	agentv1connect.UnimplementedModuleServiceHandler
	calls               []string
	schema              *structpb.Struct
	params              *structpb.Struct
	exitCode            int32
	reconcileErr        error
	offers              []*agentv1.ModuleAdoptionOffer
	reviewed, committed []*agentv1.ModuleAdoptionAnswer
}

func (f *moduleFixture) invoke(
	t *testing.T,
	stdin string,
	args ...string,
) (string, string, error) {
	t.Helper()
	root := t.TempDir()
	cli := moduleCLI{
		open: func(ctx context.Context, project string) (context.Context, moduleAPI, error) {
			if project != root {
				t.Fatalf("selected %q instead of %q", project, root)
			}
			return ctx, f, nil
		},
		reconcile: func(context.Context, string) error {
			f.calls = append(f.calls, "reconcile")
			return f.reconcileErr
		},
	}
	cmd := cli.command()
	var out, stderr bytes.Buffer
	cmd.SilenceErrors, cmd.SilenceUsage = true, true
	cmd.SetArgs(append([]string{"--project-root", root}, args...))
	cmd.SetIn(strings.NewReader(stdin))
	cmd.SetOut(&out)
	cmd.SetErr(&stderr)
	err := cmd.ExecuteContext(t.Context())
	return out.String(), stderr.String(), err
}

func (f *moduleFixture) InstallModule(
	_ context.Context,
	req *connect.Request[agentv1.InstallModuleRequest],
) (*connect.Response[agentv1.InstallModuleResponse], error) {
	f.calls = append(f.calls, "install:"+req.Msg.ModuleId+"@"+req.Msg.Version)
	return connect.NewResponse(
		&agentv1.InstallModuleResponse{
			ModuleId: "cache",
			Message:  "Installed external/cache",
		},
	), nil
}

func (f *moduleFixture) PreviewModuleEnable(
	_ context.Context,
	req *connect.Request[agentv1.PreviewModuleEnableRequest],
) (*connect.Response[agentv1.PreviewModuleEnableResponse], error) {
	f.calls = append(f.calls, "preview:"+req.Msg.ModuleId)
	f.reviewed = req.Msg.Answers
	files := []string{"cache.conf"}
	if len(f.reviewed) > 0 {
		files = append(files, "selected.conf")
	}
	return connect.NewResponse(
		&agentv1.PreviewModuleEnableResponse{
			Preview: &agentv1.ModulePreview{
				Files:  &agentv1.ModulePreviewDiff{Added: files},
				Offers: f.offers,
			},
		},
	), nil
}

func (f *moduleFixture) EnableModule(
	_ context.Context,
	req *connect.Request[agentv1.EnableModuleRequest],
) (*connect.Response[agentv1.EnableModuleResponse], error) {
	f.calls = append(f.calls, "enable:"+req.Msg.ModuleId)
	f.committed = req.Msg.Answers
	return connect.NewResponse(
		&agentv1.EnableModuleResponse{Message: "Enabled cache"},
	), nil
}

func (f *moduleFixture) DisableModule(
	_ context.Context,
	req *connect.Request[agentv1.DisableModuleRequest],
) (*connect.Response[agentv1.DisableModuleResponse], error) {
	f.calls = append(f.calls, "disable:"+req.Msg.ModuleId)
	return connect.NewResponse(
		&agentv1.DisableModuleResponse{Message: "Disabled cache"},
	), nil
}

func (f *moduleFixture) UninstallModule(
	_ context.Context,
	req *connect.Request[agentv1.UninstallModuleRequest],
) (*connect.Response[agentv1.UninstallModuleResponse], error) {
	f.calls = append(f.calls, "uninstall:"+req.Msg.ModuleId)
	return connect.NewResponse(
		&agentv1.UninstallModuleResponse{Message: "Uninstalled cache"},
	), nil
}

func (f *moduleFixture) ListRegistryModules(
	_ context.Context,
	req *connect.Request[agentv1.ListRegistryModulesRequest],
) (*connect.Response[agentv1.ListRegistryModulesResponse], error) {
	f.calls = append(
		f.calls,
		strings.Join([]string{"search", req.Msg.Query, req.Msg.Category, req.Msg.Tag}, ":"),
	)
	return connect.NewResponse(
		&agentv1.ListRegistryModulesResponse{Modules: []*agentv1.RegistryModule{
			{
				Id: "uninstalled",
			},
			{
				Id:            "external/cache",
				Installed:     true,
				LatestVersion: "1.2.0",
				Category:      "services",
			},
		}},
	), nil
}

func (f *moduleFixture) UpdateModule(
	_ context.Context,
	req *connect.Request[agentv1.UpdateModuleRequest],
) (*connect.Response[agentv1.UpdateModuleResponse], error) {
	f.calls = append(f.calls, "update:"+req.Msg.ModuleId+"@"+req.Msg.Version)
	return connect.NewResponse(
		&agentv1.UpdateModuleResponse{Message: "Updated cache"},
	), nil
}

func (f *moduleFixture) ListModules(
	context.Context,
	*connect.Request[agentv1.ListModulesRequest],
) (*connect.Response[agentv1.ListModulesResponse], error) {
	return connect.NewResponse(
		&agentv1.ListModulesResponse{
			Modules: []*agentv1.Module{{Id: "cache", Enabled: true}, {Id: "lint"}},
		},
	), nil
}

func (f *moduleFixture) GetModule(
	context.Context,
	*connect.Request[agentv1.GetModuleRequest],
) (*connect.Response[agentv1.GetModuleResponse], error) {
	settings := &structpb.Struct{
		Fields: map[string]*structpb.Value{
			"token": structpb.NewStringValue("private-setting"),
		},
	}
	return connect.NewResponse(&agentv1.GetModuleResponse{Module: &agentv1.Module{
		Id:       "cache",
		Enabled:  true,
		Settings: settings,
		Actions: map[string]*agentv1.ModuleAction{
			"flush": {ArgsSchema: f.schema, Confirm: proto.String("Flush the cache?")},
		},
	}}), nil
}

func (f *moduleFixture) GetModuleOutputs(
	context.Context,
	*connect.Request[agentv1.GetModuleOutputsRequest],
) (*connect.Response[agentv1.GetModuleOutputsResponse], error) {
	return connect.NewResponse(
		&agentv1.GetModuleOutputsResponse{
			Outputs: &agentv1.ModuleOutputs{
				ModuleId: "cache",
				Services: []*agentv1.ModuleOutputService{{Name: "cache.service"}},
			},
		},
	), nil
}

func (f *moduleFixture) ExecuteAction(
	_ context.Context,
	req *agentv1.RunModuleActionRequest,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	f.params = req.Args
	for _, ev := range []*agentv1.RunModuleActionResponse{
		{Event: &agentv1.RunModuleActionResponse_Stdout{Stdout: "done\n"}},
		{Event: &agentv1.RunModuleActionResponse_Stderr{Stderr: "progress\n"}},
		{Event: &agentv1.RunModuleActionResponse_ExitCode{ExitCode: f.exitCode}},
	} {
		if err := send(ev); err != nil {
			return err
		}
	}
	return nil
}

func TestModuleInstallAdoption(t *testing.T) {
	for _, tc := range []struct {
		name, stdin           string
		yes, adopted, wantErr bool
	}{
		{"accept", "yes\n", false, true, false},
		{"explicit flag", "", true, true, false},
		{"decline", "n\n", false, false, false},
		{"closed stdin", "", false, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &moduleFixture{}
			args := []string{"install", "external/cache@1.2.0"}
			if tc.yes {
				args = append(args, "--yes")
			}
			out, _, err := f.invoke(t, tc.stdin, args...)
			if (err != nil) != tc.wantErr || !strings.Contains(out, "cache.conf") {
				t.Fatalf("out=%q err=%v", out, err)
			}
			want := []string{"install:external/cache@1.2.0", "preview:cache"}
			if tc.adopted {
				want = append(want, "enable:cache", "reconcile")
			}
			if !slices.Equal(f.calls, want) {
				t.Fatalf("operations %v, want %v", f.calls, want)
			}
		})
	}
}

func TestModuleMutationCommands(t *testing.T) {
	for _, tc := range []struct{ args, calls []string }{
		{[]string{"enable", "cache", "--yes"}, []string{"preview:cache", "enable:cache", "reconcile"}},
		{[]string{"disable", "cache"}, []string{"disable:cache", "reconcile"}},
		{[]string{"uninstall", "external/cache"}, []string{"uninstall:external/cache", "reconcile"}},
		{[]string{"update", "external/cache@2"}, []string{"update:external/cache@2", "reconcile"}},
		{[]string{"update", "--all"}, []string{"search:::", "update:external/cache@", "reconcile"}},
	} {
		f := &moduleFixture{}
		_, _, err := f.invoke(t, "", tc.args...)
		if err != nil || !slices.Equal(f.calls, tc.calls) {
			t.Errorf("%v: operations %v err=%v", tc.args, f.calls, err)
		}
	}
	f := &moduleFixture{reconcileErr: errors.New("writer failed")}
	if _, _, err := f.invoke(
		t,
		"",
		"enable",
		"cache",
		"-y",
	); !errors.Is(
		err,
		f.reconcileErr,
	) {
		t.Fatalf("lost reconciliation failure: %v", err)
	}
}

func TestModuleDiscoveryCLI(t *testing.T) {
	f := &moduleFixture{}
	out, _, err := f.invoke(
		t,
		"",
		"search",
		"redis",
		"--category",
		"services",
		"--tag",
		"kv",
	)
	if err != nil || !slices.Equal(f.calls, []string{"search:redis:services:kv"}) ||
		!strings.Contains(out, "external/cache") {
		t.Fatalf("search: %q %v %v", out, f.calls, err)
	}
	for _, all := range []bool{true, false} {
		args := []string{"list"}
		if all {
			args = append(args, "--all")
		}
		out, _, err := f.invoke(t, "", args...)
		if err != nil || !strings.Contains(out, "cache") ||
			strings.Contains(out, "lint") != all {
			t.Errorf("%v: %q %v", args, out, err)
		}
	}
	out, _, err = f.invoke(t, "", "info", "cache")
	if err != nil || !strings.Contains(out, "flush") ||
		!strings.Contains(out, "cache.service") ||
		strings.Contains(out, "private-setting") {
		t.Errorf("info: %q %v", out, err)
	}
}

func TestModuleActionCLI(t *testing.T) {
	schema, err := structpb.NewStruct(map[string]any{"properties": map[string]any{
		"filter": map[string]any{
			"type": "string",
		},
		"force": map[string]any{"type": "boolean"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	for _, argv := range [][]string{{"--", "--filter", "false", "--force"}, {"--json", `{"filter":"false","force":true}`}} {
		f := &moduleFixture{schema: schema}
		out, stderr, err := f.invoke(
			t,
			"yes\n",
			append([]string{"run", "cache", "flush"}, argv...)...)
		if err != nil || out != "done\n" || !strings.Contains(stderr, "progress\n") ||
			f.params.GetFields()["filter"].GetStringValue() != "false" ||
			!f.params.GetFields()["force"].GetBoolValue() {
			t.Fatalf(
				"%v: stdout=%q stderr=%q args=%v err=%v",
				argv,
				out,
				stderr,
				f.params,
				err,
			)
		}
	}
	f := &moduleFixture{exitCode: 7}
	if _, _, err := f.invoke(
		t,
		"no\n",
		"run",
		"cache",
		"flush",
	); err == nil ||
		f.params != nil {
		t.Fatal("action ran without confirmation")
	}
	if _, _, err := f.invoke(
		t,
		"",
		"run",
		"cache",
		"flush",
		"--yes",
	); err == nil ||
		!strings.Contains(err.Error(), "status 7") {
		t.Fatalf("lost exit status: %v", err)
	}
	for _, args := range [][]string{{"--json", "[]"}, {"--json", `{"x":1}`, "--", "--x=2"}, {"--", "--x", "--x"}} {
		if _, _, err := f.invoke(
			t,
			"",
			append([]string{"run", "cache", "flush", "--yes"}, args...)...); err == nil {
			t.Errorf("accepted invalid arguments: %v", args)
		}
	}
}

func TestModuleOptionalAnswersRequireFinalApproval(t *testing.T) {
	choices := []*agentv1.ModuleAdoptionChoice{
		{Label: "Alpha", Value: "a"},
		{Label: "Beta", Value: "b"},
	}
	offers := []*agentv1.ModuleAdoptionOffer{
		{
			Id:       "configure",
			Module:   "cache",
			Revision: "2",
			Type:     "bool",
			Default:  structpb.NewBoolValue(true),
		},
		{
			Id:       "engine",
			Module:   "dependency",
			Revision: "4",
			Type:     "select",
			Choices:  choices,
			Default:  structpb.NewStringValue("a"),
		},
		{
			Id:       "features",
			Module:   "cache",
			Revision: "1",
			Type:     "multiselect",
			Choices:  choices,
		},
	}
	for _, tc := range []struct {
		name                 string
		flags                []string
		stdin                string
		accepted, configured bool
		engine               string
	}{
		{"interactive", nil, "yes\nb\na,b\ny\n", true, true, "b"},
		{"explicit", []string{"--yes", "--without", "configure", "--with", "engine", "--addon", "features=a,b"}, "", true, false, "a"},
		{"defaults", []string{"--yes", "--adopt-defaults", "--with", "features"}, "", true, true, "a"},
		{"cancel reviewed plan", nil, "yes\nb\na,b\nn\n", false, true, "b"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &moduleFixture{offers: offers}
			out, _, err := f.invoke(
				t,
				tc.stdin,
				append([]string{"install", "external/cache"}, tc.flags...)...)
			if err != nil || !strings.Contains(out, "selected.conf") || len(f.reviewed) != 3 {
				t.Fatalf("out=%s, answers=%v, err=%v", out, f.reviewed, err)
			}
			if a := f.reviewed[0]; a.Id != "configure" || a.Revision != "2" ||
				a.Answer.GetBoolValue() != tc.configured {
				t.Fatal(a)
			}
			if a := f.reviewed[1]; a.Id != "engine" || a.Revision != "4" ||
				a.Answer.GetStringValue() != tc.engine {
				t.Fatal(a)
			}
			if a := f.reviewed[2]; a.Id != "features" || a.Revision != "1" ||
				len(a.Answer.GetListValue().Values) != 2 {
				t.Fatal(a)
			}
			calls := []string{"install:external/cache@", "preview:cache", "preview:cache"}
			if tc.accepted {
				calls = append(calls, "enable:cache", "reconcile")
				if !slices.EqualFunc(
					f.reviewed,
					f.committed,
					func(a, b *agentv1.ModuleAdoptionAnswer) bool { return proto.Equal(a, b) },
				) {
					t.Fatal("commit does not match reviewed answers")
				}
			} else if len(f.committed) != 0 {
				t.Fatal("cancelled answers were committed")
			}
			if !slices.Equal(f.calls, calls) {
				t.Fatalf("operations: %v", f.calls)
			}
		})
	}
	f := &moduleFixture{offers: offers}
	if _, _, err := f.invoke(
		t,
		"",
		"enable",
		"cache",
		"--yes",
	); err != nil || len(f.committed) != 0 ||
		!slices.Equal(f.calls, []string{"preview:cache", "enable:cache", "reconcile"}) {
		t.Fatalf("--yes alone must enable only: %v, %v", f.calls, err)
	}
}
