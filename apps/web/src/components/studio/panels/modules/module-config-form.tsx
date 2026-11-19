import type { JsonObject } from "@bufbuild/protobuf";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Textarea } from "@ui/textarea";
import { FileCode, Loader2, Save } from "lucide-react";
import { useId, useMemo, useState } from "react";
import {
  applyFieldEdits,
  fieldKind,
  formatField,
  parseSettings,
  readSettingsSchema,
  settingsPatch,
} from "./module-settings";
import { useSaveModuleConfig } from "./use-modules";

interface ModuleConfigFormProps {
  moduleId: string;
  settings: JsonObject;
  schema?: string | null;
  onChanged: (message: string) => void;
}

type Draft = { base: JsonObject; fields: Record<string, string>; json?: string };

function SchemaField({
  name,
  schema,
  text,
  onChange,
  required,
  readOnly,
}: {
  name: string;
  schema: JsonObject;
  text: string;
  onChange: (value: string) => void;
  required: boolean;
  readOnly: boolean;
}) {
  const id = useId();
  const kind = fieldKind(schema);
  const title = typeof schema.title === "string" ? schema.title : name;
  const description = typeof schema.description === "string" ? schema.description : null;
  const props = {
    id,
    disabled: readOnly,
    "aria-describedby": description ? `${id}-description` : undefined,
  };
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>
        {title}
        {required && <span className="text-destructive"> *</span>}
      </Label>
      {description && (
        <p id={`${id}-description`} className="text-xs text-muted-foreground">
          {description}
        </p>
      )}
      {kind === "enum" && Array.isArray(schema.enum) ? (
        <select
          {...props}
          value={text}
          onChange={(e) => onChange(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
        >
          <option value="" disabled>
            Select a value
          </option>
          {schema.enum.map((v) => (
            <option key={JSON.stringify(v)} value={JSON.stringify(v, null, 2)}>
              {typeof v === "object" ? JSON.stringify(v) : String(v)}
            </option>
          ))}
        </select>
      ) : kind === "boolean" ? (
        <Switch
          {...props}
          checked={text === "true"}
          onCheckedChange={(checked) => onChange(String(checked))}
        />
      ) : kind === "string" || kind === "number" ? (
        <Input
          {...props}
          type={kind === "number" ? "number" : "text"}
          step={schema.type === "integer" ? "1" : "any"}
          value={text}
          onChange={(e) => onChange(e.target.value)}
        />
      ) : (
        <Textarea
          {...props}
          value={text}
          onChange={(e) => onChange(e.target.value)}
          placeholder="JSON value"
          className="min-h-20 font-mono text-xs"
        />
      )}
    </div>
  );
}

export function ModuleConfigForm({
  moduleId,
  schema: rawSchema,
  settings,
  onChanged,
}: ModuleConfigFormProps) {
  const save = useSaveModuleConfig(moduleId);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [jsonMode, setJsonMode] = useState(false);
  const parsed = useMemo(() => {
    try {
      return { schema: readSettingsSchema(rawSchema) };
    } catch (error) {
      return { error: error instanceof Error ? error.message : String(error) };
    }
  }, [rawSchema]);
  const schema = parsed.schema ?? null;
  const useJson = jsonMode || !schema?.fields.length;
  const base = draft?.base ?? settings;
  const result = useMemo(() => {
    if (!draft) return { patch: null };
    if (JSON.stringify(draft.base) !== JSON.stringify(settings)) {
      return {
        error: "Settings changed in the project. Discard this draft to edit the latest settings.",
      };
    }
    try {
      const next =
        draft.json === undefined
          ? applyFieldEdits(settings, draft.fields, schema)
          : parseSettings(draft.json);
      return { patch: settingsPatch(settings, next, schema) };
    } catch (error) {
      return { error: error instanceof Error ? error.message : String(error) };
    }
  }, [draft, settings, schema]);
  if (parsed.error) {
    return (
      <p
        role="alert"
        className="rounded-md border border-destructive/50 p-3 text-sm text-destructive"
      >
        Invalid settings schema: {parsed.error}
      </p>
    );
  }
  const reset = () => {
    setDraft(null);
    save.reset();
  };
  const canSave =
    result.patch && Object.keys(result.patch).length > 0 && !save.isPending && !save.unavailable;
  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (!canSave || !result.patch) return;
        save.mutate(result.patch, {
          onSuccess: ({ message }) => {
            setDraft(null);
            onChanged(message);
          },
        });
      }}
    >
      {!!schema?.fields.length && (
        <div className="flex gap-2">
          <Button
            type="button"
            variant={!useJson ? "secondary" : "outline"}
            size="sm"
            disabled={draft !== null}
            aria-pressed={!useJson}
            onClick={() => setJsonMode(false)}
          >
            Form
          </Button>
          <Button
            type="button"
            variant={useJson ? "secondary" : "outline"}
            size="sm"
            disabled={draft !== null}
            aria-pressed={useJson}
            onClick={() => setJsonMode(true)}
          >
            <FileCode className="mr-1 h-3 w-3" />
            JSON
          </Button>
        </div>
      )}
      {typeof schema?.definition.description === "string" && (
        <p className="text-sm text-muted-foreground">{schema.definition.description}</p>
      )}
      <fieldset disabled={save.isPending} className="space-y-4 rounded-md border p-4">
        {useJson ? (
          <Textarea
            aria-label="Module settings JSON"
            spellCheck={false}
            value={draft?.json ?? JSON.stringify(base, null, 2)}
            onChange={(e) => {
              save.reset();
              setDraft({ base, fields: {}, json: e.target.value });
            }}
            className="min-h-[200px] font-mono text-sm"
          />
        ) : (
          schema?.fields.map(({ name, schema: property, readOnly }) => (
            <SchemaField
              key={name}
              name={name}
              schema={property}
              required={
                Array.isArray(schema.definition.required) &&
                schema.definition.required.includes(name)
              }
              readOnly={readOnly}
              text={
                draft && Object.hasOwn(draft.fields, name)
                  ? draft.fields[name]!
                  : formatField(property, Object.hasOwn(base, name) ? base[name] : property.default)
              }
              onChange={(value) => {
                save.reset();
                setDraft((old) => ({
                  base: old?.base ?? settings,
                  fields: { ...old?.fields, [name]: value },
                }));
              }}
            />
          ))
        )}
      </fieldset>
      {result.error && (
        <p role="alert" className="whitespace-pre-wrap text-sm text-destructive">
          {result.error}
        </p>
      )}
      {save.error && (
        <p role="alert" className="text-sm text-destructive">
          Failed to save settings: {save.error.message}
        </p>
      )}
      <div className="flex items-center justify-between gap-2">
        {draft ? (
          <Button type="button" variant="ghost" size="sm" disabled={save.isPending} onClick={reset}>
            Discard draft
          </Button>
        ) : (
          <p className="text-sm text-muted-foreground">Current project settings</p>
        )}
        <Button type="submit" title={save.unavailable} disabled={!canSave}>
          {save.isPending ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : (
            <Save className="mr-2 h-4 w-4" />
          )}
          {save.isPending ? "Saving…" : "Save Changes"}
        </Button>
      </div>
    </form>
  );
}
