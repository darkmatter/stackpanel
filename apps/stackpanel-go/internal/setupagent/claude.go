package setupagent

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func claudeProtectedTools(req RunRequest) ([]string, error) {
	if len(req.ProtectedPaths) == 0 {
		return nil, nil
	}
	root, err := filepath.EvalSymlinks(req.Dir)
	if err != nil {
		return nil, err
	}
	var rules []string
	seen := map[string]bool{}
	// Claude's matcher does not protect a literal ? when written as \? or [?].
	// Leave it unescaped in deny rules: overmatching is safer than permitting
	// a protected edit. Other pattern characters retain their literal meaning.
	escape := strings.NewReplacer(`\`, `\\`, `*`, `\*`, `[`, `\[`, `]`, `\]`)
	add := func(path string) {
		// Edit rules cover both Edit and Write. Absolute patterns cannot
		// become negated rules or match a different working directory.
		rule := "Edit(/" + escape.Replace(filepath.ToSlash(path)) + ")"
		if !seen[rule] {
			rules = append(rules, rule)
			seen[rule] = true
		}
	}
	for _, path := range req.ProtectedPaths {
		if !filepath.IsLocal(path) {
			return nil, fmt.Errorf("protected user path must be repository-relative: %q", path)
		}
		absolute := filepath.Join(root, path)
		add(absolute)
		resolved, err := filepath.EvalSymlinks(absolute)
		if err == nil {
			add(resolved)
		} else if !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("resolve protected user path %q: %w", path, err)
		}
	}
	return rules, nil
}
