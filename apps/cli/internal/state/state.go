// Package state provides a thin wrapper around the shared stackpanel-go package
// for CLI-specific configuration loading.
package state

import (
	sharedstate "github.com/darkmatter/stackpanel/packages/stackpanel-go/state"
)

// Re-export types from shared package
type (
	State      = sharedstate.State
	App        = sharedstate.App
	Service    = sharedstate.Service
	Paths      = sharedstate.Paths
	Network    = sharedstate.Network
	StepConfig = sharedstate.StepConfig
)

// MOTD contains message of the day configuration (CLI-specific extension)
type MOTD struct {
	Enable   bool          `json:"enable"`
	Commands []MOTDCommand `json:"commands"`
	Features []string      `json:"features"`
	Hints    []string      `json:"hints"`
}

// MOTDCommand represents a command to show in the MOTD
type MOTDCommand struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// StateWithMOTD extends the shared State with MOTD support
type StateWithMOTD struct {
	State
	MOTD MOTD `json:"motd"`
}

// Load gets the stackpanel configuration using Nix evaluation with state file fallback.
func Load(path string) (*StateWithMOTD, error) {
	baseState, err := sharedstate.Load(path)
	if err != nil {
		return nil, err
	}

	// Wrap in StateWithMOTD (MOTD will be zero value if not present)
	return &StateWithMOTD{State: *baseState}, nil
}

// LoadFromProjectRoot loads configuration from a specific project root.
func LoadFromProjectRoot(projectRoot string) (*StateWithMOTD, error) {
	baseState, err := sharedstate.LoadFromProjectRoot(projectRoot)
	if err != nil {
		return nil, err
	}
	return &StateWithMOTD{State: *baseState}, nil
}
