"use client";

import { useState, useCallback } from "react";
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
import type { AppEntity } from "@/lib/types";

import {
  AppFormFields,
  type AppForm,
  type AppFormValues,
  parsePortValue,
} from "./app-form-fields";

interface AddAppDialogProps {
  onSuccess: () => void;
}

export function AddAppDialog({ onSuccess }: AddAppDialogProps) {
  const { token } = useAgentContext();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [formRef, setFormRef] = useState<AppForm | null>(null);
  const [isFormValid, setIsFormValid] = useState(false);

  const handleFormReady = useCallback((form: AppForm) => {
    setFormRef(form);
  }, []);

  const handleValuesChange = useCallback((values: AppFormValues) => {
    const hasId = values.id?.trim().length > 0;
    const hasPath = values.path?.trim().length > 0;
    setIsFormValid(hasId && hasPath);
  }, []);

  const handleOpenChange = (open: boolean) => {
    setDialogOpen(open);
    if (!open) {
      // Reset form and validity when closing
      formRef?.reset();
      setIsFormValid(false);
    }
  };

  const handleSubmit = async () => {
    if (!formRef || !token) {
      toast.error("Not connected to agent");
      return;
    }

    // Trigger validation
    const isValid = await formRef.trigger();
    if (!isValid) return;

    const values = formRef.getValues();

    if (!values.id.trim()) {
      toast.error("Please enter an app ID");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const appsClient = client.mapEntity<AppEntity>("apps");

      const exists = await appsClient.has(values.id);
      if (exists) {
        toast.error(`App "${values.id}" already exists`);
        setIsSaving(false);
        return;
      }

      const newApp: AppEntity = {
        id: values.id,
        name: values.name || values.id,
        description: values.description || undefined,
        path: values.path || `apps/${values.id}`,
        type: values.type || "bun",
        port: parsePortValue(values.port),
        domain: values.domain || undefined,
        tasks: {},
        variables: {},
      };

      await appsClient.set(values.id, newApp);
      toast.success(
        `Created app "${values.id}". You can now configure tasks and variables.`,
      );
      handleOpenChange(false);
      onSuccess();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to create app");
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
      <Button
        className="gap-2"
        onClick={() => setDialogOpen(true)}
        disabled={!token}
      >
        <Plus className="h-4 w-4" />
        Add App
      </Button>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Add New App</DialogTitle>
          <DialogDescription>
            Create a new app. You can configure tasks and variables after
            creation.
          </DialogDescription>
        </DialogHeader>
        <div className="py-4">
          <AppFormFields
            showIdField
            hideTasksAndVariables
            onFormReady={handleFormReady}
            onValuesChange={handleValuesChange}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={!isFormValid || isSaving}>
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Add App
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
