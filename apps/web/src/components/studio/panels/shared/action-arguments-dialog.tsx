import type { JsonObject, JsonValue } from "@bufbuild/protobuf";
import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Textarea } from "@ui/textarea";
import { useId, useState, type FormEvent } from "react";
import type { ModuleAction } from "./panel-types";
import { isJsonObject } from "./panel-data";

function properties(schema?: JsonObject): Array<[string, JsonObject]> {
  if (!isJsonObject(schema?.properties)) return [];
  return Object.entries(schema.properties).map(([key, spec]) => [
    key,
    isJsonObject(spec) ? spec : {},
  ]);
}

// Non-enumerated object schemas (e.g. a union or arbitrary key/value map) still
// accept typed arguments through a JSON editor. The agent validates the full schema.
function needsRawEditor(schema?: JsonObject) {
  if (!schema || properties(schema).length) return false;
  const hasRequiredKeys = Array.isArray(schema.required) && schema.required.length > 0;
  return (
    schema.additionalProperties !== false ||
    hasRequiredKeys ||
    Boolean(schema.anyOf || schema.oneOf || schema.allOf || schema.$ref || schema.patternProperties)
  );
}

export function needsArgumentDialog(action: ModuleAction) {
  return (
    !!action.confirm ||
    properties(action.argsSchema).length > 0 ||
    needsRawEditor(action.argsSchema)
  );
}

function choices(spec: JsonObject): JsonValue[] | undefined {
  if (Object.hasOwn(spec, "const")) return [spec.const!];
  if (Array.isArray(spec.enum)) return spec.enum;
  if (spec.type === "boolean") return [true, false];
  if (spec.type === "null") return [null];
  return undefined;
}

function draftValue(spec: JsonObject, value: JsonValue | undefined) {
  if (value === undefined) return "";
  const options = choices(spec);
  if (options) {
    // Static Nix table rows transport even numeric/boolean cells as strings.
    const encoded = JSON.stringify(value);
    for (const item of options) {
      if (JSON.stringify(item) === encoded) return encoded;
    }
    const match = options.find((item) => String(item) === value);
    return match === undefined ? "" : JSON.stringify(match);
  }
  return typeof value === "string" ? value : JSON.stringify(value);
}

function argumentValue(name: string, spec: JsonObject, text: string): JsonValue {
  if (choices(spec)) return JSON.parse(text);
  if (spec.type === "string") return text;
  if (spec.type === "integer" || spec.type === "number") {
    const n = Number(text);
    if (!Number.isFinite(n) || (spec.type === "integer" && !Number.isInteger(n)))
      throw new Error(`${name} must be a valid ${spec.type}.`);
    return n;
  }
  let parsed: JsonValue;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`${name} must be valid JSON.`);
  }
  if (
    (spec.type === "object" && !isJsonObject(parsed)) ||
    (spec.type === "array" && !Array.isArray(parsed))
  )
    throw new Error(`${name} must be a JSON ${spec.type}.`);
  return parsed;
}

export function ActionArgumentsDialog({
  action,
  row,
  onSubmit,
  onClose,
}: {
  action: ModuleAction;
  row?: JsonObject;
  onSubmit: (args: JsonObject) => void;
  onClose: () => void;
}) {
  const prefix = useId();
  const schema = action.argsSchema;
  const fields = properties(schema);
  const required = Array.isArray(schema?.required) ? schema.required : [];
  const rawEditor = needsRawEditor(schema);
  const [raw, setRaw] = useState(() => JSON.stringify(row ?? {}, null, 2));
  const [values, setValues] = useState(() =>
    Object.fromEntries(
      fields.map(([name, spec]) => {
        const preset = Object.hasOwn(spec, "const") ? spec.const : spec.default;
        const value = row && Object.hasOwn(row, name) ? row[name] : preset;
        return [name, draftValue(spec, value)];
      }),
    ),
  );
  const [error, setError] = useState("");

  function submit(event: FormEvent) {
    event.preventDefault();
    try {
      if (rawEditor) {
        const args: unknown = JSON.parse(raw);
        if (!isJsonObject(args)) throw new Error("Arguments must be a JSON object.");
        onSubmit(args);
        return;
      }
      const entries: [string, JsonValue][] = [];
      for (const [name, spec] of fields) {
        const text = values[name] ?? "";
        if (!text && !required.includes(name)) continue;
        if (!text && spec.type !== "string") throw new Error(`Enter a value for ${name}.`);
        entries.push([name, argumentValue(name, spec, text)]);
      }
      onSubmit(Object.fromEntries(entries));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Invalid arguments.");
    }
  }

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{action.label}</DialogTitle>
          <DialogDescription>
            {action.description || "Review the arguments before running this action."}
          </DialogDescription>
        </DialogHeader>
        <form className="space-y-4" onSubmit={submit}>
          {rawEditor && (
            <div className="space-y-1">
              <Label htmlFor={prefix}>Arguments (JSON)</Label>
              <Textarea id={prefix} value={raw} onChange={(e) => setRaw(e.target.value)} />
            </div>
          )}
          {fields.map(([name, spec]) => {
            const id = `${prefix}-${name}`;
            const label = typeof spec.title === "string" ? spec.title : name;
            const options = choices(spec);
            const props = {
              id,
              name,
              required: required.includes(name),
              value: values[name] ?? "",
              onChange: (event: { target: { value: string } }) => {
                const text = event.target.value;
                setValues((previous) => ({ ...previous, [name]: text }));
              },
            };
            return (
              <div key={name} className="space-y-1">
                <Label htmlFor={id}>
                  {label}
                  {props.required ? " *" : ""}
                </Label>
                {options ? (
                  <select
                    {...props}
                    className="h-9 w-full rounded-md border bg-background px-3 text-sm"
                  >
                    <option value="">Select a value</option>
                    {options.map((item) => (
                      <option key={JSON.stringify(item)} value={JSON.stringify(item)}>
                        {typeof item === "string" ? item : JSON.stringify(item)}
                      </option>
                    ))}
                  </select>
                ) : spec.type === "number" || spec.type === "integer" ? (
                  <Input
                    {...props}
                    type="number"
                    step={spec.type === "integer" ? 1 : "any"}
                    min={typeof spec.minimum === "number" ? spec.minimum : undefined}
                    max={typeof spec.maximum === "number" ? spec.maximum : undefined}
                  />
                ) : spec.type === "string" ? (
                  <Input
                    {...props}
                    type={spec.format === "password" ? "password" : "text"}
                    minLength={typeof spec.minLength === "number" ? spec.minLength : undefined}
                    maxLength={typeof spec.maxLength === "number" ? spec.maxLength : undefined}
                  />
                ) : (
                  <Textarea {...props} placeholder="JSON" />
                )}
                {typeof spec.description === "string" && (
                  <p className="text-xs text-muted-foreground">{spec.description}</p>
                )}
              </div>
            );
          })}
          {action.confirm && (
            <p className="rounded-md border p-3 text-sm font-medium">{action.confirm}</p>
          )}
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit">{action.confirm ? "Confirm and run" : "Run action"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
