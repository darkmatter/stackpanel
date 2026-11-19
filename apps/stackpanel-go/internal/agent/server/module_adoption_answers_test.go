package server

import (
	"testing"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/structpb"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

func TestAdoptionOnlyOffersPendingEnableDelta(t *testing.T) {
	spec := func(id, module string, revision int) nixeval.AddonSpec {
		return nixeval.AddonSpec{
			ID:       id,
			Module:   module,
			Revision: revision,
			Question: nixeval.AddonQuestion{Type: "bool"},
		}
	}
	enabled := []nixeval.AddonSpec{
		spec("mine", "demo", 1),
		spec("new", "dep", 1),
		spec("bump", "dep", 2),
		spec(
			"old",
			"dep",
			1,
		),
		spec("downgrade", "dep", 1),
		spec("flake", "", 1),
		spec("decided", "demo", 2),
	}
	before := []nixeval.AddonSpec{
		enabled[0],
		spec("bump", "dep", 1),
		enabled[3],
		spec("downgrade", "dep", 2),
	}
	ledger := &reconcile.Ledger{
		Seen: map[string]reconcile.LedgerEntry{
			"decided": {Revision: 2},
			"bump":    {Revision: 1},
		},
	}
	answer := &agentv1.ModuleAdoptionAnswer{
		Id:       "bump",
		Revision: "2",
		Answer:   structpb.NewBoolValue(false),
	}
	offers, mutations, records, err := resolveAdoptionAnswers(
		"demo",
		before,
		enabled,
		ledger,
		[]*agentv1.ModuleAdoptionAnswer{answer},
	)
	require.NoError(t, err)
	var ids []string
	for _, o := range offers {
		ids = append(ids, o.Id)
	}
	require.Equal(t, []string{"mine", "new", "bump"}, ids)
	require.Equal(t, "revised", offers[2].Reason)
	require.Empty(t, mutations)
	require.Equal(
		t,
		map[string]reconcile.LedgerEntry{"bump": {Revision: 2, Answer: false}},
		records,
	)
	require.Equal(
		t,
		1,
		ledger.Seen["bump"].Revision,
		"resolving a preview must not record anything",
	)

	for _, id := range []string{"old", "downgrade", "flake", "decided", "unknown"} {
		answer.Id = id
		_, _, _, err := resolveAdoptionAnswers(
			"demo",
			before,
			enabled,
			ledger,
			[]*agentv1.ModuleAdoptionAnswer{answer},
		)
		require.Error(t, err, id)
	}
}

func TestAdoptionRejectsAmbiguousAssignments(t *testing.T) {
	// A dotted attrname and a nested path are distinct; neither may overwrite
	// the other during materialization, comparison, or preview.
	base := map[string]any{"custom": map[string]any{"a.b": 1, "empty": map[string]any{}}}
	spec := nixeval.AddonSpec{
		ID:       "prefs",
		Module:   "demo",
		Revision: 1,
		Config:   base,
		Question: nixeval.AddonQuestion{
			Type:    "select",
			Choices: []nixeval.AddonChoice{{Value: "yes"}},
		},
	}
	answer := &agentv1.ModuleAdoptionAnswer{
		Id:       "prefs",
		Revision: "1",
		Answer:   structpb.NewStringValue("yes"),
	}
	resolve := func(config map[string]any) ([]reconcile.Mutation, map[string]reconcile.LedgerEntry, error) {
		spec.Question.Choices[0].Config = config
		_, mutations, records, err := resolveAdoptionAnswers(
			"demo",
			nil,
			[]nixeval.AddonSpec{spec},
			&reconcile.Ledger{},
			[]*agentv1.ModuleAdoptionAnswer{answer},
		)
		return mutations, records, err
	}
	m, _, err := resolve(
		map[string]any{"custom": map[string]any{"a": map[string]any{"b": 2}}},
	)
	require.NoError(t, err)
	require.Equal(
		t,
		map[string]any{
			"custom": map[string]any{
				"a.b":   1,
				"a":     map[string]any{"b": 2},
				"empty": map[string]any{},
			},
		},
		reconcile.Overlay(m),
	)
	for _, bad := range []map[string]any{
		{"custom": map[string]any{"a.b": 2}},                      // same leaf
		{"custom": map[string]any{"a.b": map[string]any{"c": 2}}}, // leaf then descendant
		{"custom": true}, // descendant then leaf
		{"custom": map[string]any{"empty": map[string]any{"child": true}}},
		{"modules": map[string]any{"other": map[string]any{"enable": true}}},
		{"users": map[string]any{"admin": true}},
		{"custom": map[string]any{"_module": true}},
		{"": map[string]any{"custom": true}},
		{"custom": map[string]any{"../outside": true}},
	} {
		m, records, err := resolve(bad)
		require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
		require.Nil(t, m)
		require.Nil(t, records)
	}
}

func TestAdoptionRequiresDistinctTypedAnswers(t *testing.T) {
	spec := nixeval.AddonSpec{
		ID:       "features",
		Module:   "demo",
		Revision: 3,
		Question: nixeval.AddonQuestion{
			Type:    "multiselect",
			Choices: []nixeval.AddonChoice{{Value: "one"}},
		},
	}
	run := func(answers ...*agentv1.ModuleAdoptionAnswer) error {
		_, _, _, err := resolveAdoptionAnswers(
			"demo",
			nil,
			[]nixeval.AddonSpec{spec},
			&reconcile.Ledger{},
			answers,
		)
		return err
	}
	answer := &agentv1.ModuleAdoptionAnswer{Id: spec.ID, Revision: "3"}
	for _, value := range []any{nil, false, "one", []any{true}, []any{"one", "one"}, map[string]any{"path": "modules.other.enable"}} {
		v, err := structpb.NewValue(value)
		require.NoError(t, err)
		answer.Answer = v
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(run(answer)))
	}
	answer.Answer = structpb.NewListValue(&structpb.ListValue{})
	require.NoError(t, run(answer))
	require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(run(answer, answer)))
	spec.Question.Choices = append(
		spec.Question.Choices,
		nixeval.AddonChoice{Value: "one"},
	)
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(run()))
}
