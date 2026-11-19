package server

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

func moduleProxyRegister(t *testing.T, roots ...string) {
	t.Helper()
	t.Setenv("STACKPANEL_USER_CONFIG", filepath.Join(t.TempDir(), "registry.yaml"))
	reg, err := userconfig.NewManager()
	if err != nil {
		t.Fatal(err)
	}
	for _, root := range roots {
		if _, err := reg.AddProject(root, ""); err != nil {
			t.Fatal(err)
		}
	}
}

func moduleProxyMarker(t *testing.T, root string) string {
	t.Helper()
	dir := filepath.Join(root, ".stack/state/proxy/demo")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "api.identity")
	if err := os.WriteFile(path, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// The actual service socket must be owned by a process distinct from the
// agent, as it would be under process-compose. The fixture relays bytes to a
// test-owned httptest handler so protocol assertions report to the parent T.
func moduleProxyManagedPort(t *testing.T, root, backend string) int {
	t.Helper()
	ln, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	fd, err := ln.File()
	if err != nil {
		t.Fatal(err)
	}
	defer fd.Close()
	marker, err := os.Open(moduleProxyMarker(t, root))
	if err != nil {
		t.Fatal(err)
	}
	defer marker.Close()
	reader, ready, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	cmd := exec.Command(os.Args[0], "-test.run=^TestModuleProxyFixtureProcess$")
	cmd.Env = append(os.Environ(), "STACKPANEL_TEST_PROXY_BACKEND="+backend)
	cmd.ExtraFiles = []*os.File{fd, ready, nil, nil, nil, nil, marker} // fd 3, 4, 9
	if err := cmd.Start(); err != nil {
		ready.Close()
		t.Fatal(err)
	}
	ready.Close()
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	_ = reader.SetReadDeadline(time.Now().Add(10 * time.Second))
	var b [1]byte
	if _, err := io.ReadFull(reader, b[:]); err != nil {
		t.Fatal(err)
	}
	return ln.Addr().(*net.TCPAddr).Port
}

func TestModuleProxyFixtureProcess(t *testing.T) {
	backend := os.Getenv("STACKPANEL_TEST_PROXY_BACKEND")
	if backend == "" {
		return
	}
	addr, err := net.ResolveTCPAddr("tcp4", backend)
	if err != nil || !addr.IP.Equal(net.IPv4(127, 0, 0, 1)) {
		t.Fatal("invalid fixture endpoint")
	}
	fd := os.NewFile(3, "listener")
	ln, err := net.FileListener(fd)
	if err != nil {
		t.Fatal(err)
	}
	fd.Close()
	ready := os.NewFile(4, "ready")
	_, _ = ready.Write([]byte{1})
	ready.Close()
	for {
		in, err := ln.Accept()
		if err != nil {
			return
		}
		go func() {
			defer in.Close()
			out, err := net.DialTimeout("tcp4", backend, time.Second)
			if err != nil {
				return
			}
			defer out.Close()
			go func() { _, _ = io.Copy(out, in); _ = out.(*net.TCPConn).CloseWrite() }()
			_, _ = io.Copy(in, out)
		}()
	}
}

func TestModuleProxyRegisteredPortConflict(t *testing.T) {
	selected, other, store := t.TempDir(), t.TempDir(), t.TempDir()
	moduleProxyRegister(t, selected, other)
	service := httptest.NewServer(
		http.HandlerFunc(
			func(http.ResponseWriter, *http.Request) { t.Error("denied service received bytes") },
		),
	)
	defer service.Close()
	port := moduleProxyManagedPort(t, other, service.Listener.Addr().String())
	state := moduleProxyTestState(port)
	// Same data shape as live Nix, after json.Unmarshal into map[string]any.
	state["services"].(map[string]any)["api"].(map[string]any)["proxy"].(map[string]any)["port"] = float64(
		port,
	)
	if err := moduleProxyCheckPort(
		selected,
		"api",
		port,
		state,
		store,
	); err != errModuleProxyInventory {
		t.Fatalf("missing inventory: %v", err)
	}
	dir := filepath.Join(other, ".stack/profile")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	for i, ports := range []string{fmt.Sprintf("[%d]", port), "[]"} {
		path := filepath.Join(
			store,
			fmt.Sprintf("%032d-stackpanel-module-proxy-ports.json", i),
		)
		if err := os.WriteFile(
			path,
			[]byte(`{"schemaVersion":1,"ports":`+ports+`}`),
			0o444,
		); err != nil {
			t.Fatal(err)
		}
		link := filepath.Join(dir, "module-proxy-ports.json")
		if i != 0 {
			if err := os.Remove(link); err != nil {
				t.Fatal(err)
			}
		}
		if err := os.Symlink(path, link); err != nil {
			t.Fatal(err)
		}
		err := moduleProxyCheckPort(selected, "api", port, state, store)
		if i == 0 && err != errModuleProxyConflict || i == 1 && err != nil {
			t.Fatalf("inventory %s: %v", ports, err)
		}
	}
	// A stale last-applied inventory may miss a collision; it still cannot
	// grant access to the unambiguously *other* project's physical listener.
	moduleProxyMarker(t, selected)
	address := fmt.Sprintf("127.0.0.1:%d", port)
	peer, err := newModuleProxyPeer(selected, "demo", "api", address)
	if err != nil {
		t.Fatal(err)
	}
	if c, err := peer.dial(context.Background(), "tcp", address); err == nil {
		c.Close()
		t.Fatal("cross-project peer accepted")
	}
}

func TestModuleProxyRejectsUnsafeMarkers(t *testing.T) {
	for _, kind := range []string{"missing", "public", "symlink", "hardlink", "directory alias"} {
		t.Run(kind, func(t *testing.T) {
			root := t.TempDir()
			path := moduleProxyMarker(t, root)
			var err error
			switch kind {
			case "missing":
				err = os.Remove(path)
			case "public":
				err = os.Chmod(path, 0o644)
			case "symlink":
				if err = os.Rename(path, path+".other"); err == nil {
					err = os.Symlink(path+".other", path)
				}
			case "hardlink":
				err = os.Link(path, path+".other")
			case "directory alias":
				dir := filepath.Dir(path)
				if err = os.Rename(dir, dir+".other"); err == nil {
					err = os.Symlink(dir+".other", dir)
				}
			}
			if err != nil {
				t.Fatal(err)
			}
			if _, err := newModuleProxyPeer(root, "demo", "api", "127.0.0.1:1"); err == nil {
				t.Fatal("unsafe marker accepted")
			}
		})
	}
}
