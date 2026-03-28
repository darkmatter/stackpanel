package cmd

import (
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestMachineHardwareConfigPaths(t *testing.T) {
	projectRoot := t.TempDir()

	absPath, relPath, err := machineHardwareConfigPaths(projectRoot, "volt-2")
	if err != nil {
		t.Fatalf("machineHardwareConfigPaths returned error: %v", err)
	}

	wantRel := filepath.Join(".stack", "machines", "volt-2", "hardware-configuration.nix")
	if relPath != wantRel {
		t.Fatalf("relPath = %q, want %q", relPath, wantRel)
	}

	wantAbs := filepath.Join(projectRoot, wantRel)
	if absPath != wantAbs {
		t.Fatalf("absPath = %q, want %q", absPath, wantAbs)
	}
}

func TestMachineDiskLayoutPaths(t *testing.T) {
	projectRoot := t.TempDir()

	absPath, relPath, err := machineDiskLayoutPaths(projectRoot, "volt-2")
	if err != nil {
		t.Fatalf("machineDiskLayoutPaths returned error: %v", err)
	}

	wantRel := filepath.Join(".stack", "machines", "volt-2", "disks.nix")
	if relPath != wantRel {
		t.Fatalf("relPath = %q, want %q", relPath, wantRel)
	}

	wantAbs := filepath.Join(projectRoot, wantRel)
	if absPath != wantAbs {
		t.Fatalf("absPath = %q, want %q", absPath, wantAbs)
	}
}

func TestHardwareInfoToDiskoConfigBIOS(t *testing.T) {
	info := hardwareInfo{
		RootDisk: "/dev/vda",
		IsUEFI:   false,
	}

	got := info.toDiskoConfig()
	for _, want := range []string{
		`device = lib.mkDefault "/dev/vda";`,
		`type = "gpt";`,
		`type = "EF02";`,
		`mountpoint = "/";`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("expected BIOS disko config to contain %q, got:\n%s", want, got)
		}
	}
}

func TestHardwareInfoNeedsFormatRecommendationForWholeDiskBIOS(t *testing.T) {
	info := hardwareInfo{
		RootDevice: "/dev/vda",
		RootDisk:   "/dev/vda",
		IsUEFI:     false,
	}

	if !info.needsFormatProvisioning() {
		t.Fatalf("expected whole-disk BIOS install to require --format guidance")
	}
}

func TestHardwareInfoDoesNotNeedFormatRecommendationForPartitionedBIOS(t *testing.T) {
	info := hardwareInfo{
		RootDevice: "/dev/vda1",
		RootDisk:   "/dev/vda",
		IsUEFI:     false,
	}

	if info.needsFormatProvisioning() {
		t.Fatalf("did not expect partitioned BIOS install to require --format guidance")
	}
}

func TestKnownHostsUpdateSSHArgs(t *testing.T) {
	machine := DeployMachineConfig{
		SSHPort:   2222,
		ProxyJump: "root@jump-host",
	}

	target, keygenTarget, args := knownHostsUpdateSSHArgs("root@10.0.100.11", machine)
	if target != "10.0.100.11" {
		t.Fatalf("target = %q, want %q", target, "10.0.100.11")
	}
	if keygenTarget != "[10.0.100.11]:2222" {
		t.Fatalf("keygenTarget = %q, want %q", keygenTarget, "[10.0.100.11]:2222")
	}
	for _, want := range []string{
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "BatchMode=yes",
		"-J", "root@jump-host",
		"-p", "2222",
		"10.0.100.11",
		"true",
	} {
		if !slices.Contains(args, want) {
			t.Fatalf("expected args to contain %q, got %v", want, args)
		}
	}
}
