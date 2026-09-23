package reconcile

import (
	"fmt"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Answer is the resolved response to an addon question. Only the field
// matching the question type is meaningful.
type Answer struct {
	Bool   bool
	Select string
	Multi  []string
}

// Record is the value persisted in the ledger for an answer.
func (a Answer) Record(q nixeval.AddonQuestion) any {
	switch q.Type {
	case "bool":
		return a.Bool
	case "select":
		return a.Select
	case "multiselect":
		if a.Multi == nil {
			return []string{}
		}
		return a.Multi
	}
	return nil
}

// AnswerInputs are the non-interactive sources for answers plus an optional
// prompt used when nothing else decides.
type AnswerInputs struct {
	With    []string // --with <id>: accept
	Without []string // --without <id>: decline
	Values  []string // --addon <id>=<value>: explicit
	// Prompt asks the user; nil means non-interactive (fall back to defaults).
	Prompt func(nixeval.AddonSpec) (Answer, error)
}

// ResolveAnswer determines the answer for an addon, in priority order:
// explicit --addon id=value, then --with/--without, then the prompt, then the
// question's declared default.
func ResolveAnswer(in AnswerInputs, a nixeval.AddonSpec) (Answer, error) {
	q := a.Question

	if raw, ok := explicitValue(in.Values, a.ID); ok {
		return ParseAnswer(q.Type, raw), nil
	}
	if containsFold(in.Without, a.ID) {
		return Answer{}, nil
	}
	if containsFold(in.With, a.ID) {
		switch q.Type {
		case "bool":
			return Answer{Bool: true}, nil
		case "select":
			return Answer{Select: DefaultSelect(q)}, nil
		case "multiselect":
			return Answer{Multi: AllChoiceValues(q)}, nil
		}
	}
	if in.Prompt != nil {
		return in.Prompt(a)
	}
	return DefaultAnswer(q), nil
}

// DefaultAnswer is the question's declared default.
func DefaultAnswer(q nixeval.AddonQuestion) Answer {
	switch q.Type {
	case "bool":
		b, _ := q.Default.(bool)
		return Answer{Bool: b}
	case "select":
		return Answer{Select: DefaultSelect(q)}
	case "multiselect":
		return Answer{Multi: DefaultMulti(q)}
	}
	return Answer{}
}

// ParseAnswer interprets an --addon id=value string for a question type.
func ParseAnswer(qType, raw string) Answer {
	switch qType {
	case "bool":
		v := strings.EqualFold(raw, "true") || raw == "1" || strings.EqualFold(raw, "yes")
		return Answer{Bool: v}
	case "multiselect":
		var vals []string
		for _, part := range strings.Split(raw, ",") {
			part = strings.TrimSpace(part)
			if part != "" {
				vals = append(vals, part)
			}
		}
		return Answer{Multi: vals}
	default: // select
		return Answer{Select: strings.TrimSpace(raw)}
	}
}

// Mutation is a single dot-path assignment into .stack/config.nix, relative
// to the stackpanel config root (e.g. "modules.playwright.enable" = true).
type Mutation struct {
	Path  string
	Value any
}

// Materialize turns an answer into config mutations. active reports whether
// the answer contributes anything (selecting a "none" choice is recorded but
// not applied). There is no files payload: installation belongs to modules.
func Materialize(a nixeval.AddonSpec, ans Answer) (mutations []Mutation, active bool) {
	q := a.Question
	switch q.Type {
	case "bool":
		if !ans.Bool {
			return nil, false
		}
		mutations = FlattenConfig("", a.Config)
	case "select":
		ch, ok := FindChoice(q, ans.Select)
		if !ok || ans.Select == "" {
			return nil, false
		}
		mutations = append(FlattenConfig("", a.Config), FlattenConfig("", ch.Config)...)
	case "multiselect":
		if len(ans.Multi) == 0 {
			return nil, false
		}
		mutations = FlattenConfig("", a.Config)
		for _, v := range ans.Multi {
			if ch, ok := FindChoice(q, v); ok {
				mutations = append(mutations, FlattenConfig("", ch.Config)...)
			}
		}
	}
	return mutations, len(mutations) > 0
}

// FlattenConfig turns a nested config attrset into leaf dot-paths. Map values
// are descended into; everything else (scalars, lists) is a leaf. Keys are
// sorted for deterministic patch ordering.
func FlattenConfig(prefix string, m map[string]any) []Mutation {
	if len(m) == 0 {
		return nil
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var out []Mutation
	for _, k := range keys {
		path := k
		if prefix != "" {
			path = prefix + "." + k
		}
		if child, ok := m[k].(map[string]any); ok {
			out = append(out, FlattenConfig(path, child)...)
			continue
		}
		out = append(out, Mutation{Path: path, Value: m[k]})
	}
	return out
}

// Overlay rebuilds a nested attrset from mutations, for the speculative
// evaluation (`stackpanel = <overlay>`). Later mutations win on conflict.
func Overlay(mutations []Mutation) map[string]any {
	root := map[string]any{}
	for _, m := range mutations {
		parts := strings.Split(m.Path, ".")
		node := root
		for _, p := range parts[:len(parts)-1] {
			child, ok := node[p].(map[string]any)
			if !ok {
				child = map[string]any{}
				node[p] = child
			}
			node = child
		}
		node[parts[len(parts)-1]] = m.Value
	}
	return root
}

// DescribeMutations renders mutations as `path = value` lines for the plan.
func DescribeMutations(mutations []Mutation) []string {
	out := make([]string, 0, len(mutations))
	for _, m := range mutations {
		out = append(out, fmt.Sprintf("%s = %v", m.Path, m.Value))
	}
	return out
}

// RevisionsOf indexes addons by id -> revision (for ledger migration).
func RevisionsOf(addons []nixeval.AddonSpec) map[string]int {
	out := make(map[string]int, len(addons))
	for _, a := range addons {
		out[a.ID] = a.Revision
	}
	return out
}

// PendingOffers filters addons to those the ledger says should be offered.
func PendingOffers(
	addons []nixeval.AddonSpec,
	ledger *Ledger,
	reconsider bool,
) []Offer {
	var offers []Offer
	for _, a := range addons {
		ok, reason := ledger.ShouldOffer(a.ID, a.Revision, reconsider)
		if !ok {
			continue
		}
		offers = append(offers, Offer{
			ID:          a.ID,
			Revision:    a.Revision,
			Label:       a.Question.Label,
			Description: a.Question.Description,
			Module:      a.Module,
			Reason:      reason,
		})
	}
	return offers
}

func explicitValue(pairs []string, id string) (string, bool) {
	for _, p := range pairs {
		idx := strings.IndexByte(p, '=')
		if idx < 0 {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(p[:idx]), id) {
			return strings.TrimSpace(p[idx+1:]), true
		}
	}
	return "", false
}

func containsFold(list []string, target string) bool {
	for _, s := range list {
		if strings.EqualFold(strings.TrimSpace(s), target) {
			return true
		}
	}
	return false
}

// DefaultSelect is the default choice value of a select question.
func DefaultSelect(q nixeval.AddonQuestion) string {
	if s, ok := q.Default.(string); ok {
		return s
	}
	return ""
}

// DefaultMulti is the default choice list of a multiselect question.
func DefaultMulti(q nixeval.AddonQuestion) []string {
	arr, ok := q.Default.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

// AllChoiceValues lists every choice value (used by --with on multiselects).
func AllChoiceValues(q nixeval.AddonQuestion) []string {
	out := make([]string, 0, len(q.Choices))
	for _, c := range q.Choices {
		out = append(out, c.Value)
	}
	return out
}

// ChoiceLabels returns the display labels and a label->value lookup. A choice
// with no label falls back to its value.
func ChoiceLabels(
	q nixeval.AddonQuestion,
) (labels []string, byLabel map[string]string) {
	byLabel = make(map[string]string, len(q.Choices))
	for _, c := range q.Choices {
		label := c.Label
		if label == "" {
			label = c.Value
		}
		labels = append(labels, label)
		byLabel[label] = c.Value
	}
	return labels, byLabel
}

// LabelForValue finds the label of a choice value.
func LabelForValue(q nixeval.AddonQuestion, value string) string {
	for _, c := range q.Choices {
		if c.Value == value {
			if c.Label != "" {
				return c.Label
			}
			return c.Value
		}
	}
	return ""
}

// FindChoice looks up a choice by value.
func FindChoice(q nixeval.AddonQuestion, value string) (nixeval.AddonChoice, bool) {
	for _, c := range q.Choices {
		if c.Value == value {
			return c, true
		}
	}
	return nixeval.AddonChoice{}, false
}
