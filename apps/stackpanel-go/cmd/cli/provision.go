package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/output"
	"github.com/spf13/cobra"
)

var provisionCmd = &cobra.Command{
	Use:   "provision [machine]",
	Short: "Provision machines with NixOS",
	Long: `Provision bare-metal or VM machines with NixOS.

Without arguments, lists configured machines and their provisioning status.
With a machine name, provisions that machine.

Default (no --format):
  SSHes into the running Linux system, detects hardware, generates
  hardware-configuration.nix, then installs NixOS via kexec without
  reformatting the disk.  Best for cloud VMs (Hetzner, DigitalOcean, etc.).

With --format:
  Partitions and formats the disk using disko before installing NixOS.
  Requires diskLayout to be set in the machine config.
  Best for bare metal or when you need a custom partition layout.

Examples:
  stackpanel provision                           List machines and status
  stackpanel provision prod-server               Provision (kexec, no reformat)
  stackpanel provision prod-server --dry-run     Print commands without running
  stackpanel provision prod-server --reprovision Re-provision an existing machine
  stackpanel provision prod-server --format      Provision with disko disk format`,
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
	provisionCmd.Flags().Bool("format", false, "Partition and format disk with disko before installing (requires diskLayout in machine config)")
	provisionCmd.Flags().Bool("no-hardware-config", false, "Skip hardware config generation")
	provisionCmd.Flags().Bool("dry-run", false, "Print commands without running")
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

// runProvisionMachine provisions a single machine.
func runProvisionMachine(cfg *DeployStackpanelConfig, machineName, installTarget string, format, noHardwareConfig, dryRun, reprovision bool) error {
	machine, ok := cfg.Deployment.Machines[machineName]
	if !ok {
		return fmt.Errorf("machine %q not found in deployment.machines config", machineName)
	}

	target := machine.Host
	if installTarget != "" {
		target = installTarget
	}
	if target == "" {
		return fmt.Errorf("machine %q has no host configured; use --install-target", machineName)
	}

	if !reprovision {
		state, stateErr := readMachineState()
		if stateErr == nil {
			if rec, exists := state[machineName]; exists {
				output.Error(fmt.Sprintf("%s was already provisioned on %s.", machineName, rec.ProvisionedAt))
				output.Dimmed("  Re-provisioning will erase the existing NixOS installation.")
				output.Dimmed("  Pass --reprovision to proceed, or use `stackpanel deploy` for a non-destructive update.")
				return fmt.Errorf("machine already provisioned (pass --reprovision to override)")
			}
		}
	}

	hardwareDir := filepath.Join(".stackpanel", "hardware", machineName)

	var hwConfigGenerated bool
	var provisionErr error

	if format {
		hwConfigGenerated, provisionErr = runDiskoInstall(machineName, target, hardwareDir, noHardwareConfig, dryRun)
	} else {
		hwConfigGenerated, provisionErr = runKexecInstall(machineName, target, hardwareDir, noHardwareConfig, dryRun)
	}

	if provisionErr != nil {
		return provisionErr
	}

	// Update known_hosts with the new host key so subsequent deploys can SSH in
	// without a "host key has changed" error. The machine is rebooting at this
	// point so we retry until it comes back up (up to 3 minutes).
	output.Info("Waiting for machine to come back up and updating known_hosts...")
	if err := updateKnownHosts(target, dryRun); err != nil {
		output.Warning(fmt.Sprintf("Could not update known_hosts: %v", err))
		output.Dimmed("  Run manually: ssh-keygen -R " + target + " && ssh-keyscan " + target + " >> ~/.ssh/known_hosts")
	}

	rec := MachineRecord{
		ProvisionedAt:           time.Now().UTC().Format(time.RFC3339),
		InstallTarget:           target,
		HardwareConfigGenerated: hwConfigGenerated,
		NixRevision:             gitRevision(),
	}
	if hwConfigGenerated {
		rec.HardwareConfigPath = hardwareDir
	}
	if err := recordMachineProvision(machineName, rec); err != nil {
		output.Warning(fmt.Sprintf("Failed to record provision state: %v", err))
	}

	output.Success(fmt.Sprintf("Provisioned %s", machineName))
	fmt.Println()
	if hwConfigGenerated {
		fmt.Printf("Hardware config: %s\n", hardwareDir)
		fmt.Println("Auto-included in future deploys. Commit to make it permanent:")
		fmt.Printf("  git commit -m 'Add hardware config for %s'\n", machineName)
	}

	return nil
}

// ===========================================================================
// runKexecInstall — default provisioning path (no --format)
//
// Installs NixOS onto a running Linux VM without reformatting the disk:
//
//   Step 1  SSH to the running system (Debian/Ubuntu/etc.)
//           Detect disk layout via shell commands → generate hardware-configuration.nix
//           git-stage it so the Nix flake eval can include it.
//
//   Step 2  nixos-anywhere --phases kexec
//           Reboots the target into a NixOS RAM installer.
//           Hardware config is now in the flake (git-staged → included in
//           dirty-flake store copy).
//
//   Step 3  SSH to the NixOS installer → mkfs (wipe) + mount /mnt
//           Fresh filesystem eliminates conflicts with the old OS files.
//
//   Step 4  nixos-anywhere --phases install,reboot
//           Builds NixOS from the flake, copies it to /mnt, installs
//           the bootloader, and reboots into the new NixOS system.
//
// No disk partitioning or pre-existing disk config required.
// ===========================================================================

func runKexecInstall(machineName, target, hardwareDir string, noHardwareConfig, dryRun bool) (hwConfigGenerated bool, err error) {
	installHost := "root@" + target
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	var hwInfo *hardwareInfo

	if !noHardwareConfig {
		output.Info("[1/3] Detecting hardware configuration...")
		if !dryRun {
			hwInfo, err = detectHardwareInfo(ctx, installHost)
			if err != nil {
				return false, fmt.Errorf("hardware detection: %w", err)
			}
			if hwInfo.InInstaller {
				output.Dimmed("  Target is in NixOS installer — detecting from block devices")
			}

			nixConfig := hwInfo.toNixConfig()
			if err := os.MkdirAll(filepath.Dir(hardwareDir), 0o755); err != nil {
				return false, fmt.Errorf("creating hardware dir: %w", err)
			}
			if err := os.WriteFile(hardwareDir, []byte(nixConfig), 0o644); err != nil {
				return false, fmt.Errorf("writing hardware config: %w", err)
			}
			output.Success(fmt.Sprintf("Hardware config written to %s", hardwareDir))
			output.Dimmed(fmt.Sprintf("  Root: %s (%s), Disk: %s, UEFI: %v",
				hwInfo.RootDevice, hwInfo.RootFSType, hwInfo.RootDisk, hwInfo.IsUEFI))

			if err := exec.Command("git", "add", hardwareDir).Run(); err != nil {
				output.Dimmed("Note: could not git-add hardware config")
			} else {
				output.Dimmed("Hardware config staged for flake inclusion")
			}
			hwConfigGenerated = true
		} else {
			output.Dimmed("dry-run: would SSH to detect hardware and generate hardware-configuration.nix")
		}
	}

	// kexec into NixOS installer — skip if the target is already in the installer.
	alreadyInInstaller := !dryRun && hwInfo != nil && hwInfo.InInstaller
	if alreadyInInstaller {
		output.Info("[2/3] Target already in NixOS installer (skipping kexec)")
	} else {
		output.Info("[2/3] Booting into NixOS installer (kexec)...")
		kexecArgs := []string{"--flake", ".#" + machineName, "--phases", "kexec", installHost}
		if err := runExternalCommand(ctx, "nixos-anywhere", kexecArgs, dryRun); err != nil {
			return hwConfigGenerated, fmt.Errorf("kexec: %w", err)
		}
		if !dryRun {
			output.Dimmed("Waiting for installer SSH to stabilize...")
			time.Sleep(20 * time.Second)
		}
	}

	if !dryRun && hwInfo != nil {
		// Mount the root filesystem at /mnt in the installer environment.
		// nixos-anywhere's install phase expects /mnt to be set up when disko is skipped.
		output.Dimmed("Mounting target filesystem at /mnt...")
		mountScript := hwInfo.mountScript()
		if _, err := runSSHCapture(ctx, installHost, mountScript); err != nil {
			return hwConfigGenerated, fmt.Errorf("mounting filesystem at /mnt: %w\nScript: %s", err, mountScript)
		}
	} else if dryRun {
		output.Dimmed("dry-run: would mount root filesystem at /mnt in installer")
	}

	// Install NixOS.
	// --phases install,reboot: skip kexec (done) and disko (reusing existing layout).
	// nixos-anywhere builds the flake, copies the closure, runs nixos-install, reboots.
	output.Info("[3/3] Installing NixOS...")
	installArgs := []string{"--flake", ".#" + machineName, "--phases", "install,reboot", installHost}
	if err := runExternalCommand(ctx, "nixos-anywhere", installArgs, dryRun); err != nil {
		return hwConfigGenerated, fmt.Errorf("install: %w", err)
	}

	return hwConfigGenerated, nil
}

// ===========================================================================
// runDiskoInstall — --format path
//
// Uses nixos-anywhere with disko to partition and format the disk before
// installing NixOS. Requires diskLayout to be set in the machine config.
// Best for bare metal or when a custom partition layout is needed.
// ===========================================================================

func runDiskoInstall(machineName, target, hardwareDir string, noHardwareConfig, dryRun bool) (hwConfigGenerated bool, err error) {
	installHost := "root@" + target
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	var args []string
	args = append(args, "--flake", ".#"+machineName)
	// No --phases: run the full nixos-anywhere flow including disko.
	if !noHardwareConfig {
		args = append(args, "--generate-hardware-config", "nixos-generate-config", hardwareDir)
	}
	args = append(args, installHost)

	output.Info(fmt.Sprintf("Provisioning %s via nixos-anywhere", machineName))
	if err := runExternalCommand(ctx, "nixos-anywhere", args, dryRun); err != nil {
		return false, fmt.Errorf("nixos-anywhere: %w", err)
	}

	if !noHardwareConfig && !dryRun {
		if _, err := os.Stat(hardwareDir); err == nil {
			hwConfigGenerated = true
			exec.Command("git", "add", hardwareDir).Run()
		}
	}

	return hwConfigGenerated, nil
}

// ===========================================================================
// Hardware detection helpers
// ===========================================================================

// hardwareInfo holds hardware facts detected from a running Linux system.
type hardwareInfo struct {
	RootDevice  string // e.g. /dev/sda1, /dev/vda1
	RootFSType  string // e.g. ext4, btrfs
	RootUUID    string // filesystem UUID (preferred for stable fileSystems config)
	RootDisk    string // parent disk: /dev/sda, /dev/vda
	IsUEFI      bool   // true = UEFI (systemd-boot), false = BIOS (GRUB)
	IsVM        bool   // true = KVM/QEMU → include qemu-guest.nix profile
	InInstaller bool   // true = already running the NixOS kexec installer (tmpfs root)
}

// hwDetectScript gathers hardware facts from the target.
// Works in two modes:
//   - Running OS (Debian/Ubuntu/etc.): reads from mounted filesystems
//   - NixOS kexec installer (tmpfs root): reads from unmounted block devices via lsblk
const hwDetectScript = `
set -e
# Detect if we're in the kexec installer (root is a tmpfs)
ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
if [ "$ROOT_FS" = "tmpfs" ]; then
    IN_INSTALLER=true
    # Find the first real disk (sda, vda, nvme0n1, etc.)
    for DISK_PATH in /dev/sda /dev/vda /dev/nvme0n1 /dev/hda; do
        [ -b "$DISK_PATH" ] && ROOT_DISK="$DISK_PATH" && break
    done
    [ -z "$ROOT_DISK" ] && ROOT_DISK="/dev/sda"
    # Find root partition: prefer ext4/xfs/btrfs, fall back to first partition
    ROOT_DEVICE=$(lsblk -rno NAME,FSTYPE "$ROOT_DISK" 2>/dev/null \
        | awk '$2 ~ /^(ext4|xfs|btrfs)$/ {print "/dev/" $1; exit}')
    [ -z "$ROOT_DEVICE" ] && ROOT_DEVICE="${ROOT_DISK}1"
    ROOT_FSTYPE=$(lsblk -no FSTYPE "$ROOT_DEVICE" 2>/dev/null | head -1)
    [ -z "$ROOT_FSTYPE" ] && ROOT_FSTYPE="ext4"
    ROOT_UUID=$(lsblk -no UUID "$ROOT_DEVICE" 2>/dev/null | head -1 || echo "")
else
    IN_INSTALLER=false
    ROOT_DEVICE=$(findmnt -n -o SOURCE / 2>/dev/null || echo "/dev/sda1")
    ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "ext4")
    ROOT_UUID=$(findmnt -n -o UUID / 2>/dev/null \
        || blkid -s UUID -o value "$ROOT_DEVICE" 2>/dev/null || echo "")
    if command -v lsblk >/dev/null 2>&1; then
        PKNAME=$(lsblk -no PKNAME "$ROOT_DEVICE" 2>/dev/null | head -1)
        [ -n "$PKNAME" ] && ROOT_DISK="/dev/$PKNAME"
    fi
    [ -z "$ROOT_DISK" ] && ROOT_DISK=$(echo "$ROOT_DEVICE" | sed 's/p\?[0-9]\+$//')
fi

IS_UEFI=$([ -d /sys/firmware/efi ] && echo "true" || echo "false")
VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
printf 'ROOT_DEVICE=%s\nROOT_FSTYPE=%s\nROOT_UUID=%s\nIS_UEFI=%s\nROOT_DISK=%s\nVIRT=%s\nIN_INSTALLER=%s\n' \
    "$ROOT_DEVICE" "$ROOT_FSTYPE" "$ROOT_UUID" "$IS_UEFI" "$ROOT_DISK" "$VIRT" "$IN_INSTALLER"
`

// detectHardwareInfo SSHes to host and collects hardware facts.
func detectHardwareInfo(ctx context.Context, host string) (*hardwareInfo, error) {
	raw, err := runSSHCapture(ctx, host, hwDetectScript)
	if err != nil {
		return nil, err
	}
	info := &hardwareInfo{}
	for _, line := range strings.Split(string(raw), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		switch k {
		case "ROOT_DEVICE":
			info.RootDevice = v
		case "ROOT_FSTYPE":
			info.RootFSType = v
		case "ROOT_UUID":
			info.RootUUID = v
		case "IS_UEFI":
			info.IsUEFI = v == "true"
		case "ROOT_DISK":
			info.RootDisk = v
		case "VIRT":
			info.IsVM = v == "kvm" || v == "qemu" || v == "vmware" || v == "virtualbox"
		case "IN_INSTALLER":
			info.InInstaller = v == "true"
		}
	}
	// Fallbacks for minimal/unusual environments
	if info.RootDevice == "" {
		info.RootDevice = "/dev/sda1"
	}
	if info.RootFSType == "" {
		info.RootFSType = "ext4"
	}
	if info.RootDisk == "" {
		info.RootDisk = strings.TrimRight(info.RootDevice, "0123456789")
	}
	return info, nil
}

// toNixConfig generates a hardware-configuration.nix from the detected info.
// The generated config is intentionally minimal and covers the common VPS case.
// For complex setups (LVM, ZFS, multiple disks), review and adjust manually.
func (info *hardwareInfo) toNixConfig() string {
	// Prefer UUID-based device reference for partition stability across reboots
	rootRef := info.RootDevice
	if info.RootUUID != "" {
		rootRef = "/dev/disk/by-uuid/" + info.RootUUID
	}

	importsBlock := ""
	if info.IsVM {
		importsBlock = "\n  imports = [ (modulesPath + \"/profiles/qemu-guest.nix\") ];\n"
	}

	var bootBlock string
	if info.IsUEFI {
		bootBlock = `
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;`
	} else {
		bootBlock = fmt.Sprintf(`
  boot.loader.grub = {
    enable = true;
    device = %q;
  };`, info.RootDisk)
	}

	return fmt.Sprintf(`# Generated by stackpanel provision (nixos-infect method).
# Review and commit — auto-included in the NixOS config via deploy.nix.
# For complex setups (LVM, ZFS, multiple disks) adjust as needed.
{ config, lib, pkgs, modulesPath, ... }:
{%s
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
%s

  fileSystems."/" = {
    device = %q;
    fsType = %q;
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
`, importsBlock, bootBlock, rootRef, info.RootFSType)
}

// mountScript returns a shell script to prepare and mount the root filesystem
// at /mnt in the NixOS installer environment (after kexec).
//
// The partition is reformatted with mkfs before mounting to ensure a clean
// slate — installing NixOS on top of an existing OS (Debian, Ubuntu, etc.)
// leaves conflicting /etc files that break NixOS boot. The original UUID is
// preserved so the generated hardware-configuration.nix stays valid.
func (info *hardwareInfo) mountScript() string {
	fstype := info.RootFSType
	if fstype == "" {
		fstype = "ext4"
	}
	// Use UUID flag to preserve the filesystem UUID so hardware config stays valid.
	uuidFlag := ""
	if info.RootUUID != "" {
		uuidFlag = fmt.Sprintf(" -U %s", info.RootUUID)
	}

	rootRef := info.RootDevice
	if info.RootUUID != "" {
		rootRef = "/dev/disk/by-uuid/" + info.RootUUID
	}

	script := fmt.Sprintf(
		"modprobe %[1]s 2>/dev/null || true\n"+
			"umount /mnt 2>/dev/null || true\n"+
			"mkfs.%[1]s%[2]s -F %[3]s\n"+ // wipe + preserve UUID
			"mount -t %[1]s %[4]q /mnt",
		fstype, uuidFlag, info.RootDevice, rootRef,
	)
	if info.IsUEFI {
		script += "\nmkdir -p /mnt/boot/efi"
	}
	return script
}

// ===========================================================================
// SSH helpers
// ===========================================================================

// updateKnownHosts removes any stale known_hosts entry for host and waits for
// the machine to come back up (it reboots at the end of provisioning), then
// scans the new host key and appends it. This prevents "host key has changed"
// errors on the first colmena deploy after provisioning.
func updateKnownHosts(host string, dryRun bool) error {
	// Strip user@ prefix — known_hosts uses bare host/IP.
	target := host
	if idx := strings.LastIndex(host, "@"); idx >= 0 {
		target = host[idx+1:]
	}

	if dryRun {
		output.Dimmed("dry-run: would run ssh-keygen -R " + target + " && ssh-keyscan -H " + target)
		return nil
	}

	// Remove old entry (ignore errors — entry may not exist).
	exec.Command("ssh-keygen", "-R", target).Run()

	knownHostsPath := filepath.Join(os.Getenv("HOME"), ".ssh", "known_hosts")

	// Retry until the machine comes back up (max 3 minutes).
	deadline := time.Now().Add(3 * time.Minute)
	var lastErr error
	for time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		out, err := exec.CommandContext(ctx, "ssh-keyscan", "-T", "8", "-H", target).Output()
		cancel()
		if err == nil && len(strings.TrimSpace(string(out))) > 0 {
			if err := os.MkdirAll(filepath.Dir(knownHostsPath), 0o700); err != nil {
				return err
			}
			f, err := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
			if err != nil {
				return err
			}
			_, writeErr := f.WriteString(string(out))
			f.Close()
			if writeErr != nil {
				return writeErr
			}
			output.Success("known_hosts updated for " + target)
			return nil
		}
		lastErr = err
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("timed out waiting for SSH on %s: %w", target, lastErr)
}

// runSSHCapture runs a command on a remote host via SSH and returns stdout.
// Uses accept-new host key policy — suitable for newly installed systems.
func runSSHCapture(ctx context.Context, host, command string) ([]byte, error) {
	args := []string{
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "ConnectTimeout=60",
		"-o", "ServerAliveInterval=15",
		"-o", "ServerAliveCountMax=8",
		host,
		command,
	}
	cmd := exec.CommandContext(ctx, "ssh", args...)
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("ssh failed: %w\nstderr: %s", err, string(exitErr.Stderr))
		}
		return nil, err
	}
	return out, nil
}
