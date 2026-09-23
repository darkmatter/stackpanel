package fileops

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"

	toml "github.com/pelletier/go-toml/v2"
	"gopkg.in/yaml.v3"
)

// codec turns a structured document into the generic map the op engine
// mutates and back. Baseline tracking and revert are format-agnostic: only
// the bytes on disk differ.
type codec interface {
	Decode(data []byte) (map[string]any, error)
	Encode(doc map[string]any) ([]byte, error)
}

// codecForType maps an entry type ("json-ops", "yaml-ops", "toml-ops") to its codec.
func codecForType(entryType string) (codec, bool) {
	switch entryType {
	case "json-ops":
		return jsonCodec{}, true
	case "yaml-ops":
		return yamlCodec{}, true
	case "toml-ops":
		return tomlCodec{}, true
	default:
		return nil, false
	}
}

func isOpsType(entryType string) bool {
	_, ok := codecForType(entryType)
	return ok
}

type jsonCodec struct{}

func (jsonCodec) Decode(data []byte) (map[string]any, error) {
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		return nil, err
	}
	if decoded == nil {
		decoded = map[string]any{}
	}
	return decoded, nil
}

func (jsonCodec) Encode(doc map[string]any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(doc); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// yamlCodec round-trips through yaml.v3. Comments are not preserved: the
// document is decoded to plain values and re-encoded with sorted keys and
// two-space indentation. Use writer = "block" or "full" when comments matter.
type yamlCodec struct{}

func (yamlCodec) Decode(data []byte) (map[string]any, error) {
	var decoded map[string]any
	if err := yaml.Unmarshal(data, &decoded); err != nil {
		return nil, err
	}
	if decoded == nil {
		decoded = map[string]any{}
	}
	return normalizeKeys(decoded).(map[string]any), nil
}

func (yamlCodec) Encode(doc map[string]any) ([]byte, error) {
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(doc); err != nil {
		return nil, err
	}
	if err := enc.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// tomlCodec round-trips through go-toml v2. Comments are not preserved.
type tomlCodec struct{}

func (tomlCodec) Decode(data []byte) (map[string]any, error) {
	var decoded map[string]any
	if err := toml.Unmarshal(data, &decoded); err != nil {
		return nil, err
	}
	if decoded == nil {
		decoded = map[string]any{}
	}
	return normalizeKeys(decoded).(map[string]any), nil
}

func (tomlCodec) Encode(doc map[string]any) ([]byte, error) {
	data, err := toml.Marshal(doc)
	if err != nil {
		return nil, err
	}
	if len(data) > 0 && !bytes.HasSuffix(data, []byte("\n")) {
		data = append(data, '\n')
	}
	return data, nil
}

// normalizeKeys rewrites map[any]any (which yaml can produce for non-string
// keys) and nested containers into the map[string]any / []any shapes the op
// engine expects. Non-string keys are stringified.
func normalizeKeys(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		out := make(map[string]any, len(typed))
		for k, v := range typed {
			out[k] = normalizeKeys(v)
		}
		return out
	case map[any]any:
		out := make(map[string]any, len(typed))
		for k, v := range typed {
			out[fmt.Sprint(k)] = normalizeKeys(v)
		}
		return out
	case []any:
		out := make([]any, len(typed))
		for i, v := range typed {
			out[i] = normalizeKeys(v)
		}
		return out
	default:
		return typed
	}
}

// describeCodec is used in error messages.
func describeCodec(entryType string) string {
	return strings.TrimSuffix(entryType, "-ops")
}
