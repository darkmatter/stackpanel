import { Button } from "@ui/button";
import { useState } from "react";
import { useRebuildShell } from "@/lib/use-agent";
import { AdoptionPreviewDialog } from "./adoption-preview-dialog";
import { useDisableModule } from "./use-modules";

export function ModuleEnableControl({
  moduleId,
  enabled,
  onChanged,
}: {
  moduleId: string;
  enabled: boolean;
  onChanged: (message: string) => void;
}) {
  const [review, setReview] = useState(false);
  const disable = useDisableModule(moduleId);
  return (
    <div className="space-y-2">
      {enabled ? (
        <Button
          variant="outline"
          title={disable.unavailable}
          disabled={disable.isPending || !!disable.unavailable}
          onClick={() =>
            disable.mutate(undefined, {
              onSuccess: ({ message }) => onChanged(message || `Disabled ${moduleId}.`),
            })
          }
        >
          {disable.isPending ? "Disabling…" : "Disable"}
        </Button>
      ) : (
        <Button onClick={() => setReview(true)}>Enable</Button>
      )}
      {review && (
        <AdoptionPreviewDialog
          moduleId={moduleId}
          onClose={() => setReview(false)}
          onEnabled={onChanged}
        />
      )}
      {disable.error && (
        <p role="alert" className="text-sm text-destructive">
          Disable failed: {disable.error.message}
        </p>
      )}
    </div>
  );
}

export function ShellRebuildPrompt({ message }: { message: string }) {
  const { rebuild, isRebuilding, output } = useRebuildShell();
  const [result, setResult] = useState<{ success: boolean; error?: string } | null>(null);
  async function rebuildShell() {
    setResult(null);
    try {
      const response = await rebuild("devshell");
      setResult(
        response.success
          ? { success: true }
          : {
              success: false,
              error:
                response.error ??
                (response.exitCode === undefined
                  ? "The shell rebuild ended without a completion event."
                  : `Shell rebuild exited with code ${response.exitCode}.`),
            },
      );
    } catch (error) {
      setResult({
        success: false,
        error: error instanceof Error ? error.message : "Could not rebuild the shell.",
      });
    }
  }
  return (
    <aside className="space-y-2 rounded-md border p-3 text-sm" aria-label="Shell rebuild">
      <p role="status">{message}</p>
      {result?.success ? (
        <p>Dev shell rebuilt.</p>
      ) : (
        <>
          <p className="text-muted-foreground">
            Rebuild the dev shell to load the new configuration.
          </p>
          <Button
            variant="outline"
            size="sm"
            disabled={isRebuilding}
            onClick={() => void rebuildShell()}
          >
            {isRebuilding ? "Rebuilding…" : "Rebuild shell"}
          </Button>
        </>
      )}
      {result?.error && (
        <p role="alert" className="text-destructive">
          {result.error}
        </p>
      )}
      {!!output.length && (
        <details>
          <summary>Shell rebuild output</summary>
          <pre className="max-h-48 overflow-auto whitespace-pre-wrap">{output.join("\n")}</pre>
        </details>
      )}
    </aside>
  );
}
