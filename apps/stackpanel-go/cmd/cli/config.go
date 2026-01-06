package cmd

// import (
// 	"fmt"
// 	"os"
// 	"os/exec"
// 	"path/filepath"
// 	"strings"
// 	"time"

// 	"github.com/spf13/cobra"
// )

// var (
// 	stateDir     = filepath.Join(".stackpanel", "state", "step")
// 	stepCaUrl    string
// 	stepCaFprint string
// )

// var certsCmd = &cobra.Command{
// 	Use:     "certs",
// 	Aliases: []string{"cert", "c"},
// 	Short:   "Manage certificates",
// 	Long: `Manage device certificates for development.

// Certificates are used for:
//   - TLS communication with internal services
//   - AWS Roles Anywhere authentication
//   - Step CA integration`,
// }

// var certsEnsureCmd = &cobra.Command{
// 	Use:   "ensure",
// 	Short: "Ensure device certificate exists and is valid",
// 	Long: `Request or renew a device certificate from Step CA.

// This command will:
// 1. Check if a valid certificate exists
// 2. Request a new one if missing or expired
// 3. Store it in the project's state directory`,
// 	Run: func(cmd *cobra.Command, args []string) {
// 		ensureDeviceCert()
// 	},
// }

// var certsStatusCmd = &cobra.Command{
// 	Use:   "status",
// 	Short: "Show certificate status",
// 	Run: func(cmd *cobra.Command, args []string) {
// 		showCertStatus()
// 	},
// }

// var certsRevokeCmd = &cobra.Command{
// 	Use:   "revoke",
// 	Short: "Revoke the current device certificate",
// 	Run: func(cmd *cobra.Command, args []string) {
// 		revokeCert()
// 	},
// }

// func init() {
// 	certsCmd.AddCommand(certsEnsureCmd)
// 	certsCmd.AddCommand(certsStatusCmd)
// 	certsCmd.AddCommand(certsRevokeCmd)

// 	// Get Step CA config from environment
// 	stepCaUrl = os.Getenv("STEP_CA_URL")
// 	stepCaFprint = os.Getenv("STEP_CA_FINGERPRINT")
// }

// func getStepStateDir() string {
// 	// Look for project root (where .stackpanel exists or will exist)
// 	cwd, _ := os.Getwd()

// 	// Walk up looking for .stackpanel or .git
// 	dir := cwd
// 	for {
// 		if _, err := os.Stat(filepath.Join(dir, ".stackpanel")); err == nil {
// 			return filepath.Join(dir, stateDir)
// 		}
// 		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
// 			return filepath.Join(dir, stateDir)
// 		}
// 		parent := filepath.Dir(dir)
// 		if parent == dir {
// 			break
// 		}
// 		dir = parent
// 	}

// 	// Default to current directory
// 	return filepath.Join(cwd, stateDir)
// }

// func getConfigPath() (certFile, keyFile string) {
// 	dir := getStepStateDir()
// 	hostname, _ := os.Hostname()
// 	certFile = filepath.Join(dir, hostname+".crt")
// 	keyFile = filepath.Join(dir, hostname+".key")
// 	return
// }
