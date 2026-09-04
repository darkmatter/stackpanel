package reconcile

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/nixconfig"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// ProjectConfig is the reconciler's view of the evaluated config JSON that the
// devshell exports as STACKPANEL_CONFIG_JSON. It reads only the keys this
// package needs; nixconfig.Config keeps the wire shape for everything else.
type ProjectConfig struct {
	Version     int    `json:"version"`
	ProjectName string `json:"projectName"`
	ProjectRoot string `json:"projectRoot"`
	Paths       struct {
		State string `json:"state"`
		Gen   string `json:"gen"`
		Data  string `json:"data"`
	} `json:"paths"`
	Doctor []DoctorCheck       `json:"doctor"`
	Addons []nixeval.AddonSpec `json:"addons"`
}

// DoctorCheck is one `stackpanel.doctor.<module>.<name>` entry across all
// scopes. Runtime and repo checks carry the detector fields; build checks
// carry the flake check name and derivation path.
type DoctorCheck struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Description        *string  `json:"description"`
	Module             string   `json:"module"`
	DisplayName        string   `json:"displayName"`
	Scope              string   `json:"scope"`    // build | runtime | repo
	Severity           string   `json:"severity"` // HEALTHCHECK_SEVERITY_*
	Type               string   `json:"type"`     // HEALTHCHECK_TYPE_*
	ScriptPath         *string  `json:"scriptPath"`
	HTTPUrl            *string  `json:"httpUrl"`
	HTTPMethod         string   `json:"httpMethod"`
	HTTPExpectedStatus int      `json:"httpExpectedStatus"`
	TCPHost            *string  `json:"tcpHost"`
	TCPPort            *int     `json:"tcpPort"`
	Timeout            int      `json:"timeout"`
	Tags               []string `json:"tags"`
	Enabled            bool     `json:"enabled"`
	FixCommand         *string  `json:"fixCommand"`
	DrvPath            *string  `json:"drvPath"`
	CheckName          *string  `json:"checkName"`
	Required           bool     `json:"required"`
}

// Healthcheck adapts a runtime/repo check onto the wire type the existing
// runner understands, so `stack doctor` and `stackpanel healthcheck` execute
// checks the same way.
func (c DoctorCheck) Healthcheck() nixconfig.Healthcheck {
	return nixconfig.Healthcheck{
		ID:                 c.ID,
		Name:               c.Name,
		Description:        c.Description,
		Module:             c.Module,
		Type:               c.Type,
		Severity:           c.Severity,
		ScriptPath:         c.ScriptPath,
		HTTPUrl:            c.HTTPUrl,
		HTTPMethod:         c.HTTPMethod,
		HTTPExpectedStatus: c.HTTPExpectedStatus,
		TCPHost:            c.TCPHost,
		TCPPort:            c.TCPPort,
		Timeout:            c.Timeout,
		Tags:               c.Tags,
		Enabled:            c.Enabled,
	}
}

// LoadProjectConfig reads STACKPANEL_CONFIG_JSON. It fails when the variable
// is unset, which callers use to detect "not inside a devshell".
func LoadProjectConfig(getenv func(string) string) (*ProjectConfig, error) {
	path := getenv("STACKPANEL_CONFIG_JSON")
	if path == "" {
		return nil, fmt.Errorf(
			"STACKPANEL_CONFIG_JSON not set - not inside a stackpanel devshell",
		)
	}
	return LoadProjectConfigFile(path, getenv("STACKPANEL_ROOT"))
}

// LoadProjectConfigFile parses a config JSON file, substituting the
// $STACKPANEL_ROOT placeholder Nix leaves in place.
func LoadProjectConfigFile(path, root string) (*ProjectConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config json: %w", err)
	}
	content := string(data)
	if root != "" {
		content = strings.ReplaceAll(content, "$STACKPANEL_ROOT", root)
	}
	var cfg ProjectConfig
	if err := json.Unmarshal([]byte(content), &cfg); err != nil {
		return nil, fmt.Errorf("parse config json: %w", err)
	}
	for i := range cfg.Addons {
		if cfg.Addons[i].Revision == 0 {
			cfg.Addons[i].Revision = 1
		}
	}
	return &cfg, nil
}
