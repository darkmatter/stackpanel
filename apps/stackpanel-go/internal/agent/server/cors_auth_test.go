package server

import (
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/agent/config"
)

func TestIsOriginAllowed(t *testing.T) {
	tests := []struct {
		name           string
		origin         string
		allowedOrigins []string
		want           bool
	}{
		// Loopback
		{name: "http localhost", origin: "http://localhost:3000", want: true},
		{name: "https 127.0.0.1", origin: "https://127.0.0.1", want: true},
		{name: "ipv6 loopback", origin: "http://[::1]:8080", want: true},
		{name: "caddy myapp.localhost", origin: "https://myapp.localhost", want: true},

		// Tailscale
		{name: "tailscale", origin: "https://laptop.tail-scale.ts.net", want: true},

		// local.stackpanel.* always-on
		{name: "local.stackpanel.com", origin: "https://local.stackpanel.com", want: true},
		{name: "local.stackpanel.dev", origin: "https://local.stackpanel.dev", want: true},
		{name: "local.stackpanel.com with port", origin: "https://local.stackpanel.com:8443", want: true},

		// Spoof guards on the local.stackpanel.* match
		{name: "http local.stackpanel.com rejected", origin: "http://local.stackpanel.com", want: false},
		{name: "subdomain spoof rejected", origin: "https://local.stackpanel.com.evil.example", want: false},
		{name: "deeper subdomain rejected", origin: "https://x.local.stackpanel.com", want: false},
		{name: "prefix-only spoof rejected", origin: "https://local.stackpanel.evil.example", want: false},

		// Default hosted UI
		{name: "stackpanel.com", origin: "https://stackpanel.com", want: true},
		{name: "stackpanel.dev", origin: "https://stackpanel.dev", want: true},

		// Random untrusted origins
		{name: "evil.example", origin: "https://evil.example", want: false},
		{name: "stackpanel.com sub", origin: "https://app.stackpanel.com", want: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := &Server{config: &config.Config{AllowedOrigins: tc.allowedOrigins}}
			if got := s.isOriginAllowed(tc.origin); got != tc.want {
				t.Errorf("isOriginAllowed(%q) = %v, want %v", tc.origin, got, tc.want)
			}
		})
	}
}

// TestIsOriginAllowed_LocalStackpanelBypassesAllowlist verifies that configuring
// AllowedOrigins for some other tooling does NOT disable the default
// local.stackpanel.* bridge origin.
func TestIsOriginAllowed_LocalStackpanelBypassesAllowlist(t *testing.T) {
	s := &Server{config: &config.Config{
		AllowedOrigins: []string{"https://internal-tool.example"},
	}}

	if !s.isOriginAllowed("https://local.stackpanel.com") {
		t.Errorf("expected https://local.stackpanel.com to remain allowed when AllowedOrigins is set")
	}
	if !s.isOriginAllowed("https://internal-tool.example") {
		t.Errorf("expected configured origin to be allowed")
	}
	if s.isOriginAllowed("https://stackpanel.com") {
		t.Errorf("expected hosted default to be disabled when AllowedOrigins is set")
	}
}
