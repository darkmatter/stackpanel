package cmd

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"

	agentv1 "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1"
	"github.com/darkmatter/stackpanel/stackpanel-go/internal/reconcile"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/spf13/cobra"
	"google.golang.org/protobuf/types/known/structpb"
)

type moduleAdoptionOptions struct {
	yes, defaults bool
	inputs        reconcile.AnswerInputs
}

func (o *moduleAdoptionOptions) bind(cmd *cobra.Command) {
	f := cmd.Flags()
	f.BoolVarP(
		&o.yes,
		"yes",
		"y",
		false,
		"Approve enable and reconciliation without prompting; leave unspecified optional offers unanswered unless --adopt-defaults",
	)
	f.BoolVar(
		&o.defaults,
		"adopt-defaults",
		false,
		"Use declared defaults for pending offers not explicitly answered",
	)
	f.StringSliceVar(&o.inputs.With, "with", nil, "Accept an offer by id (repeatable)")
	f.StringSliceVar(
		&o.inputs.Without,
		"without",
		nil,
		"Record a decline for an offer (repeatable)",
	)
	f.StringArrayVar(
		&o.inputs.Values,
		"addon",
		nil,
		"Answer id=value (boolean, choice, or comma-separated choices; repeatable)",
	)
}

// answers collects decisions, not config mutations. Only the service may derive
// patches and persist the ledger from the reviewed answers and their revisions.
func (o moduleAdoptionOptions) answers(
	id string,
	offers []*agentv1.ModuleAdoptionOffer,
	input *bufio.Scanner,
	w io.Writer,
) ([]*agentv1.ModuleAdoptionAnswer, error) {
	byID := make(map[string]*agentv1.ModuleAdoptionOffer, len(offers))
	for _, offer := range offers {
		if offer.GetId() == "" || offer.GetRevision() == "" {
			return nil, fmt.Errorf("invalid adoption offer for module %q", id)
		}
		if byID[offer.Id] != nil {
			return nil, fmt.Errorf("duplicate adoption offer %q", offer.Id)
		}
		byID[offer.Id] = offer
	}
	explicit := map[string]bool{}
	selectID := func(key string) error {
		if byID[key] == nil {
			return fmt.Errorf("no pending adoption offer %q for %s", key, id)
		}
		if explicit[key] {
			return fmt.Errorf("multiple answers for adoption offer %q", key)
		}
		explicit[key] = true
		return nil
	}
	for _, group := range [][]string{o.inputs.With, o.inputs.Without} {
		for _, key := range group {
			if err := selectID(key); err != nil {
				return nil, err
			}
		}
	}
	for _, pair := range o.inputs.Values {
		key, raw, ok := strings.Cut(pair, "=")
		if !ok {
			return nil, errors.New("--addon expects id=value")
		}
		if err := selectID(key); err != nil {
			return nil, err
		}
		if err := checkAddonInput(byID[key], raw); err != nil {
			return nil, err
		}
	}
	var answers []*agentv1.ModuleAdoptionAnswer
	for _, offer := range offers {
		if o.defaults && !explicit[offer.Id] && offer.GetDefault() == nil {
			continue // No declared default: leave this offer pending.
		}
		q := nixeval.AddonQuestion{
			Type:        offer.GetType(),
			Label:       offer.Label,
			Description: offer.Description,
		}
		if def := offer.GetDefault(); def != nil {
			q.Default = def.AsInterface()
		}
		for _, c := range offer.GetChoices() {
			q.Choices = append(
				q.Choices,
				nixeval.AddonChoice{Value: c.GetValue(), Label: c.GetLabel()},
			)
		}
		inputs := o.inputs
		if !explicit[offer.Id] && !o.defaults {
			if o.yes {
				continue
			}
			raw, err := promptModuleOffer(input, w, offer)
			if err != nil {
				return nil, err
			}
			if raw == "" {
				continue
			} // skip without recording a decline
			inputs.Values = []string{offer.Id + "=" + raw}
		}
		a, err := reconcile.ResolveAnswer(
			inputs,
			nixeval.AddonSpec{ID: offer.Id, Question: q},
		)
		if err != nil {
			return nil, err
		}
		if q.Type == "select" {
			if _, ok := reconcile.FindChoice(q, a.Select); !ok {
				return nil, fmt.Errorf(
					"offer %q has no choice %q; use --addon %s=<declared value> or leave it unanswered",
					offer.Id,
					a.Select,
					offer.Id,
				)
			}
		}
		var record any = a.Record(q)
		if multi, ok := record.([]string); ok {
			values := make([]any, len(multi))
			for i, v := range multi {
				values[i] = v
			}
			record = values
		}
		if record == nil {
			return nil, fmt.Errorf("unsupported adoption question type %q", q.Type)
		}
		v, err := structpb.NewValue(record)
		if err != nil {
			return nil, err
		}
		answers = append(
			answers,
			&agentv1.ModuleAdoptionAnswer{Id: offer.Id, Revision: offer.Revision, Answer: v},
		)
		if _, err := fmt.Fprintf(
			w,
			"Selected %s (revision %s): %v\n",
			offer.Id,
			offer.Revision,
			record,
		); err != nil {
			return nil, err
		}
	}
	return answers, nil
}

func promptModuleOffer(
	input *bufio.Scanner,
	w io.Writer,
	offer *agentv1.ModuleAdoptionOffer,
) (string, error) {
	if _, err := fmt.Fprintf(
		w,
		"Optional: %s (%s, module %s)\n%s\n",
		offer.Label,
		offer.Id,
		offer.Module,
		offer.Description,
	); err != nil {
		return "", err
	}
	for _, c := range offer.Choices {
		if _, err := fmt.Fprintf(w, "  %s: %s\n", c.GetValue(), c.GetLabel()); err != nil {
			return "", err
		}
	}
	var hint string
	switch offer.GetType() {
	case "bool":
		hint = "yes or no"
	case "select":
		hint = "choice value"
	case "multiselect":
		hint = "comma-separated choice values"
	default:
		return "", fmt.Errorf("unknown adoption question type %q", offer.GetType())
	}
	if _, err := fmt.Fprintf(
		w,
		"Answer (%s; Enter to leave unanswered): ",
		hint,
	); err != nil {
		return "", err
	}
	if !input.Scan() {
		if err := input.Err(); err != nil {
			return "", err
		}
		return "", errors.New("no adoption input received; nothing approved")
	}
	raw := strings.TrimSpace(input.Text())
	if raw == "" {
		return "", nil
	}
	if err := checkAddonInput(offer, raw); err != nil {
		return "", err
	}
	return raw, nil
}

func checkAddonInput(offer *agentv1.ModuleAdoptionOffer, raw string) error {
	if offer.GetType() == "bool" {
		switch strings.ToLower(raw) {
		case "1", "0", "true", "false", "yes", "no":
			return nil
		default:
			return fmt.Errorf("offer %q expects yes or no", offer.Id)
		}
	}
	// The service validates choices and revision against the live module on
	// both preview and enable. Do not duplicate its catalog validation here.
	return nil
}
