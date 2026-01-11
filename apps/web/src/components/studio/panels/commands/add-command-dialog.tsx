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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";
import type { Command } from "@/lib/types";

interface AddCommandDialogProps {
  existingCommands: Record<string, Command> | undefined;
  onSuccess: () => void;
}

interface FormState {
  package: string;
  bin: string;
  args: string;
  cwd: string;
  configPath: string;
  configArg: string;
}

const defaultFormState: FormState = {
  package: "",
  bin: "",
  args: "",
  cwd: "",
  configPath: "",
  configArg: "",
};

export function AddCommandDialog({
  existingCommands,
  onSuccess,
}: AddCommandDialogProps) {
  const { token } = useAgentContext();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [commandId, setCommandId] = useState("");
  const [formState, setFormState] = useState<FormState>(defaultFormState);
  const [isSaving, setIsSaving] = useState(false);

  const handleFormChange = (field: keyof FormState, value: string) => {
    setFormState((prev) => ({ ...prev, [field]: value }));
  };

  const handleOpenChange = (open: boolean) => {
    setDialogOpen(open);
    if (!open) {
      // Reset form when closing
      setCommandId("");
      setFormState(defaultFormState);
    }
  };

  const handleSubmit = async () => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    if (!commandId.trim()) {
      toast.error("Command ID is required");
      return;
    }

    if (!formState.package.trim()) {
      toast.error("Package name is required");
      return;
    }

    if (existingCommands && existingCommands[commandId]) {
      toast.error("A command with this ID already exists");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const allCommands = { ...existingCommands };

      const newCommand: Command = {
        package: formState.package,
        bin: formState.bin || undefined,
        args: formState.args ? formState.args.split(/\s+/).filter(Boolean) : [],
        cwd: formState.cwd || undefined,
        config_path: formState.configPath || undefined,
        config_arg: formState.configArg
          ? formState.configArg.split(/\s+/).filter(Boolean)
          : [],
        env: {},
      };

      allCommands[commandId] = newCommand;

      await client.mapEntity<Command>("commands").setAll(allCommands);
      toast.success(`Command "${commandId}" added`);
      handleOpenChange(false);
      onSuccess();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to add command");
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
      <Button
        onClick={() => setDialogOpen(true)}
        className="bg-accent text-accent-foreground hover:bg-accent/90"
        disabled={!token}
      >
        <Plus className="mr-2 h-4 w-4" />
        Add Command
      </Button>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Add New Command</DialogTitle>
          <DialogDescription>
            Configure a new tool command that can be used in your development
            workflow.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-4">
          {/* Command ID */}
          <div className="space-y-2">
            <Label htmlFor="command-id">Command ID</Label>
            <Input
              id="command-id"
              value={commandId}
              onChange={(e) => setCommandId(e.target.value)}
              placeholder="e.g., eslint, prettier, vitest"
            />
            <p className="text-xs text-muted-foreground">
              Unique identifier for this command
            </p>
          </div>

          {/* Package */}
          <div className="space-y-2">
            <Label htmlFor="package">Package</Label>
            <Input
              id="package"
              value={formState.package}
              onChange={(e) => handleFormChange("package", e.target.value)}
              placeholder="e.g., eslint, nodejs, go"
            />
            <p className="text-xs text-muted-foreground">
              Nix package that provides the binary
            </p>
          </div>

          {/* Binary */}
          <div className="space-y-2">
            <Label htmlFor="bin">Binary (optional)</Label>
            <Input
              id="bin"
              value={formState.bin}
              onChange={(e) => handleFormChange("bin", e.target.value)}
              placeholder="Defaults to package name"
            />
            <p className="text-xs text-muted-foreground">
              Binary name if different from package
            </p>
          </div>

          {/* Arguments */}
          <div className="space-y-2">
            <Label htmlFor="args">Arguments</Label>
            <Input
              id="args"
              value={formState.args}
              onChange={(e) => handleFormChange("args", e.target.value)}
              placeholder="e.g., --fix . or run --coverage"
            />
            <p className="text-xs text-muted-foreground">
              Space-separated arguments to pass to the command
            </p>
          </div>

          {/* Working Directory */}
          <div className="space-y-2">
            <Label htmlFor="cwd">Working Directory (optional)</Label>
            <Input
              id="cwd"
              value={formState.cwd}
              onChange={(e) => handleFormChange("cwd", e.target.value)}
              placeholder="e.g., apps/server or packages/ui"
            />
            <p className="text-xs text-muted-foreground">
              Directory to run the command in
            </p>
          </div>

          {/* Config Path */}
          <div className="space-y-2">
            <Label htmlFor="configPath">Config File (optional)</Label>
            <Input
              id="configPath"
              value={formState.configPath}
              onChange={(e) => handleFormChange("configPath", e.target.value)}
              placeholder="e.g., eslint.config.js or .prettierrc"
            />
          </div>

          {/* Config Arg */}
          <div className="space-y-2">
            <Label htmlFor="configArg">Config Argument (optional)</Label>
            <Input
              id="configArg"
              value={formState.configArg}
              onChange={(e) => handleFormChange("configArg", e.target.value)}
              placeholder="e.g., --config or -c"
            />
            <p className="text-xs text-muted-foreground">
              Argument prefix for config file (e.g., --config)
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={
              isSaving || !commandId.trim() || !formState.package.trim()
            }
            className="bg-accent text-accent-foreground hover:bg-accent/90"
          >
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Add Command
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
