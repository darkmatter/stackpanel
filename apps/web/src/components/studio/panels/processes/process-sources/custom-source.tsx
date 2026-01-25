"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Checkbox } from "@ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@ui/tooltip";
import { Folder, Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import type { ProcessSource, ProcessStatus } from "../types";
import { ProcessStatusIndicator } from "../process-status-indicator";

interface CustomSourceProps {
  sources: ProcessSource[];
  statuses: Record<string, ProcessStatus>;
  onToggle: (id: string, enabled: boolean) => void;
  onAdd: (source: Omit<ProcessSource, "id" | "type">) => void;
  onRemove: (id: string) => void;
  onUpdate: (id: string, updates: Partial<ProcessSource>) => void;
}

export function CustomSource({
  sources,
  statuses,
  onToggle,
  onAdd,
  onRemove,
}: CustomSourceProps) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [formData, setFormData] = useState({
    name: "",
    command: "",
    workingDir: "",
    namespace: "",
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.name || !formData.command) return;

    onAdd({
      name: formData.name,
      command: formData.command,
      workingDir: formData.workingDir || undefined,
      namespace: formData.namespace || "custom",
      enabled: true,
      autoStart: true,
      useEntrypoint: false,
    });

    setFormData({ name: "", command: "", workingDir: "", namespace: "" });
    setDialogOpen(false);
  };

  return (
    <div className="space-y-4">
      {sources.length === 0 ? (
        <div className="py-8 text-center">
          <Plus className="mx-auto h-12 w-12 text-muted-foreground/50" />
          <p className="mt-2 text-muted-foreground">
            No custom processes defined
          </p>
          <p className="mt-1 text-sm text-muted-foreground/70">
            Add custom processes that aren&apos;t apps, scripts, or tasks
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {sources.map((source) => {
            const status = statuses[source.name];
            return (
              <div
                key={source.id}
                className="flex items-center gap-3 rounded-lg border p-3 hover:bg-secondary/30"
              >
                <Checkbox
                  checked={source.enabled}
                  onCheckedChange={(checked) => onToggle(source.id, !!checked)}
                />
                
                <ProcessStatusIndicator status={status} />
                
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium truncate">{source.name}</span>
                    {source.namespace && (
                      <Badge variant="outline" className="text-xs">
                        {source.namespace}
                      </Badge>
                    )}
                  </div>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <code className="text-xs text-muted-foreground truncate block">
                        {source.command}
                      </code>
                    </TooltipTrigger>
                    <TooltipContent side="bottom" className="max-w-md">
                      <code className="text-xs">{source.command}</code>
                    </TooltipContent>
                  </Tooltip>
                </div>
                
                {source.workingDir && (
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <div className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Folder className="h-3 w-3" />
                        <span className="truncate max-w-[100px]">{source.workingDir}</span>
                      </div>
                    </TooltipTrigger>
                    <TooltipContent>
                      <code>{source.workingDir}</code>
                    </TooltipContent>
                  </Tooltip>
                )}
                
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-muted-foreground hover:text-destructive"
                  onClick={() => onRemove(source.id)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            );
          })}
        </div>
      )}

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogTrigger asChild>
          <Button variant="outline" className="w-full">
            <Plus className="mr-2 h-4 w-4" />
            Add Custom Process
          </Button>
        </DialogTrigger>
        <DialogContent>
          <form onSubmit={handleSubmit}>
            <DialogHeader>
              <DialogTitle>Add Custom Process</DialogTitle>
              <DialogDescription>
                Define a custom process to run with process-compose.
              </DialogDescription>
            </DialogHeader>
            
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="name">Process Name</Label>
                <Input
                  id="name"
                  placeholder="my-process"
                  value={formData.name}
                  onChange={(e) => setFormData((f) => ({ ...f, name: e.target.value }))}
                  required
                />
              </div>
              
              <div className="grid gap-2">
                <Label htmlFor="command">Command</Label>
                <Input
                  id="command"
                  placeholder="npm run watch"
                  value={formData.command}
                  onChange={(e) => setFormData((f) => ({ ...f, command: e.target.value }))}
                  required
                />
              </div>
              
              <div className="grid gap-2">
                <Label htmlFor="workingDir">Working Directory (optional)</Label>
                <Input
                  id="workingDir"
                  placeholder="apps/my-app"
                  value={formData.workingDir}
                  onChange={(e) => setFormData((f) => ({ ...f, workingDir: e.target.value }))}
                />
              </div>
              
              <div className="grid gap-2">
                <Label htmlFor="namespace">Namespace (optional)</Label>
                <Input
                  id="namespace"
                  placeholder="custom"
                  value={formData.namespace}
                  onChange={(e) => setFormData((f) => ({ ...f, namespace: e.target.value }))}
                />
              </div>
            </div>
            
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={!formData.name || !formData.command}>
                Add Process
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
