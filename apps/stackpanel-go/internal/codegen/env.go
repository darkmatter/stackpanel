package codegen

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const envModuleName = "env"

type envModule struct{}

type envManifest struct {
	SchemaVersion int             `json:"schemaVersion"`
	DataRoot      string          `json:"dataRoot"`
	Targets       []envTargetSpec `json:"targets"`
}

type envTargetSpec struct {
	App         string                    `json:"app"`
	Environment string                    `json:"environment"`
	OutputPath  string                    `json:"outputPath"`
	Recipients  []string                  `json:"recipients"`
	Vars        map[string]envVarResolver `json:"vars"`
}

type envVarResolver struct {
	Kind       string `json:"kind"`
	Value      string `json:"value,omitempty"`
	VariableID string `json:"variableId,omitempty"`
	Path       string `json:"path,omitempty"`
	FileType   string `json:"fileType,omitempty"`
	Key        string `json:"key,omitempty"`
}

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
const generatedPayloadsRoot = "packages/gen/env/src/generated-payloads"

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

func (envModule) Build(ctx context.Context, req BuildRequest) (*BuildOutput, error) {
	manifestPath := filepath.Join(req.ProjectRoot, ".stack", "gen", "codegen", "env-manifest.json")
	manifest, err := loadEnvManifest(manifestPath)
	if err != nil {
		if os.IsNotExist(err) {
			return &BuildOutput{Notes: []string{"env manifest not found; skipping env payload generation"}}, nil
		}
		return nil, err
	}

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

		encrypted, err := encryptSopsJSON(ctx, req.ProjectRoot, plaintext, target.OutputPath, target.Recipients)
		if err != nil {
			return nil, fmt.Errorf("encrypt %s/%s payload: %w", target.App, target.Environment, err)
		}

		outputPath := resolveProjectPath(req.ProjectRoot, target.OutputPath)
		desiredOutputs[outputPath] = struct{}{}
		artifacts = append(artifacts, Artifact{
			Path:    outputPath,
			Kind:    ArtifactKindText,
			Mode:    0644,
			Content: encrypted,
		})

		payloadModulePath := generatedPayloadModulePath(req.ProjectRoot, target)
		desiredOutputs[payloadModulePath] = struct{}{}
		artifacts = append(artifacts, Artifact{
			Path:    payloadModulePath,
			Kind:    ArtifactKindText,
			Mode:    0644,
			Content: renderGeneratedPayloadModule(encrypted),
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

	if manifest.SchemaVersion != 1 {
		return nil, fmt.Errorf("unsupported env manifest schema version %d", manifest.SchemaVersion)
	}

	return &manifest, nil
}

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

func renderGeneratedPayloadModule(encrypted []byte) []byte {
	quoted := strconv.Quote(string(encrypted))
	content := "// Auto-generated by Stackpanel — do not edit manually.\n" +
		"const encryptedPayload = " + quoted + ";\n\n" +
		"export default encryptedPayload;\n"
	return []byte(content)
}

func renderGeneratedPayloadRegistry(targets []envTargetSpec) []byte {
	byApp := make(map[string][]string)
	for _, target := range targets {
		byApp[target.App] = append(byApp[target.App], target.Environment)
	}

	apps := make([]string, 0, len(byApp))
	for app := range byApp {
		apps = append(apps, app)
	}
	sort.Strings(apps)

	var builder strings.Builder
	builder.WriteString("// Auto-generated by Stackpanel — do not edit manually.\n")
	builder.WriteString("const payloadLoaders: Record<string, Record<string, () => Promise<string>>> = {\n")
	for _, app := range apps {
		envs := byApp[app]
		sort.Strings(envs)
		builder.WriteString("  ")
		builder.WriteString(strconv.Quote(app))
		builder.WriteString(": {\n")
		for _, env := range envs {
			builder.WriteString("    ")
			builder.WriteString(strconv.Quote(env))
			builder.WriteString(": async () => (await import(")
			builder.WriteString(strconv.Quote("./" + app + "/" + env))
			builder.WriteString(")).default,\n")
		}
		builder.WriteString("  },\n")
	}
	builder.WriteString("};\n\n")
	builder.WriteString("export async function loadGeneratedPayload(app: string, env: string): Promise<string | null> {\n")
	builder.WriteString("  const appLoaders = payloadLoaders[app];\n")
	builder.WriteString("  if (!appLoaders) return null;\n")
	builder.WriteString("  const loader = appLoaders[env];\n")
	builder.WriteString("  if (!loader) return null;\n")
	builder.WriteString("  return loader();\n")
	builder.WriteString("}\n")
	return []byte(builder.String())
}

func resolveProjectPath(projectRoot, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(projectRoot, path)
}

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

func sopsInputType(fileType string) string {
	if fileType == "env" {
		return "dotenv"
	}
	return fileType
}
