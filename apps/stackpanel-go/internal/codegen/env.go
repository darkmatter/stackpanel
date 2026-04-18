package codegen

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const envModuleName = "env"

type envModule struct{}

// envManifest is the Nix-generated input that drives env codegen. Nix evaluates
// secret schemas from .stack/secrets/apps/ and writes this to
// .stack/gen/codegen/env-manifest.json on each devshell entry.
type envManifest struct {
	SchemaVersion int             `json:"schemaVersion"`
	DataRoot      string          `json:"dataRoot"`
	Targets       []envTargetSpec `json:"targets"`
}

// envTargetSpec defines one (app, environment) pair to generate. Each target
// produces a SOPS-encrypted JSON payload and a TS module that embeds it.
type envTargetSpec struct {
	App         string                    `json:"app"`
	Environment string                    `json:"environment"`
	OutputPath  string                    `json:"outputPath"`
	Recipients  []string                  `json:"recipients"`
	Vars        map[string]envVarResolver `json:"vars"`
}

// envVarResolver describes how to resolve a single env var's value.
// Kind "literal" uses Value directly; "group"/"sopsRef" decrypt a SOPS file
// and extract Key from the decrypted JSON.
type envVarResolver struct {
	Kind       string `json:"kind"`
	Value      string `json:"value,omitempty"`
	VariableID string `json:"variableId,omitempty"`
	Path       string `json:"path,omitempty"`
	FileType   string `json:"fileType,omitempty"`
	Key        string `json:"key,omitempty"`
}

// envWarning captures a non-fatal issue (e.g., a referenced key missing from
// a SOPS file). Warnings are collected per-target and written to a JSON file
// so the studio UI and CLI can surface them.
type envWarning struct {
	App         string `json:"app"`
	Environment string `json:"environment"`
	EnvKey      string `json:"envKey"`
	VariableID  string `json:"variableId,omitempty"`
	Path        string `json:"path,omitempty"`
	Key         string `json:"key,omitempty"`
	Message     string `json:"message"`
}

type envWarningsFile struct {
	SchemaVersion int          `json:"schemaVersion"`
	Warnings      []envWarning `json:"warnings"`
}

const envWarningsPath = ".stack/gen/codegen/env-warnings.json"

// generatedPayloadsRoot is where TS modules containing embedded encrypted
// payloads are written. These are checked into git so the @gen/env package
// works in CI and IDEs without requiring SOPS or an active devshell.
// Must stay in sync with `payloadRuntimeDir` in nix/stackpanel/lib/codegen/env-package.nix
// and the `./generated-payloads/registry` import in packages/gen/env/src/runtime/{loader,node-loader}.ts.
// Go overwrites the no-op registry stub that Nix emits here during `stackpanel preflight run`.
const generatedPayloadsRoot = "packages/gen/env/src/runtime/generated-payloads"

// NewEnvModule returns the generated env payload builder.
func NewEnvModule() Module {
	return envModule{}
}

func (envModule) Name() string {
	return envModuleName
}

func (envModule) Description() string {
	return "Build encrypted runtime env payloads from the generated env manifest"
}

// Build produces SOPS-encrypted env payloads and TS wrapper modules for each
// (app, environment) target in the manifest. For each target it:
//  1. Resolves all vars (literals directly, SOPS refs via sops --decrypt)
//  2. Encrypts the flat key=value JSON with the target's AGE recipients
//  3. Generates a TS module that embeds the encrypted payload as a string
//  4. Generates a registry.ts with lazy loaders for all payloads
//  5. Cleans up stale artifacts from removed apps/environments
func (envModule) Build(ctx context.Context, req BuildRequest) (*BuildOutput, error) {
	manifestPath := filepath.Join(req.ProjectRoot, ".stack", "gen", "codegen", "env-manifest.json")
	manifest, err := loadEnvManifest(manifestPath)
	if err != nil {
		if os.IsNotExist(err) {
			return &BuildOutput{Notes: []string{"env manifest not found; skipping env payload generation"}}, nil
		}
		return nil, err
	}

	// decryptCache avoids decrypting the same SOPS file multiple times when
	// several env vars reference different keys within the same source file.
	decryptCache := make(map[string]map[string]any)
	desiredOutputs := make(map[string]struct{}, len(manifest.Targets))
	artifacts := make([]Artifact, 0, len(manifest.Targets))
	warnings := make([]envWarning, 0)
	registryTargets := make([]envTargetSpec, 0, len(manifest.Targets))

	for _, target := range manifest.Targets {
		flatEnv, targetWarnings, err := buildFlatEnvPayload(ctx, req.ProjectRoot, target, decryptCache)
		if err != nil {
			return nil, fmt.Errorf("build %s/%s payload: %w", target.App, target.Environment, err)
		}
		warnings = append(warnings, targetWarnings...)

		plaintext, err := json.MarshalIndent(flatEnv, "", "  ")
		if err != nil {
			return nil, fmt.Errorf("marshal %s/%s payload: %w", target.App, target.Environment, err)
		}
		plaintext = append(plaintext, '\n')

		outputPath := resolveProjectPath(req.ProjectRoot, target.OutputPath)
		payloadModulePath := generatedPayloadModulePath(req.ProjectRoot, target)
		payloadHash := computePayloadHash(plaintext, target.Recipients)

		var encrypted []byte
		if !req.Force {
			existingHash, _ := extractPayloadHashFromModule(payloadModulePath)
			if existingHash == payloadHash {
				encrypted, _ = os.ReadFile(outputPath)
				// If readFile fails (file absent), encrypted stays nil → falls through to encrypt.
			}
		}
		if encrypted == nil {
			encrypted, err = encryptSopsJSON(ctx, req.ProjectRoot, plaintext, outputPath, target.Recipients)
			if err != nil {
				return nil, fmt.Errorf("encrypt %s/%s payload: %w", target.App, target.Environment, err)
			}
		}
		desiredOutputs[outputPath] = struct{}{}
		artifacts = append(artifacts, Artifact{
			Path:    outputPath,
			Kind:    ArtifactKindText,
			Mode:    0644,
			Content: encrypted,
		})

		desiredOutputs[payloadModulePath] = struct{}{}
		artifacts = append(artifacts, Artifact{
			Path:    payloadModulePath,
			Kind:    ArtifactKindText,
			Mode:    0644,
			Content: renderGeneratedPayloadModule(encrypted, payloadHash),
		})
		registryTargets = append(registryTargets, target)
	}

	registryPath := filepath.Join(req.ProjectRoot, generatedPayloadsRoot, "registry.ts")
	desiredOutputs[registryPath] = struct{}{}
	artifacts = append(artifacts, Artifact{
		Path:    registryPath,
		Kind:    ArtifactKindText,
		Mode:    0644,
		Content: renderGeneratedPayloadRegistry(registryTargets),
	})

	removals, err := findStaleEnvArtifacts(req.ProjectRoot, manifest.DataRoot, desiredOutputs)
	if err != nil {
		return nil, err
	}

	warningMessages := make([]string, 0, len(warnings))
	if len(warnings) > 0 {
		warningContent, err := json.MarshalIndent(envWarningsFile{
			SchemaVersion: 1,
			Warnings:      warnings,
		}, "", "  ")
		if err != nil {
			return nil, fmt.Errorf("marshal env warnings: %w", err)
		}
		warningContent = append(warningContent, '\n')
		artifacts = append(artifacts, Artifact{
			Path:    filepath.Join(req.ProjectRoot, envWarningsPath),
			Kind:    ArtifactKindJSON,
			Mode:    0644,
			Content: warningContent,
		})
		for _, warning := range warnings {
			warningMessages = append(warningMessages, warning.Message)
		}
	} else {
		removals = append(removals, filepath.Join(req.ProjectRoot, envWarningsPath))
	}

	return &BuildOutput{
		Artifacts: artifacts,
		Removals:  removals,
		Warnings:  warningMessages,
	}, nil
}

func loadEnvManifest(path string) (*envManifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var manifest envManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("parse env manifest %s: %w", path, err)
	}

	if manifest.SchemaVersion != 1 && manifest.SchemaVersion != 2 {
		return nil, fmt.Errorf("unsupported env manifest schema version %d", manifest.SchemaVersion)
	}

	return &manifest, nil
}

// buildFlatEnvPayload resolves all vars for a target into a flat map[string]string
// suitable for JSON serialization. Keys are sorted for deterministic output.
// Missing SOPS keys produce warnings rather than errors, allowing partial builds.
func buildFlatEnvPayload(
	ctx context.Context,
	projectRoot string,
	target envTargetSpec,
	decryptCache map[string]map[string]any,
) (map[string]string, []envWarning, error) {
	keys := make([]string, 0, len(target.Vars))
	for key := range target.Vars {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	result := make(map[string]string, len(keys))
	warnings := make([]envWarning, 0)

	for _, envKey := range keys {
		resolver := target.Vars[envKey]
		switch resolver.Kind {
		case "literal":
			result[envKey] = resolver.Value
		case "group", "sopsRef":
			parsed, err := decryptSourceFile(ctx, projectRoot, resolver, decryptCache)
			if err != nil {
				return nil, nil, fmt.Errorf("resolve %s: %w", envKey, err)
			}
			value, ok := parsed[resolver.Key]
			if !ok {
				result[envKey] = ""
				warnings = append(warnings, envWarning{
					App:         target.App,
					Environment: target.Environment,
					EnvKey:      envKey,
					VariableID:  resolver.VariableID,
					Path:        resolver.Path,
					Key:         resolver.Key,
					Message:     fmt.Sprintf("%s/%s: %s missing key %s in %s", target.App, target.Environment, envKey, resolver.Key, resolver.Path),
				})
				continue
			}
			result[envKey] = stringifyEnvValue(value)
		default:
			return nil, nil, fmt.Errorf("unsupported resolver kind %q", resolver.Kind)
		}
	}

	return result, warnings, nil
}

// decryptSourceFile shells out to `sops --decrypt` and caches the result.
// The cache key includes the file type because SOPS needs --input-type to
// correctly parse the same file path as different formats (yaml vs dotenv).
func decryptSourceFile(
	ctx context.Context,
	projectRoot string,
	resolver envVarResolver,
	decryptCache map[string]map[string]any,
) (map[string]any, error) {
	filePath := resolveProjectPath(projectRoot, resolver.Path)
	cacheKey := resolver.FileType + ":" + filePath
	if cached, ok := decryptCache[cacheKey]; ok {
		return cached, nil
	}

	cmd := exec.CommandContext(
		ctx,
		"sops",
		"--decrypt",
		"--input-type",
		sopsInputType(resolver.FileType),
		"--output-type",
		"json",
		filePath,
	)
	cmd.Dir = projectRoot
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("decrypt %s: %w: %s", filePath, err, strings.TrimSpace(string(output)))
	}

	var parsed map[string]any
	if err := json.Unmarshal(output, &parsed); err != nil {
		return nil, fmt.Errorf("parse decrypted output for %s: %w", filePath, err)
	}

	decryptCache[cacheKey] = parsed
	return parsed, nil
}

// computePayloadHash returns a deterministic SHA-256 hex digest of the
// canonical plaintext and sorted recipients. This hash is embedded in the
// generated .ts module so subsequent runs can detect unchanged content
// without needing to decrypt the SOPS ciphertext.
func computePayloadHash(canonicalPlaintext []byte, recipients []string) string {
	sorted := make([]string, len(recipients))
	copy(sorted, recipients)
	sort.Strings(sorted)

	h := sha256.New()
	h.Write(canonicalPlaintext)
	h.Write([]byte("\x00"))
	h.Write([]byte(strings.Join(sorted, ",")))
	return hex.EncodeToString(h.Sum(nil))
}

const payloadHashPrefix = "// content-hash: "

// extractPayloadHashFromModule reads a previously generated .ts module and
// extracts the embedded content hash. Returns ("", nil) when no hash line is
// present (e.g., files generated by an older version of the tool).
func extractPayloadHashFromModule(modulePath string) (string, error) {
	data, err := os.ReadFile(modulePath)
	if err != nil {
		return "", err
	}
	for _, line := range strings.SplitN(string(data), "\n", 5) {
		if strings.HasPrefix(line, payloadHashPrefix) {
			return strings.TrimPrefix(line, payloadHashPrefix), nil
		}
	}
	return "", nil
}

// encryptSopsJSON encrypts a JSON plaintext payload using SOPS with AGE
// recipients. It writes to a temp file because SOPS requires a file path
// (it doesn't support stdin for encryption with --age).
func encryptSopsJSON(ctx context.Context, projectRoot string, plaintext []byte, outputPath string, recipients []string) ([]byte, error) {
	if len(recipients) == 0 {
		return nil, fmt.Errorf("no recipients configured for %s", outputPath)
	}

	file, err := os.CreateTemp("", "stackpanel-codegen-*.json")
	if err != nil {
		return nil, fmt.Errorf("create temp plaintext file: %w", err)
	}
	tempPath := file.Name()
	defer os.Remove(tempPath)

	if _, err := file.Write(plaintext); err != nil {
		file.Close()
		return nil, fmt.Errorf("write temp plaintext file: %w", err)
	}
	if err := file.Close(); err != nil {
		return nil, fmt.Errorf("close temp plaintext file: %w", err)
	}

	cmd := exec.CommandContext(
		ctx,
		"sops",
		"--encrypt",
		"--input-type",
		"json",
		"--output-type",
		"json",
		"--age",
		strings.Join(recipients, ","),
		tempPath,
	)
	cmd.Dir = projectRoot
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("encrypt payload: %w: %s", err, strings.TrimSpace(string(output)))
	}

	return output, nil
}

// findStaleEnvArtifacts walks the data root and generated payloads directory,
// returning paths for files that exist on disk but aren't in the desired set.
// This handles cleanup when apps or environments are removed from the manifest.
func findStaleEnvArtifacts(projectRoot, dataRoot string, desired map[string]struct{}) ([]string, error) {
	roots := []struct {
		path   string
		suffix string
		label  string
	}{
		{path: resolveProjectPath(projectRoot, dataRoot), suffix: ".sops.json", label: "env data root"},
		{path: filepath.Join(projectRoot, generatedPayloadsRoot), suffix: ".ts", label: "generated payload root"},
	}

	entries := make([]string, 0)
	for _, root := range roots {
		if root.path == "" {
			continue
		}
		if _, err := os.Stat(root.path); err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, fmt.Errorf("stat %s %s: %w", root.label, root.path, err)
		}

		err := filepath.WalkDir(root.path, func(path string, d fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				if os.IsNotExist(walkErr) {
					return nil
				}
				return walkErr
			}
			if d.IsDir() {
				return nil
			}
			if !strings.HasSuffix(path, root.suffix) {
				return nil
			}
			if _, ok := desired[path]; ok {
				return nil
			}
			entries = append(entries, path)
			return nil
		})
		if err != nil {
			return nil, fmt.Errorf("scan stale artifacts in %s: %w", root.path, err)
		}
	}

	sort.Strings(entries)
	return entries, nil
}

func generatedPayloadModulePath(projectRoot string, target envTargetSpec) string {
	return filepath.Join(projectRoot, generatedPayloadsRoot, target.App, target.Environment+".ts")
}

// payloadModuleData drives templates/env-payload.ts.tmpl.
type payloadModuleData struct {
	Hash      string
	Encrypted string
}

// renderGeneratedPayloadModule produces a TS module that exports the encrypted
// SOPS payload as a string constant. At runtime, the app's entrypoint decrypts
// this using the local AGE identity. The content-hash comment embeds a
// deterministic digest of the plaintext and recipients so that subsequent
// codegen runs can skip re-encryption without needing to decrypt the payload.
//
// The encrypted JSON is embedded as a real (multi-line, indented) JS object
// literal rather than as a single-line escaped string so the file is reviewable
// in diffs and editors. JSON.stringify at module load preserves the existing
// `Promise<string>` registry contract that the loader expects.
func renderGeneratedPayloadModule(encrypted []byte, contentHash string) []byte {
	literal := formatEncryptedForEmbed(encrypted)
	out, err := renderTemplate("env-payload.ts.tmpl", payloadModuleData{
		Hash:      contentHash,
		Encrypted: literal,
	})
	if err != nil {
		// Templates are validated at init via template.Must; an error here
		// would mean a programmer bug, not a user-facing condition.
		panic(err)
	}
	return out
}

// formatEncryptedForEmbed re-indents SOPS's JSON output to 2 spaces (project
// convention) so the value can be embedded directly as a JS object literal.
// JSON is a syntactically valid subset of JS object literals, so the result is
// well-formed TypeScript. SOPS's MAC is computed over the encrypted values, not
// the surrounding whitespace, so reformatting is safe for downstream
// decryption. Falls back to the raw bytes if parsing fails.
func formatEncryptedForEmbed(encrypted []byte) string {
	var parsed any
	if err := json.Unmarshal(encrypted, &parsed); err != nil {
		return string(encrypted)
	}
	indented, err := json.MarshalIndent(parsed, "", "  ")
	if err != nil {
		return string(encrypted)
	}
	return string(indented)
}

// registryData drives templates/env-registry.ts.tmpl.
type registryData struct {
	Apps []registryApp
}

type registryApp struct {
	Name    string
	Loaders []registryLoader
}

type registryLoader struct {
	Env        string
	ImportPath string
}

// renderGeneratedPayloadRegistry generates registry.ts with lazy dynamic imports
// for all payload modules, keyed by app and environment. This enables the runtime
// loader to fetch only the payload it needs without bundling all environments.
func renderGeneratedPayloadRegistry(targets []envTargetSpec) []byte {
	byApp := make(map[string][]string)
	for _, target := range targets {
		byApp[target.App] = append(byApp[target.App], target.Environment)
	}

	apps := make([]registryApp, 0, len(byApp))
	for name := range byApp {
		envs := byApp[name]
		sort.Strings(envs)
		loaders := make([]registryLoader, 0, len(envs))
		for _, env := range envs {
			loaders = append(loaders, registryLoader{
				Env:        env,
				ImportPath: "./" + name + "/" + env,
			})
		}
		apps = append(apps, registryApp{Name: name, Loaders: loaders})
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Name < apps[j].Name })

	out, err := renderTemplate("env-registry.ts.tmpl", registryData{Apps: apps})
	if err != nil {
		panic(err)
	}
	return out
}

func resolveProjectPath(projectRoot, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(projectRoot, path)
}

// stringifyEnvValue coerces arbitrary JSON values to strings for env payloads.
// SOPS decryption returns typed JSON (booleans, numbers) but env vars are always strings.
func stringifyEnvValue(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return v
	case bool:
		if v {
			return "true"
		}
		return "false"
	case float64:
		return strings.TrimSuffix(strings.TrimSuffix(fmt.Sprintf("%f", v), "0"), ".")
	default:
		encoded, err := json.Marshal(v)
		if err != nil {
			return fmt.Sprintf("%v", v)
		}
		return string(encoded)
	}
}

// sopsInputType maps our file type names to SOPS --input-type values.
// SOPS uses "dotenv" while we use "env" in the manifest schema.
func sopsInputType(fileType string) string {
	if fileType == "env" {
		return "dotenv"
	}
	return fileType
}
