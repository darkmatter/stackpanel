// Package envvars provides centralized environment variable definitions for Stackpanel.
//
// This package is the Go counterpart to nix/stackpanel/core/lib/envvars.nix.
// It provides a single source of truth for all environment variables used by
// the Stackpanel CLI and related tools.
//
// IMPORTANT: When adding new environment variables, also update envvars.nix
// to keep Nix and Go definitions in sync.
package envvars

import (
	"fmt"
	"os"
	"strings"
)

// Source indicates where an environment variable is set
type Source string

const (
	SourceNix     Source = "nix"     // Set by Nix/devenv configuration
	SourceDynamic Source = "dynamic" // Set dynamically at runtime
	SourceDevenv  Source = "devenv"  // Set by devenv itself
	SourceSystem  Source = "system"  // System environment variable
)

// Category groups related environment variables
type Category string

const (
	CategoryCore     Category = "Core Stackpanel"
	CategoryPaths    Category = "Paths & Directories"
	CategoryAgent    Category = "Stackpanel Agent"
	CategoryStepCA   Category = "Step CA (Certificates)"
	CategoryAWS      Category = "AWS & Roles Anywhere"
	CategoryMinio    Category = "MinIO (S3-Compatible Storage)"
	CategoryServices Category = "Services Config"
	CategoryDevenv   Category = "Devenv Integration"
	CategoryIDE      Category = "IDE Integration"
)

// EnvVar represents a single environment variable definition
type EnvVar struct {
	Name               string   // The environment variable name
	Description        string   // Human-readable description
	Category           Category // Grouping for documentation
	Source             Source   // Where the variable is set
	Required           bool     // Whether required for basic operation
	Default            string   // Default value if applicable
	Example            string   // Example value for documentation
	Deprecated         bool     // Whether the variable is deprecated
	DeprecationMessage string   // Message explaining deprecation
	GoField            string   // Corresponding Go struct field name
}

// Get retrieves the current value of this environment variable
func (e EnvVar) Get() string {
	return os.Getenv(e.Name)
}

// GetOr retrieves the value or returns the provided default
func (e EnvVar) GetOr(defaultValue string) string {
	if v := os.Getenv(e.Name); v != "" {
		return v
	}
	return defaultValue
}

// GetOrDefault retrieves the value or returns the defined default
func (e EnvVar) GetOrDefault() string {
	if v := os.Getenv(e.Name); v != "" {
		return v
	}
	return e.Default
}

// IsSet returns true if the environment variable is set and non-empty
func (e EnvVar) IsSet() bool {
	return os.Getenv(e.Name) != ""
}

// Set sets the environment variable
func (e EnvVar) Set(value string) error {
	return os.Setenv(e.Name, value)
}

// Unset removes the environment variable
func (e EnvVar) Unset() error {
	return os.Unsetenv(e.Name)
}

// ===========================================================================
// Core Stackpanel Variables
// ===========================================================================

var (
	// StackpanelRoot is the absolute path to the project root directory
	StackpanelRoot = EnvVar{
		Name:        "STACKPANEL_ROOT",
		Description: "Absolute path to the project root directory",
		Category:    CategoryCore,
		Source:      SourceNix,
		Required:    true,
		Example:     "/home/user/my-project",
		GoField:     "ProjectRoot",
	}

	// StackpanelRootMarker is the filename used to identify project root
	StackpanelRootMarker = EnvVar{
		Name:        "STACKPANEL_ROOT_MARKER",
		Description: "Filename used as a marker to identify project root",
		Category:    CategoryCore,
		Source:      SourceNix,
		Default:     ".stackpanel-root",
		GoField:     "RootMarker",
	}

	// StackpanelRootDirName is the name of the .stackpanel directory
	StackpanelRootDirName = EnvVar{
		Name:        "STACKPANEL_ROOT_DIR_NAME",
		Description: "Name of the config directory within the project (.stack or .stackpanel)",
		Category:    CategoryCore,
		Source:      SourceNix,
		Default:     ".stack",
	}

	// StackpanelShellID is a unique identifier for the current shell session
	StackpanelShellID = EnvVar{
		Name:        "STACKPANEL_SHELL_ID",
		Description: "Unique identifier for the current shell session",
		Category:    CategoryCore,
		Source:      SourceNix,
		Default:     "1",
	}

	// StackpanelNixConfig is the path to the source Nix config file
	StackpanelNixConfig = EnvVar{
		Name:        "STACKPANEL_NIX_CONFIG",
		Description: "Path to the source Nix config file (.stack/config.nix or .stackpanel/config.nix)",
		Category:    CategoryCore,
		Source:      SourceNix,
		Example:     "/home/user/my-project/.stack/config.nix",
		GoField:     "NixConfigPath",
	}

	// StackpanelConfigJson is the path to the Nix-generated config JSON
	StackpanelConfigJson = EnvVar{
		Name:        "STACKPANEL_CONFIG_JSON",
		Description: "Path to the Nix-generated config JSON in the Nix store (for Go CLI)",
		Category:    CategoryCore,
		Source:      SourceNix,
		Example:     "/nix/store/xxx-stackpanel-config.json",
		GoField:     "ConfigJsonPath",
	}
)

// ===========================================================================
// Paths & Directories
// ===========================================================================

var (
	// StackpanelStateDir is the directory for runtime state (profile - ephemeral)
	StackpanelStateDir = EnvVar{
		Name:        "STACKPANEL_STATE_DIR",
		Description: "Directory for runtime state (profile: stackpanel.json, shell.log)",
		Category:    CategoryPaths,
		Source:      SourceNix,
		Required:    true,
		Example:     "/home/user/my-project/.stack/profile",
		GoField:     "StateDir",
	}

	// StackpanelStateFile is the full path to the stackpanel.json state file
	StackpanelStateFile = EnvVar{
		Name:        "STACKPANEL_STATE_FILE",
		Description: "Full path to the stackpanel.json state file",
		Category:    CategoryPaths,
		Source:      SourceNix,
		Example:     "/home/user/my-project/.stack/profile/stackpanel.json",
		GoField:     "StateFile",
	}

	// StackpanelShellLog is the log file capturing shell entry output
	StackpanelShellLog = EnvVar{
		Name:        "STACKPANEL_SHELL_LOG",
		Description: "Log file capturing shell entry output",
		Category:    CategoryPaths,
		Source:      SourceNix,
		Example:     "/home/user/my-project/.stack/profile/shell.log",
		GoField:     "ShellLog",
	}

	// StackpanelGenDir is the directory for generated files
	StackpanelGenDir = EnvVar{
		Name:        "STACKPANEL_GEN_DIR",
		Description: "Directory for generated files (configs, scripts)",
		Category:    CategoryPaths,
		Source:      SourceNix,
		Example:     "/home/user/my-project/.stack/gen",
		GoField:     "GenDir",
	}

	// StackpanelDataDir is the directory for persistent data
	StackpanelDataDir = EnvVar{
		Name:        "STACKPANEL_DATA_DIR",
		Description: "Directory for persistent data (databases, etc.)",
		Category:    CategoryPaths,
		Source:      SourceNix,
		Example:     "/home/user/my-project/.stack/data",
		GoField:     "DataDir",
	}
)

// ===========================================================================
// Stackpanel Agent Variables
// ===========================================================================

var (
	// StackpanelProjectRoot is the project root override for the agent
	StackpanelProjectRoot = EnvVar{
		Name:        "STACKPANEL_PROJECT_ROOT",
		Description: "Project root override for the agent (when spawned externally)",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		GoField:     "ProjectRoot",
	}

	// StackpanelAuthToken is the authentication token for the agent API
	StackpanelAuthToken = EnvVar{
		Name:        "STACKPANEL_AUTH_TOKEN",
		Description: "Authentication token for the agent API",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		GoField:     "AuthToken",
	}

	// StackpanelAPIEndpoint is the API endpoint URL for the agent
	StackpanelAPIEndpoint = EnvVar{
		Name:        "STACKPANEL_API_ENDPOINT",
		Description: "API endpoint URL for the agent",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Default:     "http://localhost:6401",
		GoField:     "APIEndpoint",
	}

	// StackpanelUserConfig is the path to the user-level config file
	// This stores data that spans multiple repos (e.g., projects list)
	StackpanelUserConfig = EnvVar{
		Name:        "STACKPANEL_USER_CONFIG",
		Description: "Path to user-level config file (stores cross-repo data like projects list)",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Default:     "~/.config/stackpanel/stackpanel.yaml",
		Example:     "/home/user/.config/stackpanel/stackpanel.yaml",
		GoField:     "UserConfigPath",
	}

	// StackpanelBindAddress is the address the agent binds to
	StackpanelBindAddress = EnvVar{
		Name:        "STACKPANEL_BIND_ADDRESS",
		Description: "Address the agent binds to (use 0.0.0.0 for remote/Tailscale access)",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Default:     "127.0.0.1",
		Example:     "0.0.0.0",
		GoField:     "BindAddress",
	}

	// StackpanelAllowedOrigins is a comma-separated list of allowed CORS origins
	StackpanelAllowedOrigins = EnvVar{
		Name:        "STACKPANEL_ALLOWED_ORIGINS",
		Description: "Comma-separated list of allowed CORS origins for remote access",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Example:     "https://myhost.tail1234.ts.net,http://192.168.1.100:3000",
		GoField:     "AllowedOrigins",
	}

	// StackpanelDevRepo is the path to a local stackpanel repo for development mode.
	// When set, the wrapper script will run 'go run' from this path instead of the installed binary.
	// This is an alternative to using 'stackpanel debug enable <path>' (alias: 'stackpanel dev enable <path>').
	StackpanelDevRepo = EnvVar{
		Name:        "STACKPANEL_DEV_REPO",
		Description: "Path to local stackpanel repo for dev mode (runs via 'go run' instead of installed binary)",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Example:     "~/projects/stackpanel",
		GoField:     "DevRepoPath",
	}

	// StackpanelTestPairingToken enables test mode with a deterministic pairing token.
	// When set, the agent uses a fixed signing key and agent ID derived from this token,
	// making the token valid across agent restarts. This is useful for automated testing
	// and E2E tests where the pairing flow needs to be bypassed.
	// The value should be a secret string that will be used to derive the signing key.
	// WARNING: Only use this in test/development environments, never in production.
	StackpanelTestPairingToken = EnvVar{
		Name:        "STACKPANEL_TEST_PAIRING_TOKEN",
		Description: "Secret for deterministic pairing token (test mode only, enables predictable agent ID)",
		Category:    CategoryAgent,
		Source:      SourceDynamic,
		Example:     "my-test-secret-for-e2e",
		GoField:     "TestPairingToken",
	}
)

// ===========================================================================
// Step CA (Certificate Authority)
// ===========================================================================

var (
	// StepCAURL is the URL of the Step CA server
	StepCAURL = EnvVar{
		Name:        "STEP_CA_URL",
		Description: "URL of the Step CA server",
		Category:    CategoryStepCA,
		Source:      SourceNix,
		Example:     "https://ca.internal:443",
	}

	// StepCAFingerprint is the SHA256 fingerprint of the Step CA root certificate
	StepCAFingerprint = EnvVar{
		Name:        "STEP_CA_FINGERPRINT",
		Description: "SHA256 fingerprint of the Step CA root certificate",
		Category:    CategoryStepCA,
		Source:      SourceNix,
		Example:     "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a",
	}
)

// ===========================================================================
// AWS & Roles Anywhere
// ===========================================================================

var (
	// AWSTrustAnchorARN is the ARN of the IAM Roles Anywhere trust anchor
	AWSTrustAnchorARN = EnvVar{
		Name:        "AWS_TRUST_ANCHOR_ARN",
		Description: "ARN of the IAM Roles Anywhere trust anchor",
		Category:    CategoryAWS,
		Source:      SourceNix,
		Example:     "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/abc123",
	}

	// AWSProfileARN is the ARN of the IAM Roles Anywhere profile
	AWSProfileARN = EnvVar{
		Name:        "AWS_PROFILE_ARN",
		Description: "ARN of the IAM Roles Anywhere profile",
		Category:    CategoryAWS,
		Source:      SourceNix,
		Example:     "arn:aws:rolesanywhere:us-east-1:123456789012:profile/def456",
	}

	// AWSRoleARN is the ARN of the IAM role to assume via Roles Anywhere
	AWSRoleARN = EnvVar{
		Name:        "AWS_ROLE_ARN",
		Description: "ARN of the IAM role to assume via Roles Anywhere",
		Category:    CategoryAWS,
		Source:      SourceNix,
		Example:     "arn:aws:iam::123456789012:role/DeveloperRole",
	}

	// AWSRegion is the default AWS region for API calls
	AWSRegion = EnvVar{
		Name:        "AWS_REGION",
		Description: "Default AWS region for API calls",
		Category:    CategoryAWS,
		Source:      SourceNix,
		Default:     "us-east-1",
	}

	// AWSAccessKeyID is the AWS access key ID (set dynamically)
	AWSAccessKeyID = EnvVar{
		Name:        "AWS_ACCESS_KEY_ID",
		Description: "AWS access key ID (set dynamically by credential scripts)",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}

	// AWSSecretAccessKey is the AWS secret access key (set dynamically)
	AWSSecretAccessKey = EnvVar{
		Name:        "AWS_SECRET_ACCESS_KEY",
		Description: "AWS secret access key (set dynamically by credential scripts)",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}

	// AWSSessionToken is the AWS session token for temporary credentials
	AWSSessionToken = EnvVar{
		Name:        "AWS_SESSION_TOKEN",
		Description: "AWS session token for temporary credentials",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}

	// AWSSharedCredentialsFile is the path to AWS credentials file
	AWSSharedCredentialsFile = EnvVar{
		Name:        "AWS_SHARED_CREDENTIALS_FILE",
		Description: "Path to AWS credentials file (set to /dev/null to force Roles Anywhere)",
		Category:    CategoryAWS,
		Source:      SourceNix,
		Default:     "/dev/null",
	}

	// AWSCertPath is the override path to device certificate
	AWSCertPath = EnvVar{
		Name:        "AWS_CERT_PATH",
		Description: "Override path to device certificate for Roles Anywhere",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}

	// AWSKeyPath is the override path to device private key
	AWSKeyPath = EnvVar{
		Name:        "AWS_KEY_PATH",
		Description: "Override path to device private key for Roles Anywhere",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}

	// AWSSigningHelper is the override path to aws_signing_helper binary
	AWSSigningHelper = EnvVar{
		Name:        "AWS_SIGNING_HELPER",
		Description: "Override path to aws_signing_helper binary",
		Category:    CategoryAWS,
		Source:      SourceDynamic,
	}
)

// ===========================================================================
// MinIO (S3-Compatible Storage)
// ===========================================================================

var (
	// MinioRootUser is the MinIO admin username
	MinioRootUser = EnvVar{
		Name:        "MINIO_ROOT_USER",
		Description: "MinIO admin username",
		Category:    CategoryMinio,
		Source:      SourceNix,
		Default:     "minioadmin",
	}

	// MinioRootPassword is the MinIO admin password
	MinioRootPassword = EnvVar{
		Name:        "MINIO_ROOT_PASSWORD",
		Description: "MinIO admin password",
		Category:    CategoryMinio,
		Source:      SourceNix,
		Default:     "minioadmin",
	}

	// MinioEndpoint is the MinIO S3 endpoint URL
	MinioEndpoint = EnvVar{
		Name:        "MINIO_ENDPOINT",
		Description: "MinIO S3 endpoint URL",
		Category:    CategoryMinio,
		Source:      SourceNix,
		Example:     "http://localhost:9000",
	}

	// MinioAccessKey is the MinIO access key (alias for MINIO_ROOT_USER)
	MinioAccessKey = EnvVar{
		Name:        "MINIO_ACCESS_KEY",
		Description: "MinIO access key (alias for MINIO_ROOT_USER)",
		Category:    CategoryMinio,
		Source:      SourceNix,
	}

	// MinioSecretKey is the MinIO secret key (alias for MINIO_ROOT_PASSWORD)
	MinioSecretKey = EnvVar{
		Name:        "MINIO_SECRET_KEY",
		Description: "MinIO secret key (alias for MINIO_ROOT_PASSWORD)",
		Category:    CategoryMinio,
		Source:      SourceNix,
	}

	// MinioConsoleAddress is the MinIO console bind address
	MinioConsoleAddress = EnvVar{
		Name:        "MINIO_CONSOLE_ADDRESS",
		Description: "MinIO console bind address (e.g., :9001)",
		Category:    CategoryMinio,
		Source:      SourceNix,
	}

	// S3Endpoint is the S3-compatible endpoint URL
	S3Endpoint = EnvVar{
		Name:        "S3_ENDPOINT",
		Description: "S3-compatible endpoint URL (points to MinIO when enabled)",
		Category:    CategoryMinio,
		Source:      SourceNix,
		Example:     "http://localhost:9000",
	}
)

// ===========================================================================
// Services Config
// ===========================================================================

var (
	// StackpanelStablePort is the base port for the project (index 0 in the port layout)
	StackpanelStablePort = EnvVar{
		Name:        "STACKPANEL_STABLE_PORT",
		Description: "Base port for the project (index 0 in the port layout)",
		Category:    CategoryServices,
		Source:      SourceNix,
		Example:     "6400",
	}

	// StackpanelServicesConfig is the JSON array of service definitions with ports
	StackpanelServicesConfig = EnvVar{
		Name:        "STACKPANEL_SERVICES_CONFIG",
		Description: "JSON array of service definitions with ports",
		Category:    CategoryServices,
		Source:      SourceNix,
		Example:     `[{"key":"POSTGRES","name":"PostgreSQL","port":6410}]`,
	}
)

// ===========================================================================
// Devenv Integration
// ===========================================================================

var (
	// DevenvRoot is the root directory of the devenv project
	DevenvRoot = EnvVar{
		Name:        "DEVENV_ROOT",
		Description: "Root directory of the devenv project (set by devenv)",
		Category:    CategoryDevenv,
		Source:      SourceDevenv,
	}

	// DevenvState is the state directory for devenv
	DevenvState = EnvVar{
		Name:        "DEVENV_STATE",
		Description: "State directory for devenv (set by devenv)",
		Category:    CategoryDevenv,
		Source:      SourceDevenv,
	}

	// DevenvDotfile is the path to devenv dotfile directory
	DevenvDotfile = EnvVar{
		Name:        "DEVENV_DOTFILE",
		Description: "Path to devenv dotfile directory",
		Category:    CategoryDevenv,
		Source:      SourceDevenv,
	}

	// DevenvProfile is the current devenv profile path
	DevenvProfile = EnvVar{
		Name:        "DEVENV_PROFILE",
		Description: "Current devenv profile path",
		Category:    CategoryDevenv,
		Source:      SourceDevenv,
	}
)

// ===========================================================================
// IDE Integration
// ===========================================================================

var (
	// DevenvVSCodeShell is a marker to prevent shell recursion in VS Code
	DevenvVSCodeShell = EnvVar{
		Name:        "DEVENV_VSCODE_SHELL",
		Description: "Marker to prevent shell recursion in VS Code (1 = inside VS Code shell)",
		Category:    CategoryIDE,
		Source:      SourceNix,
	}

	// Editor is the default text editor
	Editor = EnvVar{
		Name:        "EDITOR",
		Description: "Default text editor",
		Category:    CategoryIDE,
		Source:      SourceNix,
		Default:     "vim",
	}
)

// ===========================================================================
// Registry and Helper Functions
// ===========================================================================

// All returns all defined environment variables
func All() []EnvVar {
	return []EnvVar{
		// Core
		StackpanelRoot,
		StackpanelRootMarker,
		StackpanelRootDirName,
		StackpanelShellID,
		StackpanelNixConfig,
		// Paths
		StackpanelStateDir,
		StackpanelStateFile,
		StackpanelGenDir,
		StackpanelDataDir,
		// Agent
		StackpanelProjectRoot,
		StackpanelAuthToken,
		StackpanelAPIEndpoint,
		StackpanelUserConfig,
		StackpanelTestPairingToken,
		// Step CA
		StepCAURL,
		StepCAFingerprint,
		// AWS
		AWSTrustAnchorARN,
		AWSProfileARN,
		AWSRoleARN,
		AWSRegion,
		AWSAccessKeyID,
		AWSSecretAccessKey,
		AWSSessionToken,
		AWSSharedCredentialsFile,
		AWSCertPath,
		AWSKeyPath,
		AWSSigningHelper,
		// MinIO
		MinioRootUser,
		MinioRootPassword,
		MinioEndpoint,
		MinioAccessKey,
		MinioSecretKey,
		MinioConsoleAddress,
		S3Endpoint,
		// Services Config
		StackpanelStablePort,
		StackpanelServicesConfig,
		// Devenv
		DevenvRoot,
		DevenvState,
		DevenvDotfile,
		DevenvProfile,
		// IDE
		DevenvVSCodeShell,
		Editor,
	}
}

// Required returns all required environment variables
func Required() []EnvVar {
	var result []EnvVar
	for _, v := range All() {
		if v.Required {
			result = append(result, v)
		}
	}
	return result
}

// ByCategory returns all variables in a given category
func ByCategory(category Category) []EnvVar {
	var result []EnvVar
	for _, v := range All() {
		if v.Category == category {
			result = append(result, v)
		}
	}
	return result
}

// BySource returns all variables from a given source
func BySource(source Source) []EnvVar {
	var result []EnvVar
	for _, v := range All() {
		if v.Source == source {
			result = append(result, v)
		}
	}
	return result
}

// Lookup finds an environment variable definition by name
func Lookup(name string) (EnvVar, bool) {
	for _, v := range All() {
		if v.Name == name {
			return v, true
		}
	}
	return EnvVar{}, false
}

// ValidationResult contains the result of validating environment variables
type ValidationResult struct {
	Missing  []EnvVar // Required variables that are not set
	Warnings []string // Warning messages
	Valid    bool     // Whether all required variables are set
}

// Validate checks that all required environment variables are set
func Validate() ValidationResult {
	result := ValidationResult{Valid: true}

	for _, v := range Required() {
		if !v.IsSet() {
			result.Missing = append(result.Missing, v)
			result.Valid = false
		}
	}

	// Check for deprecated variables that are set
	for _, v := range All() {
		if v.Deprecated && v.IsSet() {
			msg := fmt.Sprintf("%s is deprecated", v.Name)
			if v.DeprecationMessage != "" {
				msg += ": " + v.DeprecationMessage
			}
			result.Warnings = append(result.Warnings, msg)
		}
	}

	return result
}

// PrintDebug prints all environment variables and their current values
// Useful for debugging configuration issues
func PrintDebug() {
	fmt.Println("Stackpanel Environment Variables:")
	fmt.Println(strings.Repeat("=", 60))

	currentCategory := Category("")
	for _, v := range All() {
		if v.Category != currentCategory {
			currentCategory = v.Category
			fmt.Printf("\n[%s]\n", currentCategory)
		}

		value := v.Get()
		if value == "" {
			if v.Required {
				fmt.Printf("  ❌ %s (REQUIRED, NOT SET)\n", v.Name)
			} else {
				fmt.Printf("  ○ %s (not set)\n", v.Name)
			}
		} else {
			// Truncate long values
			display := value
			if len(display) > 50 {
				display = display[:47] + "..."
			}
			// Mask sensitive values
			if strings.Contains(strings.ToLower(v.Name), "secret") ||
				strings.Contains(strings.ToLower(v.Name), "password") ||
				strings.Contains(strings.ToLower(v.Name), "token") ||
				strings.Contains(strings.ToLower(v.Name), "key") {
				display = "****"
			}
			fmt.Printf("  ✓ %s = %s\n", v.Name, display)
		}
	}
}
