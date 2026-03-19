"use client";

import Editor, { useMonaco } from "@monaco-editor/react";
import type { editor } from "monaco-editor";
import { useEffect } from "react";
import type { JsonSchema } from "@/lib/stackpanel-config-editor";

interface JsonSchemaEditorProps {
  value: string;
  onChange?: (value: string) => void;
  schema?: JsonSchema | null;
  modelPath: string;
  readOnly?: boolean;
  height?: string;
  onValidate?: (markers: editor.IMarker[]) => void;
}

export function JsonSchemaEditor({
  value,
  onChange,
  schema,
  modelPath,
  readOnly = false,
  height = "500px",
  onValidate,
}: JsonSchemaEditorProps) {
  const monaco = useMonaco();

  useEffect(() => {
    if (!monaco) {
      return;
    }

    const jsonDefaults = (
      monaco.languages as typeof monaco.languages & {
        json?: {
          jsonDefaults?: {
            setDiagnosticsOptions: (options: unknown) => void;
          };
        };
      }
    ).json?.jsonDefaults;

    jsonDefaults?.setDiagnosticsOptions({
      validate: true,
      allowComments: false,
      trailingCommas: "error",
      enableSchemaRequest: false,
      schemas: schema
        ? [
            {
              uri: `${modelPath}.schema.json`,
              fileMatch: [modelPath],
              schema,
            },
          ]
        : [],
    });
  }, [modelPath, monaco, schema]);

  return (
    <Editor
      language="json"
      path={modelPath}
      value={value}
      onChange={(nextValue) => onChange?.(nextValue ?? "")}
      onValidate={onValidate}
      height={height}
      loading={<div className="rounded-md border bg-muted/30 p-4 text-xs text-muted-foreground">Loading editor...</div>}
      options={{
        readOnly,
        minimap: { enabled: false },
        fontSize: 12,
        lineNumbers: "on",
        wordWrap: "on",
        scrollBeyondLastLine: false,
        automaticLayout: true,
        tabSize: 2,
        formatOnPaste: true,
        formatOnType: true,
        quickSuggestions: !readOnly,
        suggestOnTriggerCharacters: !readOnly,
      }}
    />
  );
}
