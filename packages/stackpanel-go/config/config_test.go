package config

import (
	"strings"
	"testing"
)

func TestLoadFromReader(t *testing.T) {
	json := `{"version":1,"projectName":"demo","projectRoot":"/tmp","basePort":6400,"paths":{"state":".stackpanel/state","gen":".stackpanel/gen","data":".stackpanel"},"apps":{},"services":{},"network":{"step":{"enable":false}}}`
	cfg, err := LoadFromReader(strings.NewReader(json))
	if err != nil {
		t.Fatalf("LoadFromReader returned error: %v", err)
	}
	if cfg.ProjectName != "demo" || cfg.BasePort != 6400 {
		t.Fatalf("unexpected config parsed: %+v", cfg)
	}
}
