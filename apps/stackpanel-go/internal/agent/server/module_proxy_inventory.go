package server

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

var (
	errModuleProxyConflict  = errors.New("port claimed by another service")
	errModuleProxyInventory = errors.New(
		"service inventory unavailable; re-enter registered projects' dev shells",
	)
)

// Never evaluate another project's flake, start its runtime, or use the
// agent's own shell environment. For other projects, use only the immutable
// port projection installed by their last applied dev shell.
func moduleProxyCheckPort(
	root, service string,
	port int,
	state map[string]any,
	store string,
) error {
	services, ok := state["services"].(map[string]any)
	if !ok {
		return errModuleProxyInventory
	}
	for name, entry := range services {
		if name == service {
			continue
		}
		svc, _ := entry.(map[string]any)
		enabled, ok := svc["enable"].(bool)
		if !ok {
			return errModuleProxyInventory
		}
		if !enabled {
			continue
		}
		proxy, _ := svc["proxy"].(map[string]any)
		if svc["port"] == float64(port) ||
			proxy["enable"] == true && proxy["port"] == float64(port) {
			return errModuleProxyConflict
		}
	}
	registry, err := userconfig.NewManager()
	if err != nil {
		return errModuleProxyInventory
	}
	selected := false
	for _, project := range registry.ListProjects() {
		if project.Path == root {
			if selected {
				return errModuleProxyInventory
			}
			selected = true
			continue
		}
		ports, err := moduleProxyAppliedPorts(project.Path, store)
		if err != nil {
			return errModuleProxyInventory
		}
		if slices.Contains(ports, port) {
			return errModuleProxyConflict
		}
	}
	if !selected {
		return errModuleProxyInventory
	}
	return nil
}

func moduleProxyAppliedPorts(root, store string) ([]int, error) {
	const name = "module-proxy-ports.json"
	if !filepath.IsAbs(root) {
		return nil, errModuleProxyInventory
	}
	profile := root
	for _, component := range []string{".stack", "profile"} {
		profile = filepath.Join(profile, component)
		info, err := os.Lstat(profile)
		if err != nil || !info.IsDir() {
			return nil, errModuleProxyInventory
		}
	}
	target, err := os.Readlink(filepath.Join(profile, name))
	if err != nil || !validModulePackage(target, store) ||
		!strings.HasSuffix(target, "-stackpanel-"+name) {
		return nil, errModuleProxyInventory
	}
	info, err := os.Lstat(target)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o222 != 0 ||
		info.Size() > 1<<20 {
		return nil, errModuleProxyInventory
	}
	data, err := os.ReadFile(target)
	if err != nil {
		return nil, errModuleProxyInventory
	}
	var index struct {
		SchemaVersion int   `json:"schemaVersion"`
		Ports         []int `json:"ports"`
	}
	if json.Unmarshal(data, &index) != nil || index.SchemaVersion != 1 ||
		index.Ports == nil {
		return nil, errModuleProxyInventory
	}
	for _, port := range index.Ports {
		if port < 1 || port > 65535 {
			return nil, errModuleProxyInventory
		}
	}
	return index.Ports, nil
}
