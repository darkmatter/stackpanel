package cmd

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var provisionCmd = &cobra.Command{
	Use:   "provision [machine]",
	Short: "Provision machines with nixos-anywhere",
	Long: `Provision bare-metal or VM machines with NixOS using nixos-anywhere.

Without arguments, lists configured machines and their provisioning status.
With a machine name, provisions that machine using nixos-anywhere.

Provisioning is a one-time, destructive operation that installs NixOS from
scratch. For subsequent, non-destructive updates use 'stackpanel deploy'.

Examples:
  stackpanel provision                          List machines and status
  stackpanel provision prod-server              Provision prod-server
  stackpanel provision prod-server --dry-run    Print command without running
  stackpanel provision prod-server --install-target 10.0.0.5`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		defer cancel()

		cfg, err := loadDeployConfig(ctx)
		if err != nil {
			output.Error(fmt.Sprintf("Failed to load deploy config: %v", err))
			os.Exit(1)
		}

		if len(args) == 0 {
			listMachines(cfg)
			return
		}

		machineName := args[0]
		installTarget, _ := cmd.Flags().GetString("install-target")
		format, _ := cmd.Flags().GetBool("format")
		noHardwareConfig, _ := cmd.Flags().GetBool("no-hardware-config")
		dryRun, _ := cmd.Flags().GetBool("dry-run")
		reprovision, _ := cmd.Flags().GetBool("reprovision")

		if err := runProvisionMachine(cfg, machineName, installTarget, format, noHardwareConfig, dryRun, reprovision); err != nil {
			output.Error(fmt.Sprintf("Provision failed: %v", err))
			os.Exit(1)
		}
	},
}

func init() {
	provisionCmd.Flags().String("install-target", "", "IP/host for provisioning (default: machine's host in config)")
	provisionCmd.Flags().Bool("format", false, "Format disk via machine's diskLayout (default: --no-reformat)")
	provisionCmd.Flags().Bool("no-hardware-config", false, "Skip hardware config generation")
	provisionCmd.Flags().Bool("dry-run", false, "Print nixos-anywhere command without running")
	provisionCmd.Flags().Bool("reprovision", false, "Allow re-provisioning an already-provisioned machine")
}

// listMachines prints all configured machines with their provisioning status.
func listMachines(cfg *DeployStackpanelConfig) {
	if len(cfg.Deployment.Machines) == 0 {
		output.Warning("No machines configured.")
		output.Dimmed("Add machines to stackpanel.deployment.machines in your config.")
		return
	}

	state, _ := readMachineState()
	if state == nil {
		state = make(MachinesState)
	}

	names := make([]string, 0, len(cfg.Deployment.Machines))
	for name := range cfg.Deployment.Machines {
		names = append(names, name)
	}
	sort.Strings(names)

	fmt.Println("Machines:")
	for _, name := range names {
		machine := cfg.Deployment.Machines[name]
		rec, provisioned := state[name]

		fmt.Printf("  %s\n", output.Purple.Sprint(name))
		output.Dimmed(fmt.Sprintf("    host:        %s", machine.Host))
		if provisioned {
			output.Dimmed(fmt.Sprintf("    provisioned: %s", rec.ProvisionedAt))
			if rec.HardwareConfigGenerated {
				output.Dimmed("    hw-config:   ✓")
			} else {
				output.Dimmed("    hw-config:   ✗")
			}
		} else {
			output.Dimmed("    provisioned: not provisioned")
		}
	}
}

// runProvisionMachine provisions a single machine using nixos-anywhere.
func runProvisionMachine(cfg *DeployStackpanelConfig, machineName, installTarget string, format, noHardwareConfig, dryRun, reprovision bool) error {
	machine, ok := cfg.Deployment.Machines[machineName]
	if !ok {
		return fmt.Errorf("machine %q not found in deployment.machines config", machineName)
	}

	// Resolve install target: flag overrides config
	target := machine.Host
	if installTarget != "" {
		target = installTarget
	}
	if target == "" {
		return fmt.Errorf("machine %q has no host configured; use --install-target to specify an IP", machineName)
	}

	// Re-provision guard
	if !reprovision {
		state, stateErr := readMachineState()
		if stateErr == nil {
			if rec, exists := state[machineName]; exists {
				output.Error(fmt.Sprintf("%s was already provisioned on %s.", machineName, rec.ProvisionedAt))
				output.Dimmed("  Re-provisioning will format the disk and erase all data.")
				output.Dimmed("  Pass --reprovision to proceed, or use `stackpanel deploy` for a non-destructive update.")
				return fmt.Errorf("machine already provisioned (pass --reprovision to override)")
			}
		}
	}

	hardwareDir := filepath.Join(".stackpanel", "hardware", machineName)

	// Build nixos-anywhere args
	user := machine.User
	if user == "" {
		user = "root"
	}
	installHost := fmt.Sprintf("%s@%s", user, target)

	var args []string
	args = append(args, "--flake", fmt.Sprintf(".#%s", machineName))
	if !format {
		args = append(args, "--no-reformat")
	}
	if !noHardwareConfig {
		args = append(args, "--generate-hardware-config", "nixos-generate-config", hardwareDir)
	}
	// Trailing positional: user@host
	args = append(args, installHost)

	if dryRun {
		output.Info(fmt.Sprintf("dry-run: nixos-anywhere %v", args))
		return nil
	}

	// Run with 30-minute timeout
	provCtx, provCancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer provCancel()

	output.Info(fmt.Sprintf("Provisioning %s at %s using nixos-anywhere", machineName, target))
	if err := runExternalCommand(provCtx, "nixos-anywhere", args, false); err != nil {
		return fmt.Errorf("nixos-anywhere failed: %w", err)
	}

	// Check if hardware config was written
	hwConfigPath := filepath.Join(hardwareDir, "hardware-configuration.nix")
	hwConfigGenerated := false
	if !noHardwareConfig {
		if _, err := os.Stat(hwConfigPath); err == nil {
			hwConfigGenerated = true
		}
	}

	// Record provision state
	rec := MachineRecord{
		ProvisionedAt:           time.Now().UTC().Format(time.RFC3339),
		InstallTarget:           target,
		HardwareConfigGenerated: hwConfigGenerated,
		NixRevision:             gitRevision(),
	}
	if hwConfigGenerated {
		rec.HardwareConfigPath = hwConfigPath
	}
	if err := recordMachineProvision(machineName, rec); err != nil {
		output.Warning(fmt.Sprintf("Failed to record provision state: %v", err))
	}

	// Print success and next steps
	output.Success(fmt.Sprintf("Provisioned %s", machineName))
	fmt.Println()
	if hwConfigGenerated {
		fmt.Println("Generated hardware config:")
		fmt.Printf("  %s\n", hwConfigPath)
		fmt.Println()
		fmt.Println("Next steps:")
		fmt.Println("  1. Review the generated hardware config")
		fmt.Println("  2. Add it to config.nix:")
		fmt.Printf("       hardwareConfig = ./%s;\n", hwConfigPath)
		fmt.Println("  3. Commit and run: stackpanel deploy <app>")
	} else {
		fmt.Println("Next steps:")
		fmt.Println("  1. Commit your config and run: stackpanel deploy <app>")
	}

	return nil
}
