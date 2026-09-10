//go:build !unix

package setupagent

import (
	"os/exec"
	"time"
)

func configureProcess(cmd *exec.Cmd) {
	cmd.WaitDelay = time.Second
}
