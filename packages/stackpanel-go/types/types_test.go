package types

import "testing"

func TestConfigHelpers(t *testing.T) {
	cfg := &Config{
		Apps: map[string]App{
			"web": {Port: 3000},
		},
		Services: map[string]Service{
			"postgres": {Port: 5432},
		},
	}

	if cfg.GetApp("web") == nil {
		t.Fatalf("expected web app to be present")
	}
	if port := cfg.GetAppPort("web"); port != 3000 {
		t.Fatalf("expected app port 3000, got %d", port)
	}

	if cfg.GetService("postgres") == nil {
		t.Fatalf("expected postgres service to be present")
	}
	if port := cfg.GetServicePort("postgres"); port != 5432 {
		t.Fatalf("expected service port 5432, got %d", port)
	}

	if len(cfg.AppNames()) != 1 || cfg.AppNames()[0] != "web" {
		t.Fatalf("unexpected app names: %v", cfg.AppNames())
	}
	if len(cfg.ServiceNames()) != 1 || cfg.ServiceNames()[0] != "postgres" {
		t.Fatalf("unexpected service names: %v", cfg.ServiceNames())
	}
}
