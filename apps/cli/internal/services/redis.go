package services

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// RedisService manages the Redis service
type RedisService struct {
	BaseService
}

func init() {
	Register(NewRedisService())
}

// NewRedisService creates a new Redis service
func NewRedisService() *RedisService {
	return &RedisService{
		BaseService: NewBaseService("redis", "Redis", 6379, "rd"),
	}
}

func (r *RedisService) ConfigFile() string {
	return filepath.Join(r.ServiceDir(), "redis.conf")
}

func (r *RedisService) SocketFile() string {
	return filepath.Join(r.ServiceDir(), "redis.sock")
}

func (r *RedisService) ConfigDir() string {
	return filepath.Join(r.ServiceDir(), "config.d")
}

func (r *RedisService) Start() error {
	// Ensure directories
	if err := r.EnsureDir(); err != nil {
		return err
	}
	os.MkdirAll(r.ConfigDir(), 0755)

	// Check if already running
	if status := r.Status(); status.Running {
		return nil
	}

	// Generate config
	config := fmt.Sprintf(`# Global Redis configuration
port %d
bind 127.0.0.1
unixsocket %s
unixsocketperm 700
dir %s
pidfile %s
logfile %s
daemonize yes

# Include project-specific configs
include %s/*.conf
`, r.Port(), r.SocketFile(), r.DataDir(), r.PidFile(), r.LogFile(), r.ConfigDir())

	if err := os.WriteFile(r.ConfigFile(), []byte(config), 0644); err != nil {
		return err
	}

	// Start Redis
	cmd := exec.Command("redis-server", r.ConfigFile())
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("redis-server failed: %v\n%s", err, output)
	}

	return nil
}

func (r *RedisService) Stop() error {
	status := r.Status()
	if !status.Running {
		return nil
	}

	// Try graceful shutdown first
	cmd := exec.Command("redis-cli", "-p", fmt.Sprintf("%d", r.Port()), "shutdown")
	if err := cmd.Run(); err != nil {
		// Force kill
		if status.PID > 0 {
			KillProcess(status.PID, 9)
		}
	}

	r.RemovePID()
	return nil
}

func (r *RedisService) Status() ServiceStatus {
	status := ServiceStatus{
		Port: r.Port(),
		Info: make(map[string]string),
	}

	pid := r.ReadPID()
	if pid > 0 && IsProcessRunning(pid) {
		status.Running = true
		status.PID = pid
	} else if IsPortInUse(r.Port()) {
		if portPid := GetPIDOnPort(r.Port()); portPid > 0 {
			status.Running = true
			status.PID = portPid
			r.WritePID(portPid)
		}
	}

	return status
}

func (r *RedisService) StatusInfo() map[string]string {
	info := map[string]string{
		"Socket": r.SocketFile(),
	}

	// Try to get version
	cmd := exec.Command("redis-cli", "-p", fmt.Sprintf("%d", r.Port()), "INFO", "server")
	output, err := cmd.Output()
	if err == nil {
		for _, line := range strings.Split(string(output), "\n") {
			if strings.HasPrefix(line, "redis_version:") {
				info["Version"] = strings.TrimSpace(strings.TrimPrefix(line, "redis_version:"))
			}
		}
	}

	return info
}
