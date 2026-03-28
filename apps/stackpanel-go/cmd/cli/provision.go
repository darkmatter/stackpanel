// provision.go implements NixOS machine provisioning via two strategies:
//
//   - kexec (default): Boots the running Linux system into a NixOS RAM installer
//     via kexec, then installs NixOS without requiring disko or disk layout config.
//     Best for cloud VMs where the provider's default partitioning is acceptable.
//
//   - disko (--format): Partitions and formats the disk before installing NixOS.
//     Requires diskLayout in the machine config. Best for bare metal.
//
// Both paths generate hardware-configuration.nix and git-stage it so the Nix
// flake eval can include it during the install phase.
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

// @todo dont hard-code the path to the hardware-configuration.nix file
func machineHardwareConfigPaths(projectRoot, machineName string) (string, string, error) {
	if projectRoot == "" {
		return "", "", fmt.Errorf("could not find stackpanel project root")
	}

	relPath := filepath.Join(".stack", "machines", machineName, "hardware-configuration.nix")
	return filepath.Join(projectRoot, relPath), relPath, nil
}

func machineDiskLayoutPaths(projectRoot, machineName string) (string, string, error) {
	if projectRoot == "" {
		return "", "", fmt.Errorf("could not find stackpanel project root")
	}

	relPath := filepath.Join(".stack", "machines", machineName, "disks.nix")
	return filepath.Join(projectRoot, relPath), relPath, nil
}

// runProvisionMachine provisions a single machine. The --reprovision guard exists
// because re-provisioning is destructive (wipes the root filesystem), and users
// who just want to update an existing NixOS machine should use `stackpanel deploy`.
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

	projectRoot := detectStackpanelProject()
	hwConfigPath, hwConfigRelPath, err := machineHardwareConfigPaths(projectRoot, machineName)
	if err != nil {
		return fmt.Errorf("%w; try running from the repo root or set STACKPANEL_ROOT", err)
	}
	diskLayoutPath, diskLayoutRelPath, err := machineDiskLayoutPaths(projectRoot, machineName)
	if err != nil {
		return fmt.Errorf("%w; try running from the repo root or set STACKPANEL_ROOT", err)
	}

	var hwConfigGenerated bool
	var diskLayoutGenerated bool
	var provisionErr error

	if format {
		hwConfigGenerated, diskLayoutGenerated, provisionErr = runDiskoInstall(machineName, target, machine, hwConfigPath, diskLayoutPath, diskLayoutRelPath, noHardwareConfig, dryRun)
	} else {
		hwConfigGenerated, provisionErr = runKexecInstall(machineName, target, machine, hwConfigPath, noHardwareConfig, dryRun)
	}

	if provisionErr != nil {
		return provisionErr
	}

	// Update known_hosts with the new host key so subsequent deploys can SSH in
	// without a "host key has changed" error. The machine is rebooting at this
	// point so we retry until it comes back up (up to 3 minutes).
	output.Info("Waiting for machine to come back up and updating known_hosts...")
	if err := updateKnownHosts(target, machine, dryRun); err != nil {
		_, keygenTarget, sshArgs := knownHostsUpdateSSHArgs(target, machine)
		output.Warning(fmt.Sprintf("Could not update known_hosts: %v", err))
		output.Dimmed("  Run manually: ssh-keygen -R " + keygenTarget + " && ssh " + strings.Join(sshArgs, " "))
	}

	rec := MachineRecord{
		ProvisionedAt:           time.Now().UTC().Format(time.RFC3339),
		InstallTarget:           target,
		HardwareConfigGenerated: hwConfigGenerated,
		NixRevision:             gitRevision(),
	}
	if hwConfigGenerated {
		rec.HardwareConfigPath = hwConfigRelPath
	}
	if err := recordMachineProvision(machineName, rec); err != nil {
		output.Warning(fmt.Sprintf("Failed to record provision state: %v", err))
	}

	output.Success(fmt.Sprintf("Provisioned %s", machineName))
	fmt.Println()
	if diskLayoutGenerated {
		fmt.Printf("Disk layout: %s\n", diskLayoutRelPath)
	}
	if hwConfigGenerated {
		fmt.Printf("Hardware config: %s\n", hwConfigRelPath)
	}
	if diskLayoutGenerated || hwConfigGenerated {
		fmt.Println("Auto-included in future deploys. Commit to make it permanent:")
		if diskLayoutGenerated && hwConfigGenerated {
			fmt.Printf("  git commit -m 'Add machine disk and hardware config for %s'\n", machineName)
		} else if diskLayoutGenerated {
			fmt.Printf("  git commit -m 'Add disk layout for %s'\n", machineName)
		} else {
			fmt.Printf("  git commit -m 'Add hardware config for %s'\n", machineName)
		}
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

// sshArgs builds extra SSH flags for nixos-anywhere when proxyJump or a
// non-standard port is configured.
func sshArgs(machine DeployMachineConfig) []string {
	var args []string
	if machine.ProxyJump != "" {
		args = append(args, "--ssh-option", "ProxyJump="+machine.ProxyJump)
	}
	if machine.SSHPort != 0 && machine.SSHPort != 22 {
		args = append(args, "--ssh-option", fmt.Sprintf("Port=%d", machine.SSHPort))
	}
	return args
}

func runKexecInstall(machineName, target string, machine DeployMachineConfig, hwConfigPath string, noHardwareConfig, dryRun bool) (hwConfigGenerated bool, err error) {
	installHost := machine.User + "@" + target
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	var hwInfo *hardwareInfo

	if !noHardwareConfig {
		output.Info("[1/3] Detecting hardware configuration...")
		if !dryRun {
			hwInfo, err = detectHardwareInfo(ctx, installHost, machine)
			if err != nil {
				return false, fmt.Errorf("hardware detection: %w", err)
			}
			if hwInfo.needsFormatProvisioning() {
				return false, fmt.Errorf(
					"detected BIOS install on whole-disk filesystem %s; this layout often fails GRUB installation without a BIOS boot partition.\nRetry with: stackpanel provision %s --reprovision --format",
					hwInfo.RootDisk,
					machineName,
				)
			}
			if hwInfo.InInstaller {
				output.Dimmed("  Target is in NixOS installer — detecting from block devices")
			}

			nixConfig := hwInfo.toNixConfig()
			if err := os.MkdirAll(filepath.Dir(hwConfigPath), 0o755); err != nil {
				return false, fmt.Errorf("creating hardware dir: %w", err)
			}
			if err := os.WriteFile(hwConfigPath, []byte(nixConfig), 0o644); err != nil {
				return false, fmt.Errorf("writing hardware config: %w", err)
			}
			output.Success(fmt.Sprintf("Hardware config written to %s", hwConfigPath))
			output.Dimmed(fmt.Sprintf("  Root: %s (%s), Disk: %s, UEFI: %v",
				hwInfo.RootDevice, hwInfo.RootFSType, hwInfo.RootDisk, hwInfo.IsUEFI))

			if err := exec.Command("git", "add", hwConfigPath).Run(); err != nil {
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
		kexecArgs := append([]string{"--flake", ".#" + machineName, "--phases", "kexec"}, sshArgs(machine)...)
		kexecArgs = append(kexecArgs, installHost)
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
		if _, err := runSSHCapture(ctx, installHost, mountScript, machine); err != nil {
			return hwConfigGenerated, fmt.Errorf("mounting filesystem at /mnt: %w\nScript: %s", err, mountScript)
		}
	} else if dryRun {
		output.Dimmed("dry-run: would mount root filesystem at /mnt in installer")
	}

	// Install NixOS.
	// --phases install,reboot: skip kexec (done) and disko (reusing existing layout).
	// nixos-anywhere builds the flake, copies the closure, runs nixos-install, reboots.
	output.Info("[3/3] Installing NixOS...")
	installArgs := append([]string{"--flake", ".#" + machineName, "--phases", "install,reboot"}, sshArgs(machine)...)
	installArgs = append(installArgs, installHost)
	if err := runExternalCommand(ctx, "nixos-anywhere", installArgs, dryRun); err != nil {
		return hwConfigGenerated, fmt.Errorf("install: %w", err)
	}

	return hwConfigGenerated, nil
}

// ===========================================================================
// runDiskoInstall — --format path
//
// Uses nixos-anywhere with disko to partition and format the disk before
// installing NixOS. If no explicit diskLayout is configured, a starter
// .stack/machines/<machine>/disks.nix is generated from detected hardware facts.
// Best for bare metal or when a custom partition layout is needed.
// ===========================================================================

func runDiskoInstall(machineName, target string, machine DeployMachineConfig, hwConfigPath, diskLayoutPath, diskLayoutRelPath string, noHardwareConfig, dryRun bool) (hwConfigGenerated bool, diskLayoutGenerated bool, err error) {
	installHost := machine.User + "@" + target
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	if !machine.HasDiskLayout {
		if _, err := os.Stat(diskLayoutPath); err == nil {
			if !dryRun {
				exec.Command("git", "add", diskLayoutPath).Run()
			}
		} else if os.IsNotExist(err) {
			if dryRun {
				output.Dimmed("dry-run: would detect hardware and generate " + diskLayoutRelPath)
			} else {
				output.Info("Detecting hardware for starter disk layout...")
				hwInfo, detectErr := detectHardwareInfo(ctx, installHost, machine)
				if detectErr != nil {
					return false, false, fmt.Errorf("hardware detection for disk layout: %w", detectErr)
				}
				if err := os.MkdirAll(filepath.Dir(diskLayoutPath), 0o755); err != nil {
					return false, false, fmt.Errorf("creating disk layout dir: %w", err)
				}
				if err := os.WriteFile(diskLayoutPath, []byte(hwInfo.toDiskoConfig()), 0o644); err != nil {
					return false, false, fmt.Errorf("writing starter disk layout: %w", err)
				}
				exec.Command("git", "add", diskLayoutPath).Run()
				diskLayoutGenerated = true
				output.Success(fmt.Sprintf("Disk layout written to %s", diskLayoutRelPath))
			}
		} else {
			return false, false, fmt.Errorf("checking disk layout path: %w", err)
		}
	}

	var args []string
	args = append(args, "--flake", ".#"+machineName)
	if !noHardwareConfig {
		args = append(args, "--generate-hardware-config", "nixos-generate-config", hwConfigPath)
	}
	args = append(args, sshArgs(machine)...)
	args = append(args, installHost)

	if !noHardwareConfig && !dryRun {
		if err := os.MkdirAll(filepath.Dir(hwConfigPath), 0o755); err != nil {
			return false, diskLayoutGenerated, fmt.Errorf("creating machine dir: %w", err)
		}
	}
	output.Info(fmt.Sprintf("Provisioning %s via nixos-anywhere", machineName))
	if err := runExternalCommand(ctx, "nixos-anywhere", args, dryRun); err != nil {
		return false, diskLayoutGenerated, fmt.Errorf("nixos-anywhere: %w", err)
	}

	if !noHardwareConfig && !dryRun {
		if _, err := os.Stat(hwConfigPath); err == nil {
			hwConfigGenerated = true
			exec.Command("git", "add", hwConfigPath).Run()
		}
	}

	return hwConfigGenerated, diskLayoutGenerated, nil
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

// needsFormatProvisioning catches the BIOS whole-disk layout that later causes
// GRUB to fail with blocklist/embedding errors on the non-format path.
func (info *hardwareInfo) needsFormatProvisioning() bool {
	return !info.IsUEFI && info.RootDevice != "" && info.RootDevice == info.RootDisk
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
func detectHardwareInfo(ctx context.Context, host string, machine DeployMachineConfig) (*hardwareInfo, error) {
	raw, err := runSSHCapture(ctx, host, hwDetectScript, machine)
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

func (info *hardwareInfo) toDiskoConfig() string {
	rootDisk := info.RootDisk
	if rootDisk == "" {
		rootDisk = "/dev/vda"
	}

	var partitions string
	if info.IsUEFI {
		partitions = `
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };`
	} else {
		partitions = `
          bios = {
            size = "1M";
            type = "EF02";
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };`
	}

	return fmt.Sprintf(`{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = lib.mkDefault %q;
      content = {
        type = "gpt";
        partitions = {%s
        };
      };
    };
  };
}
`, rootDisk, partitions)
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

// knownHostsUpdateSSHArgs derives the hostnames and ssh command used to refresh
// known_hosts after provisioning. We probe with ssh instead of ssh-keyscan so
// ProxyJump and non-standard ports work the same way they do during provision.
func knownHostsUpdateSSHArgs(host string, machine DeployMachineConfig) (target string, keygenTarget string, args []string) {
	// Strip user@ prefix — known_hosts uses bare host/IP.
	target = host
	if idx := strings.LastIndex(host, "@"); idx >= 0 {
		target = host[idx+1:]
	}

	keygenTarget = target
	if machine.SSHPort != 0 && machine.SSHPort != 22 {
		keygenTarget = fmt.Sprintf("[%s]:%d", target, machine.SSHPort)
	}

	args = []string{
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=8",
	}
	if machine.ProxyJump != "" {
		args = append(args, "-J", machine.ProxyJump)
	}
	if machine.SSHPort != 0 && machine.SSHPort != 22 {
		args = append(args, "-p", fmt.Sprintf("%d", machine.SSHPort))
	}
	args = append(args, target, "true")
	return target, keygenTarget, args
}

// updateKnownHosts removes any stale known_hosts entry for host and waits for
// the machine to come back up (it reboots at the end of provisioning), then
// performs a real SSH handshake to repopulate known_hosts. This works for
// direct SSH as well as ProxyJump/private-network setups.
func updateKnownHosts(host string, machine DeployMachineConfig, dryRun bool) error {
	target, keygenTarget, sshArgs := knownHostsUpdateSSHArgs(host, machine)

	if dryRun {
		output.Dimmed("dry-run: would run ssh-keygen -R " + keygenTarget + " && ssh " + strings.Join(sshArgs, " "))
		return nil
	}

	// Remove old entry (ignore errors — entry may not exist).
	exec.Command("ssh-keygen", "-R", keygenTarget).Run()

	// Retry until the machine comes back up (max 3 minutes).
	deadline := time.Now().Add(3 * time.Minute)
	var lastErr error
	for time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		err := exec.CommandContext(ctx, "ssh", sshArgs...).Run()
		cancel()
		if err == nil {
			output.Success("known_hosts updated for " + target)
			return nil
		}
		lastErr = err
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("timed out waiting for SSH on %s: %w", target, lastErr)
}

// runSSHCapture runs a command on a remote host via SSH and returns stdout.
// Uses StrictHostKeyChecking=accept-new because provisioned machines always have
// new host keys, and we update known_hosts immediately after provisioning anyway.
func runSSHCapture(ctx context.Context, host, command string, machine DeployMachineConfig) ([]byte, error) {
	args := []string{
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "ConnectTimeout=60",
		"-o", "ServerAliveInterval=15",
		"-o", "ServerAliveCountMax=8",
	}
	if machine.ProxyJump != "" {
		args = append(args, "-J", machine.ProxyJump)
	}
	if machine.SSHPort != 0 && machine.SSHPort != 22 {
		args = append(args, "-p", fmt.Sprintf("%d", machine.SSHPort))
	}
	args = append(args, host, command)
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
