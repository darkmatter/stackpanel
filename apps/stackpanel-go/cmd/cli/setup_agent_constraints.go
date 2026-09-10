package cmd

import (
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
)

// setupAgentExpectations freezes explicit CLI choices independently of the
// agent's interpretation. Unrequested addons do not contribute their defaults.
func setupAgentExpectations(plan reconcile.Expectations, opts setupFlags, addons []nixeval.AddonSpec) (reconcile.Expectations, error) {
	byID := make(map[string]nixeval.AddonSpec, len(addons))
	for _, addon := range addons {
		byID[strings.ToLower(addon.ID)] = addon
	}
	requested := map[string]bool{}
	lookup := func(raw string) (nixeval.AddonSpec, error) {
		id := strings.ToLower(strings.TrimSpace(raw))
		addon, ok := byID[id]
		if !ok {
			return addon, fmt.Errorf("unknown onboarding addon %q", raw)
		}
		requested[id] = true
		return addon, nil
	}
	for _, raw := range append(append([]string{}, opts.with...), opts.without...) {
		if _, err := lookup(raw); err != nil {
			return plan, err
		}
	}
	for _, value := range opts.addonValues {
		id, raw, ok := strings.Cut(value, "=")
		if !ok {
			return plan, fmt.Errorf("invalid --addon %q: expected id=value", value)
		}
		addon, err := lookup(id)
		if err != nil {
			return plan, err
		}
		if err := validateSetupAddonValue(addon, strings.TrimSpace(raw)); err != nil {
			return plan, err
		}
	}
	// Copy the slice before replacing assertions; the caller may retain the
	// original plan for display or diagnostics.
	plan.Config = slices.Clone(plan.Config)
	inputs := reconcile.AnswerInputs{With: opts.with, Without: opts.without, Values: opts.addonValues}
	for _, addon := range addons {
		if !requested[strings.ToLower(addon.ID)] {
			continue
		}
		answer, err := reconcile.ResolveAnswer(inputs, addon)
		if err != nil {
			return plan, err
		}
		mutations, active := reconcile.Materialize(addon, answer)
		if err := validateSetupAddonAnswer(addon, answer); err != nil {
			return plan, err
		}
		var disabled []reconcile.Mutation
		if !active {
			disabled = append(disabled, setupAddonDisableSwitches(addon.Config)...)
		}
		for _, choice := range addon.Question.Choices {
			selected := active && (answer.Select == choice.Value || slices.Contains(answer.Multi, choice.Value))
			if !selected {
				disabled = append(disabled, setupAddonDisableSwitches(choice.Config)...)
			}
		}
		if !active && len(disabled) == 0 {
			return plan, fmt.Errorf("cannot verify declining addon %q: metadata has no enable switch to disable", addon.ID)
		}
		// Selected values win when a choice shares an enable switch with other
		// choices, matching Materialize's base-then-choice assignment order.
		for _, mutation := range append(disabled, mutations...) {
			if mutation.Path == "enable" && mutation.Value != true {
				return plan, fmt.Errorf("addon %q conflicts with enabling Stackpanel", addon.ID)
			}
			value, err := json.Marshal(mutation.Value)
			if err != nil {
				return plan, fmt.Errorf("addon %q configuration: %w", addon.ID, err)
			}
			plan.Config = replaceSetupAssertion(plan.Config, reconcile.ConfigAssertion{
				Path: strings.Split(mutation.Path, "."), Equals: value,
			})
		}
	}
	plan.Config = replaceSetupAssertion(plan.Config, reconcile.ConfigAssertion{Path: []string{"enable"}, Equals: json.RawMessage("true")})
	return plan, reconcile.ValidateExpectations(plan)
}

func validateSetupAddonValue(addon nixeval.AddonSpec, raw string) error {
	if addon.Question.Type == "bool" {
		switch strings.ToLower(raw) {
		case "true", "false", "1", "0", "yes", "no":
			return nil
		default:
			return fmt.Errorf("addon %q requires a boolean value, got %q", addon.ID, raw)
		}
	}
	return validateSetupAddonAnswer(addon, reconcile.ParseAnswer(addon.Question.Type, raw))
}

func validateSetupAddonAnswer(addon nixeval.AddonSpec, answer reconcile.Answer) error {
	var selected []string
	switch addon.Question.Type {
	case "bool":
		return nil
	case "select":
		if answer.Select != "" {
			selected = []string{answer.Select}
		}
	case "multiselect":
		selected = answer.Multi
	default:
		return fmt.Errorf("addon %q has unsupported question type %q", addon.ID, addon.Question.Type)
	}
	for _, value := range selected {
		if _, ok := reconcile.FindChoice(addon.Question, value); !ok {
			return fmt.Errorf("addon %q has no choice %q", addon.ID, value)
		}
	}
	return nil
}

// Only enable=true has a well-defined inverse. Arbitrary strings, lists, and
// settings in adoption metadata do not tell us their disabled/default values.
func setupAddonDisableSwitches(config map[string]any) []reconcile.Mutation {
	var switches []reconcile.Mutation
	for _, mutation := range reconcile.FlattenConfig("", config) {
		if mutation.Value == true && (mutation.Path == "enable" || strings.HasSuffix(mutation.Path, ".enable")) {
			switches = append(switches, reconcile.Mutation{Path: mutation.Path, Value: false})
		}
	}
	return switches
}

// A CLI assertion also replaces enclosing agent assertions. For example, an
// agent's equality assertion for the whole modules attrset must not contradict
// an explicit --without that fixes one nested module's enable value.
func replaceSetupAssertion(assertions []reconcile.ConfigAssertion, replacement reconcile.ConfigAssertion) []reconcile.ConfigAssertion {
	out := assertions[:0]
	for _, assertion := range assertions {
		n := min(len(assertion.Path), len(replacement.Path))
		if !slices.Equal(assertion.Path[:n], replacement.Path[:n]) {
			out = append(out, assertion)
		}
	}
	return append(out, replacement)
}
