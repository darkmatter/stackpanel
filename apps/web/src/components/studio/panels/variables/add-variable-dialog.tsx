"use client";

import { useState } from "react";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";
import type { Variable } from "@/lib/types";

import { VariableFormFields } from "./variable-form-fields";
import { type VariableFormState, defaultFormState } from "./types";

interface AddVariableDialogProps {
  onSuccess: () => void;
}

export function AddVariableDialog({ onSuccess }: AddVariableDialogProps) {
  const { token } = useAgentContext();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [variableId, setVariableId] = useState("");
  const [formState, setFormState] =
    useState<VariableFormState>(defaultFormState);
  const [isSaving, setIsSaving] = useState(false);

  const handleFormChange = (updates: Partial<VariableFormState>) => {
    setFormState((prev) => ({ ...prev, ...updates }));
  };

  const handleOpenChange = (open: boolean) => {
    setDialogOpen(open);
    if (!open) {
      // Reset form when closing
      setVariableId("");
      setFormState(defaultFormState);
    }
  };

  const handleSubmit = async () => {
    if (!variableId.trim() || !token) {
      toast.error(
        !token ? "Not connected to agent" : "Please enter a variable name",
      );
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const variablesClient = client.mapEntity<Variable>("variables");

      const exists = await variablesClient.has(variableId);
      if (exists) {
        toast.error(`Variable "${variableId}" already exists`);
        setIsSaving(false);
        return;
      }

      const newVariable: Variable = {
        name: formState.name || variableId,
        description: formState.description || "",
        type: formState.type,
        required: formState.required || undefined,
        sensitive: formState.sensitive || undefined,
        default: formState.default || undefined,
        options: formState.options
          ? formState.options.split(",").map((s) => s.trim())
          : undefined,
        service: formState.type === "service" ? formState.service : undefined,
      };

      await variablesClient.set(variableId, newVariable);
      toast.success(`Created variable "${variableId}"`);
      handleOpenChange(false);
      onSuccess();
    } catch (err) {
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
        onClick={() => setDialogOpen(true)}
        disabled={!token}
        className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-dashed border-border bg-background text-xs hover:border-blue-500/50 hover:bg-blue-500/5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <Plus className="h-3 w-3 text-blue-500" />
        <span className="font-medium">Add Variable</span>
      </button>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Add New Variable</DialogTitle>
          <DialogDescription>
            Create a new environment variable that can be linked to apps.
          </DialogDescription>
        </DialogHeader>
        <div className="py-4">
          <VariableFormFields
            formState={formState}
            onFormChange={handleFormChange}
            showIdField
            variableId={variableId}
            onVariableIdChange={setVariableId}
            idPrefix="new-variable"
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={isSaving || !variableId.trim()}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
          >
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Add Variable
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
