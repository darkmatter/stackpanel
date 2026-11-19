package flakeedit

import (
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"
)

func validIdent(s string) bool {
	switch s {
	case "if", "then", "else", "assert", "with", "let", "in", "rec", "inherit", "or":
		return false
	}
	return isValidIdentifier(s)
}

var (
	refChars    = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9./_+-]*$`)
	gitRev      = regexp.MustCompile(`^[a-fA-F0-9]{40}$`)
	repoSegment = regexp.MustCompile(`^[~A-Za-z0-9._-]+$`)
)

// gitReference holds the *source identity*, including ?dir= and ?host=,
// separately from mutable version selectors. In particular two modules from
// different subdirectories of the registry repo are NOT interchangeable.
type gitReference struct {
	base, options, ref, rev string
	forge, git              bool
}

func safeURLText(s string) bool {
	return s != "" && utf8.ValidString(s) && !strings.ContainsAny(s, "\"\\#") &&
		!strings.Contains(s, "${") &&
		strings.IndexFunc(
			s,
			func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) },
		) < 0
}

func parseReference(raw string) (gitReference, error) {
	var r gitReference
	if !safeURLText(raw) {
		return r, errors.New("unsafe or empty flake URL")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return r, errors.New("invalid flake URL")
	}
	r.base, _, _ = strings.Cut(raw, "?")
	switch u.Scheme {
	case "github", "gitlab", "sourcehut":
		r.forge = true
		parts := strings.SplitN(u.Opaque, "/", 3)
		if len(parts) < 2 || !repoSegment.MatchString(parts[0]) ||
			!repoSegment.MatchString(parts[1]) {
			return r, errors.New("expected owner/repo in flake URL")
		}
		r.base = u.Scheme + ":" + parts[0] + "/" + parts[1]
		if len(parts) > 2 {
			if gitRev.MatchString(parts[2]) {
				r.rev = parts[2]
			} else {
				r.ref = parts[2]
			}
		}
	case "git+https", "git+ssh", "git+http", "git+file", "git":
		r.git = true
	default:
		// Archive URLs can contain arbitrary query fields (including ref).
		// Never drop or reinterpret any of them to authorize a replacement.
		r.base = raw
		return r, nil
	}
	var options []string
	seen := map[string]bool{}
	if u.RawQuery != "" {
		for _, field := range strings.Split(u.RawQuery, "&") {
			key, value, ok := strings.Cut(field, "=")
			if !ok || !isValidIdentifier(key) || seen[key] {
				return r, errors.New("ambiguous flake URL query")
			}
			seen[key] = true
			v, err := url.PathUnescape(value)
			if err != nil {
				return r, errors.New("invalid flake URL escaping")
			}
			switch key {
			case "ref":
				if r.ref != "" || v == "" {
					return r, errors.New("ambiguous ref in flake URL")
				}
				r.ref = v
			case "rev":
				if r.rev != "" || v == "" {
					return r, errors.New("ambiguous rev in flake URL")
				}
				r.rev = v
			default:
				options = append(options, field)
			}
		}
	}
	if r.forge && r.rev != "" && r.ref != "" {
		return r, errors.New("forge URL cannot contain both ref and rev")
	}
	slices.Sort(options)
	r.options = strings.Join(options, "&")
	return r, r.validate()
}

func (r gitReference) validate() error {
	if r.ref != "" &&
		(!refChars.MatchString(r.ref) || strings.Contains(r.ref, "..") || strings.HasSuffix(r.ref, "/")) {
		return errors.New("invalid git ref")
	}
	if r.rev != "" && !gitRev.MatchString(r.rev) {
		return errors.New("invalid git revision (expected a full commit hash)")
	}
	return nil
}

func (r gitReference) withInput(i FlakeInput) (gitReference, error) {
	if i.Ref == "" && i.Rev == "" {
		return r, nil
	}
	if !r.git && !r.forge {
		return r, errors.New("ref/rev requires a git flake URL")
	}
	if i.Ref != "" {
		r.ref, r.rev = i.Ref, ""
	}
	if i.Rev != "" {
		r.rev = i.Rev
	}
	if err := r.validate(); err != nil {
		return r, err
	}
	if r.forge && r.rev != "" {
		// Nix forge fetchers require either ref or rev; pin the immutable rev.
		r.ref = ""
	} else if r.forge && gitRev.MatchString(r.ref) {
		r.rev, r.ref = r.ref, ""
	}
	return r, nil
}

func (r gitReference) URL() string {
	base := r.base
	opts := r.options
	add := func(key, value string) {
		if opts != "" {
			opts += "&"
		}
		opts += key + "=" + url.PathEscape(value)
	}
	if r.forge {
		if r.rev != "" {
			base += "/" + r.rev
		} else if r.ref != "" {
			base += "/" + r.ref
		}
	} else {
		if r.ref != "" {
			add("ref", r.ref)
		}
		if r.rev != "" {
			add("rev", r.rev)
		}
	}
	if opts != "" {
		base += "?" + opts
	}
	return base
}

func targetReference(input FlakeInput) (gitReference, error) {
	if !validIdent(input.Name) || input.Name == "self" {
		return gitReference{}, fmt.Errorf("invalid flake input name %q", input.Name)
	}
	r, err := parseReference(input.URL)
	if err != nil {
		return r, err
	}
	return r.withInput(input)
}

// PinnedURL resolves the same catalog selectors used when editing flake.nix.
func (i FlakeInput) PinnedURL() (string, error) {
	r, err := targetReference(i)
	if err != nil {
		return "", err
	}
	return r.URL(), nil
}
