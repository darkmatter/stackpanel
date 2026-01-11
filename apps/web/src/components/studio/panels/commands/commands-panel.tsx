"use client";

import { useState, useMemo } from "react";
import {
  ChevronDown,
  ChevronRight,
  Loader2,
  Pencil,
  Package,
  Search,
  Terminal,
  Trash2,
  X,
  Save,
  FolderOpen,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useCommands } from "@/lib/use-nix-config";
import type { Command } from "@/lib/types";
import { useAgentContext } from "@/lib/agent-provider";
import { NixClient } from "@/lib/nix-client";

interface CommandWithId extends Command {
  id: string;
}

interface EditFormState {
  package: string;
  bin: string;
  args: string;
  cwd: string;
  configPath: string;
  configArg: string;
}

const defaultEditForm: EditFormState = {
  package: "",
  bin: "",
  args: "",
  cwd: "",
  configPath: "",
  configArg: "",
};

/**
 * Get a display-friendly category from the package name
 */
function getCategory(pkg: string): string {
  const lowerPkg = pkg.toLowerCase();
  if (
    lowerPkg.includes("eslint") ||
    lowerPkg.includes("biome") ||
    lowerPkg.includes("prettier")
  ) {
    return "linting";
  }
  if (lowerPkg.includes("typescript") || lowerPkg.includes("tsc")) {
    return "types";
  }
  if (lowerPkg.includes("vitest") || lowerPkg.includes("jest")) {
    return "testing";
  }
  if (lowerPkg.includes("turbo")) {
    return "build";
  }
  if (lowerPkg.includes("drizzle") || lowerPkg.includes("prisma")) {
    return "database";
  }
  if (lowerPkg.includes("go")) {
    return "go";
  }
  if (lowerPkg.includes("buf") || lowerPkg.includes("proto")) {
    return "proto";
  }
  return "other";
}

function getCategoryColor(category: string): string {
  switch (category) {
    case "linting":
      return "bg-purple-500/20 text-purple-400 border-purple-500/30";
    case "types":
      return "bg-blue-500/20 text-blue-400 border-blue-500/30";
    case "testing":
      return "bg-green-500/20 text-green-400 border-green-500/30";
    case "build":
      return "bg-orange-500/20 text-orange-400 border-orange-500/30";
    case "database":
      return "bg-cyan-500/20 text-cyan-400 border-cyan-500/30";
    case "go":
      return "bg-sky-500/20 text-sky-400 border-sky-500/30";
    case "proto":
      return "bg-yellow-500/20 text-yellow-400 border-yellow-500/30";
    default:
      return "bg-gray-500/20 text-gray-400 border-gray-500/30";
  }
}

export function CommandsPanel() {
  const { token } = useAgentContext();
  const { data: commands, isLoading, error, refetch } = useCommands();

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(
    new Set(["linting", "testing", "build"]),
  );
  const [editingCommand, setEditingCommand] = useState<string | null>(null);
  const [editForm, setEditForm] = useState<EditFormState>(defaultEditForm);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState<string | null>(null);

  // Filter commands based on search and category
  const filteredCommands = useMemo(() => {
    if (!commands) return {};

    return Object.entries(commands).reduce(
      (acc, [id, cmd]) => {
        const category = getCategory(cmd.package);
        const searchLower = searchQuery.toLowerCase();

        const matchesSearch =
          !searchQuery ||
          id.toLowerCase().includes(searchLower) ||
          cmd.package.toLowerCase().includes(searchLower) ||
          (cmd.bin?.toLowerCase().includes(searchLower) ?? false) ||
          cmd.args.some((arg) => arg.toLowerCase().includes(searchLower));

        const matchesCategory =
          !selectedCategory || category === selectedCategory;

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
    const result: Record<string, CommandWithId[]> = {};

    for (const [id, cmd] of Object.entries(filteredCommands)) {
      const category = getCategory(cmd.package);
      if (!result[category]) {
        result[category] = [];
      }
      result[category].push({ ...cmd, id });
    }

    return result;
  }, [filteredCommands]);

  // Get all unique categories for filter dropdown
  const allCategories = useMemo(() => {
    if (!commands) return [];
    const cats = new Set<string>();
    for (const cmd of Object.values(commands)) {
      cats.add(getCategory(cmd.package));
    }
    return Array.from(cats).sort();
  }, [commands]);

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
    setEditForm({
      package: command.package,
      bin: command.bin ?? "",
      args: command.args.join(" "),
      cwd: command.cwd ?? "",
      configPath: command.config_path ?? "",
      configArg: command.config_arg?.join(" ") ?? "",
    });
  };

  const handleFormChange = (field: keyof EditFormState, value: string) => {
    setEditForm((prev) => ({ ...prev, [field]: value }));
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

      const updatedCommand: Command = {
        package: editForm.package,
        bin: editForm.bin || undefined,
        args: editForm.args ? editForm.args.split(/\s+/).filter(Boolean) : [],
        cwd: editForm.cwd || undefined,
        config_path: editForm.configPath || undefined,
        config_arg: editForm.configArg
          ? editForm.configArg.split(/\s+/).filter(Boolean)
          : [],
        env: allCommands[commandId]?.env ?? {},
      };

      allCommands[commandId] = updatedCommand;

      await client.mapEntity<Command>("commands").setAll(allCommands);
      toast.success("Command updated");
      setEditingCommand(null);
      setEditForm(defaultEditForm);
      refetch();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to save command",
      );
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setEditingCommand(null);
    setEditForm(defaultEditForm);
  };

  const handleDelete = async (commandId: string) => {
    if (!token) {
      toast.error("Not connected to agent");
      return;
    }

    if (!confirm(`Are you sure you want to delete "${commandId}"?`)) {
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
      toast.error(
        err instanceof Error ? err.message : "Failed to delete command",
      );
    } finally {
      setIsDeleting(null);
    }
  };

  /**
   * Build the full command string for display
   */
  const getCommandString = (cmd: Command): string => {
    const parts: string[] = [];
    const binary = cmd.bin ?? cmd.package;
    parts.push(binary);

    if (cmd.config_path && cmd.config_arg?.length) {
      parts.push(...cmd.config_arg, cmd.config_path);
    }

    parts.push(...cmd.args);
    return parts.join(" ");
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
            {totalCommands} command{totalCommands !== 1 ? "s" : ""} configured
          </p>
        </div>
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
          onValueChange={(value) =>
            setSelectedCategory(value === "all" ? null : value)
          }
        >
          <SelectTrigger className="w-40">
            <SelectValue placeholder="All categories" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All categories</SelectItem>
            {allCategories.map((cat) => (
              <SelectItem key={cat} value={cat}>
                {cat.charAt(0).toUpperCase() + cat.slice(1)}
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
                  : "No commands configured yet"}
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
                        {category.charAt(0).toUpperCase() + category.slice(1)}
                      </Badge>
                      <span className="text-muted-foreground text-sm">
                        {categoryCommands.length} command
                        {categoryCommands.length !== 1 ? "s" : ""}
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
                              <div className="space-y-4">
                                {/* Edit Form */}
                                <div className="grid gap-4 md:grid-cols-2">
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-package`}>
                                      Package
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-package`}
                                      value={editForm.package}
                                      onChange={(e) =>
                                        handleFormChange(
                                          "package",
                                          e.target.value,
                                        )
                                      }
                                      placeholder="e.g., eslint"
                                    />
                                  </div>
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-bin`}>
                                      Binary (optional)
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-bin`}
                                      value={editForm.bin}
                                      onChange={(e) =>
                                        handleFormChange("bin", e.target.value)
                                      }
                                      placeholder="Defaults to package name"
                                    />
                                  </div>
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-args`}>
                                      Arguments
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-args`}
                                      value={editForm.args}
                                      onChange={(e) =>
                                        handleFormChange("args", e.target.value)
                                      }
                                      placeholder="Space-separated args"
                                    />
                                  </div>
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-cwd`}>
                                      Working Directory
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-cwd`}
                                      value={editForm.cwd}
                                      onChange={(e) =>
                                        handleFormChange("cwd", e.target.value)
                                      }
                                      placeholder="e.g., apps/server"
                                    />
                                  </div>
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-configPath`}>
                                      Config Path
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-configPath`}
                                      value={editForm.configPath}
                                      onChange={(e) =>
                                        handleFormChange(
                                          "configPath",
                                          e.target.value,
                                        )
                                      }
                                      placeholder="e.g., eslint.config.js"
                                    />
                                  </div>
                                  <div className="space-y-2">
                                    <Label htmlFor={`${cmd.id}-configArg`}>
                                      Config Arg Prefix
                                    </Label>
                                    <Input
                                      id={`${cmd.id}-configArg`}
                                      value={editForm.configArg}
                                      onChange={(e) =>
                                        handleFormChange(
                                          "configArg",
                                          e.target.value,
                                        )
                                      }
                                      placeholder="e.g., --config"
                                    />
                                  </div>
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
                                    disabled={isSaving || !editForm.package}
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
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <code className="rounded bg-background px-1.5 py-0.5 font-mono text-sm font-medium">
                                      {cmd.id}
                                    </code>
                                    <div className="flex items-center gap-1 text-muted-foreground text-xs">
                                      <Package className="h-3 w-3" />
                                      <span>{cmd.package}</span>
                                    </div>
                                    {cmd.cwd && (
                                      <div className="flex items-center gap-1 text-muted-foreground text-xs">
                                        <FolderOpen className="h-3 w-3" />
                                        <span>{cmd.cwd}</span>
                                      </div>
                                    )}
                                  </div>
                                  <code className="mt-2 block rounded bg-background px-2 py-1.5 font-mono text-muted-foreground text-xs overflow-x-auto">
                                    $ {getCommandString(cmd)}
                                  </code>
                                </div>
                                <div className="flex gap-1 shrink-0">
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
