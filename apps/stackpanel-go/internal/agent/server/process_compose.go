// Package server provides process-compose integration handlers.
package server

import (
	"encoding/json"
	"net/http"
	"strings"
)

// ProcessInfo represents information about a running process from process-compose.
type ProcessInfo struct {
	Name       string `json:"name"`
	Namespace  string `json:"namespace,omitempty"`
	Status     string `json:"status"`
	PID        int    `json:"pid,omitempty"`
	ExitCode   int    `json:"exit_code,omitempty"`
	IsRunning  bool   `json:"is_running"`
	Restarts   int    `json:"restarts,omitempty"`
	SystemTime string `json:"system_time,omitempty"`
}

// ProcessComposeStatusResponse represents the response from the processes endpoint.
type ProcessComposeStatusResponse struct {
	Available bool          `json:"available"`
	Running   bool          `json:"running"`
	Processes []ProcessInfo `json:"processes"`
	Error     string        `json:"error,omitempty"`
}

// handleProcessComposeProcesses returns the list of processes and their status.
func (s *Server) handleProcessComposeProcesses(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	response := ProcessComposeStatusResponse{
		Available: false,
		Running:   false,
		Processes: []ProcessInfo{},
	}

	// Check if process-compose is available
	whichRes, err := s.exec.Run("which", "process-compose")
	if err != nil || whichRes.ExitCode != 0 {
		response.Error = "process-compose not found in PATH"
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	response.Available = true

	// Try to get process list from process-compose
	// Using -j flag for JSON output
	res, err := s.exec.Run("process-compose", "process", "list", "-j")
	if err != nil {
		response.Error = err.Error()
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	// process-compose returns exit code 1 if no processes are running
	if res.ExitCode != 0 {
		// Check if it's because process-compose server isn't running
		if strings.Contains(res.Stderr, "connection refused") ||
			strings.Contains(res.Stderr, "dial") ||
			strings.Contains(res.Stderr, "connect") {
			response.Error = "process-compose server not running"
		} else {
			response.Error = strings.TrimSpace(res.Stderr)
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	// Parse the JSON output
	// process-compose outputs a JSON object with a "data" array
	var pcOutput struct {
		Data []struct {
			Name       string `json:"name"`
			Namespace  string `json:"namespace"`
			Status     string `json:"status"`
			PID        int    `json:"pid"`
			ExitCode   int    `json:"exit_code"`
			Restarts   int    `json:"restarts"`
			SystemTime string `json:"system_time"`
		} `json:"data"`
	}

	if err := json.Unmarshal([]byte(res.Stdout), &pcOutput); err != nil {
		// Try parsing as a plain array (some versions output differently)
		var processes []struct {
			Name       string `json:"name"`
			Namespace  string `json:"namespace"`
			Status     string `json:"status"`
			PID        int    `json:"pid"`
			ExitCode   int    `json:"exit_code"`
			Restarts   int    `json:"restarts"`
			SystemTime string `json:"system_time"`
		}
		if err := json.Unmarshal([]byte(res.Stdout), &processes); err != nil {
			response.Error = "failed to parse process-compose output"
			s.writeJSON(w, http.StatusOK, map[string]interface{}{
				"success": true,
				"data":    response,
			})
			return
		}
		// Convert to our format
		for _, p := range processes {
			response.Processes = append(response.Processes, ProcessInfo{
				Name:       p.Name,
				Namespace:  p.Namespace,
				Status:     p.Status,
				PID:        p.PID,
				ExitCode:   p.ExitCode,
				IsRunning:  isProcessRunning(p.Status),
				Restarts:   p.Restarts,
				SystemTime: p.SystemTime,
			})
		}
	} else {
		// Convert from wrapped format
		for _, p := range pcOutput.Data {
			response.Processes = append(response.Processes, ProcessInfo{
				Name:       p.Name,
				Namespace:  p.Namespace,
				Status:     p.Status,
				PID:        p.PID,
				ExitCode:   p.ExitCode,
				IsRunning:  isProcessRunning(p.Status),
				Restarts:   p.Restarts,
				SystemTime: p.SystemTime,
			})
		}
	}

	// If we got processes, process-compose is running
	response.Running = len(response.Processes) > 0 || res.ExitCode == 0

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    response,
	})
}

// isProcessRunning determines if a process status indicates it's running.
func isProcessRunning(status string) bool {
	status = strings.ToLower(status)
	return status == "running" ||
		status == "launched" ||
		status == "restarting"
}
