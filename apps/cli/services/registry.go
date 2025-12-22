package services

import (
	"strings"
	"sync"
)

// Registry holds all registered services
type Registry struct {
	mu       sync.RWMutex
	services map[string]Service
	aliases  map[string]string // alias -> canonical name
	order    []string          // insertion order for consistent iteration
}

// DefaultRegistry is the global service registry
var DefaultRegistry = NewRegistry()

// NewRegistry creates a new service registry
func NewRegistry() *Registry {
	return &Registry{
		services: make(map[string]Service),
		aliases:  make(map[string]string),
		order:    make([]string, 0),
	}
}

// Register adds a service to the registry
func (r *Registry) Register(svc Service) {
	r.mu.Lock()
	defer r.mu.Unlock()

	name := svc.Name()
	r.services[name] = svc
	r.order = append(r.order, name)

	// Register aliases
	r.aliases[name] = name
	for _, alias := range svc.Aliases() {
		r.aliases[strings.ToLower(alias)] = name
	}
}

// Get returns a service by name or alias
func (r *Registry) Get(nameOrAlias string) Service {
	r.mu.RLock()
	defer r.mu.RUnlock()

	canonical, ok := r.aliases[strings.ToLower(nameOrAlias)]
	if !ok {
		return nil
	}
	return r.services[canonical]
}

// Normalize converts an alias to canonical name
func (r *Registry) Normalize(nameOrAlias string) string {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if canonical, ok := r.aliases[strings.ToLower(nameOrAlias)]; ok {
		return canonical
	}
	return nameOrAlias
}

// All returns all services in registration order
func (r *Registry) All() []Service {
	r.mu.RLock()
	defer r.mu.RUnlock()

	result := make([]Service, 0, len(r.order))
	for _, name := range r.order {
		result = append(result, r.services[name])
	}
	return result
}

// Names returns all canonical service names in order
func (r *Registry) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()

	result := make([]string, len(r.order))
	copy(result, r.order)
	return result
}

// Has checks if a service exists
func (r *Registry) Has(nameOrAlias string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()

	_, ok := r.aliases[strings.ToLower(nameOrAlias)]
	return ok
}

// Global convenience functions using DefaultRegistry

// Register adds a service to the default registry
func Register(svc Service) {
	DefaultRegistry.Register(svc)
}

// Get returns a service from the default registry
func Get(nameOrAlias string) Service {
	return DefaultRegistry.Get(nameOrAlias)
}

// Normalize converts an alias to canonical name
func Normalize(nameOrAlias string) string {
	return DefaultRegistry.Normalize(nameOrAlias)
}

// All returns all services from the default registry
func All() []Service {
	return DefaultRegistry.All()
}

// Names returns all service names from the default registry
func Names() []string {
	return DefaultRegistry.Names()
}

// Has checks if a service exists in the default registry
func Has(nameOrAlias string) bool {
	return DefaultRegistry.Has(nameOrAlias)
}
