package services

import "os/exec"

// NewBackgroundProcess creates a process that won't be killed when parent exits
func NewBackgroundProcess(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	// Don't attach to parent process group
	cmd.SysProcAttr = nil
	return cmd
}
