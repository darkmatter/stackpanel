// Package server provides process-compose integration handlers.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/gorilla/websocket"
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

// ProjectState represents the project state from process-compose.
type ProjectState struct {
	FileNames        []string `json:"fileNames,omitempty"`
	ProcessNum       int      `json:"processNum"`
	RunningProcesses int      `json:"runningProcessNum"`
	HostName         string   `json:"hostName,omitempty"`
	Version          string   `json:"version,omitempty"`
	MemoryState      *struct {
		Allocated uint64 `json:"allocated,omitempty"`
		Total     uint64 `json:"total,omitempty"`
		System    uint64 `json:"system,omitempty"`
	} `json:"memoryState,omitempty"`
}

// ProcessPorts represents ports used by a process.
type ProcessPorts struct {
	Name     string `json:"name"`
	TcpPorts []int  `json:"tcpPorts,omitempty"`
	UdpPorts []int  `json:"udpPorts,omitempty"`
}

// ProcessLogs represents log output from a process.
type ProcessLogs struct {
	Logs []string `json:"logs"`
}

// LogMessage represents a single log message for WebSocket streaming.
type LogMessage struct {
	ProcessName string `json:"processName"`
	Message     string `json:"message"`
}

// getProcessComposePort returns the port for the process-compose API.
// Reads from PC_PORT_NUM environment variable, defaults to 8080.
func getProcessComposePort() string {
	port := os.Getenv("PC_PORT_NUM")
	if port == "" {
		if fallback := getProcessComposePortFromState(); fallback != "" {
			return fallback
		}
		port = "8080"
	}
	return port
}

func getProcessComposePortFromState() string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	config, err := nixeval.GetConfigWithEval(ctx, "")
	if err != nil {
		return ""
	}

	if config.ProcessComposePort <= 0 {
		return ""
	}

	return strconv.Itoa(config.ProcessComposePort)
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

// getProcessComposeClient returns an HTTP client configured for process-compose API calls.
func getProcessComposeClient() *http.Client {
	return &http.Client{
		Timeout: 5 * time.Second,
	}
}

// getProcessComposeBaseURL returns the base URL for the process-compose API.
func getProcessComposeBaseURL() string {
	return fmt.Sprintf("http://localhost:%s", getProcessComposePort())
}

// handleProcessComposeProjectState returns the project state from process-compose.
// GET /api/process-compose/project/state
func (s *Server) handleProcessComposeProjectState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/project/state?withMemory=true"

	resp, err := client.Get(apiURL)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": map[string]interface{}{
				"available": false,
				"error":     fmt.Sprintf("process-compose server not running (tried %s)", apiURL),
			},
		})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": map[string]interface{}{
				"available": false,
				"error":     "failed to read response",
			},
		})
		return
	}

	// Check for non-2xx status codes
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		preview := string(body)
		if len(preview) > 200 {
			preview = preview[:200] + "..."
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": map[string]interface{}{
				"available": false,
				"error":     fmt.Sprintf("process-compose at %s returned status %d: %s", apiURL, resp.StatusCode, preview),
			},
		})
		return
	}

	// Check Content-Type to detect non-JSON responses early
	contentType := resp.Header.Get("Content-Type")
	if contentType != "" && !strings.Contains(contentType, "application/json") {
		preview := string(body)
		if len(preview) > 200 {
			preview = preview[:200] + "..."
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": map[string]interface{}{
				"available": false,
				"error":     fmt.Sprintf("process-compose returned non-JSON response (Content-Type: %s): %s", contentType, preview),
			},
		})
		return
	}

	// Parse as generic map to handle any response format
	var state map[string]interface{}
	if err := json.Unmarshal(body, &state); err != nil {
		// Include body preview for debugging
		preview := string(body)
		if len(preview) > 200 {
			preview = preview[:200] + "..."
		}
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"data": map[string]interface{}{
				"available": false,
				"error":     fmt.Sprintf("failed to parse response as JSON: %s", preview),
			},
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data": map[string]interface{}{
			"available": true,
			"state":     state,
		},
	})
}

// handleProcessComposeProcessInfo returns detailed info about a specific process.
// GET /api/process-compose/process/info/{name}
func (s *Server) handleProcessComposeProcessInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path: /api/process-compose/process/info/{name}
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/process/info/" + name

	resp, err := client.Get(apiURL)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read response")
		return
	}

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	var info map[string]interface{}
	if err := json.Unmarshal(body, &info); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse response")
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    info,
	})
}

// handleProcessComposeProcessPorts returns ports used by a specific process.
// GET /api/process-compose/process/ports/{name}
func (s *Server) handleProcessComposeProcessPorts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path: /api/process-compose/process/ports/{name}
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/process/ports/" + name

	resp, err := client.Get(apiURL)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read response")
		return
	}

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	var ports ProcessPorts
	if err := json.Unmarshal(body, &ports); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse response")
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    ports,
	})
}

// handleProcessComposeProcessLogs returns logs for a specific process.
// GET /api/process-compose/process/logs/{name}?offset=0&limit=100
func (s *Server) handleProcessComposeProcessLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path: /api/process-compose/process/logs/{name}
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	// Get query params
	offsetStr := r.URL.Query().Get("offset")
	limitStr := r.URL.Query().Get("limit")

	offset := 0
	limit := 100
	if offsetStr != "" {
		if v, err := strconv.Atoi(offsetStr); err == nil {
			offset = v
		}
	}
	if limitStr != "" {
		if v, err := strconv.Atoi(limitStr); err == nil {
			limit = v
		}
	}

	client := getProcessComposeClient()
	apiURL := fmt.Sprintf("%s/process/logs/%s/%d/%d", getProcessComposeBaseURL(), name, offset, limit)

	resp, err := client.Get(apiURL)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to read response")
		return
	}

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	var logs ProcessLogs
	if err := json.Unmarshal(body, &logs); err != nil {
		s.writeAPIError(w, http.StatusInternalServerError, "failed to parse response")
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"data":    logs,
	})
}

// handleProcessComposeStart starts a specific process.
// POST /api/process-compose/process/start/{name}
func (s *Server) handleProcessComposeStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/process/start/" + name

	req, _ := http.NewRequest(http.MethodPost, apiURL, nil)
	resp, err := client.Do(req)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("Process %s started", name),
	})
}

// handleProcessComposeStop stops a specific process.
// POST /api/process-compose/process/stop/{name}
func (s *Server) handleProcessComposeStop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/process/stop/" + name

	req, _ := http.NewRequest(http.MethodPatch, apiURL, nil)
	resp, err := client.Do(req)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("Process %s stopped", name),
	})
}

// handleProcessComposeRestart restarts a specific process.
// POST /api/process-compose/process/restart/{name}
func (s *Server) handleProcessComposeRestart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// Extract process name from path
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 6 {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}
	name := parts[5]

	client := getProcessComposeClient()
	apiURL := getProcessComposeBaseURL() + "/process/restart/" + name

	req, _ := http.NewRequest(http.MethodPost, apiURL, nil)
	resp, err := client.Do(req)
	if err != nil {
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   "process-compose server not running",
		})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		json.Unmarshal(body, &errResp)
		s.writeJSON(w, http.StatusOK, map[string]interface{}{
			"success": false,
			"error":   errResp["error"],
		})
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": fmt.Sprintf("Process %s restarted", name),
	})
}

// handleProcessComposeLogsWS streams process logs via WebSocket.
// Note: Uses the shared wsUpgrader from ws.go
// WS /api/process-compose/logs/ws?name=processName&offset=0&follow=true
func (s *Server) handleProcessComposeLogsWS(w http.ResponseWriter, r *http.Request) {
	processName := r.URL.Query().Get("name")
	if processName == "" {
		s.writeAPIError(w, http.StatusBadRequest, "process name required")
		return
	}

	follow := r.URL.Query().Get("follow") == "true"
	offsetStr := r.URL.Query().Get("offset")
	offset := 0
	if offsetStr != "" {
		if v, err := strconv.Atoi(offsetStr); err == nil {
			offset = v
		}
	}

	// Upgrade to WebSocket
	ws, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer ws.Close()

	// Connect to process-compose WebSocket
	pcURL := fmt.Sprintf("ws://localhost:%s/process/logs/ws?name=%s&offset=%d&follow=%t",
		getProcessComposePort(), processName, offset, follow)

	pcWS, _, err := websocket.DefaultDialer.Dial(pcURL, nil)
	if err != nil {
		ws.WriteJSON(map[string]string{"error": "Failed to connect to process-compose"})
		return
	}
	defer pcWS.Close()

	// Relay messages from process-compose to client
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			_, msg, err := ws.ReadMessage()
			if err != nil {
				return
			}
			// Forward any client messages to process-compose (for control)
			pcWS.WriteMessage(websocket.TextMessage, msg)
		}
	}()

	for {
		select {
		case <-done:
			return
		default:
			var logMsg LogMessage
			err := pcWS.ReadJSON(&logMsg)
			if err != nil {
				return
			}
			if err := ws.WriteJSON(logMsg); err != nil {
				return
			}
		}
	}
}
