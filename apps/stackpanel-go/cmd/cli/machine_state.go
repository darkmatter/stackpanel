// machine_state.go persists provisioning metadata for NixOS machines.
//
// This state is shared between `provision` and `deploy` commands: provision
// writes it after a successful install, deploy reads it to show machine status
// and guard against re-provisioning without --reprovision. Stored in
// .stack/state/machines.json (gitignored, local to each developer's machine).
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// MachineRecord tracks when and how a machine was provisioned. The hardware
// config path is stored so `deploy` can verify the file still exists before
// building a NixOS closure that references it.
type MachineRecord struct {
	ProvisionedAt           string `json:"provisionedAt"`
	InstallTarget           string `json:"installTarget"`
	HardwareConfigGenerated bool   `json:"hardwareConfigGenerated"`
	HardwareConfigPath      string `json:"hardwareConfigPath,omitempty"`
	NixRevision             string `json:"nixRevision,omitempty"`
}

type MachinesState map[string]MachineRecord

func machineStateFile() string {
	root := os.Getenv("STACKPANEL_ROOT")
	if root == "" {
		root = detectStackpanelProject()
	}
	if root == "" {
		root = "."
	}
	return filepath.Join(root, ".stack", "state", "machines.json")
}

func readMachineState() (MachinesState, error) {
	data, err := os.ReadFile(machineStateFile())
	if err != nil {
		return nil, err
	}
	var state MachinesState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("failed to parse machines.json: %w", err)
	}
	return state, nil
}

func writeMachineState(state MachinesState) error {
	stateFile := machineStateFile()
	if err := os.MkdirAll(filepath.Dir(stateFile), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(stateFile, data, 0o644)
}

func recordMachineProvision(name string, rec MachineRecord) error {
	state, err := readMachineState()
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if state == nil {
		state = make(MachinesState)
	}
	if rec.ProvisionedAt == "" {
		rec.ProvisionedAt = time.Now().UTC().Format(time.RFC3339)
	}
	state[name] = rec
	return writeMachineState(state)
}
