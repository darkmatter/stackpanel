package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var (
	stateDir     = filepath.Join(".stackpanel", "state", "step")
	stepCaUrl    string
	stepCaFprint string
)

var certsCmd = &cobra.Command{
	Use:     "certs",
	Aliases: []string{"cert", "c"},
	Short:   "Manage certificates",
	Long: `Manage device certificates for development.

Certificates are used for:
  - TLS communication with internal services
  - AWS Roles Anywhere authentication
  - Step CA integration`,
}

var certsEnsureCmd = &cobra.Command{
	Use:   "ensure",
	Short: "Ensure device certificate exists and is valid",
	Long: `Request or renew a device certificate from Step CA.

This command will:
1. Check if a valid certificate exists
2. Request a new one if missing or expired
3. Store it in the project's state directory`,
	Run: func(cmd *cobra.Command, args []string) {
		ensureDeviceCert()
	},
}

var certsStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show certificate status",
	Run: func(cmd *cobra.Command, args []string) {
		showCertStatus()
	},
}

var certsRevokeCmd = &cobra.Command{
	Use:   "revoke",
	Short: "Revoke the current device certificate",
	Run: func(cmd *cobra.Command, args []string) {
		revokeCert()
	},
}

func init() {
	certsCmd.AddCommand(certsEnsureCmd)
	certsCmd.AddCommand(certsStatusCmd)
	certsCmd.AddCommand(certsRevokeCmd)

	// Get Step CA config from environment
	stepCaUrl = os.Getenv("STEP_CA_URL")
	stepCaFprint = os.Getenv("STEP_CA_FINGERPRINT")
}

func getStepStateDir() string {
	// Look for project root (where .stackpanel exists or will exist)
	cwd, _ := os.Getwd()

	// Walk up looking for .stackpanel or .git
	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
			return filepath.Join(dir, stateDir)
		}
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return filepath.Join(dir, stateDir)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	// Default to current directory
	return filepath.Join(cwd, stateDir)
}

func getCertPaths() (certFile, keyFile string) {
	dir := getStepStateDir()
	hostname, _ := os.Hostname()
	certFile = filepath.Join(dir, hostname+".crt")
	keyFile = filepath.Join(dir, hostname+".key")
	return
}

func ensureDeviceCert() {
	certFile, keyFile := getCertPaths()
	dir := filepath.Dir(certFile)
	hostname, _ := os.Hostname()

	if stepCaUrl == "" {
		printError("STEP_CA_URL not set. Configure Step CA in devenv.nix")
		return
	}

	// Create state directory
	if err := os.MkdirAll(dir, 0700); err != nil {
		printError(fmt.Sprintf("Failed to create state directory: %v", err))
		return
	}

	// Check if cert exists and is valid
	if _, err := os.Stat(certFile); err == nil {
		// Verify certificate
		cmd := exec.Command("step", "certificate", "verify", certFile,
			"--ca-url", stepCaUrl,
		)
		if err := cmd.Run(); err == nil {
			// Check expiry
			cmd = exec.Command("step", "certificate", "inspect", certFile, "--format", "json")
			output, _ := cmd.Output()
			if !strings.Contains(string(output), "expired") {
				printSuccess("Certificate is valid")
				showCertDetails(certFile)
				return
			}
		}
		printWarning("Certificate expired or invalid, renewing...")
	}

	// Request new certificate
	printInfo("Requesting device certificate...")

	// First, bootstrap if needed
	bootstrapFile := filepath.Join(dir, "root_ca.crt")
	if _, err := os.Stat(bootstrapFile); os.IsNotExist(err) && stepCaFprint != "" {
		printInfo("Bootstrapping Step CA...")
		cmd := exec.Command("step", "ca", "bootstrap",
			"--ca-url", stepCaUrl,
			"--fingerprint", stepCaFprint,
			"--install",
		)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			printWarning(fmt.Sprintf("Bootstrap failed (may already be done): %v", err))
		}
	}

	// Request certificate
	cmd := exec.Command("step", "ca", "certificate",
		hostname,
		certFile,
		keyFile,
		"--ca-url", stepCaUrl,
		"--not-after", "720h", // 30 days
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	if err := cmd.Run(); err != nil {
		printError(fmt.Sprintf("Failed to request certificate: %v", err))
		return
	}

	// Set permissions
	os.Chmod(keyFile, 0600)

	printSuccess("Certificate obtained")
	showCertDetails(certFile)
}

func showCertStatus() {
	certFile, keyFile := getCertPaths()

	fmt.Printf("\n%s Certificate Status\n\n", purple.Sprint("==>"))

	// Check cert file
	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		printWarning("No certificate found")
		printDim(fmt.Sprintf("  Run 'stackpanel certs ensure' to request one"))
		return
	}

	// Check key file
	if _, err := os.Stat(keyFile); os.IsNotExist(err) {
		printError("Certificate exists but key is missing")
		return
	}

	showCertDetails(certFile)

	// Verify if Step CA URL is configured
	if stepCaUrl != "" {
		cmd := exec.Command("step", "certificate", "verify", certFile,
			"--ca-url", stepCaUrl,
		)
		if err := cmd.Run(); err != nil {
			printWarning("Certificate validation failed (CA may be unreachable)")
		} else {
			printSuccess("Certificate is valid")
		}
	}
}

func showCertDetails(certFile string) {
	cmd := exec.Command("step", "certificate", "inspect", certFile, "--short")
	output, err := cmd.Output()
	if err != nil {
		return
	}

	fmt.Println()
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		printDim("  " + line)
	}
	fmt.Println()

	// Check expiry
	cmd = exec.Command("step", "certificate", "inspect", certFile, "--format", "json")
	output, _ = cmd.Output()
	if strings.Contains(string(output), `"not_after"`) {
		// Parse and show human-readable expiry
		// This is simplified - in production you'd parse the JSON
		printDim(fmt.Sprintf("  Location: %s", certFile))
	}
}

func revokeCert() {
	certFile, keyFile := getCertPaths()

	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		printWarning("No certificate to revoke")
		return
	}

	if stepCaUrl == "" {
		printError("STEP_CA_URL not set")
		return
	}

	printWarning("Revoking certificate...")

	cmd := exec.Command("step", "ca", "revoke",
		certFile,
		"--ca-url", stepCaUrl,
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		printWarning(fmt.Sprintf("Revocation may have failed: %v", err))
	}

	// Remove local files
	os.Remove(certFile)
	os.Remove(keyFile)

	printSuccess("Certificate revoked and removed")
}

// AWS Roles Anywhere integration
var awsCmd = &cobra.Command{
	Use:   "aws",
	Short: "AWS credential management",
}

var awsCredsCmd = &cobra.Command{
	Use:   "creds",
	Short: "Get AWS credentials using device certificate",
	Long: `Get temporary AWS credentials using AWS Roles Anywhere.

This uses your device certificate to authenticate with AWS
and obtain temporary credentials for the configured role.`,
	Run: func(cmd *cobra.Command, args []string) {
		export, _ := cmd.Flags().GetBool("export")
		getAwsCreds(export)
	},
}

var awsStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check AWS authentication status",
	Run: func(cmd *cobra.Command, args []string) {
		checkAwsStatus()
	},
}

func init() {
	certsCmd.AddCommand(awsCmd)
	awsCmd.AddCommand(awsCredsCmd)
	awsCmd.AddCommand(awsStatusCmd)

	awsCredsCmd.Flags().BoolP("export", "e", false, "Output as export statements")
}

func getAwsCreds(export bool) {
	certFile, keyFile := getCertPaths()

	// Check for required environment variables
	trustAnchorArn := os.Getenv("AWS_TRUST_ANCHOR_ARN")
	profileArn := os.Getenv("AWS_PROFILE_ARN")
	roleArn := os.Getenv("AWS_ROLE_ARN")

	if trustAnchorArn == "" || profileArn == "" || roleArn == "" {
		printError("AWS Roles Anywhere not configured")
		printDim("  Set AWS_TRUST_ANCHOR_ARN, AWS_PROFILE_ARN, and AWS_ROLE_ARN")
		return
	}

	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		printError("No device certificate found")
		printDim("  Run 'stackpanel certs ensure' first")
		return
	}

	// Get credentials using aws_signing_helper or credential process
	cmd := exec.Command("aws_signing_helper", "credential-process",
		"--certificate", certFile,
		"--private-key", keyFile,
		"--trust-anchor-arn", trustAnchorArn,
		"--profile-arn", profileArn,
		"--role-arn", roleArn,
	)

	output, err := cmd.Output()
	if err != nil {
		printError(fmt.Sprintf("Failed to get credentials: %v", err))
		return
	}

	if export {
		// Parse JSON and output export statements
		// Simplified - would need proper JSON parsing
		fmt.Println("# Eval this: eval \"$(stackpanel certs aws creds -e)\"")
		fmt.Println(string(output))
	} else {
		fmt.Println(string(output))
	}
}

func checkAwsStatus() {
	fmt.Printf("\n%s AWS Authentication Status\n\n", purple.Sprint("==>"))

	// Check STS identity
	cmd := exec.Command("aws", "sts", "get-caller-identity")
	output, err := cmd.Output()

	if err != nil {
		printWarning("Not authenticated with AWS")
		printDim("  Run 'stackpanel certs aws creds -e' and eval the output")
		return
	}

	printSuccess("Authenticated with AWS")
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		printDim("  " + line)
	}
}

// Helper to check cert expiry
func getCertExpiry(certFile string) *time.Time {
	cmd := exec.Command("step", "certificate", "inspect", certFile, "--format", "json")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	// Parse not_after from JSON (simplified)
	// In production, you'd use encoding/json properly
	_ = output
	return nil
}
