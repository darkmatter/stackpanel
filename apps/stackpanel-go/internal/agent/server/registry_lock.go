package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/flakeedit"
)

// Node keys are local to a lock file. Only a direct edge in the designated
// root's inputs can establish ownership of a catalog slug.
type registryLock struct {
	root  *registryLockNode
	nodes map[string]*registryLockNode
}

type registryLockNode struct {
	inputs map[string]any
	input  registryLockedInput
}

type registryLockedInput struct {
	root, name string
	original   registryReference
	lockedRev  string
}

type registryReference struct {
	source   registrySource
	ref, rev string
}

type registrySource struct {
	kind     string
	location string // forge host, full transport URL, or absolute filesystem path
	owner    string
	repo     string
	dir      string // flake subdirectory within the fetched tree
}

func readRegistryLock(root string) (*registryLock, error) {
	if root == "" {
		return nil, errors.New("cannot read flake.lock without a project root")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	path := filepath.Join(root, "flake.lock")
	info, err := os.Lstat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return &registryLock{root: &registryLockNode{}}, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("flake.lock must be a regular project file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc map[string]any
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("decode flake.lock: %w", err)
	}
	// v5 and earlier separate the lock evidence across different fields.
	if v := doc["version"]; v != float64(6) && v != float64(7) {
		return nil, errors.New("flake.lock: missing or unsupported lock file version")
	}
	rootKey, _ := doc["root"].(string)
	nodes, _ := doc["nodes"].(map[string]any)
	if rootKey == "" || nodes[rootKey] == nil {
		return nil, fmt.Errorf("flake.lock: missing root node %q", rootKey)
	}
	lock := &registryLock{nodes: make(map[string]*registryLockNode, len(nodes))}
	for key, raw := range nodes {
		fields, ok := raw.(map[string]any)
		if !ok || key == "" {
			return nil, fmt.Errorf("flake.lock: invalid node %q", key)
		}
		n := new(registryLockNode)
		if rawInputs, exists := fields["inputs"]; exists {
			if n.inputs, ok = rawInputs.(map[string]any); !ok {
				return nil, fmt.Errorf("flake.lock: node %q inputs must be an object", key)
			}
		}
		lock.nodes[key] = n
		if key == rootKey {
			_, orig := fields["original"]
			if _, locked := fields["locked"]; orig || locked {
				return nil, fmt.Errorf("flake.lock: root node %q has source attributes", key)
			}
			lock.root = n
			continue
		}
		n.input, err = registryNodeInput(root, fields)
		if err != nil {
			return nil, fmt.Errorf("flake.lock: node %q: %w", key, err)
		}
	}
	// A dangling edge anywhere in the graph invalidates it as installation
	// evidence, even when that edge isn't itself the requested module.
	seen := make(map[registryLockEdge]*registryLockNode)
	for key, n := range lock.nodes {
		for name := range n.inputs {
			if name == "" {
				return nil, fmt.Errorf("flake.lock: empty input name in node %q", key)
			}
			if _, err := lock.resolve(n, name, seen); err != nil {
				return nil, fmt.Errorf("node %q: %w", key, err)
			}
		}
	}
	return lock, nil
}

func registryNodeInput(root string, node map[string]any) (registryLockedInput, error) {
	original, err := registryAttrs(root, node["original"], false)
	if err != nil {
		return registryLockedInput{}, fmt.Errorf("original: %w", err)
	}
	locked, err := registryAttrs(root, node["locked"], true)
	if err != nil {
		return registryLockedInput{}, fmt.Errorf("locked: %w", err)
	}
	if raw, ok := node["flake"]; ok {
		flake, ok := raw.(bool)
		if !ok {
			return registryLockedInput{}, errors.New("flake must be a boolean")
		}
		if !flake {
			return registryLockedInput{}, nil
		}
	}
	if raw, ok := node["parent"]; ok {
		parent, ok := raw.([]any)
		if !ok {
			return registryLockedInput{}, errors.New("parent must be an input path")
		}
		for _, part := range parent {
			if s, ok := part.(string); !ok || s == "" {
				return registryLockedInput{}, errors.New("invalid parent input path")
			}
		}
		// Relative path inputs of another flake are not project-relative.
		if len(parent) != 0 {
			return registryLockedInput{}, nil
		}
	}
	// An override can preserve the original URL while locking a different
	// source. Neither source then proves catalog ownership of the binding.
	if original.source != locked.source {
		return registryLockedInput{}, nil
	}
	return registryLockedInput{root: root, original: original, lockedRev: locked.rev}, nil
}

// input distinguishes an unbound name from an occupied but non-matching name
// (including follows). A broken edge is never evidence that a name is free.
func (l *registryLock) input(name string) (registryLockedInput, bool, error) {
	edge, exists := l.root.inputs[name]
	if !exists {
		return registryLockedInput{}, false, nil
	}
	if _, direct := edge.(string); !direct {
		return registryLockedInput{}, true, nil // Validated follows; not a declaration.
	}
	node, err := l.resolve(l.root, name, nil)
	if err != nil {
		return registryLockedInput{}, true, err
	}
	n := node.input
	n.name = name
	return n, true, nil
}

type registryLockEdge struct {
	from *registryLockNode
	name string
}

// A follows edge contains an input-name path starting at the lock root, not
// a list of node keys. Memoize expansions; a pending edge is a follows cycle.
func (l *registryLock) resolve(
	from *registryLockNode,
	name string,
	seen map[registryLockEdge]*registryLockNode,
) (*registryLockNode, error) {
	switch edge := from.inputs[name].(type) {
	case string:
		n := l.nodes[edge]
		if n == nil || n == l.root {
			return nil, fmt.Errorf(
				"flake.lock: input %q points to invalid node %q",
				name,
				edge,
			)
		}
		return n, nil
	case []any:
		key := registryLockEdge{from, name}
		if n, ok := seen[key]; ok {
			if n == nil {
				return nil, fmt.Errorf("flake.lock: follows cycle at input %q", name)
			}
			return n, nil
		}
		if seen == nil {
			seen = make(map[registryLockEdge]*registryLockNode)
		}
		seen[key] = nil
		n := l.root
		for _, part := range edge {
			s, ok := part.(string)
			if !ok || s == "" {
				return nil, fmt.Errorf("flake.lock: malformed follows path for %q", name)
			}
			var err error
			n, err = l.resolve(n, s, seen)
			if err != nil {
				return nil, err
			}
		}
		seen[key] = n
		return n, nil
	default:
		return nil, fmt.Errorf("flake.lock: missing or invalid input binding %q", name)
	}
}

// registryAttrs recognizes only fetchers and source fields whose meaning we
// know. Additional fetcher options can change the tree (e.g. submodules or
// lfs); their presence makes a binding unmatchable, not available to install.
func registryAttrs(root string, raw any, locked bool) (registryReference, error) {
	a, _ := raw.(map[string]any)
	kind, _ := a["type"].(string)
	if kind == "" {
		return registryReference{}, errors.New("missing source type")
	}
	str := func(key string) string {
		s, _ := a[key].(string)
		return s
	}
	supported := true
	for key, val := range a {
		s, isString := val.(string)
		switch key {
		case "type":
			continue
		case "host", "owner", "repo":
			supported = supported && registryForge(kind)
		case "url":
			supported = supported && (kind == "git" || kind == "tarball")
		case "path":
			supported = supported && kind == "path"
		case "ref", "rev", "dir":
			// Projected below, after checking their types.
		case "lastModified", "revCount":
			n, ok := val.(float64)
			if !ok || n < 0 || n != float64(uint64(n)) {
				return registryReference{}, fmt.Errorf("invalid %s attribute", key)
			}
			supported = supported && locked
			continue
		case "narHash", "treeHash":
			// Locked result metadata isn't a different repository. On the
			// original input, however, these are explicit constraints.
			supported = supported && locked
		default:
			supported = false
			continue
		}
		if !isString || s == "" {
			return registryReference{}, fmt.Errorf("invalid %s attribute", key)
		}
	}
	r := registryReference{
		source: registrySource{kind: kind, dir: str("dir")},
		ref:    str("ref"),
		rev:    strings.ToLower(str("rev")),
	}
	if registryForge(kind) || kind == "git" {
		if r.rev != "" && !registryCommit(r.rev) {
			return registryReference{}, errors.New("invalid commit hash")
		}
		if locked && r.rev == "" && str("narHash") == "" {
			return registryReference{}, errors.New(
				"locked repository has neither rev nor narHash",
			)
		}
	}
	switch kind {
	case "github", "gitlab", "sourcehut":
		if r.ref != "" && r.rev != "" {
			return registryReference{}, errors.New("forge input has both ref and rev")
		}
		r.source.owner, r.source.repo = str("owner"), str("repo")
		if r.source.owner == "" || r.source.repo == "" {
			return registryReference{}, errors.New("missing forge owner or repo")
		}
		r.source.location = registryForgeHost(kind, str("host"))
		if strings.Trim(r.source.location, "abcdefghijklmnopqrstuvwxyz0123456789.-") != "" {
			return registryReference{}, errors.New("invalid forge host")
		}
	case "path":
		address := str("path")
		if address == "" {
			return registryReference{}, errors.New("missing path")
		}
		if locked && filepath.IsAbs(address) && str("narHash") == "" {
			return registryReference{}, errors.New("locked absolute path has no narHash")
		}
		r.source.location = registryLocalPath(root, address)
	case "git", "tarball":
		address := str("url")
		if address == "" {
			return registryReference{}, errors.New("missing URL")
		}
		if kind == "tarball" && locked && str("narHash") == "" {
			return registryReference{}, errors.New("locked tarball has no narHash")
		}
		u, err := url.Parse(address)
		if err != nil {
			return registryReference{}, errors.New("malformed source URL")
		}
		r.source.location = registryTransport(root, kind, u)
	default:
		supported = false
	}
	if !supported || r.source.location == "" {
		return registryReference{}, nil
	}
	return r, nil
}

func registryForge(kind string) bool {
	return kind == "github" || kind == "gitlab" || kind == "sourcehut"
}

func registryForgeHost(kind, host string) string {
	if host != "" {
		return strings.ToLower(host)
	}
	if kind == "sourcehut" {
		return "git.sr.ht"
	}
	return kind + ".com"
}

func registryLocalPath(root, p string) string {
	if p == "" || strings.ContainsRune(p, 0) {
		return ""
	}
	if !filepath.IsAbs(p) {
		return filepath.Join(root, p)
	}
	return filepath.Clean(p)
}

func registryURLPath(u *url.URL) string {
	if u.Host != "" || u.User != nil {
		return ""
	}
	// Nix filesystem URL segments cannot contain an encoded separator.
	if strings.Contains(strings.ToLower(u.RawPath), "%2f") ||
		strings.Contains(strings.ToLower(u.Opaque), "%2f") {
		return ""
	}
	if u.Opaque != "" {
		p, err := url.PathUnescape(u.Opaque)
		if err != nil {
			return ""
		}
		return p
	}
	return u.Path
}

func registryTransport(root, kind string, u *url.URL) string {
	if u.Fragment != "" || u.RawQuery != "" || u.ForceQuery {
		return ""
	}
	if kind == "git" {
		// Nix lock attributes can omit the git+ fetcher prefix.
		u.Scheme = strings.TrimPrefix(u.Scheme, "git+")
		if u.Scheme == "file" {
			if p := registryLocalPath(root, registryURLPath(u)); p != "" {
				return "file:" + p
			}
			return ""
		}
		if u.Scheme != "ssh" && u.Scheme != "https" && u.Scheme != "http" &&
			u.Scheme != "git" {
			return ""
		}
	} else if u.Scheme != "https" {
		return ""
	}
	if u.Hostname() == "" || u.Path == "" || u.Path == "/" {
		return ""
	}
	// Preserve the entire remote address, including user, port, and escaped
	// repository path. Two remotes on the same host need not be related.
	return u.String()
}

func (n registryLockedInput) catalogRef(
	flakeURL, ref, rev string,
) (registryReference, bool) {
	if n.original.source.kind == "" {
		return registryReference{}, false
	}
	// Use the editor's effective pin: forge fetchers take only a rev when
	// both selectors are specified, while a git fetcher can take both.
	input := flakeedit.FlakeInput{Name: n.name, URL: flakeURL, Ref: ref, Rev: rev}
	pinned, err := input.PinnedURL()
	if err != nil {
		return registryReference{}, false
	}
	u, err := url.Parse(pinned)
	if err != nil || u.Fragment != "" {
		return registryReference{}, false
	}
	// Nix query strings percent-decode but do not translate '+' to a space.
	q, err := url.ParseQuery(strings.ReplaceAll(u.RawQuery, "+", "%2B"))
	if err != nil {
		return registryReference{}, false
	}
	r := registryReference{source: registrySource{kind: u.Scheme}}
	for key, values := range q {
		if len(values) != 1 || values[0] == "" {
			return registryReference{}, false
		}
		value := values[0]
		switch key {
		case "dir":
			if !fs.ValidPath(value) || strings.ContainsAny(value, "\\\x00") {
				return registryReference{}, false
			}
			r.source.dir = value
		case "host":
			if !registryForge(u.Scheme) {
				return registryReference{}, false
			}
			r.source.location = value
		case "ref", "rev":
			if !strings.HasPrefix(u.Scheme, "git+") && u.Scheme != "git" {
				return registryReference{}, false
			}
			if key == "ref" {
				r.ref = value
			} else {
				r.rev = strings.ToLower(value)
			}
		default:
			return registryReference{}, false
		}
	}
	u.RawQuery, u.ForceQuery = "", false
	switch u.Scheme {
	case "github", "gitlab", "sourcehut":
		parts := strings.SplitN(u.Opaque, "/", 3)
		if len(parts) < 2 || parts[0] == "" || parts[1] == "" {
			return registryReference{}, false
		}
		r.source.owner, r.source.repo = parts[0], parts[1]
		r.source.location = registryForgeHost(u.Scheme, r.source.location)
		if len(parts) == 3 {
			if registryCommit(parts[2]) {
				r.rev = strings.ToLower(parts[2])
			} else {
				r.ref = parts[2]
			}
		}
	case "git+file", "git+http", "git+https", "git+ssh", "git":
		r.source.kind = "git"
		r.source.location = registryTransport(n.root, "git", u)
	case "https":
		r.source.kind = "tarball"
		r.source.location = registryTransport(n.root, "tarball", u)
	case "path":
		r.source.location = registryLocalPath(n.root, registryURLPath(u))
	case "":
		// Bare identifiers are indirect flake registry references, not paths.
		p, _, _ := strings.Cut(pinned, "?")
		if !filepath.IsAbs(p) && p != "." && p != ".." && !strings.HasPrefix(p, "./") &&
			!strings.HasPrefix(p, "../") {
			return registryReference{}, false
		}
		r.source.kind = "path"
		r.source.location = registryLocalPath(n.root, p)
	default:
		return registryReference{}, false
	}
	return r, r.source == n.original.source
}

func registryCommit(s string) bool {
	return len(s) == 40 && strings.Trim(s, "0123456789abcdefABCDEF") == ""
}

func (n registryLockedInput) matchesSource(flakeURL string) bool {
	_, ok := n.catalogRef(flakeURL, "", "")
	return ok
}

func (n registryLockedInput) matchesPin(flakeURL, ref, rev string) bool {
	want, ok := n.catalogRef(flakeURL, ref, rev)
	return ok && want.ref == n.original.ref && want.rev == n.original.rev &&
		(want.rev == "" || want.rev == n.lockedRev)
}
