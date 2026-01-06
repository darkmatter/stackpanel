"use client";

import { useState, useMemo } from "react";
import {
  ChevronDown,
  ChevronRight,
  Loader2,
  Pencil,
  Plus,
  Save,
  Search,
  Terminal,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import {
  useCommands,
  useCommandsByCategory,
  useAppsWithCommand,
} from "@/lib/use-nix-config";
import type { Command } from "@/lib/types";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";

const COMMAND_CATEGORIES = [
  { value: "development", label: "Development", color: "bg-blue-500/20 text-blue-400" },
  { value: "build", label: "Build", color: "bg-orange-500/20 text-orange-400" },
  { value: "testing", label: "Testing", color: "bg-green-500/20 text-green-400" },
  { value: "quality", label: "Quality", color: "bg-purple-500/20 text-purple-400" },
  { value: "database", label: "Database", color: "bg-cyan-500/20 text-cyan-400" },
  { value: "deployment", label: "Deployment", color: "bg-red-500/20 text-red-400" },
  { value: "codegen", label: "Code Generation", color: "bg-yellow-500/20 text-yellow-400" },
  { value: "production", label: "Production", color: "bg-pink-500/20 text-pink-400" },
  { value: "other", label: "Other", color: "bg-gray-500/20 text-gray-400" },
];

function getCategoryColor(category: string): string {
  return COMMAND_CATEGORIES.find((c) => c.value === category)?.color ?? "bg-gray-500/20 text-gray-400";
}

function getCategoryLabel(category: string): string {
  return COMMAND_CATEGORIES.find((c) => c.value === category)?.label ?? category;
}

interface CommandFormState {
  name: string;
  description: string;
  category: string;
  command?: string;
}

const defaultFormState: CommandFormState = {
  name: "",
  description: "",
  category: "development",
  command: "",
};

function CommandUsageInfo({ commandId }: { commandId: string }) {
  const { data: apps, isLoading } = useAppsWithCommand(commandId);

  if (isLoading) {
    return <span className="text-muted-foreground text-xs">Loading...</span>;
  }

  if (!apps || apps.length === 0) {
    return <span className="text-muted-foreground text-xs">Not used by any app</span>;
  }

  return (
    <div className="flex flex-wrap gap-1">
      {apps.map((app) => (
        <Badge key={app.id} variant="outline" className="text-xs">
          {app.name}
        </Badge>
      ))}
    </div>
  );
}

export function CommandsPanel() {
  const { token } = useAgentContext();
  const { data: commands, isLoading, error, refetch } = useCommands();
  const { data: groupedCommands } = useCommandsByCategory();

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set(["development", "testing"]));
  const [editingCommand, setEditingCommand] = useState<string | null>(null);
  const [formState, setFormState] = useState<CommandFormState>(defaultFormState);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newCommandId, setNewCommandId] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState<string | null>(null);

  // Filter commands based on search and category
  const filteredCommands = useMemo(() => {
    if (!commands) return {};

    return Object.entries(commands).reduce(
      (acc, [id, cmd]) => {
        const matchesSearch =
          !searchQuery ||
          cmd.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          cmd.description.toLowerCase().includes(searchQuery.toLowerCase());

        const matchesCategory = !selectedCategory || cmd.category === selectedCategory;

        if (matchesSearch && matchesCategory) {
          acc[id] = cmd;
        }
        return acc;
      },
      {} as Record<string, Command>,
    );
  }, [commands, searchQuery, selectedCategory]);

  // Group filtered commands by category
  const filteredGrouped = useMemo(() => {
    const result: Record<string, Array<Command & { id: string }>> = {};

    for (const [id, cmd] of Object.entries(filteredCommands)) {
      const category = cmd.category ?? "other";
      if (!result[category]) {
        result[category] = [];
      }
      result[category].push({ ...cmd, id });
    }

    return result;
  }, [filteredCommands]);

  const toggleCategory = (category: string) => {
    setExpandedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) {
        next.delete(category);
      } else {
        next.add(category);
      }
      return next;
    });
  };

  const handleEdit = (commandId: string, command: Command) => {
    setEditingCommand(commandId);
    setFormState({
      name: command.name,
      description: command.description,
      category: command.category,
      command: command.command ?? "",
    });
  };

  const handleSave = async (commandId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const allCommands = { ...commands };
      allCommands[commandId] = {
        name: formState.name,
        description: formState.description,
        category: formState.category,
        ...(formState.command ? { command: formState.command } : {}),
      };

      await client.mapEntity<Command>("commands").setAll(allCommands);
      toast.success("Command updated");
      setEditingCommand(null);
      setFormState(defaultFormState);
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save command");
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setEditingCommand(null);
    setFormState(defaultFormState);
  };

  const handleDelete = async (commandId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    setIsDeleting(commandId);
    try {
      const client = new NixClient({ token });
      const allCommands = { ...commands };
      delete allCommands[commandId];

      await client.mapEntity<Command>("commands").setAll(allCommands);
      toast.success("Command deleted");
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete command");
    } finally {
      setIsDeleting(null);
    }
  };

  const handleAddCommand = async () => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    if (!newCommandId.trim()) {
      toast.error("Command ID is required");
      return;
    }

    if (commands && commands[newCommandId]) {
      toast.error("A command with this ID already exists");
      return;
    }

    setIsSaving(true);
    try {
      const client = new NixClient({ token });
      const allCommands = { ...commands };
      allCommands[newCommandId] = {
        name: formState.name || newCommandId,
        description: formState.description,
        category: formState.category,
        ...(formState.command ? { command: formState.command } : {}),
      };

      await client.mapEntity<Command>("commands").setAll(allCommands);
      toast.success("Command added");
      setDialogOpen(false);
      setNewCommandId("");
      setFormState(defaultFormState);
      refetch();

      // Expand the category of the new command
      setExpandedCategories((prev) => new Set([...prev, formState.category]));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to add command");
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="border-destructive/50">
        <CardContent className="py-6">
          <p className="text-center text-destructive">
            Failed to load commands: {error.message}
          </p>
        </CardContent>
      </Card>
    );
  }

  const totalCommands = commands ? Object.keys(commands).length : 0;
  const categories = Object.keys(filteredGrouped).sort();

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">Commands</h2>
          <p className="text-muted-foreground text-sm">
            {totalCommands} command{totalCommands !== 1 ? "s" : ""} defined
          </p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <Button
            onClick={() => setDialogOpen(true)}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
            disabled={!token}
          >
            <Plus className="mr-2 h-4 w-4" />
            Add Command
          </Button>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add New Command</DialogTitle>
              <DialogDescription>
                Create a new command that can be linked to apps.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="command-id">Command ID</Label>
                <Input
                  id="command-id"
                  placeholder="e.g., build, test:unit, deploy:prod"
                  value={newCommandId}
                  onChange={(e) => setNewCommandId(e.target.value)}
                  className="font-mono"
                />
                <p className="text-muted-foreground text-xs">
                  Unique identifier used to reference this command
                </p>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="command-name">Display Name</Label>
                <Input
                  id="command-name"
                  placeholder="e.g., Build, Unit Tests, Deploy to Production"
                  value={formState.name}
                  onChange={(e) => setFormState((s) => ({ ...s, name: e.target.value }))}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="command-description">Description</Label>
                <Textarea
                  id="command-description"
                  placeholder="What does this command do?"
                  value={formState.description}
                  onChange={(e) => setFormState((s) => ({ ...s, description: e.target.value }))}
                  rows={2}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="command-category">Category</Label>
                <Select
                  value={formState.category}
                  onValueChange={(value) => setFormState((s) => ({ ...s, category: value }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {COMMAND_CATEGORIES.map((cat) => (
                      <SelectItem key={cat.value} value={cat.value}>
                        {cat.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="command-cmd">Command (optional)</Label>
                <Input
                  id="command-cmd"
                  placeholder="e.g., npm run build"
                  value={formState.command}
                  onChange={(e) => setFormState((s) => ({ ...s, command: e.target.value }))}
                  className="font-mono"
                />
                <p className="text-muted-foreground text-xs">
                  Default command to run. Apps can override this.
                </p>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button
                onClick={handleAddCommand}
                disabled={isSaving || !newCommandId.trim()}
                className="bg-accent text-accent-foreground hover:bg-accent/90"
              >
                {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Add Command
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {/* Search and Filter */}
      <div className="flex gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search commands..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>
        <Select
          value={selectedCategory ?? "all"}
          onValueChange={(value) => setSelectedCategory(value === "all" ? null : value)}
        >
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder="All categories" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All categories</SelectItem>
            {COMMAND_CATEGORIES.map((cat) => (
              <SelectItem key={cat.value} value={cat.value}>
                {cat.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Commands by Category */}
      <div className="space-y-2">
        {categories.length === 0 ? (
          <Card>
            <CardContent className="py-8 text-center">
              <Terminal className="mx-auto h-12 w-12 text-muted-foreground/50" />
              <p className="mt-2 text-muted-foreground">
                {searchQuery || selectedCategory
                  ? "No commands match your search"
                  : "No commands defined yet"}
              </p>
            </CardContent>
          </Card>
        ) : (
          categories.map((category) => {
            const categoryCommands = filteredGrouped[category] ?? [];
            const isExpanded = expandedCategories.has(category);

            return (
              <Card key={category}>
                <CardHeader
                  className="cursor-pointer py-3"
                  onClick={() => toggleCategory(category)}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      {isExpanded ? (
                        <ChevronDown className="h-4 w-4 text-muted-foreground" />
                      ) : (
                        <ChevronRight className="h-4 w-4 text-muted-foreground" />
                      )}
                      <Badge className={getCategoryColor(category)}>
                        {getCategoryLabel(category)}
                      </Badge>
                      <span className="text-muted-foreground text-sm">
                        {categoryCommands.length} command{categoryCommands.length !== 1 ? "s" : ""}
                      </span>
                    </div>
                  </div>
                </CardHeader>

                {isExpanded && (
                  <CardContent className="pt-0">
                    <div className="space-y-2">
                      {categoryCommands.map((cmd) => {
                        const isEditing = editingCommand === cmd.id;

                        return (
                          <div
                            key={cmd.id}
                            className="rounded-lg border border-border bg-secondary/30 p-3"
                          >
                            {isEditing ? (
                              <div className="space-y-3">
                                <div className="grid gap-2">
                                  <Label>Name</Label>
                                  <Input
                                    value={formState.name}
                                    onChange={(e) =>
                                      setFormState((s) => ({ ...s, name: e.target.value }))
                                    }
                                  />
                                </div>
                                <div className="grid gap-2">
                                  <Label>Description</Label>
                                  <Textarea
                                    value={formState.description}
                                    onChange={(e) =>
                                      setFormState((s) => ({ ...s, description: e.target.value }))
                                    }
                                    rows={2}
                                  />
                                </div>
                                <div className="grid gap-2">
                                  <Label>Category</Label>
                                  <Select
                                    value={formState.category}
                                    onValueChange={(value) =>
                                      setFormState((s) => ({ ...s, category: value }))
                                    }
                                  >
                                    <SelectTrigger>
                                      <SelectValue />
                                    </SelectTrigger>
                                    <SelectContent>
                                      {COMMAND_CATEGORIES.map((cat) => (
                                        <SelectItem key={cat.value} value={cat.value}>
                                          {cat.label}
                                        </SelectItem>
                                      ))}
                                    </SelectContent>
                                  </Select>
                                </div>
                                <div className="grid gap-2">
                                  <Label>Command (optional)</Label>
                                  <Input
                                    value={formState.command}
                                    onChange={(e) =>
                                      setFormState((s) => ({ ...s, command: e.target.value }))
                                    }
                                    className="font-mono"
                                    placeholder="e.g., npm run build"
                                  />
                                </div>
                                <div className="flex justify-end gap-2">
                                  <Button
                                    size="sm"
                                    variant="outline"
                                    onClick={handleCancel}
                                  >
                                    <X className="mr-1 h-3 w-3" />
                                    Cancel
                                  </Button>
                                  <Button
                                    size="sm"
                                    onClick={() => handleSave(cmd.id)}
                                    disabled={isSaving}
                                    className="bg-accent text-accent-foreground hover:bg-accent/90"
                                  >
                                    {isSaving ? (
                                      <Loader2 className="mr-1 h-3 w-3 animate-spin" />
                                    ) : (
                                      <Save className="mr-1 h-3 w-3" />
                                    )}
                                    Save
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <div className="flex items-start justify-between gap-4">
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center gap-2">
                                    <code className="rounded bg-background px-1.5 py-0.5 font-mono text-sm">
                                      {cmd.id}
                                    </code>
                                    <span className="text-muted-foreground">→</span>
                                    <span className="font-medium">{cmd.name}</span>
                                  </div>
                                  <p className="mt-1 text-muted-foreground text-sm">
                                    {cmd.description}
                                  </p>
                                  {cmd.command && (
                                    <code className="mt-1 block rounded bg-background px-2 py-1 font-mono text-muted-foreground text-xs">
                                      $ {cmd.command}
                                    </code>
                                  )}
                                  <div className="mt-2">
                                    <span className="text-muted-foreground text-xs">Used by: </span>
                                    <CommandUsageInfo commandId={cmd.id} />
                                  </div>
                                </div>
                                <div className="flex gap-1">
                                  <Button
                                    size="icon"
                                    variant="ghost"
                                    className="h-8 w-8"
                                    onClick={() => handleEdit(cmd.id, cmd)}
                                    disabled={!token}
                                  >
                                    <Pencil className="h-4 w-4" />
                                  </Button>
                                  <Button
                                    size="icon"
                                    variant="ghost"
                                    className="h-8 w-8 text-destructive hover:text-destructive"
                                    onClick={() => handleDelete(cmd.id)}
                                    disabled={!token || isDeleting === cmd.id}
                                  >
                                    {isDeleting === cmd.id ? (
                                      <Loader2 className="h-4 w-4 animate-spin" />
                                    ) : (
                                      <Trash2 className="h-4 w-4" />
                                    )}
                                  </Button>
                                </div>
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </CardContent>
                )}
              </Card>
            );
          })
        )}
      </div>
    </div>
  );
}
