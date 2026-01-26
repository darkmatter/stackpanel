// Package server provides process-compose integration handlers.
package server

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
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
	Port      int           `json:"port,omitempty"`
	Error     string        `json:"error,omitempty"`
}

// getProcessComposePort returns the port for the process-compose API.
// Reads from PC_PORT_NUM environment variable, defaults to 8080.
func getProcessComposePort() string {
	port := os.Getenv("PC_PORT_NUM")
	if port == "" {
		port = "8080"
	}
	return port
}

// handleProcessComposeProcesses returns the list of processes and their status.
// Uses the process-compose HTTP API instead of the CLI for better performance.
func (s *Server) handleProcessComposeProcesses(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	port := getProcessComposePort()
	response := ProcessComposeStatusResponse{
		Available: false,
		Running:   false,
		Processes: []ProcessInfo{},
	}

	// Try to fetch from the process-compose HTTP API
	client := &http.Client{
		Timeout: 2 * time.Second,
	}

	apiURL := fmt.Sprintf("http://localhost:%s/processes", port)
	resp, err := client.Get(apiURL)
	if err != nil {
		// Connection failed - process-compose server not running
		if strings.Contains(err.Error(), "connection refused") ||
			strings.Contains(err.Error(), "dial") {
			response.Error = "process-compose server not running"
		} else {
			response.Error = fmt.Sprintf("failed to connect to process-compose API: %v", err)
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}
	defer resp.Body.Close()

	response.Available = true

	if resp.StatusCode != http.StatusOK {
		response.Error = fmt.Sprintf("process-compose API returned status %d", resp.StatusCode)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	// Read and parse the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		response.Error = fmt.Sprintf("failed to read process-compose response: %v", err)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	// Parse the JSON output from process-compose API
	// The API returns: { "data": [...processes...] }
	var pcOutput struct {
		Data []struct {
			Name       string `json:"name"`
			Namespace  string `json:"namespace"`
			Status     string `json:"status"`
			PID        int    `json:"pid"`
			ExitCode   int    `json:"exit_code"`
			IsRunning  bool   `json:"is_running"`
			Restarts   int    `json:"restarts"`
			SystemTime string `json:"system_time"`
		} `json:"data"`
	}

	if err := json.Unmarshal(body, &pcOutput); err != nil {
		response.Error = fmt.Sprintf("failed to parse process-compose response: %v", err)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data":    response,
		})
		return
	}

	// Convert to our format
	for _, p := range pcOutput.Data {
		response.Processes = append(response.Processes, ProcessInfo{
			Name:       p.Name,
			Namespace:  p.Namespace,
			Status:     p.Status,
			PID:        p.PID,
			ExitCode:   p.ExitCode,
			IsRunning:  p.IsRunning, // Use the API's is_running field directly
			Restarts:   p.Restarts,
			SystemTime: p.SystemTime,
		})
	}

	// If we got a successful response, process-compose is running
	response.Running = true

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
