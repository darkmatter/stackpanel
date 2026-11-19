package server

import (
	"maps"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/registry"
)

// authorizeDependencyUpdates supplies catalog evidence, not permission to edit
// an arbitrary matching URL. The editor must independently verify its marker
// and the complete live declaration. Without proof, normal add/reuse rules apply.
func (op registryOperation) authorizeDependencyUpdates(
	previous *registry.Version,
	deps []flakeedit.FlakeInput,
) error {
	for i := range deps {
		deps[i].PreviousDependency = nil
	}
	if previous == nil || len(deps) == 0 {
		return nil
	}

	lock, module := op.view.lock, op.module
	input, exists, err := lock.input(module.Slug)
	if err != nil || !exists {
		return err
	}
	// installedRelease can choose a representative for import removal even
	// when the pin is custom or ambiguous. That isn't dependency ownership.
	var prior *registry.Version
	for i := range module.Versions {
		v := &module.Versions[i]
		if input.matchesPin(v.FlakeURL, v.Ref, v.Rev) {
			if prior != nil {
				return nil
			}
			prior = v
		}
	}
	if prior == nil || prior.Version != previous.Version || len(prior.FlakeInputs) == 0 {
		return nil
	}
	available := make(map[string]*registry.FlakeInput, len(prior.FlakeInputs))
	for i := range prior.FlakeInputs {
		d := &prior.FlakeInputs[i]
		available[d.Name] = d
	}

	// Catalog consumers need not appear as lock edges: a module can use the
	// project's inputs at evaluation time. A possible consumer is enough to
	// withhold authorization, even if its requested pin differs from ours.
	for i := range op.view.modules {
		other := &op.view.modules[i]
		if other.Slug == module.Slug {
			continue
		}
		n, exists, err := lock.input(other.Slug)
		if err != nil {
			return err
		}
		if !exists {
			continue
		}
		for _, v := range installedCandidates(n, other) {
			delete(available, other.Slug)
			if v.FollowsNixpkgs {
				delete(available, "nixpkgs")
			}
			for i := range v.FlakeInputs {
				d := &v.FlakeInputs[i]
				delete(available, d.Name)
				if d.FollowsNixpkgs {
					delete(available, "nixpkgs")
				}
			}
		}
		if len(available) == 0 {
			return nil
		}
	}

	for i := range deps {
		d := available[deps[i].Name]
		if d == nil {
			continue
		}
		n, exists, err := lock.input(d.Name)
		if err != nil {
			return err
		}
		if exists && n.matchesPin(d.URL, d.Ref, "") &&
			lock.exclusiveDependency(module.Slug, d.Name) {
			deps[i].PreviousDependency = &flakeedit.FlakeInput{
				Name: d.Name, URL: d.URL, Ref: d.Ref, FollowsNixpkgs: d.FollowsNixpkgs,
			}
		}
	}
	return nil
}

func (l *registryLock) exclusiveDependency(owner, dep string) bool {
	depKey, direct := l.root.inputs[dep].(string)
	if !direct || l.root.inputs[owner] == depKey {
		return false
	}

	// Don't mistake the module following its own dependency, or a nested
	// input following [dep, child], for a second consumer. Direct edges
	// identify the nodes introduced by these two inputs. They are private
	// only if no independent input also reaches them.
	private := make(map[*registryLockNode]bool)
	var markDirect func(*registryLockNode)
	markDirect = func(n *registryLockNode) {
		if private[n] {
			return
		}
		private[n] = true
		for _, input := range n.inputs {
			if key, ok := input.(string); ok {
				markDirect(l.nodes[key])
			}
		}
	}
	markDirect(l.nodes[l.root.inputs[owner].(string)])
	markDirect(l.nodes[depKey])

	// In the validated lock, every independent edge must still resolve
	// without the dependency node. This catches aliases and follows paths
	// that pass THROUGH dep to another node, including chained follows.
	without := registryLock{root: l.root, nodes: maps.Clone(l.nodes)}
	delete(without.nodes, depKey)
	resolved := make(map[registryLockEdge]*registryLockNode)
	checked := make(map[*registryLockNode]bool)
	var independent func(*registryLockNode) bool
	independent = func(n *registryLockNode) bool {
		if checked[n] {
			return true
		}
		checked[n] = true
		for name := range n.inputs {
			if n == l.root && (name == owner || name == dep) {
				continue
			}
			child, err := without.resolve(n, name, resolved)
			if err != nil || !independent(child) {
				return false
			}
		}
		return true
	}
	for _, n := range l.nodes {
		if !private[n] && !independent(n) {
			return false
		}
	}
	return true
}
