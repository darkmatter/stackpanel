package services

import "os/exec"

// NewBackgroundProcess creates an exec.Cmd that survives the parent CLI process
// exiting. This is critical for services like PostgreSQL that must keep running
// after `stack services start` returns.
//
// Note: SysProcAttr is set to nil (the zero value) which relies on Go's default
// behavior of not setting Setpgid. On macOS/Linux, the child process inherits
// the parent's process group but isn't killed on parent exit since there's no
// Pdeathsig set. For stronger detachment, consider setting Setpgid: true.
func NewBackgroundProcess(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = nil
	return cmd
}
