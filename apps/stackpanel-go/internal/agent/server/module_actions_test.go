package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1/agentv1connect"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

type actionFixture struct {
	root, store, script, profile string
	state, module, action        map[string]any
	req                          *agentv1.RunModuleActionRequest
}

func newActionFixture(t *testing.T, program string) *actionFixture {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	store := filepath.Join(root, "store")
	script := filepath.Join(store, strings.Repeat("0", 32)+"-report", "bin", "report")
	profile := filepath.Join(store, strings.Repeat("1", 32)+"-profile")
	profileDir := filepath.Join(root, ".stack", "profile")
	for _, dir := range []string{filepath.Dir(script), filepath.Join(profile, "bin"), profileDir} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(
		script,
		[]byte("#!/bin/sh\nset -eu\n"+program+"\n"),
		0o700,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(script, filepath.Join(profile, "bin", "report")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(profile, filepath.Join(profileDir, "profile")); err != nil {
		t.Fatal(err)
	}
	action := map[string]any{
		"script":     "report",
		"argsSchema": map[string]any{"type": "object"},
		"outputMode": "stream",
	}
	module := map[string]any{
		"id":      "sample",
		"enabled": true,
		"actions": map[string]any{"run": action},
	}
	state := map[string]any{
		"modulesListAll": []any{module},
		"moduleOutputs": map[string]any{"sample": map[string]any{
			"scripts": []any{map[string]any{"name": "report", "binPath": script}},
		}},
	}
	return &actionFixture{
		root,
		store,
		script,
		profile,
		state,
		module,
		action,
		&agentv1.RunModuleActionRequest{ModuleId: "sample", ActionId: "run"},
	}
}

func (f *actionFixture) run(
	ctx context.Context,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	profileBin := moduleActionProfile(f.root, f.store, f.state)
	return runEvaluatedModuleAction(ctx, f.root, f.store, profileBin, f.state, f.req, send)
}

func TestModuleActionAttributedScript(t *testing.T) {
	f := newActionFixture(t, `
[ "$PWD" = "$STACKPANEL_ROOT" ] && [ -f selected-project ] || exit 11
[ "$#" = 0 ] && [ "$STACKPANEL_ACTION" = 1 ] || exit 12
[ -z "${STACKPANEL_AUTH_TOKEN+x}${SSH_AUTH_SOCK+x}" ] || exit 13
printf '%s\n' "$PATH" >&2
IFS= read -r args
printf '%s' "$args"
exit 7`)
	t.Setenv("STACKPANEL_AUTH_TOKEN", "must-not-leak")
	t.Setenv("SSH_AUTH_SOCK", "must-not-leak")
	// If resolution (or the child environment) consults ambient PATH this
	// executable wins instead of the attributed project script.
	t.Setenv("PATH", f.root)
	if err := os.WriteFile(
		filepath.Join(f.root, "report"),
		[]byte("#!/bin/sh\nexit 99\n"),
		0o700,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(f.root, "selected-project"),
		nil,
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	input := "'$(echo injected); \"line\n2"
	f.req.Args, _ = structpb.NewStruct(map[string]any{"text": input})
	f.action["argsSchema"] = map[string]any{
		"type": "object", "$defs": map[string]any{"text": map[string]any{"type": "string"}},
		"properties": map[string]any{"text": map[string]any{"$ref": "#/$defs/text"}},
		"required":   []any{"text"}, "additionalProperties": false,
	}
	var stdout, stderr strings.Builder
	var codes []int32
	err := f.run(t.Context(), func(msg *agentv1.RunModuleActionResponse) error {
		if len(codes) != 0 {
			t.Error("event after terminal exit code")
		}
		switch ev := msg.Event.(type) {
		case *agentv1.RunModuleActionResponse_Stdout:
			stdout.WriteString(ev.Stdout)
		case *agentv1.RunModuleActionResponse_Stderr:
			stderr.WriteString(ev.Stderr)
		case *agentv1.RunModuleActionResponse_ExitCode:
			codes = append(codes, ev.ExitCode)
		default:
			t.Errorf("unexpected event %T", ev)
		}
		return nil
	})
	var got map[string]string
	if err != nil || len(codes) != 1 || codes[0] != 7 ||
		json.Unmarshal([]byte(stdout.String()), &got) != nil ||
		got["text"] != input ||
		stderr.String() != filepath.Join(f.profile, "bin")+"\n" {
		t.Fatalf(
			"got stdout=%q stderr=%q codes=%v err=%v",
			stdout.String(),
			stderr.String(),
			codes,
			err,
		)
	}
}

func TestModuleActionDeniedBeforeExec(t *testing.T) {
	for _, tc := range []struct {
		name   string
		code   connect.Code
		change func(*testing.T, *actionFixture)
	}{
		{"disabled", connect.CodeFailedPrecondition, func(_ *testing.T, f *actionFixture) { f.module["enabled"] = false }},
		{"undeclared", connect.CodeNotFound, func(_ *testing.T, f *actionFixture) { f.req.ActionId = "report" }},
		{"cross-module", connect.CodeFailedPrecondition, func(_ *testing.T, f *actionFixture) {
			out := f.state["moduleOutputs"].(map[string]any)
			out["other"] = out["sample"]
			delete(out, "sample")
		}},
		{"relative", connect.CodeFailedPrecondition, func(_ *testing.T, f *actionFixture) { f.action["script"] = "../bin/report" }},
		{"outside-store", connect.CodeFailedPrecondition, func(_ *testing.T, f *actionFixture) { f.action["script"] = "/bin/sh" }},
		{"escaped-link", connect.CodeFailedPrecondition, func(t *testing.T, f *actionFixture) {
			path := f.script + "-link"
			if err := os.Symlink("/bin/sh", path); err != nil {
				t.Fatal(err)
			}
			f.action["script"] = path
		}},
		{"stale-profile", connect.CodeFailedPrecondition, func(t *testing.T, f *actionFixture) {
			path := filepath.Join(f.profile, "bin", "report")
			if err := os.Remove(path); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, []byte("#!/bin/sh\n: >ran"), 0o700); err != nil {
				t.Fatal(err)
			}
		}},
		{"invalid-args", connect.CodeInvalidArgument, func(_ *testing.T, f *actionFixture) {
			f.action["argsSchema"] = map[string]any{"required": []any{"text"}}
		}},
		{"external-schema", connect.CodeFailedPrecondition, func(t *testing.T, f *actionFixture) {
			path := filepath.Join(f.root, "outside.json")
			if err := os.WriteFile(path, []byte(`{"type":"object"}`), 0o600); err != nil {
				t.Fatal(err)
			}
			f.action["argsSchema"] = map[string]any{"$ref": "file://" + path}
		}},
		{"embedded-meta-ref", connect.CodeFailedPrecondition, func(_ *testing.T, f *actionFixture) {
			f.action["argsSchema"] = map[string]any{"allOf": []any{map[string]any{"$ref": "https://json-schema.org/draft/2020-12/schema"}}}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newActionFixture(t, ": >ran")
			tc.change(t, f)
			err := f.run(
				t.Context(),
				func(*agentv1.RunModuleActionResponse) error { t.Error("denied action emitted an event"); return nil },
			)
			if connect.CodeOf(err) != tc.code {
				t.Fatalf("got %v, want %v", err, tc.code)
			}
			if _, err := os.Stat(
				filepath.Join(f.root, "ran"),
			); !errors.Is(
				err,
				os.ErrNotExist,
			) {
				t.Fatalf("script was not denied: stat: %v", err)
			}
		})
	}
}

func TestModuleActionJSON(t *testing.T) {
	for _, tc := range []struct {
		name, program string
		wantErr       connect.Code
	}{
		{"valid", `printf 'diagnostic' >&2; printf '[null,true]'`, 0},
		{"malformed", `printf '{} {}'`, connect.CodeDataLoss},
		{"oversize", `printf '%01048577d' 0`, connect.CodeResourceExhausted},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newActionFixture(t, tc.program)
			f.action["outputMode"], f.action["script"] = "json", f.script
			var events []*agentv1.RunModuleActionResponse
			err := f.run(
				t.Context(),
				func(msg *agentv1.RunModuleActionResponse) error { events = append(events, msg); return nil },
			)
			if tc.wantErr != 0 {
				if connect.CodeOf(err) != tc.wantErr || len(events) != 0 {
					t.Fatalf("events=%v err=%v", events, err)
				}
				return
			}
			if err != nil || len(events) != 3 || events[0].GetStderr() != "diagnostic" {
				t.Fatalf("events=%v err=%v", events, err)
			}
			vals := events[1].GetJson().GetListValue().GetValues()
			exit, ok := events[2].Event.(*agentv1.RunModuleActionResponse_ExitCode)
			if len(vals) != 2 || !vals[1].GetBoolValue() || !ok || exit.ExitCode != 0 {
				t.Fatalf("bad JSON or terminal event: %v", events)
			}
		})
	}
}

// A held FIFO writer proves the child actually died, without relying on PID
// polling (a dead but unreaped orphan may still answer kill(pid, 0)).
func TestModuleActionCancellationKillsChild(t *testing.T) {
	f := newActionFixture(t, `(exec 9>alive; printf ready; exec sleep 10) &
exit 0`)
	sleep, err := exec.LookPath("sleep")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(sleep, filepath.Join(f.profile, "bin", "sleep")); err != nil {
		t.Fatal(err)
	}
	fifo := filepath.Join(f.root, "alive")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	fd, err := syscall.Open(
		fifo,
		syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC,
		0,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(fd)
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	var ready strings.Builder
	err = f.run(ctx, func(msg *agentv1.RunModuleActionResponse) error {
		ready.WriteString(msg.GetStdout())
		if ready.String() == "ready" {
			cancel()
		}
		return nil
	})
	if !errors.Is(err, context.Canceled) || ready.String() != "ready" {
		t.Fatalf("output %q, err=%v", ready.String(), err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		n, err := syscall.Read(fd, make([]byte, 1))
		if n == 0 && err == nil {
			break
		} // EOF: last writer exited
		if !errors.Is(err, syscall.EAGAIN) || time.Now().After(deadline) {
			t.Fatalf("child retained FIFO after cancellation: n=%d err=%v", n, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// Exercise the actual generated client and RPC handler with an immutable Nix
// store fixture, without building a flake or doing network I/O. The tests
// above also run on hosts without a Nix installation.
func TestRunModuleActionConnect(t *testing.T) {
	nixStore, err := exec.LookPath("nix-store")
	if err != nil {
		t.Skip("requires a local Nix store")
	}
	f := newActionFixture(t, `printf ready
IFS= read -r ack < ack
printf diagnostic >&2
exit 4`)
	fifo := filepath.Join(f.root, "ack")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	ack, err := os.OpenFile(fifo, os.O_RDWR|syscall.O_NONBLOCK, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer ack.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, nixStore, "--add", f.script)
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	f.action["script"] = strings.TrimSpace(string(out))
	client := moduleActionTestClient(t, newUITestServer(t), f.root, f.state)
	req := connect.NewRequest(f.req)
	req.Header().Set(projectHeader, "selected")
	stream, err := client.RunModuleAction(ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	var stdout, stderr strings.Builder
	var exit *agentv1.RunModuleActionResponse_ExitCode
	for stream.Receive() {
		if exit != nil {
			t.Fatal("event after exit")
		}
		switch ev := stream.Msg().Event.(type) {
		case *agentv1.RunModuleActionResponse_Stdout:
			stdout.WriteString(ev.Stdout)
			if stdout.String() == "ready" {
				// Script cannot exit before its first output reaches the client.
				if _, err := ack.WriteString("ack\n"); err != nil {
					t.Fatal(err)
				}
			}
		case *agentv1.RunModuleActionResponse_Stderr:
			stderr.WriteString(ev.Stderr)
		case *agentv1.RunModuleActionResponse_ExitCode:
			exit = ev
		}
	}
	if err := stream.Err(); err != nil || stdout.String() != "ready" ||
		stderr.String() != "diagnostic" ||
		exit == nil ||
		exit.ExitCode != 4 {
		t.Fatalf(
			"stdout=%q stderr=%q exit=%v err=%v",
			stdout.String(),
			stderr.String(),
			exit,
			err,
		)
	}
}

func moduleActionTestClient(
	t *testing.T,
	s *Server,
	projectRoot string,
	state map[string]any,
) agentv1connect.ModuleServiceClient {
	t.Helper()
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	registry, _ := newTestRegistry()
	registry.create = func(root string) (*projectRuntime, error) {
		return &projectRuntime{
			root:            root,
			evalModuleState: func(context.Context, string) ([]byte, error) { return data, nil },
		}, nil
	}
	scope := projectInterceptor{
		runtimes: registry,
		resolve: func(id string) (string, error) {
			if id != "selected" {
				return "", errors.New("missing project header")
			}
			return projectRoot, nil
		},
	}
	mux := http.NewServeMux()
	mux.Handle(
		agentv1connect.NewModuleServiceHandler(
			&moduleService{s: s},
			connect.WithInterceptors(scope),
		),
	)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return agentv1connect.NewModuleServiceClient(srv.Client(), srv.URL)
}

func TestRunModuleActionChecksPanelGrantBeforeDispatch(t *testing.T) {
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "user.yaml"))
	s := newUITestServer(t)
	root := t.TempDir()
	for _, tc := range []struct {
		name string
		want connect.Code
	}{
		{"valid", connect.CodeInvalidArgument},
		{"tampered", connect.CodePermissionDenied},
		{"retargeted", connect.CodePermissionDenied},
		{"revoked", connect.CodePermissionDenied},
	} {
		t.Run(tc.name, func(t *testing.T) {
			state, panel, module := uiTestState()
			// Invalid arguments give dispatch a distinct observable outcome on
			// every host without requiring Nix or executing a side effect.
			action := map[string]any{
				"script":     "inspect",
				"outputMode": "stream",
				"argsSchema": map[string]any{"required": []any{"name"}},
			}
			module["actions"] = map[string]any{"inspect": action, "publish": action}
			bundle := panel["uiBundle"].(map[string]any)
			bundle["actionIds"] = []any{"inspect"}
			bundle["permissions"] = []any{"actions:run"}
			grant, err := s.issueModuleUIGrant(
				root,
				state,
				"demo",
				"inspector",
				"",
				moduleStoreRoot,
				userconfig.LinkedModule{},
			)
			if err != nil {
				t.Fatal(err)
			}
			req := connect.NewRequest(
				&agentv1.RunModuleActionRequest{ModuleId: "demo", ActionId: "inspect"},
			)
			switch tc.name {
			case "tampered":
				grant = "invalid-" + grant
			case "retargeted":
				req.Msg.ActionId = "publish"
			case "revoked":
				bundle["permissions"] = []any{}
			}
			req.Header().Set(projectHeader, "selected")
			req.Header().Set(moduleUIGrantHeader, grant)
			client := moduleActionTestClient(t, s, root, state)
			stream, err := client.RunModuleAction(t.Context(), req)
			if err == nil {
				defer stream.Close()
				if stream.Receive() {
					t.Fatal("unexpected action output")
				}
				err = stream.Err()
			}
			if connect.CodeOf(err) != tc.want {
				t.Fatalf("got %v, want %s", err, tc.want)
			}
		})
	}
}
