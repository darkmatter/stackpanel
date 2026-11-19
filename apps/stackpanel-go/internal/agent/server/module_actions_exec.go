package server

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"

	"connectrpc.com/connect"
	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/transform"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
)

const maxModuleActionJSON = 1 << 20

func execModuleAction(
	ctx context.Context,
	root, executable, profileBin, mode string,
	stdin []byte,
	send func(*agentv1.RunModuleActionResponse) error,
) error {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	cmd := exec.CommandContext(ctx, executable)
	cmd.Dir = root
	cmd.Stdin = bytes.NewReader(stdin)
	if profileBin == "" {
		profileBin = os.DevNull // not "" (some shells treat empty PATH entries as the cwd)
	}
	cmd.Env = []string{
		"PATH=" + profileBin,
		"STACKPANEL_ROOT=" + root,
		"STACKPANEL_ACTION=1",
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.WaitDelay = time.Second // bound stdin teardown if a descendant retained its read end
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		_ = stdout.Close()
		if childEnd, ok := cmd.Stdout.(io.Closer); ok {
			_ = childEnd.Close()
		}
		return err
	}
	cmd.Cancel = func() error {
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		// Even a process that detached and retained a write fd cannot wedge
		// the handler after its client has left.
		_ = stdout.Close()
		_ = stderr.Close()
		if errors.Is(err, syscall.ESRCH) {
			return os.ErrProcessDone
		}
		return err
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start module action: %w", err)
	}

	var mu sync.Mutex // a Connect stream must have only one sender at a time
	drain := func(r io.Reader, stderr bool) {
		err := streamModuleActionText(r, func(text string) error {
			mu.Lock()
			defer mu.Unlock()
			if err := context.Cause(ctx); err != nil {
				return err
			}
			msg := &agentv1.RunModuleActionResponse{}
			if stderr {
				msg.Event = &agentv1.RunModuleActionResponse_Stderr{Stderr: text}
			} else {
				msg.Event = &agentv1.RunModuleActionResponse_Stdout{Stdout: text}
			}
			return send(msg)
		})
		if err != nil {
			cancel(err)
		}
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		drain(stderr, true)
	}()
	var data []byte
	if mode == "json" {
		data, err = io.ReadAll(io.LimitReader(stdout, maxModuleActionJSON+1))
		if err != nil {
			cancel(err)
		} else if len(data) > maxModuleActionJSON {
			cancel(
				connect.NewError(
					connect.CodeResourceExhausted,
					errors.New("module action JSON exceeds 1 MiB"),
				),
			)
		}
	} else {
		drain(stdout, false)
	}
	<-done
	// Drain before reaping: Wait closes the pipes. This also keeps the
	// process group addressable if the leader exits before its children.
	err = cmd.Wait()
	if cause := context.Cause(ctx); cause != nil {
		return cause
	}
	var exit *exec.ExitError
	if err != nil && !errors.As(err, &exit) {
		return fmt.Errorf("wait for module action: %w", err)
	}
	code := cmd.ProcessState.ExitCode()
	if status, ok := cmd.ProcessState.Sys().(syscall.WaitStatus); ok &&
		status.Signaled() {
		code = 128 + int(status.Signal())
	}
	if mode == "json" && code == 0 {
		value := &structpb.Value{}
		if err := (protojson.UnmarshalOptions{RecursionLimit: 100}).Unmarshal(
			data,
			value,
		); err != nil {
			return connect.NewError(
				connect.CodeDataLoss,
				fmt.Errorf("invalid module action JSON: %w", err),
			)
		}
		if err := send(
			&agentv1.RunModuleActionResponse{
				Event: &agentv1.RunModuleActionResponse_Json{Json: value},
			},
		); err != nil {
			return err
		}
	}
	return send(
		&agentv1.RunModuleActionResponse{
			Event: &agentv1.RunModuleActionResponse_ExitCode{ExitCode: int32(code)},
		},
	)
}

type moduleActionTextSink func(string) error

func (send moduleActionTextSink) Write(p []byte) (int, error) {
	if len(p) > 0 {
		if err := send(string(p)); err != nil {
			return 0, err
		}
	}
	return len(p), nil
}

// A string oneof must contain valid UTF-8. Decode incrementally so that a
// multibyte rune split across pipe reads survives, without buffering lines.
func streamModuleActionText(r io.Reader, send moduleActionTextSink) error {
	w := transform.NewWriter(send, unicode.UTF8.NewDecoder())
	if _, err := io.Copy(w, r); err != nil {
		return err
	}
	return w.Close()
}
