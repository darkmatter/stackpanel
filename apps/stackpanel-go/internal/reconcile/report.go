package reconcile

import (
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
)

// Offer is an addon the user has not decided on at its current revision.
type Offer struct {
	ID          string `json:"id"`
	Revision    int    `json:"revision"`
	Label       string `json:"label"`
	Description string `json:"description,omitempty"`
	Module      string `json:"module,omitempty"`
	// Reason says why it is being offered: "new", "revised", or "reconsider".
	Reason string `json:"reason"`
}

// Report is the merged, read-only output of a Registry.Diagnose run. Both
// `stack doctor` and `stack setup` render exactly this.
type Report struct {
	Reconcilers []string          `json:"reconcilers"`
	Findings    []Finding         `json:"findings"`
	Changes     []Change          `json:"changes"`
	Offers      []Offer           `json:"offers"`
	Notes       []string          `json:"notes,omitempty"`
	Errors      []ReconcilerError `json:"errors,omitempty"`
}

// HasErrors reports whether any finding is error severity (or a reconciler failed).
func (r *Report) HasErrors() bool {
	if len(r.Errors) > 0 {
		return true
	}
	for _, f := range r.Findings {
		if f.Severity == SeverityError {
			return true
		}
	}
	return false
}

// HasChanges reports whether Apply would do anything.
func (r *Report) HasChanges() bool {
	return len(r.Changes) > 0
}

// Count returns the number of findings at a severity.
func (r *Report) Count(sev Severity) int {
	n := 0
	for _, f := range r.Findings {
		if f.Severity == sev {
			n++
		}
	}
	return n
}

// JSON renders the report for --json consumers.
func (r *Report) JSON() ([]byte, error) {
	data, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

// RenderOptions tunes the text renderer.
type RenderOptions struct {
	// Title is the first line, e.g. "stack doctor".
	Title string
	// Verbose prints per-reconciler notes.
	Verbose bool
	// NextStep is appended when changes are pending, e.g. "run `stack setup` to apply".
	NextStep string
}

// Render writes the human-readable report. Sections follow the registry order
// so codegen/files/fileops read as one "Reconciliation" story, then checks,
// then offers.
func (r *Report) Render(w io.Writer, opts RenderOptions) {
	if opts.Title != "" {
		fmt.Fprintln(w, output.Purple.Sprint(opts.Title))
		fmt.Fprintln(w)
	}

	changesBy := map[string][]Change{}
	for _, c := range r.Changes {
		changesBy[c.Reconciler] = append(changesBy[c.Reconciler], c)
	}
	findingsBy := map[string][]Finding{}
	for _, f := range r.Findings {
		findingsBy[f.Reconciler] = append(findingsBy[f.Reconciler], f)
	}
	notesBy := map[string][]string{}
	for _, n := range r.Notes {
		if idx := strings.Index(n, ": "); idx > 0 {
			notesBy[n[:idx]] = append(notesBy[n[:idx]], n[idx+2:])
		}
	}

	for _, id := range r.Reconcilers {
		changes := changesBy[id]
		findings := findingsBy[id]
		notes := notesBy[id]

		status := output.Green.Sprint("✓")
		summary := "up to date"
		worst := worstSeverity(findings)
		switch {
		case worst == SeverityError:
			status = output.Red.Sprint("✗")
			summary = fmt.Sprintf("%d problem(s)", countSeverity(findings, SeverityError))
		case len(changes) > 0:
			status = output.Yellow.Sprint("~")
			summary = fmt.Sprintf("%d change(s) pending", len(changes))
		case worst == SeverityWarning:
			status = output.Yellow.Sprint("!")
			summary = fmt.Sprintf("%d warning(s)", countSeverity(findings, SeverityWarning))
		case len(findings) > 0:
			status = output.DimC.Sprint("·")
			summary = fmt.Sprintf("%d note(s)", len(findings))
		}
		fmt.Fprintf(w, "%s %-10s %s\n", status, id, output.DimC.Sprint(summary))

		for _, c := range changes {
			fmt.Fprintf(w, "    %s %s", changeGlyph(c.Kind), c.Path)
			if c.Summary != "" {
				fmt.Fprintf(w, "  %s", output.DimC.Sprint(c.Summary))
			}
			fmt.Fprintln(w)
		}
		for _, f := range findings {
			fmt.Fprintf(w, "    %s %s", severityGlyph(f.Severity), f.Title)
			if f.Path != "" {
				fmt.Fprintf(w, " %s", output.DimC.Sprint(f.Path))
			}
			fmt.Fprintln(w)
			if f.Detail != "" {
				for _, line := range strings.Split(strings.TrimRight(f.Detail, "\n"), "\n") {
					fmt.Fprintf(w, "        %s\n", output.DimC.Sprint(line))
				}
			}
			if f.FixCommand != "" {
				fmt.Fprintf(w, "        fix: %s\n", f.FixCommand)
			}
		}
		if opts.Verbose {
			for _, n := range notes {
				fmt.Fprintf(w, "    %s\n", output.DimC.Sprint(n))
			}
		}
	}

	if len(r.Offers) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, output.Purple.Sprint("Offers"))
		for _, o := range r.Offers {
			fmt.Fprintf(
				w,
				"    · %s %s  %s\n",
				o.ID,
				output.DimC.Sprintf("(rev %d, %s)", o.Revision, o.Reason),
				o.Label,
			)
			if o.Description != "" {
				fmt.Fprintf(w, "        %s\n", output.DimC.Sprint(o.Description))
			}
		}
	}

	fmt.Fprintln(w)
	parts := []string{
		fmt.Sprintf("%d change(s)", len(r.Changes)),
		fmt.Sprintf("%d warning(s)", r.Count(SeverityWarning)),
		fmt.Sprintf("%d error(s)", r.Count(SeverityError)),
	}
	if len(r.Offers) > 0 {
		parts = append(parts, fmt.Sprintf("%d offer(s)", len(r.Offers)))
	}
	fmt.Fprintln(w, output.DimC.Sprint(strings.Join(parts, ", ")))
	if r.HasChanges() && opts.NextStep != "" {
		fmt.Fprintln(w, opts.NextStep)
	}
}

func worstSeverity(findings []Finding) Severity {
	worst := Severity("")
	for _, f := range findings {
		if worst == "" || severityRank(f.Severity) < severityRank(worst) {
			worst = f.Severity
		}
	}
	return worst
}

func countSeverity(findings []Finding, sev Severity) int {
	n := 0
	for _, f := range findings {
		if f.Severity == sev {
			n++
		}
	}
	return n
}

func changeGlyph(kind ChangeKind) string {
	switch kind {
	case ChangeCreate:
		return output.Green.Sprint("+")
	case ChangeDelete:
		return output.Red.Sprint("-")
	case ChangeRestore:
		return output.Yellow.Sprint("↺")
	case ChangeBackup:
		return output.DimC.Sprint("⧉")
	case ChangeUnknown:
		return output.DimC.Sprint("?")
	default:
		return output.Yellow.Sprint("~")
	}
}

func severityGlyph(sev Severity) string {
	switch sev {
	case SeverityError:
		return output.Red.Sprint("✗")
	case SeverityWarning:
		return output.Yellow.Sprint("!")
	default:
		return output.DimC.Sprint("·")
	}
}

// SortChanges orders changes by reconciler then path for stable output.
func SortChanges(changes []Change) {
	sort.SliceStable(changes, func(i, j int) bool {
		if changes[i].Reconciler != changes[j].Reconciler {
			return changes[i].Reconciler < changes[j].Reconciler
		}
		return changes[i].Path < changes[j].Path
	})
}
