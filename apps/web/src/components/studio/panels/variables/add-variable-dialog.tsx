"use client";

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
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import {
  AlertTriangle,
  Eye,
  EyeOff,
  Key,
  Loader2,
  Plus,
  Settings,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useVariablesBackend } from "@/lib/use-agent";
import { formatSecretKeyError, getVariableName, resolveGroup } from "./constants";

type VariableMode = "plaintext" | "secret";

interface AddVariableDialogProps {
  onSuccess: () => void;
}

/**
 * Dialog to add a new variable or secret.
 *
 * Two modes via explicit toggle:
 * - plaintext: stored directly in variables.nix as a literal value (vals references also accepted)
 * - secret: encrypted with AGE (vals backend) or stored in AWS SSM (chamber backend)
 *
 * When a vals reference (ref+...) is entered in plaintext mode, it is validated
 * by running `vals eval` before saving.
 */
export function AddVariableDialog({ onSuccess }: AddVariableDialogProps) {
  const { token } = useAgentContext();
  const agentClient = useAgentClient();
  const { data: backendData } = useVariablesBackend();
  const isChamber = backendData?.backend === "chamber";
  const [dialogOpen, setDialogOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [showValue, setShowValue] = useState(false);

  // Form state
  const [mode, setMode] = useState<VariableMode>("plaintext");
  const [varId, setVarId] = useState("");
  const [varValue, setVarValue] = useState("");
  const [varDescription, setVarDescription] = useState("");
  // Validation state for vals references
  const [valsError, setValsError] = useState<string | null>(null);

  const handleOpenChange = (open: boolean) => {
    setDialogOpen(open);
    if (!open) {
      setMode("plaintext");
      setVarId("");
      setVarValue("");
        setVarDescription("");
        setShowValue(false);
        setValsError(null);
      }
    };

  /**
   * Validate a vals reference by running `vals eval` via the agent exec API.
   * Returns null if valid, or an error message string if invalid.
   */
  const validateValsReference = async (ref: string): Promise<string | null> => {
    try {
      const result = await agentClient.exec({
        command: "sh",
        args: ["-c", `printf 'v: %s\\n' "$_VALS_REF" | vals eval`],
        env: [`_VALS_REF=${ref}`],
      });
      if (result.exit_code !== 0) {
        const errMsg = (result.stderr || result.stdout || "").trim();
        return errMsg || "vals could not resolve this reference";
      }
      return null;
    } catch (err) {
      // If exec itself fails (e.g. vals not installed), return the error
      return err instanceof Error
        ? err.message
        : "Failed to validate reference";
    }
  };

  const handleSubmit = async () => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    const trimmedId = varId.trim();
    const trimmedValue = varValue.trim();

    if (!trimmedId) {
      toast.error("Please enter a name");
      return;
    }

    if (!trimmedValue) {
      toast.error("Please enter a value");
      return;
    }

    const normalizedId = trimmedId.startsWith("/")
      ? trimmedId
      : `/${trimmedId}`;
    const isValsRef = trimmedValue.startsWith("ref+");

    setIsSaving(true);
    setValsError(null);
    try {
      const client = agentClient;
      if (token) client.setToken(token);

      // Validate vals references before saving
      if (isValsRef && mode === "plaintext") {
        const error = await validateValsReference(trimmedValue);
        if (error) {
          setValsError(error);
          setIsSaving(false);
          return;
        }
      }

      const { idPrefix } = resolveGroup("shared", mode);
      const envKey = getVariableName(normalizedId);

      // Validate key follows Chamber naming rules
      const keyError = formatSecretKeyError(envKey);
      if (keyError) {
        toast.error(keyError);
        setIsSaving(false);
        return;
      }

      // Build the full variable ID with the group prefix
      const fullId = `${idPrefix}${envKey}`;

      if (mode === "secret") {
        await client.writeAgenixSecret({
          id: fullId,
          key: envKey,
          value: trimmedValue,
          description: varDescription.trim() || undefined,
        });

        // Create a variable entry with empty value -- the SOPS file is the source of truth
        const variablesClient = client.nix.mapEntity<{ value: string }>("variables");
        const newVariable = {
          value: "",
        };
        await variablesClient.set(fullId, newVariable);

        toast.success(`Created secret "${fullId}"`);
      } else {
        // Plaintext variable (either "shared" → /var/ or a group like /dev/)
        const variablesClient = client.nix.mapEntity<{ value: string }>("variables");

        const existing = await variablesClient.get(fullId);
        if (existing) {
          toast.error(`Variable "${fullId}" already exists`);
          setIsSaving(false);
          return;
        }

        const newVariable = {
          value: trimmedValue,
        };

        await variablesClient.set(fullId, newVariable);
        toast.success(`Created variable "${fullId}"`);
      }

      handleOpenChange(false);
      onSuccess();
    } catch (err) {
      console.error("[AddVariable] Error:", err);
      toast.error(
        err instanceof Error ? err.message : "Failed to create variable",
      );
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
      <button
        type="button"
        onClick={() => setDialogOpen(true)}
        disabled={!token}
        className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-dashed border-border bg-background text-xs hover:border-blue-500/50 hover:bg-blue-500/5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <Plus className="h-3 w-3 text-blue-500" />
        <span className="font-medium">Add Variable</span>
      </button>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Add Variable</DialogTitle>
          <DialogDescription>
            Create a new variable or encrypted secret.
          </DialogDescription>
        </DialogHeader>
        <div className="py-4 space-y-4">
          {/* Mode toggle */}
          <div className="space-y-2">
            <Label>Type</Label>
            <ToggleGroup
              type="single"
              variant="outline"
              value={mode}
              onValueChange={(value) => {
                if (value) {
                  setMode(value as VariableMode);
                  setValsError(null);
                }
              }}
              className="justify-start"
            >
              <ToggleGroupItem
                value="plaintext"
                size="sm"
                className="gap-1.5 text-xs px-3"
              >
                <Settings className="h-3.5 w-3.5" />
                Plaintext
              </ToggleGroupItem>
              <ToggleGroupItem
                value="secret"
                size="sm"
                className="gap-1.5 text-xs px-3"
              >
                <Key className="h-3.5 w-3.5" />
                Secret
              </ToggleGroupItem>
            </ToggleGroup>
            <p className="text-xs text-muted-foreground">
              {mode === "plaintext" &&
                "Stored as a literal value. Vals references (ref+...) are also accepted."}
              {mode === "secret" &&
                (isChamber
                  ? "Stored in AWS SSM Parameter Store. Encryption is handled by AWS KMS."
                  : "Stored in its own SOPS file under .stack/secrets/vars/. Environment links determine which tagged recipients can decrypt it.")}
            </p>
          </div>

          {/* Variable name */}
          <div className="space-y-2">
            <Label htmlFor="var-id">Name *</Label>
            <Input
              id="var-id"
              value={varId}
              onChange={(e) => setVarId(e.target.value)}
              placeholder={
                mode === "secret"
                  ? "postgres-url-production"
                  : "some-api-hostname"
              }
              className="font-mono"
            />
            <p className="text-xs text-muted-foreground">
              Unique identifier for this variable. Environment mapping is
              configured separately.
            </p>
          </div>

          {/* Value */}
          <div className="space-y-2">
            <Label htmlFor="var-value">
              {mode === "secret" ? "Secret Value *" : "Value *"}
            </Label>
            <div className="relative">
              <Textarea
                id="var-value"
                value={varValue}
                onChange={(e) => {
                  setVarValue(e.target.value);
                  if (valsError) setValsError(null);
                }}
                placeholder={
                  mode === "secret"
                    ? isChamber
                      ? "Enter the secret value (encrypted via AWS KMS)"
                      : "Enter the secret value (will be encrypted with AGE)"
                    : "Literal value or vals reference (ref+...)"
                }
                className={`font-mono min-h-[80px] ${mode === "secret" ? "pr-10" : ""}`}
                style={
                  mode === "secret" && !showValue
                    ? ({ WebkitTextSecurity: "disc" } as React.CSSProperties)
                    : undefined
                }
              />
              {mode === "secret" && (
                <button
                  type="button"
                  onClick={() => setShowValue(!showValue)}
                  className="absolute right-2 top-2 text-muted-foreground hover:text-foreground"
                >
                  {showValue ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              )}
            </div>

            {/* Vals reference validation error */}
            {valsError && (
              <div className="flex gap-2 rounded-md border border-destructive/50 bg-destructive/10 p-3">
                <AlertTriangle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
                <div className="space-y-1 min-w-0">
                  <p className="text-sm font-medium text-destructive">
                    Could not resolve vals reference
                  </p>
                  <pre className="text-xs text-destructive/80 whitespace-pre-wrap break-all">
                    {valsError}
                  </pre>
                </div>
              </div>
            )}
          </div>

          {/* Description (secrets only) */}
          {mode === "secret" && (
            <div className="space-y-2">
              <Label htmlFor="var-description">Description (optional)</Label>
              <Input
                id="var-description"
                value={varDescription}
                onChange={(e) => setVarDescription(e.target.value)}
                placeholder="What is this secret used for?"
              />
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={isSaving || !varId.trim() || !varValue.trim()}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
          >
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {mode === "secret" ? "Add Secret" : "Add Variable"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
