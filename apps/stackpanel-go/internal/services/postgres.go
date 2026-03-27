// Package services implements dev service lifecycle management for local
// development. Each service (postgres, redis, minio) self-registers via init()
// into the global service registry so the CLI can discover and manage them
// uniformly through the "stack services" commands.
package services

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	svc "github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
)

// PostgresService manages a project-local PostgreSQL instance. Data is stored
// under the service directory so each stack project gets an isolated cluster.
type PostgresService struct {
	svc.BaseService
}

func init() {
	svc.Register(NewPostgresService())
}

// NewPostgresService creates a new PostgreSQL service
func NewPostgresService() *PostgresService {
	return &PostgresService{
		BaseService: svc.NewBaseService("postgres", "PostgreSQL", 5432, "pg", "postgresql"),
	}
}

// SocketDir returns the Unix socket directory. Postgres requires sockets in a
// short path (< 107 chars on most systems) - ServiceDir is kept shallow for this.
func (p *PostgresService) SocketDir() string {
	return filepath.Join(p.ServiceDir(), "socket")
}

// DatabasesDir holds per-project .conf files listing databases to auto-create.
// Format: one "database=<name>" per line.
func (p *PostgresService) DatabasesDir() string {
	return filepath.Join(p.ServiceDir(), "databases.d")
}

func (p *PostgresService) Start() error {
	// Ensure directories
	if err := p.EnsureDir(); err != nil {
		return err
	}
	os.MkdirAll(p.SocketDir(), 0755)
	os.MkdirAll(p.DatabasesDir(), 0755)

	// Check if already running
	if status := p.Status(); status.Running {
		// Just ensure registered databases exist
		p.createRegisteredDatabases()
		return nil
	}

	// Initialize if needed
	if _, err := os.Stat(filepath.Join(p.DataDir(), "PG_VERSION")); os.IsNotExist(err) {
		cmd := exec.Command("initdb", "-D", p.DataDir(), "--locale=C", "--encoding=UTF8")
		if output, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("initdb failed: %v\n%s", err, output)
		}
	}

	// Start PostgreSQL
	cmd := exec.Command("pg_ctl", "start",
		"-D", p.DataDir(),
		"-l", p.LogFile(),
		"-o", fmt.Sprintf("-p %d -k %s -c listen_addresses=127.0.0.1", p.Port(), p.SocketDir()),
		"-w",
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("pg_ctl start failed: %v\n%s", err, output)
	}

	// Read PID from postmaster.pid rather than trusting pg_ctl output.
	// The first line of this file is always the PID.
	postmasterPid := filepath.Join(p.DataDir(), "postmaster.pid")
	if data, err := os.ReadFile(postmasterPid); err == nil {
		lines := strings.Split(string(data), "\n")
		if len(lines) > 0 {
			pid, _ := strconv.Atoi(lines[0])
			p.WritePID(pid)
		}
	}

	// Create registered databases
	p.createRegisteredDatabases()

	return nil
}

func (p *PostgresService) Stop() error {
	if status := p.Status(); !status.Running {
		return nil
	}

	cmd := exec.Command("pg_ctl", "stop", "-D", p.DataDir(), "-m", "fast")
	if err := cmd.Run(); err != nil {
		return err
	}

	p.RemovePID()
	return nil
}

// Status checks liveness via PID file first, then falls back to port probing.
// The fallback handles cases where postgres was started outside our control.
func (p *PostgresService) Status() svc.ServiceStatus {
	status := svc.ServiceStatus{
		Port: p.Port(),
		Info: make(map[string]string),
	}

	pid := p.ReadPID()
	if pid > 0 && svc.IsProcessRunning(pid) {
		status.Running = true
		status.PID = pid
	} else if svc.IsPortInUse(p.Port()) {
		if portPid := svc.GetPIDOnPort(p.Port()); portPid > 0 {
			status.Running = true
			status.PID = portPid
			p.WritePID(portPid)
		}
	}

	return status
}

func (p *PostgresService) StatusInfo() map[string]string {
	info := map[string]string{
		"Socket": p.SocketDir(),
	}

	// List registered projects
	entries, _ := os.ReadDir(p.DatabasesDir())
	var projects []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".conf") {
			project := strings.TrimSuffix(e.Name(), ".conf")
			data, _ := os.ReadFile(filepath.Join(p.DatabasesDir(), e.Name()))
			var dbs []string
			for _, line := range strings.Split(string(data), "\n") {
				if strings.HasPrefix(line, "database=") {
					dbs = append(dbs, strings.TrimPrefix(line, "database="))
				}
			}
			projects = append(projects, fmt.Sprintf("%s: %s", project, strings.Join(dbs, ", ")))
		}
	}
	if len(projects) > 0 {
		info["Projects"] = strings.Join(projects, "; ")
	}

	return info
}

// createRegisteredDatabases ensures all databases declared in databases.d/*.conf
// exist. This is called on every start so new projects get their databases
// without requiring a full service restart.
func (p *PostgresService) createRegisteredDatabases() {
	entries, _ := os.ReadDir(p.DatabasesDir())
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".conf") {
			continue
		}
		data, _ := os.ReadFile(filepath.Join(p.DatabasesDir(), e.Name()))
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "database=") {
				dbName := strings.TrimPrefix(line, "database=")
				// Check if exists
				cmd := exec.Command("psql", "-h", p.SocketDir(), "-p", strconv.Itoa(p.Port()), "-lqt")
				output, _ := cmd.Output()
				if !strings.Contains(string(output), dbName) {
					exec.Command("createdb", "-h", p.SocketDir(), "-p", strconv.Itoa(p.Port()), dbName).Run()
				}
			}
		}
	}
}
