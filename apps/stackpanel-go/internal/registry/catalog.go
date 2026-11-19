// Package registry reads versioned Stackpanel module catalogs. The same wire
// contract is used by the static official index and private HTTP registries.
package registry

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

const OfficialURL = "https://raw.githubusercontent.com/darkmatter/stackpanel-registry/main/registry.v1.json"

//go:embed registry.v1.schema.json
var schemaJSON []byte

//go:embed snapshot.json
var snapshot []byte

type Catalog struct {
	SchemaVersion int      `json:"schemaVersion"`
	Modules       []Module `json:"modules"`
}

type Module struct {
	ID            string    `json:"id"`
	Slug          string    `json:"slug"`
	Name          string    `json:"name"`
	Description   string    `json:"description"`
	Category      string    `json:"category"`
	Icon          string    `json:"icon"`
	Author        string    `json:"author"`
	Tier          string    `json:"tier"`
	LatestVersion string    `json:"latestVersion"`
	Versions      []Version `json:"versions"`
	Features      []string  `json:"features"`
	UISlots       []string  `json:"uiSlots"`
	Tags          []string  `json:"tags,omitempty"`
	ReadmeURL     string    `json:"readmeUrl,omitempty"`
	Homepage      string    `json:"homepage,omitempty"`
	source        string
}

type Version struct {
	Version        string       `json:"version"`
	FlakeURL       string       `json:"flakeUrl"`
	Ref            string       `json:"ref,omitempty"`
	Rev            string       `json:"rev,omitempty"`
	FollowsNixpkgs bool         `json:"followsNixpkgs"`
	FlakePath      string       `json:"flakePath,omitempty"`
	FlakeInputs    []FlakeInput `json:"flakeInputs"`
}

type FlakeInput struct {
	Name           string `json:"name"`
	URL            string `json:"url"`
	Ref            string `json:"ref,omitempty"`
	FollowsNixpkgs bool   `json:"followsNixpkgs"`
}

func (m *Module) Matches(query, category, tag string) bool {
	if category != "" && !strings.EqualFold(m.Category, category) {
		return false
	}
	query = strings.ToLower(strings.TrimSpace(query))
	match := query == "" || strings.Contains(strings.ToLower(m.Name), query) ||
		strings.Contains(
			strings.ToLower(m.Slug),
			query,
		) || strings.Contains(strings.ToLower(m.Description), query) ||
		strings.Contains(strings.ToLower(m.ID), query)
	matchTag := tag == ""
	for _, t := range m.Tags {
		matchTag = matchTag || strings.EqualFold(t, tag)
		match = match || strings.Contains(strings.ToLower(t), query)
	}
	return match && matchTag
}

var compiledSchema = sync.OnceValues(func() (*jsonschema.Schema, error) {
	var doc any
	if err := json.Unmarshal(schemaJSON, &doc); err != nil {
		return nil, err
	}
	compiler := jsonschema.NewCompiler()
	compiler.AssertFormat()
	const name = "https://raw.githubusercontent.com/darkmatter/stackpanel-registry/main/registry.v1.schema.json"
	if err := compiler.AddResource(name, doc); err != nil {
		return nil, err
	}
	return compiler.Compile(name)
})

func decodeCatalog(data []byte) ([]Module, error) {
	schema, err := compiledSchema()
	if err != nil {
		return nil, fmt.Errorf("compile embedded catalog schema: %w", err)
	}
	var doc any
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("decode catalog: %w", err)
	}
	if err := schema.Validate(doc); err != nil {
		return nil, fmt.Errorf("invalid catalog: %w", err)
	}
	var catalog Catalog
	if err := json.Unmarshal(data, &catalog); err != nil {
		return nil, err
	}
	// JSON Schema cannot express foreign-key or property-level uniqueness.
	identities := make(map[string]bool, len(catalog.Modules))
	for _, m := range catalog.Modules {
		if identities[m.ID] || identities[m.Slug] {
			return nil, fmt.Errorf("ambiguous catalog identity for %q (%s)", m.ID, m.Slug)
		}
		identities[m.ID], identities[m.Slug] = true, true
		versions := make(map[string]bool, len(m.Versions))
		for _, v := range m.Versions {
			if versions[v.Version] {
				return nil, fmt.Errorf("module %q repeats version %q", m.ID, v.Version)
			}
			versions[v.Version] = true
			inputs := map[string]bool{m.Slug: true}
			for _, dep := range v.FlakeInputs {
				if inputs[dep.Name] {
					return nil, fmt.Errorf(
						"module %q version %q has colliding input %q",
						m.ID,
						v.Version,
						dep.Name,
					)
				}
				inputs[dep.Name] = true
			}
		}
		if !versions[m.LatestVersion] {
			return nil, fmt.Errorf("module %q latestVersion is not in versions", m.ID)
		}
	}
	return catalog.Modules, nil
}
