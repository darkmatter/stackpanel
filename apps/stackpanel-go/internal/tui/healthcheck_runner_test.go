package tui

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
)

func TestHealthcheckScriptCancellationAndInheritedPipes(t *testing.T) {
	for _, earlyExit := range []bool{false, true} {
		t.Run(strconv.FormatBool(earlyExit), func(t *testing.T) {
			root := t.TempDir()
			pidPath, script := filepath.Join(root, "pid"), filepath.Join(root, "check")
			body := "#!/bin/sh\necho $$ > '" + pidPath + "'\nsleep 30 &\n"
			if !earlyExit {
				body += "wait\n"
			}
			if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			t.Cleanup(func() {
				data, _ := os.ReadFile(pidPath)
				if pid, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
					_ = syscall.Kill(-pid, syscall.SIGKILL)
				}
			})
			done := make(chan []HealthcheckResult, 1)
			go func() {
				done <- RunHealthchecksContext(ctx, []nixconfig.Healthcheck{{ID: "slow-script", Enabled: true, Type: "HEALTHCHECK_TYPE_SCRIPT", ScriptPath: &script, Timeout: 30}}, nil)
			}()
			deadline := time.Now().Add(2 * time.Second)
			for {
				if _, err := os.Stat(pidPath); err == nil {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("check never started")
				}
				time.Sleep(10 * time.Millisecond)
			}
			if !earlyExit {
				cancel()
			}
			select {
			case results := <-done:
				if len(results) != 1 || results[0].Status != "fail" {
					t.Fatalf("expected failed check, got %+v", results)
				}
				if !earlyExit && !strings.Contains(results[0].Message, "canceled") {
					t.Fatalf("cancellation was lost: %+v", results)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("doctor hung waiting for a descendant's output pipe")
			}
		})
	}
}

func TestHealthcheckHTTPUsesCallerCancellation(t *testing.T) {
	started := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, request *http.Request) {
		close(started)
		<-request.Context().Done()
	}))
	defer server.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan []HealthcheckResult, 1)
	go func() {
		done <- RunHealthchecksContext(ctx, []nixconfig.Healthcheck{{ID: "slow-http", Enabled: true, Type: "HEALTHCHECK_TYPE_HTTP", HTTPUrl: &server.URL, HTTPMethod: "GET", Timeout: 30}}, nil)
	}()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("HTTP check never started")
	}
	cancel()
	select {
	case results := <-done:
		if len(results) != 1 || results[0].Status != "fail" || !strings.Contains(results[0].Message, "canceled") {
			t.Fatalf("HTTP cancellation was lost: %+v", results)
		}
	case <-time.After(time.Second):
		t.Fatal("HTTP check ignored doctor cancellation")
	}
}
