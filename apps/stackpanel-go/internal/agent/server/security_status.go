package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// AWSSessionStatus represents the status of the AWS session
type AWSSessionStatus struct {
	Enabled        bool   `json:"enabled"`
	Valid          bool   `json:"valid"`
	ExpiresAt      string `json:"expires_at,omitempty"`
	ExpiresIn      string `json:"expires_in,omitempty"`
	ProfileARN     string `json:"profile_arn,omitempty"`
	RoleARN        string `json:"role_arn,omitempty"`
	Region         string `json:"region,omitempty"`
	Error          string `json:"error,omitempty"`
	HasCredentials bool   `json:"has_credentials"`
}

// CertificateStatus represents the status of the Step CA certificate
type CertificateStatus struct {
	Enabled     bool   `json:"enabled"`
	Valid       bool   `json:"valid"`
	ExpiresAt   string `json:"expires_at,omitempty"`
	ExpiresIn   string `json:"expires_in,omitempty"`
	Subject     string `json:"subject,omitempty"`
	Issuer      string `json:"issuer,omitempty"`
	CertPath    string `json:"cert_path,omitempty"`
	Error       string `json:"error,omitempty"`
	CAReachable bool   `json:"ca_reachable"`
	CAURL       string `json:"ca_url,omitempty"`
}

// SecurityStatus represents the combined security status
type SecurityStatus struct {
	AWS         AWSSessionStatus  `json:"aws"`
	Certificate CertificateStatus `json:"certificate"`
}

// handleSecurityStatus returns the combined AWS and certificate status
func (s *Server) handleSecurityStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	status := SecurityStatus{
		AWS:         s.checkAWSSessionStatus(),
		Certificate: s.checkCertificateStatus(),
	}

	s.writeAPI(w, http.StatusOK, status)
}

// handleAWSStatus returns only the AWS session status
func (s *Server) handleAWSStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	status := s.checkAWSSessionStatus()
	s.writeAPI(w, http.StatusOK, status)
}

// handleCertificateStatus returns only the certificate status
func (s *Server) handleCertificateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeAPIError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	status := s.checkCertificateStatus()
	s.writeAPI(w, http.StatusOK, status)
}

// checkAWSSessionStatus checks if AWS credentials are valid and active
func (s *Server) checkAWSSessionStatus() AWSSessionStatus {
	status := AWSSessionStatus{
		Enabled: false,
		Valid:   false,
	}

	// Check if AWS Roles Anywhere is configured
	// Use s.exec.GetEnv to read from cached devshell env when running outside nix develop
	getEnv := os.Getenv
	if s.exec != nil {
		getEnv = s.exec.GetEnv
	}

	profileARN := getEnv("AWS_PROFILE_ARN")
	roleARN := getEnv("AWS_ROLE_ARN")
	trustAnchorARN := getEnv("AWS_TRUST_ANCHOR_ARN")
	region := getEnv("AWS_REGION")
	if region == "" {
		region = getEnv("AWS_DEFAULT_REGION")
	}

	// AWS is considered enabled if any of the Roles Anywhere config is present
	if profileARN != "" || roleARN != "" || trustAnchorARN != "" {
		status.Enabled = true
		status.ProfileARN = profileARN
		status.RoleARN = roleARN
		status.Region = region
	}

	if !status.Enabled {
		return status
	}

	// Check if credentials exist in environment
	accessKey := getEnv("AWS_ACCESS_KEY_ID")
	secretKey := getEnv("AWS_SECRET_ACCESS_KEY")
	sessionToken := getEnv("AWS_SESSION_TOKEN")

	status.HasCredentials = accessKey != "" && secretKey != ""

	// Try to validate credentials using AWS STS get-caller-identity
	// This is the most reliable way to check if credentials are valid
	cmd := exec.Command("aws", "sts", "get-caller-identity", "--output", "json")
	if s.exec != nil {
		cmd.Env = s.exec.BuildEnv(nil)
	}
	output, err := cmd.Output()
	if err != nil {
		// Check if it's an expiration error
		if exitErr, ok := err.(*exec.ExitError); ok {
			stderr := string(exitErr.Stderr)
			if strings.Contains(stderr, "ExpiredToken") || strings.Contains(stderr, "expired") {
				status.Error = "Session expired"
			} else if strings.Contains(stderr, "InvalidClientTokenId") {
				status.Error = "Invalid credentials"
			} else if strings.Contains(stderr, "could not be found") || strings.Contains(stderr, "not found") {
				status.Error = "AWS CLI not found"
			} else {
				status.Error = "Unable to validate credentials"
			}
		} else {
			status.Error = "AWS CLI not available"
		}
		return status
	}

	// Parse the response to extract account info
	var stsResponse struct {
		Account string `json:"Account"`
		Arn     string `json:"Arn"`
		UserId  string `json:"UserId"`
	}
	if err := json.Unmarshal(output, &stsResponse); err == nil {
		status.Valid = true
	}

	// Try to get session expiration if using session credentials
	if sessionToken != "" {
		// For Roles Anywhere, try to check credential_process expiration
		// or parse from the signing helper output if available
		status.Valid = true // If we got here with a session token, credentials are working
	}

	return status
}

// checkCertificateStatus checks if the Step CA certificate is valid
func (s *Server) checkCertificateStatus() CertificateStatus {
	status := CertificateStatus{
		Enabled: false,
		Valid:   false,
	}

	// Check if Step CA is configured
	// Use s.exec.GetEnv to read from cached devshell env when running outside nix develop
	getCertEnv := os.Getenv
	if s.exec != nil {
		getCertEnv = s.exec.GetEnv
	}

	caURL := getCertEnv("STEP_CA_URL")
	caFingerprint := getCertEnv("STEP_CA_FINGERPRINT")

	if caURL != "" {
		status.Enabled = true
		status.CAURL = caURL
	}

	if !status.Enabled {
		return status
	}

	// Find the certificate file
	certPath := s.findCertificatePath()
	if certPath == "" {
		status.Error = "No certificate found"
		return status
	}
	status.CertPath = certPath

	// Check if the certificate file exists
	if _, err := os.Stat(certPath); os.IsNotExist(err) {
		status.Error = "Certificate file not found"
		return status
	}

	// Use step CLI to inspect the certificate
	cmd := exec.Command("step", "certificate", "inspect", certPath, "--format", "json")
	if s.exec != nil {
		cmd.Env = s.exec.BuildEnv(nil)
	}
	output, err := cmd.Output()
	if err != nil {
		status.Error = "Unable to inspect certificate"
		return status
	}

	// Parse certificate info
	var certInfo struct {
		Validity struct {
			NotBefore string `json:"notBefore"`
			NotAfter  string `json:"notAfter"`
		} `json:"validity"`
		Subject struct {
			CommonName string `json:"commonName"`
		} `json:"subject"`
		Issuer struct {
			CommonName string `json:"commonName"`
		} `json:"issuer"`
	}

	if err := json.Unmarshal(output, &certInfo); err != nil {
		status.Error = "Unable to parse certificate"
		return status
	}

	status.Subject = certInfo.Subject.CommonName
	status.Issuer = certInfo.Issuer.CommonName

	// Parse expiration time
	notAfter, err := time.Parse(time.RFC3339, certInfo.Validity.NotAfter)
	if err != nil {
		// Try alternative format
		notAfter, err = time.Parse("2006-01-02T15:04:05Z", certInfo.Validity.NotAfter)
	}

	if err == nil {
		status.ExpiresAt = notAfter.Format(time.RFC3339)
		duration := time.Until(notAfter)

		if duration > 0 {
			status.Valid = true
			status.ExpiresIn = formatDuration(duration)
		} else {
			status.Error = "Certificate expired"
			status.ExpiresIn = "expired"
		}
	}

	// Check if CA is reachable (only if we have the fingerprint)
	if caFingerprint != "" && caURL != "" {
		status.CAReachable = s.checkCAReachable(caURL, caFingerprint)
	}

	return status
}

// findCertificatePath finds the device certificate path
func (s *Server) findCertificatePath() string {
	// Check environment variable override first
	// Use s.exec.GetEnv to read from cached devshell env when running outside nix develop
	getPathEnv := os.Getenv
	if s.exec != nil {
		getPathEnv = s.exec.GetEnv
	}
	if certPath := getPathEnv("AWS_CERT_PATH"); certPath != "" {
		return certPath
	}

	// Get hostname for default certificate name
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "device"
	}

	// Check in project state directory if we have a project
	if s.config.ProjectRoot != "" {
		stateDir := filepath.Join(s.config.ProjectRoot, ".stack", "state", "step")
		certPath := filepath.Join(stateDir, hostname+".crt")
		if _, err := os.Stat(certPath); err == nil {
			return certPath
		}
	}

	// Check in home directory
	homeDir, err := os.UserHomeDir()
	if err == nil {
		// Check ~/.step/certs
		certPath := filepath.Join(homeDir, ".step", "certs", hostname+".crt")
		if _, err := os.Stat(certPath); err == nil {
			return certPath
		}

		// Check ~/.stack/certs
		certPath = filepath.Join(homeDir, ".stack", "certs", hostname+".crt")
		if _, err := os.Stat(certPath); err == nil {
			return certPath
		}
	}

	return ""
}

// checkCAReachable checks if the CA server is reachable
func (s *Server) checkCAReachable(caURL, fingerprint string) bool {
	// Use step CA health check
	cmd := exec.Command("step", "ca", "health", "--ca-url", caURL, "--root", fingerprint)
	if s.exec != nil {
		cmd.Env = s.exec.BuildEnv([]string{"STEP_CA_URL=" + caURL})
	} else {
		cmd.Env = append(os.Environ(), "STEP_CA_URL="+caURL)
	}

	err := cmd.Run()
	return err == nil
}

// formatDuration formats a duration in a human-readable way
func formatDuration(d time.Duration) string {
	if d < 0 {
		return "expired"
	}

	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 {
		return pluralize(days, "day")
	}
	if hours > 0 {
		return pluralize(hours, "hour")
	}
	return pluralize(minutes, "minute")
}

// pluralize returns a string with the count and pluralized unit
func pluralize(count int, unit string) string {
	if count == 1 {
		return fmt.Sprintf("1 %s", unit)
	}
	return fmt.Sprintf("%d %ss", count, unit)
}
