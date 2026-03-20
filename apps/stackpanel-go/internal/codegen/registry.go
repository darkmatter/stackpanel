package codegen

import (
	"fmt"
	"sort"
)

// Registry stores the known codegen modules.
type Registry struct {
	modules map[string]Module
}

// NewRegistry creates a registry with the provided modules.
func NewRegistry(modules ...Module) *Registry {
	r := &Registry{modules: make(map[string]Module, len(modules))}
	for _, module := range modules {
		if err := r.Register(module); err != nil {
			panic(err)
		}
	}
	return r
}

// DefaultRegistry returns the built-in codegen modules.
func DefaultRegistry() *Registry {
	return NewRegistry(
		NewManifestModule(),
		NewEnvModule(),
	)
}

// Register adds a module to the registry.
func (r *Registry) Register(module Module) error {
	if module == nil {
		return fmt.Errorf("codegen: cannot register a nil module")
	}

	name := module.Name()
	if name == "" {
		return fmt.Errorf("codegen: module name cannot be empty")
	}
	if _, exists := r.modules[name]; exists {
		return fmt.Errorf("codegen: module %q is already registered", name)
	}

	r.modules[name] = module
	return nil
}

// Lookup returns a registered module by name.
func (r *Registry) Lookup(name string) (Module, bool) {
	module, ok := r.modules[name]
	return module, ok
}

// Modules returns all registered modules sorted by name.
func (r *Registry) Modules() []Module {
	names := make([]string, 0, len(r.modules))
	for name := range r.modules {
		names = append(names, name)
	}
	sort.Strings(names)

	modules := make([]Module, 0, len(names))
	for _, name := range names {
		modules = append(modules, r.modules[name])
	}
	return modules
}

// ModuleInfos returns the sorted module metadata.
func (r *Registry) ModuleInfos() []ModuleInfo {
	modules := r.Modules()
	infos := make([]ModuleInfo, 0, len(modules))
	for _, module := range modules {
		infos = append(infos, ModuleInfo{
			Name:        module.Name(),
			Description: module.Description(),
		})
	}
	return infos
}
