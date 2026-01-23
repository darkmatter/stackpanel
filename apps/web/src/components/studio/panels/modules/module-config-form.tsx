/**
 * Module Configuration Form
 *
 * A form for editing module configuration. Supports JSON Schema-based
 * configuration when a schema is provided, otherwise falls back to a
 * simple key-value editor.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Textarea } from "@ui/textarea";
import {
  AlertCircle,
  Check,
  FileCode,
  Loader2,
  Plus,
  Save,
  Trash2,
} from "lucide-react";
import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";
import { useModuleConfig, useSaveModuleConfig } from "./use-modules";
import type { ModuleConfig } from "./types";

// =============================================================================
// Props
// =============================================================================

interface ModuleConfigFormProps {
  moduleId: string;
  schema?: string | null;
  initialConfig?: ModuleConfig;
}

// =============================================================================
// JSON Schema Types (simplified)
// =============================================================================

interface JsonSchemaProperty {
  type?: string;
  description?: string;
  default?: unknown;
  enum?: unknown[];
  items?: JsonSchemaProperty;
  properties?: Record<string, JsonSchemaProperty>;
  required?: string[];
}

interface JsonSchema {
  type?: string;
  properties?: Record<string, JsonSchemaProperty>;
  required?: string[];
  description?: string;
}

// =============================================================================
// Schema-Based Form
// =============================================================================

function SchemaBasedForm({
  schema,
  config,
  onChange,
}: {
  schema: JsonSchema;
  config: Record<string, unknown>;
  onChange: (config: Record<string, unknown>) => void;
}) {
  if (!schema.properties) {
    return (
      <p className="text-sm text-muted-foreground">
        Schema has no configurable properties.
      </p>
    );
  }

  const handleFieldChange = (key: string, value: unknown) => {
    onChange({ ...config, [key]: value });
  };

  return (
    <div className="space-y-4">
      {Object.entries(schema.properties).map(([key, prop]) => (
        <SchemaField
          key={key}
          name={key}
          property={prop}
          value={config[key]}
          required={schema.required?.includes(key) ?? false}
          onChange={(value) => handleFieldChange(key, value)}
        />
      ))}
    </div>
  );
}

function SchemaField({
  name,
  property,
  value,
  required,
  onChange,
}: {
  name: string;
  property: JsonSchemaProperty;
  value: unknown;
  required: boolean;
  onChange: (value: unknown) => void;
}) {
  const { type, description, enum: enumValues } = property;

  // Handle enum types as select
  if (enumValues && enumValues.length > 0) {
    return (
      <div className="space-y-2">
        <Label htmlFor={name} className="flex items-center gap-2">
          {name}
          {required && <span className="text-destructive">*</span>}
        </Label>
        {description && (
          <p className="text-xs text-muted-foreground">{description}</p>
        )}
        <select
          id={name}
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        >
          <option value="">Select...</option>
          {enumValues.map((v) => (
            <option key={String(v)} value={String(v)}>
              {String(v)}
            </option>
          ))}
        </select>
      </div>
    );
  }

  // Handle boolean type
  if (type === "boolean") {
    return (
      <div className="flex items-center justify-between rounded-md border p-3">
        <div className="space-y-0.5">
          <Label htmlFor={name}>{name}</Label>
          {description && (
            <p className="text-xs text-muted-foreground">{description}</p>
          )}
        </div>
        <Switch
          id={name}
          checked={Boolean(value)}
          onCheckedChange={onChange}
        />
      </div>
    );
  }

  // Handle number/integer type
  if (type === "number" || type === "integer") {
    return (
      <div className="space-y-2">
        <Label htmlFor={name} className="flex items-center gap-2">
          {name}
          {required && <span className="text-destructive">*</span>}
        </Label>
        {description && (
          <p className="text-xs text-muted-foreground">{description}</p>
        )}
        <Input
          id={name}
          type="number"
          value={String(value ?? "")}
          onChange={(e) => onChange(Number(e.target.value))}
        />
      </div>
    );
  }

  // Handle object type (nested)
  if (type === "object" && property.properties) {
    return (
      <div className="space-y-2">
        <Label className="flex items-center gap-2">
          {name}
          {required && <span className="text-destructive">*</span>}
        </Label>
        {description && (
          <p className="text-xs text-muted-foreground">{description}</p>
        )}
        <div className="rounded-md border p-3">
          <SchemaBasedForm
            schema={property as JsonSchema}
            config={(value as Record<string, unknown>) ?? {}}
            onChange={onChange as (config: Record<string, unknown>) => void}
          />
        </div>
      </div>
    );
  }

  // Handle array type
  if (type === "array") {
    const arrayValue = Array.isArray(value) ? value : [];
    return (
      <div className="space-y-2">
        <Label className="flex items-center gap-2">
          {name}
          {required && <span className="text-destructive">*</span>}
        </Label>
        {description && (
          <p className="text-xs text-muted-foreground">{description}</p>
        )}
        <div className="space-y-2">
          {arrayValue.map((item, index) => (
            <div key={index} className="flex items-center gap-2">
              <Input
                value={String(item)}
                onChange={(e) => {
                  const newArray = [...arrayValue];
                  newArray[index] = e.target.value;
                  onChange(newArray);
                }}
              />
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  onChange(arrayValue.filter((_, i) => i !== index));
                }}
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          ))}
          <Button
            variant="outline"
            size="sm"
            onClick={() => onChange([...arrayValue, ""])}
          >
            <Plus className="mr-2 h-4 w-4" />
            Add Item
          </Button>
        </div>
      </div>
    );
  }

  // Default: string input
  return (
    <div className="space-y-2">
      <Label htmlFor={name} className="flex items-center gap-2">
        {name}
        {required && <span className="text-destructive">*</span>}
      </Label>
      {description && (
        <p className="text-xs text-muted-foreground">{description}</p>
      )}
      <Input
        id={name}
        value={String(value ?? "")}
        onChange={(e) => onChange(e.target.value)}
        placeholder={property.default ? String(property.default) : undefined}
      />
    </div>
  );
}

// =============================================================================
// Key-Value Editor (fallback)
// =============================================================================

function KeyValueEditor({
  config,
  onChange,
}: {
  config: Record<string, unknown>;
  onChange: (config: Record<string, unknown>) => void;
}) {
  const entries = Object.entries(config);

  const handleAdd = () => {
    onChange({ ...config, "": "" });
  };

  const handleRemove = (key: string) => {
    const newConfig = { ...config };
    delete newConfig[key];
    onChange(newConfig);
  };

  const handleKeyChange = (oldKey: string, newKey: string) => {
    if (oldKey === newKey) return;
    const value = config[oldKey];
    const newConfig = { ...config };
    delete newConfig[oldKey];
    newConfig[newKey] = value;
    onChange(newConfig);
  };

  const handleValueChange = (key: string, value: string) => {
    onChange({ ...config, [key]: value });
  };

  return (
    <div className="space-y-3">
      {entries.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No configuration settings yet.
        </p>
      ) : (
        entries.map(([key, value], index) => (
          <div key={index} className="flex items-start gap-2">
            <div className="flex-1 space-y-1">
              <Input
                placeholder="Key"
                value={key}
                onChange={(e) => handleKeyChange(key, e.target.value)}
                className="font-mono text-sm"
              />
            </div>
            <div className="flex-1 space-y-1">
              <Input
                placeholder="Value"
                value={String(value ?? "")}
                onChange={(e) => handleValueChange(key, e.target.value)}
                className="font-mono text-sm"
              />
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => handleRemove(key)}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
        ))
      )}
      <Button variant="outline" size="sm" onClick={handleAdd}>
        <Plus className="mr-2 h-4 w-4" />
        Add Setting
      </Button>
    </div>
  );
}

// =============================================================================
// Raw JSON Editor (fallback for complex configs)
// =============================================================================

function RawJsonEditor({
  config,
  onChange,
  error,
}: {
  config: Record<string, unknown>;
  onChange: (config: Record<string, unknown>) => void;
  error?: string | null;
}) {
  const [text, setText] = useState(JSON.stringify(config, null, 2));
  const [parseError, setParseError] = useState<string | null>(null);

  useEffect(() => {
    setText(JSON.stringify(config, null, 2));
  }, [config]);

  const handleChange = (value: string) => {
    setText(value);
    try {
      const parsed = JSON.parse(value);
      setParseError(null);
      onChange(parsed);
    } catch (e) {
      setParseError((e as Error).message);
    }
  };

  return (
    <div className="space-y-2">
      <Textarea
        value={text}
        onChange={(e) => handleChange(e.target.value)}
        className={cn(
          "min-h-[200px] font-mono text-sm",
          (parseError || error) && "border-destructive",
        )}
      />
      {(parseError || error) && (
        <p className="flex items-center gap-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4" />
          {parseError || error}
        </p>
      )}
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export function ModuleConfigForm({
  moduleId,
  schema: schemaString,
  initialConfig,
}: ModuleConfigFormProps) {
  const { data: savedConfig, isLoading: isLoadingConfig } = useModuleConfig(moduleId);
  const saveMutation = useSaveModuleConfig(moduleId);

  const [config, setConfig] = useState<Record<string, unknown>>(
    initialConfig?.settings ?? {},
  );
  const [editorMode, setEditorMode] = useState<"schema" | "kv" | "json">("schema");
  const [hasChanges, setHasChanges] = useState(false);

  // Parse schema if provided
  const schema = schemaString ? (JSON.parse(schemaString) as JsonSchema) : null;

  // Update config when saved config loads
  useEffect(() => {
    if (savedConfig?.settings) {
      setConfig(savedConfig.settings);
    }
  }, [savedConfig]);

  // Determine default editor mode
  useEffect(() => {
    if (schema?.properties) {
      setEditorMode("schema");
    } else {
      setEditorMode("kv");
    }
  }, [schema]);

  const handleConfigChange = (newConfig: Record<string, unknown>) => {
    setConfig(newConfig);
    setHasChanges(true);
  };

  const handleSave = async () => {
    await saveMutation.mutateAsync({ settings: config });
    setHasChanges(false);
  };

  if (isLoadingConfig) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Editor Mode Tabs */}
      <div className="flex items-center gap-2">
        {schema?.properties && (
          <Badge
            variant={editorMode === "schema" ? "default" : "outline"}
            className="cursor-pointer"
            onClick={() => setEditorMode("schema")}
          >
            Form
          </Badge>
        )}
        <Badge
          variant={editorMode === "kv" ? "default" : "outline"}
          className="cursor-pointer"
          onClick={() => setEditorMode("kv")}
        >
          Key-Value
        </Badge>
        <Badge
          variant={editorMode === "json" ? "default" : "outline"}
          className="cursor-pointer"
          onClick={() => setEditorMode("json")}
        >
          <FileCode className="mr-1 h-3 w-3" />
          JSON
        </Badge>
      </div>

      {/* Schema Info */}
      {schema?.description && editorMode === "schema" && (
        <p className="text-sm text-muted-foreground">{schema.description}</p>
      )}

      {/* Editor */}
      <div className="rounded-md border p-4">
        {editorMode === "schema" && schema?.properties ? (
          <SchemaBasedForm
            schema={schema}
            config={config}
            onChange={handleConfigChange}
          />
        ) : editorMode === "kv" ? (
          <KeyValueEditor config={config} onChange={handleConfigChange} />
        ) : (
          <RawJsonEditor
            config={config}
            onChange={handleConfigChange}
            error={saveMutation.error?.message}
          />
        )}
      </div>

      {/* Save Button */}
      <div className="flex items-center justify-between">
        {hasChanges ? (
          <p className="text-sm text-muted-foreground">You have unsaved changes</p>
        ) : (
          <p className="text-sm text-muted-foreground">Configuration is saved</p>
        )}
        <Button
          onClick={handleSave}
          disabled={!hasChanges || saveMutation.isPending}
        >
          {saveMutation.isPending ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : saveMutation.isSuccess && !hasChanges ? (
            <Check className="mr-2 h-4 w-4" />
          ) : (
            <Save className="mr-2 h-4 w-4" />
          )}
          {saveMutation.isPending
            ? "Saving..."
            : saveMutation.isSuccess && !hasChanges
              ? "Saved"
              : "Save Changes"}
        </Button>
      </div>

      {/* Error */}
      {saveMutation.isError && (
        <div className="rounded-md border border-destructive/50 bg-destructive/10 p-3">
          <p className="text-sm text-destructive">
            Failed to save: {saveMutation.error?.message}
          </p>
        </div>
      )}
    </div>
  );
}
