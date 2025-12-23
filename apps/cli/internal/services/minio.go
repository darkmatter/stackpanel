package services

import (
	"fmt"
	"os"
	"syscall"
)

// MinioService manages the Minio S3-compatible service
type MinioService struct {
	BaseService
	consolePort int
}

func init() {
	Register(NewMinioService())
}

// NewMinioService creates a new Minio service
func NewMinioService() *MinioService {
	return &MinioService{
		BaseService: NewBaseService("minio", "Minio", 9000, "s3"),
		consolePort: 9001,
	}
}

func (m *MinioService) ConsolePort() int {
	return m.consolePort
}

func (m *MinioService) Start() error {
	// Ensure directories
	if err := m.EnsureDir(); err != nil {
		return err
	}

	// Check if already running
	if status := m.Status(); status.Running {
		return nil
	}

	// Set default credentials if not set
	if os.Getenv("MINIO_ROOT_USER") == "" {
		os.Setenv("MINIO_ROOT_USER", "minioadmin")
	}
	if os.Getenv("MINIO_ROOT_PASSWORD") == "" {
		os.Setenv("MINIO_ROOT_PASSWORD", "minioadmin")
	}

	// Start Minio in background
	cmd := NewBackgroundProcess("minio", "server", m.DataDir(),
		"--address", fmt.Sprintf(":%d", m.Port()),
		"--console-address", fmt.Sprintf(":%d", m.consolePort),
	)

	logFd, _ := os.OpenFile(m.LogFile(), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	cmd.Stdout = logFd
	cmd.Stderr = logFd

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("minio start failed: %v", err)
	}

	m.WritePID(cmd.Process.Pid)
	return nil
}

func (m *MinioService) Stop() error {
	status := m.Status()
	if !status.Running {
		return nil
	}

	if status.PID > 0 {
		if err := KillProcess(status.PID, syscall.SIGTERM); err != nil {
			KillProcess(status.PID, syscall.SIGKILL)
		}
	}

	m.RemovePID()
	return nil
}

func (m *MinioService) Status() ServiceStatus {
	status := ServiceStatus{
		Port: m.Port(),
		Info: make(map[string]string),
	}

	pid := m.ReadPID()
	if pid > 0 && IsProcessRunning(pid) {
		status.Running = true
		status.PID = pid
	} else if IsPortInUse(m.Port()) {
		if portPid := GetPIDOnPort(m.Port()); portPid > 0 {
			status.Running = true
			status.PID = portPid
			m.WritePID(portPid)
		}
	}

	return status
}

func (m *MinioService) StatusInfo() map[string]string {
	return map[string]string{
		"API":      fmt.Sprintf("http://localhost:%d", m.Port()),
		"Console":  fmt.Sprintf("http://localhost:%d", m.consolePort),
		"User":     "minioadmin",
		"Password": "minioadmin",
	}
}
