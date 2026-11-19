package userconfig

import (
	"fmt"
	"maps"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// LinkedModule is local to a single consumer. The map key is its flake input name.
type LinkedModule struct {
	Path     string `yaml:"path" json:"path"`
	UIDevURL string `yaml:"uiDevUrl,omitempty" json:"uiDevUrl,omitempty"`
}

var moduleID = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_-]*$`)

func ValidModuleID(id string) bool { return moduleID.MatchString(id) }

// ValidateUIDevURL accepts an optional absolute HTTP(S) URL to a literal
// loopback host. No DNS resolution: arbitrary names can be rebound after link.
func ValidateUIDevURL(raw string) error {
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.User == nil &&
		u.Host != "" && !strings.ContainsAny(raw, "?#\\\r\n\t") {
		host := u.Hostname()
		ip, _ := netip.ParseAddr(host)
		if port := u.Port(); port != "" {
			n, err := strconv.ParseUint(port, 10, 16)
			if err != nil || n == 0 {
				return fmt.Errorf("ui-dev-url has invalid port")
			}
		}
		if strings.EqualFold(host, "localhost") || (ip.IsLoopback() && ip.Zone() == "") {
			return nil
		}
	}
	return fmt.Errorf(
		"ui-dev-url must use HTTP(S) on a loopback host, without credentials, query, or fragment",
	)
}

// projectPath requires an explicit consumer root. Never select a project by
// basename, the active/default project, or the working directory here.
func projectPath(root string) (string, error) {
	if root == "" {
		return "", fmt.Errorf("project root is required")
	}
	return filepath.Abs(root)
}

func (l LinkedModule) validate(id string) error {
	if !ValidModuleID(id) {
		return fmt.Errorf("invalid flake input name %q", id)
	}
	if !filepath.IsAbs(l.Path) {
		return fmt.Errorf("linked module %s needs an absolute path", id)
	}
	return ValidateUIDevURL(l.UIDevURL)
}

// SetLinkedModule records an override without modifying the project flake or
// selecting a new active/default project. Resolve relative author paths once,
// here at the CLI boundary, never in an unrelated agent's working directory.
func (m *Manager) SetLinkedModule(root, id string, link LinkedModule) error {
	root, err := projectPath(root)
	if err != nil {
		return err
	}
	if link.Path == "" {
		return fmt.Errorf("linked module path is required")
	}
	link.Path, err = filepath.Abs(link.Path)
	if err != nil {
		return err
	}
	link.Path, err = filepath.EvalSymlinks(link.Path)
	if err != nil {
		return err
	}
	if err := link.validate(id); err != nil {
		return err
	}
	for _, dir := range []string{root, link.Path} {
		if info, err := os.Stat(
			filepath.Join(dir, "flake.nix"),
		); err != nil ||
			!info.Mode().IsRegular() {
			return fmt.Errorf("no flake.nix in %s", dir)
		}
	}
	return m.update(func(c *UserConfig) error {
		p := ensureProject(c, root)
		if p.LinkedModules == nil {
			p.LinkedModules = make(map[string]LinkedModule)
		}
		p.LinkedModules[id] = link
		return nil
	})
}

func (m *Manager) UnlinkModule(root, id string) error {
	root, err := projectPath(root)
	if err != nil {
		return err
	}
	return m.update(func(c *UserConfig) error {
		for i := range c.Projects {
			p := &c.Projects[i]
			if p.Path == root {
				if _, ok := p.LinkedModules[id]; ok {
					delete(p.LinkedModules, id)
					return nil
				}
			}
		}
		return fmt.Errorf("module %q is not linked in %s", id, root)
	})
}

// LoadLinkedModules reads a fresh snapshot on each eval. A malformed link is
// an error, not permission to silently evaluate a different (locked) input.
func LoadLinkedModules(root string) (map[string]LinkedModule, error) {
	root, err := projectPath(root)
	if err != nil {
		return nil, err
	}
	m, err := NewManager()
	if err != nil {
		return nil, err
	}
	if p := m.GetProject(root); p != nil {
		for id, link := range p.LinkedModules {
			if err := link.validate(id); err != nil {
				return nil, fmt.Errorf("linkedModules.%s: %w", id, err)
			}
		}
		return p.LinkedModules, nil
	}
	return nil, nil
}

// LinkedModules is a fail-closed convenience for UI metadata. Evaluation must
// use LoadLinkedModules to report malformed machine configuration to the author.
func LinkedModules(root string) map[string]LinkedModule {
	links, _ := LoadLinkedModules(root)
	return links
}

func (m *Manager) RegistrySources() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return slices.Clone(m.config.Registries)
}

// RegistryHeaders returns only machine-authorized credentials for sources in
// this user's ordered registry list; never inherit credentials via URL prefix.
func (m *Manager) RegistryHeaders() map[string]map[string]string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	h := make(map[string]map[string]string)
	for _, source := range m.config.Registries {
		if headers := m.config.RegistryHeaders[source]; len(headers) != 0 {
			h[source] = maps.Clone(headers)
		}
	}
	return h
}
