package services

import "testing"

func TestNewBackgroundProcess(t *testing.T) {
	cmd := NewBackgroundProcess("sleep", "0")
	if cmd.SysProcAttr != nil {
		t.Fatalf("expected SysProcAttr to remain nil")
	}
}
