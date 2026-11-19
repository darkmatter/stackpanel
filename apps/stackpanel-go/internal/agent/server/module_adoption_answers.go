package server

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// Resolve against the fresh enable-only snapshot, never against metadata from
// the client or a plan already modified by answers. Omitted answers stay pending.
func resolveAdoptionAnswers(
	id string,
	before, enabled []nixeval.AddonSpec,
	ledger *reconcile.Ledger,
	answers []*agentv1.ModuleAdoptionAnswer,
) (offers []*agentv1.ModuleAdoptionOffer, mutations []reconcile.Mutation, records map[string]reconcile.LedgerEntry, err error) {
	if ledger == nil || id == "" {
		return nil, nil, nil, invalidModuleState("missing module adoption context")
	}
	previous := make(map[string]int, len(before))
	for _, a := range before {
		if a.ID == "" || a.Revision < 1 || previous[a.ID] != 0 {
			return nil, nil, nil, invalidModuleState(
				"invalid or duplicate adoption offer identity before enable",
			)
		}
		previous[a.ID] = a.Revision
	}
	requested := make(map[string]*agentv1.ModuleAdoptionAnswer, len(answers))
	for _, a := range answers {
		if a.GetId() == "" || a.GetRevision() == "" || a.GetAnswer() == nil {
			return nil, nil, nil, connect.NewError(
				connect.CodeInvalidArgument,
				errors.New("adoption answer needs an offer ID, revision and answer"),
			)
		}
		if requested[a.Id] != nil {
			return nil, nil, nil, connect.NewError(
				connect.CodeInvalidArgument,
				errors.New("duplicate adoption answer"),
			)
		}
		requested[a.Id] = a
	}

	seen := make(map[string]bool, len(enabled))
	assignments := adoptionAssignments{}
	records = make(map[string]reconcile.LedgerEntry, len(answers))
	for _, a := range enabled {
		if a.ID == "" || a.Revision < 1 || seen[a.ID] {
			return nil, nil, nil, invalidModuleState(
				"invalid or duplicate adoption offer identity after enable",
			)
		}
		seen[a.ID] = true
		// A flake-level offer is not a dependency. An unrelated offer that
		// merely remained pending (or whose revision decreased) isn't one either.
		if a.Module == "" || (a.Module != id && a.Revision <= previous[a.ID]) {
			continue
		}
		pending, reason := ledger.ShouldOffer(a.ID, a.Revision, false)
		if !pending {
			if requested[a.ID] != nil {
				return nil, nil, nil, invalidModuleState("adoption offer is no longer pending")
			}
			continue
		}
		offer, choices, err := projectAdoptionOffer(a, reason)
		if err != nil {
			return nil, nil, nil, err
		}
		offers = append(offers, offer)
		request := requested[a.ID]
		if request == nil {
			continue
		}
		if request.Revision != offer.Revision {
			return nil, nil, nil, invalidModuleState(
				"adoption offer revision changed; preview again",
			)
		}
		answer, err := decodeAdoptionAnswer(a.Question.Type, choices, request.Answer)
		if err != nil {
			return nil, nil, nil, connect.NewError(
				connect.CodeInvalidArgument,
				fmt.Errorf("adoption offer %q: %w", a.ID, err),
			)
		}
		resolved, _ := reconcile.Materialize(a, answer)
		for _, m := range resolved {
			if !assignments.reserve(nixdata.SplitConfigPath(m.Path)) {
				return nil, nil, nil, invalidModuleState(
					"adoption answers have overlapping config assignments",
				)
			}
		}
		mutations = append(mutations, resolved...)
		records[a.ID] = reconcile.LedgerEntry{
			Revision: a.Revision,
			Answer:   answer.Record(a.Question),
		}
		delete(requested, a.ID)
	}
	if len(requested) != 0 {
		return nil, nil, nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("answer does not name a pending adoption offer for this enable"),
		)
	}
	return offers, mutations, records, nil
}

// The public projection is an allowlist. In particular neither config attrset
// (including a choice's config) is copied into the offer or error messages.
func projectAdoptionOffer(
	a nixeval.AddonSpec,
	reason string,
) (*agentv1.ModuleAdoptionOffer, map[string]bool, error) {
	q := a.Question
	switch q.Type {
	case "bool":
		if len(q.Choices) != 0 {
			return nil, nil, invalidModuleState("boolean adoption question declares choices")
		}
	case "select", "multiselect":
		if len(q.Choices) == 0 {
			return nil, nil, invalidModuleState("adoption question is missing choices")
		}
	default:
		return nil, nil, invalidModuleState("unsupported adoption question type")
	}
	offer := &agentv1.ModuleAdoptionOffer{
		Id: a.ID, Revision: strconv.Itoa(a.Revision), Module: a.Module, Reason: reason,
		Type: q.Type, Label: q.Label, Description: q.Description,
	}
	if err := validateAdoptionConfig(a.Module, a.Config); err != nil {
		return nil, nil, err
	}
	choices := make(map[string]bool, len(q.Choices))
	for _, c := range q.Choices {
		if choices[c.Value] {
			return nil, nil, invalidModuleState("duplicate adoption choice value")
		}
		choices[c.Value] = true
		if err := validateAdoptionConfig(a.Module, c.Config); err != nil {
			return nil, nil, err
		}
		label := c.Label
		if label == "" {
			label = c.Value
		}
		offer.Choices = append(
			offer.Choices,
			&agentv1.ModuleAdoptionChoice{Label: label, Value: c.Value},
		)
	}
	if q.Default != nil {
		v, err := structpb.NewValue(q.Default)
		if err != nil {
			return nil, nil, invalidModuleState("invalid adoption question default")
		}
		if _, err := decodeAdoptionAnswer(q.Type, choices, v); err != nil {
			return nil, nil, invalidModuleState("invalid adoption question default")
		}
		offer.Default = v
	}
	return offer, choices, nil
}

func decodeAdoptionAnswer(
	typ string,
	choices map[string]bool,
	v *structpb.Value,
) (reconcile.Answer, error) {
	var answer reconcile.Answer
	switch typ {
	case "bool":
		b, ok := v.GetKind().(*structpb.Value_BoolValue)
		if !ok || b == nil {
			return answer, errors.New("expected a boolean answer")
		}
		answer.Bool = b.BoolValue
	case "select":
		s, ok := v.GetKind().(*structpb.Value_StringValue)
		if !ok || s == nil || !choices[s.StringValue] {
			return answer, errors.New("expected a declared choice value")
		}
		answer.Select = s.StringValue
	case "multiselect":
		field, ok := v.GetKind().(*structpb.Value_ListValue)
		if !ok || field == nil || field.ListValue == nil {
			return answer, errors.New("expected a list of choice values")
		}
		list := field.ListValue
		selected := make(map[string]bool, len(list.Values))
		answer.Multi = make([]string, 0, len(list.Values))
		for _, item := range list.Values {
			s, ok := item.GetKind().(*structpb.Value_StringValue)
			if !ok || s == nil || !choices[s.StringValue] || selected[s.StringValue] {
				return answer, errors.New("expected distinct declared choice values")
			}
			selected[s.StringValue] = true
			answer.Multi = append(answer.Multi, s.StringValue)
		}
	default:
		return answer, errors.New("unsupported adoption question type")
	}
	return answer, nil
}

// Check the original attrset, before any dotted path codec can discard an
// empty segment. Match the module write boundary, permitting literal dots in
// nested attribute names without granting another module's settings namespace.
func validateAdoptionConfig(module string, config map[string]any) error {
	for root, value := range config {
		if nixdata.ValidateEntityName(root) != nil {
			return invalidModuleState("invalid adoption config namespace")
		}
		switch root {
		case "enable", "stackpanel", "variables", "secrets", "users", "apps", "registries":
			return invalidModuleState("adoption config targets a protected namespace")
		case "modules":
			owners, _ := value.(map[string]any)
			own, _ := owners[module].(map[string]any)
			if len(owners) != 1 || len(own) == 0 {
				return invalidModuleState(
					"adoption config must assign within the contributing module",
				)
			}
		}
	}
	if !safeAdoptionKeys(config) {
		return invalidModuleState("invalid declared adoption config path")
	}
	return nil
}

func safeAdoptionKeys(config map[string]any) bool {
	for k, v := range config {
		if !safeAdoptionSegment(k) {
			return false
		}
		if child, ok := v.(map[string]any); ok && !safeAdoptionKeys(child) {
			return false
		}
	}
	return true
}

func safeAdoptionSegment(s string) bool {
	if s == "" || s == "." || s == ".." || s == "imports" || strings.HasPrefix(s, "_") {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'A' && r <= 'Z',
			r >= 'a' && r <= 'z',
			r >= '0' && r <= '9',
			r == '_',
			r == '-',
			r == '.':
		default:
			return false
		}
	}
	return true
}

// A nil child marks an assignment; a non-nil child is a namespace. Reject
// duplicates and ancestor/descendant collisions independent of answer order.
type adoptionAssignments map[string]adoptionAssignments

func (tree adoptionAssignments) reserve(parts []string) bool {
	for i, part := range parts {
		child, exists := tree[part]
		if i == len(parts)-1 {
			if exists {
				return false
			}
			tree[part] = nil
			return true
		}
		if !exists {
			child = adoptionAssignments{}
			tree[part] = child
		} else if child == nil {
			return false
		}
		tree = child
	}
	return false
}
