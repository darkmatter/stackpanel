/**
 * Inspector Panel
 *
 * Provides a comprehensive view of the Stackpanel environment for debugging
 * and inspection purposes. Shows generated files, integrations, scripts,
 * state files, and configuration data in organized tabs.
 */

const ALL_CONTRIBUTORS_VALUE = "__all__";

import { FileType } from "@stackpanel/proto";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@ui/collapsible";
import { ScrollArea, ScrollBar } from "@ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import {
  AlertTriangle,
  Check,
  ChevronDown,
  ChevronRight,
  Code,
  Copy,
  Database,
  FileCode,
  FileJson,
  FolderOpen,
  Info,
  Loader2,
  Play,
  Puzzle,
  RefreshCw,
  Search,
  Terminal,
  X,
} from "lucide-react";
import { useMemo, useState } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import {
  type InspectorDataFile,
  type InspectorData,
  type InspectorGeneratedFile,
  type InspectorIntegration,
  type InspectorScript,
  type InspectorStateFile,
  useInspectorData,
} from "@/lib/use-inspector-data";
import { cn } from "@/lib/utils";
import { PanelHeader } from "./shared/panel-header";

// =============================================================================
// Generated Files Tab
// =============================================================================

function FileStatusBadge({ file }: { file: InspectorGeneratedFile }) {
  if (!file.enable) {
    return (
      <Badge variant="secondary" className="text-xs">
        Disabled
      </Badge>
    );
  }

  if (!file.existsOnDisk) {
    return (
      <Badge variant="destructive" className="text-xs">
        Missing
      </Badge>
    );
  }

  if (file.isStale) {
    return (
      <Badge
        variant="outline"
        className="border-yellow-500/50 bg-yellow-500/10 text-yellow-600 text-xs dark:text-yellow-400"
      >
        Stale
      </Badge>
    );
  }

  return (
    <Badge
      variant="outline"
      className="border-green-500/50 bg-green-500/10 text-green-600 text-xs dark:text-green-400"
    >
      Up to date
    </Badge>
  );
}

// -----------------------------------------------------------------------------
// File tree data structure
// -----------------------------------------------------------------------------

interface FileTreeNode {
  name: string;
  /** Full path segment up to this node (used as key) */
  path: string;
  children: Map<string, FileTreeNode>;
  /** Present only on leaf nodes (actual files) */
  file?: InspectorGeneratedFile;
}

/**
 * Build a nested tree from a flat list of generated files.
 * Each file's `path` is split on "/" to create intermediate folder nodes.
 */
function buildFileTree(files: InspectorGeneratedFile[]): FileTreeNode {
  const root: FileTreeNode = { name: "", path: "", children: new Map() };

  for (const file of files) {
    const parts = file.path.split("/").filter(Boolean);
    let current = root;

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const segmentPath = parts.slice(0, i + 1).join("/");

      if (!current.children.has(part)) {
        current.children.set(part, {
          name: part,
          path: segmentPath,
          children: new Map(),
        });
      }
      current = current.children.get(part)!;
    }

    // Mark the final node as a file leaf
    current.file = file;
  }

  return root;
}

/** Count total files (leaves) under a tree node */
function countFiles(node: FileTreeNode): number {
  if (node.file && node.children.size === 0) return 1;
  let count = node.file ? 1 : 0;
  for (const child of node.children.values()) {
    count += countFiles(child);
  }
  return count;
}

/** Check if any file in the subtree is stale */
function hasStaleFiles(node: FileTreeNode): boolean {
  if (node.file?.isStale && node.file.enable) return true;
  for (const child of node.children.values()) {
    if (hasStaleFiles(child)) return true;
  }
  return false;
}

/**
 * Collapse single-child intermediate folders into one node for a cleaner tree.
 * e.g. `home / .config / nix` becomes `home/.config/nix` when each has only
 * one child and is not itself a file.
 */
function collapseSingleChildFolders(node: FileTreeNode): FileTreeNode {
  // First, recursively collapse children
  const collapsedChildren = new Map<string, FileTreeNode>();
  for (const [key, child] of node.children) {
    collapsedChildren.set(key, collapseSingleChildFolders(child));
  }
  node.children = collapsedChildren;

  // If this node has exactly one child and is not a file, merge with child
  if (node.children.size === 1 && !node.file && node.name !== "") {
    const [, onlyChild] = [...node.children.entries()][0];
    return {
      ...onlyChild,
      name: `${node.name}/${onlyChild.name}`,
    };
  }

  return node;
}

// -----------------------------------------------------------------------------
// Tree rendering components
// -----------------------------------------------------------------------------

function FileContentPreview({ file }: { file: InspectorGeneratedFile }) {
  if (!file.text) return null;

  const maxPreviewLines = 12;
  const lines = file.text.split("\n");
  const truncated = lines.length > maxPreviewLines;
  const preview = truncated
    ? lines.slice(0, maxPreviewLines).join("\n") + "\n..."
    : file.text;

  return (
    <div className="mt-1.5">
      <pre className="max-h-[200px] overflow-auto rounded border bg-muted/50 p-2 font-mono text-[11px] leading-relaxed text-muted-foreground">
        {preview}
      </pre>
    </div>
  );
}

function FileLeafNode({
  node,
  depth,
}: {
  node: FileTreeNode;
  depth: number;
}) {
  const file = node.file!;
  const [expanded, setExpanded] = useState(false);

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <CollapsibleTrigger asChild>
        <div
          className={cn(
            "flex cursor-pointer items-center gap-2 rounded-md px-2 py-1 text-sm transition-colors hover:bg-accent/50",
            file.isStale && file.enable && "text-yellow-600 dark:text-yellow-400",
          )}
          style={{ paddingLeft: `${depth * 16 + 8}px` }}
        >
          {expanded ? (
            <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          )}
          <FileCode
            className={cn(
              "h-4 w-4 shrink-0",
              file.type === FileType.DERIVATION
                ? "text-blue-500"
                : "text-muted-foreground",
            )}
          />
          <span className="truncate font-mono text-sm">{node.name}</span>
          <FileStatusBadge file={file} />
          {file.source && (
            <Badge variant="secondary" className="ml-auto shrink-0 text-[10px]">
              {file.source}
            </Badge>
          )}
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div
          className="space-y-2 border-l border-border/50 py-1"
          style={{ marginLeft: `${depth * 16 + 20}px` }}
        >
          {/* Metadata */}
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 px-3 text-xs">
            <div>
              <span className="text-muted-foreground">Path: </span>
              <span className="font-mono">{file.path}</span>
            </div>
            <div>
              <span className="text-muted-foreground">Type: </span>
              <span>{file.type === FileType.DERIVATION ? "Derivation" : "Text"}</span>
            </div>
            {file.mode && (
              <div>
                <span className="text-muted-foreground">Mode: </span>
                <span className="font-mono">{file.mode}</span>
              </div>
            )}
            {file.size !== null && (
              <div>
                <span className="text-muted-foreground">Size: </span>
                <span>{formatFileSize(file.size)}</span>
              </div>
            )}
            {file.description && (
              <div className="col-span-2">
                <span className="text-muted-foreground">Description: </span>
                <span>{file.description}</span>
              </div>
            )}
            {file.store_path && (
              <div className="col-span-2">
                <span className="text-muted-foreground">Store: </span>
                <span className="break-all font-mono text-[10px]">{file.store_path}</span>
              </div>
            )}
          </div>

          {/* Content preview */}
          <div className="px-3">
            <FileContentPreview file={file} />
          </div>
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function FolderTreeNode({
  node,
  depth,
  defaultOpen,
  filter,
}: {
  node: FileTreeNode;
  depth: number;
  defaultOpen?: boolean;
  filter: string;
}) {
  const [open, setOpen] = useState(defaultOpen ?? depth < 1);
  const fileCount = countFiles(node);
  const stale = hasStaleFiles(node);

  // Sort children: folders first (alphabetically), then files (alphabetically)
  const sortedChildren = [...node.children.values()].sort((a, b) => {
    const aIsFolder = a.children.size > 0 && !a.file;
    const bIsFolder = b.children.size > 0 && !b.file;
    if (aIsFolder && !bIsFolder) return -1;
    if (!aIsFolder && bIsFolder) return 1;
    return a.name.localeCompare(b.name);
  });

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger asChild>
        <div
          className={cn(
            "flex cursor-pointer items-center gap-2 rounded-md px-2 py-1 text-sm transition-colors hover:bg-accent/50",
            stale && "text-yellow-600 dark:text-yellow-400",
          )}
          style={{ paddingLeft: `${depth * 16 + 8}px` }}
        >
          {open ? (
            <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          )}
          {open ? (
            <FolderOpen className="h-4 w-4 shrink-0 text-blue-400" />
          ) : (
            <FolderOpen className="h-4 w-4 shrink-0 text-muted-foreground" />
          )}
          <span className="truncate font-medium">{node.name}</span>
          <span className="ml-auto shrink-0 text-xs text-muted-foreground">
            {fileCount}
          </span>
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="border-l border-border/40" style={{ marginLeft: `${depth * 16 + 16}px` }}>
          {sortedChildren.map((child) => (
            <FileTreeNodeRenderer
              key={child.path}
              node={child}
              depth={depth + 1}
              filter={filter}
            />
          ))}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function FileTreeNodeRenderer({
  node,
  depth,
  filter,
}: {
  node: FileTreeNode;
  depth: number;
  filter: string;
}) {
  // Leaf file node (has a file and no children)
  if (node.file && node.children.size === 0) {
    return <FileLeafNode node={node} depth={depth} />;
  }

  // Folder node
  return (
    <FolderTreeNode
      node={node}
      depth={depth}
      defaultOpen={filter.length > 0 || depth < 1}
      filter={filter}
    />
  );
}

// -----------------------------------------------------------------------------
// Generated Files Tab
// -----------------------------------------------------------------------------

function GeneratedFilesTab({
  files,
  totalCount,
  staleCount,
  enabledCount,
}: {
  files: InspectorGeneratedFile[];
  totalCount: number;
  staleCount: number;
  enabledCount: number;
}) {
  const [filter, setFilter] = useState("");

  const filteredFiles = files.filter(
    (f) =>
      f.path.toLowerCase().includes(filter.toLowerCase()) ||
      (f.source?.toLowerCase().includes(filter.toLowerCase()) ?? false),
  );

  const tree = useMemo(() => {
    const raw = buildFileTree(filteredFiles);
    // Collapse single-child folders for a cleaner view
    const collapsed: FileTreeNode = {
      ...raw,
      children: new Map(
        [...raw.children.entries()].map(([k, v]) => [
          k,
          collapseSingleChildFolders(v),
        ]),
      ),
    };
    return collapsed;
  }, [filteredFiles]);

  // Sort top-level: folders first, then files
  const sortedTopLevel = useMemo(() => {
    return [...tree.children.values()].sort((a, b) => {
      const aIsFolder = a.children.size > 0 && !a.file;
      const bIsFolder = b.children.size > 0 && !b.file;
      if (aIsFolder && !bIsFolder) return -1;
      if (!aIsFolder && bIsFolder) return 1;
      return a.name.localeCompare(b.name);
    });
  }, [tree]);

  return (
    <div className="space-y-4">
      {/* Stats */}
      <div className="flex flex-wrap items-center gap-4 text-sm">
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">Total:</span>
          <span className="font-medium">{totalCount} files</span>
        </div>
        <div className="flex items-center gap-2">
          <Check className="h-4 w-4 text-green-500" />
          <span>{enabledCount - staleCount} up to date</span>
        </div>
        {staleCount > 0 && (
          <div className="flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-yellow-500" />
            <span className="text-yellow-600 dark:text-yellow-400">
              {staleCount} stale
            </span>
          </div>
        )}
      </div>

      {/* Filter */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <input
          type="text"
          placeholder="Filter files by path or source..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full rounded-md border bg-background px-9 py-2 text-sm"
        />
      </div>

      {/* File tree */}
      {filteredFiles.length === 0 ? (
        <div className="flex h-[220px] flex-col items-center justify-center gap-2 rounded-lg border border-dashed">
          <FileCode className="h-5 w-5 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            No generated files match this filter
          </p>
        </div>
      ) : (
        <ScrollArea className="h-[500px]">
          <div className="pr-4">
            {sortedTopLevel.map((child) => (
              <FileTreeNodeRenderer
                key={child.path}
                node={child}
                depth={0}
                filter={filter}
              />
            ))}
          </div>
        </ScrollArea>
      )}
    </div>
  );
}

// =============================================================================
// Integrations Tab
// =============================================================================

function IntegrationItem({
  integration,
}: {
  integration: InspectorIntegration;
}) {
  return (
    <div className="flex items-center justify-between rounded-md border px-4 py-3">
      <div className="flex items-center gap-3">
        <div
          className={cn(
            "flex h-8 w-8 items-center justify-center rounded-full",
            integration.enabled ? "bg-green-500/10" : "bg-muted",
          )}
        >
          <Puzzle
            className={cn(
              "h-4 w-4",
              integration.enabled
                ? "text-green-600 dark:text-green-400"
                : "text-muted-foreground",
            )}
          />
        </div>
        <div>
          <p className="font-medium text-sm">{integration.displayName}</p>
          <p className="text-muted-foreground text-xs">{integration.name}</p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        {integration.tags?.map((tag) => (
          <Badge key={tag} variant="secondary" className="text-xs">
            {tag}
          </Badge>
        ))}
        <Badge
          variant={integration.enabled ? "default" : "secondary"}
          className={cn(
            "text-xs",
            integration.enabled &&
              "bg-green-500/10 text-green-600 hover:bg-green-500/20 dark:text-green-400",
          )}
        >
          {integration.enabled ? "Enabled" : "Disabled"}
        </Badge>
      </div>
    </div>
  );
}

function IntegrationsTab({
  integrations,
}: {
  integrations: InspectorIntegration[];
}) {
  const enabledCount = integrations.filter((i) => i.enabled).length;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4 text-sm">
        <span className="text-muted-foreground">
          {enabledCount} of {integrations.length} integrations enabled
        </span>
      </div>

      {integrations.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed py-12">
          <Puzzle className="h-8 w-8 text-muted-foreground/50" />
          <p className="text-muted-foreground text-sm">
            No integrations configured
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {integrations.map((integration) => (
            <IntegrationItem key={integration.name} integration={integration} />
          ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Scripts Tab
// =============================================================================

function ScriptItem({ script }: { script: InspectorScript }) {
  const [expanded, setExpanded] = useState(false);
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(script.name);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <CollapsibleTrigger asChild>
        <div className="flex cursor-pointer items-center gap-3 rounded-md border px-3 py-2 transition-colors hover:bg-accent/50">
          {expanded ? (
            <ChevronDown className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
          )}
          <Terminal className="h-4 w-4 flex-shrink-0 text-accent" />
          <div className="min-w-0 flex-1">
            <span className="font-mono text-sm">{script.name}</span>
            {script.description && (
              <span className="ml-2 text-xs text-muted-foreground">
                — {script.description}
              </span>
            )}
          </div>
          <Badge variant="secondary" className="flex-shrink-0 text-xs">
            {script.source}
          </Badge>
          <Button
            variant="ghost"
            size="sm"
            className="h-6 w-6 p-0"
            onClick={(e) => {
              e.stopPropagation();
              handleCopy();
            }}
          >
            {copied ? (
              <Check className="h-3 w-3 text-green-500" />
            ) : (
              <Copy className="h-3 w-3" />
            )}
          </Button>
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="ml-7 mt-2 space-y-3 overflow-hidden rounded-md border bg-muted/30 p-3">
          {/* Script path */}
          {script.scriptPath && (
            <div className="text-xs text-muted-foreground">
              <span className="font-medium">Path:</span>{" "}
              <code className="rounded bg-background px-1">
                {script.scriptPath}
              </code>
            </div>
          )}

          {/* Source code or binary indicator */}
          {script.isBinary ? (
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Code className="h-4 w-4" />
              <span>Binary executable (source not available)</span>
            </div>
          ) : script.scriptSource ? (
            <div>
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span className="font-medium">Source:</span>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-5 gap-1 px-1 text-xs"
                  onClick={() =>
                    navigator.clipboard.writeText(script.scriptSource!)
                  }
                >
                  <Copy className="h-3 w-3" />
                  Copy
                </Button>
              </div>
              <ScrollArea className="mt-1 max-h-[300px] w-full">
                <pre className="min-w-0 rounded bg-background p-2 font-mono text-xs">
                  {script.scriptSource}
                </pre>
                <ScrollBar orientation="horizontal" />
              </ScrollArea>
            </div>
          ) : (
            <div className="text-xs text-muted-foreground">
              <span className="font-medium">Command:</span>{" "}
              <code className="rounded bg-background px-1">
                {script.command || script.name}
              </code>
            </div>
          )}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function ScriptsTab({ scripts }: { scripts: InspectorScript[] }) {
  const [filter, setFilter] = useState("");

  const filteredScripts = scripts.filter((s) =>
    s.name.toLowerCase().includes(filter.toLowerCase()),
  );

  if (filteredScripts.length === 0) {
    return (
      <div className="flex h-[220px] flex-col items-center justify-center gap-2 rounded-lg border border-dashed">
        <Terminal className="h-5 w-5 text-muted-foreground" />
        <p className="text-sm text-muted-foreground">
          No scripts match this filter
        </p>
      </div>
    );
  }

  // Group by source
  const scriptsBySource = filteredScripts.reduce(
    (acc, script) => {
      if (!acc[script.source]) acc[script.source] = [];
      acc[script.source].push(script);
      return acc;
    },
    {} as Record<string, InspectorScript[]>,
  );

  return (
    <div className="space-y-4">
      <div className="text-sm text-muted-foreground">
        {scripts.length} scripts/commands available in PATH
      </div>

      {/* Filter */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <input
          type="text"
          placeholder="Filter scripts..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full rounded-md border bg-background px-9 py-2 text-sm"
        />
      </div>

      <ScrollArea className="h-[500px]">
        <div className="space-y-4 pr-4">
          {Object.entries(scriptsBySource).map(([source, sourceScripts]) => (
            <div key={source} className="space-y-2">
              <h3 className="flex items-center gap-2 font-medium text-sm">
                <Play className="h-4 w-4" />
                {source}
                <Badge variant="secondary" className="text-xs">
                  {sourceScripts.length}
                </Badge>
              </h3>
              <div className="space-y-1">
                {sourceScripts.map((script) => (
                  <ScriptItem key={script.name} script={script} />
                ))}
              </div>
            </div>
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}

// =============================================================================
// State Files Tab
// =============================================================================

function StateFileItem({ file }: { file: InspectorStateFile }) {
  const [expanded, setExpanded] = useState(false);

  let parsedContent: unknown = null;
  let isJson = false;
  try {
    parsedContent = JSON.parse(file.content);
    isJson = true;
  } catch {
    parsedContent = file.content;
  }

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <CollapsibleTrigger asChild>
        <div className="flex cursor-pointer items-center gap-3 overflow-hidden rounded-md border px-3 py-2 transition-colors hover:bg-accent/50">
          {expanded ? (
            <ChevronDown className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
          )}
          <FileJson className="h-4 w-4 flex-shrink-0 text-orange-500" />
          <span className="truncate font-mono text-sm">{file.name}</span>
          <span className="ml-auto truncate text-muted-foreground text-xs">
            {file.path}
          </span>
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="ml-7 mt-2 overflow-hidden rounded-md border bg-muted/30 p-3">
          <ScrollArea className="max-h-[300px] w-full">
            <pre className="min-w-0 font-mono text-xs">
              {isJson
                ? JSON.stringify(parsedContent, null, 2)
                : String(parsedContent)}
            </pre>
            <ScrollBar orientation="horizontal" />
          </ScrollArea>
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function StateFilesTab({ files }: { files: InspectorStateFile[] }) {
  return (
    <div className="space-y-4">
      <div className="text-sm text-muted-foreground">
        {files.length} state files in .stackpanel/state/
      </div>

      {files.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed py-12">
          <FileJson className="h-8 w-8 text-muted-foreground/50" />
          <p className="text-muted-foreground text-sm">No state files found</p>
        </div>
      ) : (
        <div className="space-y-2">
          {files.map((file) => (
            <StateFileItem key={file.name} file={file} />
          ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Data Files Tab
// =============================================================================

function DataFileItem({ file }: { file: InspectorDataFile }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <Collapsible open={expanded} onOpenChange={setExpanded}>
      <CollapsibleTrigger asChild>
        <div className="flex cursor-pointer items-center gap-3 rounded-md border px-3 py-2 transition-colors hover:bg-accent/50">
          {expanded ? (
            <ChevronDown className="h-4 w-4 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          )}
          <Database className="h-4 w-4 text-purple-500" />
          <span className="font-mono text-sm">{file.name}</span>
          <span className="text-muted-foreground text-xs">{file.path}</span>
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="ml-7 mt-2 rounded-md border bg-muted/30 p-3">
          <ScrollArea className="max-h-[300px]">
            <pre className="overflow-x-auto whitespace-pre-wrap break-all font-mono text-xs">
              {JSON.stringify(file.data, null, 2)}
            </pre>
          </ScrollArea>
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function DataFilesTab({ files }: { files: InspectorDataFile[] }) {
  return (
    <div className="space-y-4">
      <div className="text-sm text-muted-foreground">
        {files.length} data entities in .stackpanel/data/
      </div>

      {files.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed py-12">
          <Database className="h-8 w-8 text-muted-foreground/50" />
          <p className="text-muted-foreground text-sm">No data files found</p>
        </div>
      ) : (
        <div className="space-y-2">
          {files.map((file) => (
            <DataFileItem key={file.name} file={file} />
          ))}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Config Tab
// =============================================================================

function ConfigSourceBadge({ source }: { source: string | null }) {
  if (!source) return null;

  const sourceLabels: Record<
    string,
    { label: string; variant: "default" | "secondary" | "outline" }
  > = {
    flake_watcher: { label: "FlakeWatcher", variant: "default" },
    legacy_cache: { label: "Cached", variant: "secondary" },
    fresh_eval: { label: "Fresh Eval", variant: "outline" },
    passthru: { label: "Passthru", variant: "default" },
  };

  const { label, variant } = sourceLabels[source] ?? {
    label: source,
    variant: "secondary" as const,
  };

  return (
    <Badge variant={variant} className="text-xs">
      {label}
    </Badge>
  );
}

/**
 * Resolve a dot-notation path against a nested object.
 * Supports case-insensitive key matching and partial (prefix) paths.
 * e.g. "ide.zed" on { ide: { zed: { … } } } returns { ide: { zed: { … } } }
 *
 * Returns `undefined` when no match is found.
 */
function resolveConfigPath(
  obj: Record<string, unknown>,
  path: string,
): unknown | undefined {
  const segments = path.split(".");
  let current: unknown = obj;

  for (const segment of segments) {
    if (current == null || typeof current !== "object") return undefined;
    const record = current as Record<string, unknown>;
    // Try exact key first, then case-insensitive fallback
    const key =
      segment in record
        ? segment
        : Object.keys(record).find(
            (k) => k.toLowerCase() === segment.toLowerCase(),
          );
    if (key === undefined) return undefined;
    current = record[key];
  }
  return current;
}

/**
 * Collect every node in `obj` whose full key-path contains `query` as a
 * case-insensitive substring. Returns a sparse reconstruction of the original
 * object that keeps only matching branches (preserving complete subtrees once
 * a key path matches).
 */
function filterConfigByKeySearch(
  obj: Record<string, unknown>,
  query: string,
): Record<string, unknown> | undefined {
  const lowerQuery = query.toLowerCase();

  function walk(
    node: unknown,
    currentPath: string,
  ): unknown | undefined {
    if (node == null || typeof node !== "object") {
      // Leaf – keep it only if the path so far matches
      return currentPath.toLowerCase().includes(lowerQuery) ? node : undefined;
    }

    const record = node as Record<string, unknown>;
    const result: Record<string, unknown> = {};
    let hasMatch = false;

    for (const [key, value] of Object.entries(record)) {
      const childPath = currentPath ? `${currentPath}.${key}` : key;

      // If the path up to (and including) this key already matches,
      // include the entire subtree as-is.
      if (childPath.toLowerCase().includes(lowerQuery)) {
        result[key] = value;
        hasMatch = true;
      } else {
        // Otherwise recurse – there may be deeper matches.
        const filtered = walk(value, childPath);
        if (filtered !== undefined) {
          result[key] = filtered;
          hasMatch = true;
        }
      }
    }

    return hasMatch ? result : undefined;
  }

  const out = walk(obj, "");
  return out !== undefined ? (out as Record<string, unknown>) : undefined;
}

function ConfigTab({
  config,
  configSource,
  contributorFilter,
}: {
  config: Record<string, unknown> | null;
  configSource: string | null;
  contributorFilter?: string | null;
}) {
  const [filter, setFilter] = useState("");
  const [showFilterHint, setShowFilterHint] = useState(true);

  if (!config) {
    return (
      <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed py-12">
        <Code className="h-8 w-8 text-muted-foreground/50" />
        <p className="text-muted-foreground text-sm">
          Config not available. Is the agent connected?
        </p>
      </div>
    );
  }

  const configString = JSON.stringify(config, null, 2);
  const contributorFilterLower = contributorFilter?.toLowerCase() ?? "";

  // ---------------------------------------------------------------------------
  // Filtering strategy:
  //   1. If the filter text resolves as a dot-path (e.g. "ide.zed"), show the
  //      value at that path wrapped in its parent keys so the context is clear.
  //   2. Otherwise, do a key-path substring search across the whole tree,
  //      returning every branch whose path contains the filter text.
  //   3. If neither yields results, fall through to the raw JSON string.
  //   4. Contributor filter is applied separately as a line-level filter on the
  //      final JSON string.
  // ---------------------------------------------------------------------------
  let filteredConfig: string;

  if (filter) {
    const trimmed = filter.trim();

    // Attempt 1: exact dot-path resolution
    const exactMatch = resolveConfigPath(config, trimmed);
    // Attempt 2: key-path substring search
    const fuzzyMatch = filterConfigByKeySearch(config, trimmed);

    if (exactMatch !== undefined) {
      // Wrap the result back into its path for context
      const segments = trimmed.split(".");
      let wrapped: unknown = exactMatch;
      for (let i = segments.length - 1; i >= 0; i--) {
        // Find the actual key (preserving original casing)
        let lookupObj: unknown = config;
        for (let j = 0; j < i; j++) {
          const rec = lookupObj as Record<string, unknown>;
          const realKey =
            segments[j] in rec
              ? segments[j]
              : Object.keys(rec).find(
                  (k) => k.toLowerCase() === segments[j].toLowerCase(),
                ) ?? segments[j];
          lookupObj = rec[realKey];
        }
        const rec = lookupObj as Record<string, unknown>;
        const realKey =
          segments[i] in rec
            ? segments[i]
            : Object.keys(rec).find(
                (k) => k.toLowerCase() === segments[i].toLowerCase(),
              ) ?? segments[i];
        wrapped = { [realKey]: wrapped };
      }
      filteredConfig = JSON.stringify(wrapped, null, 2);
    } else if (fuzzyMatch !== undefined) {
      filteredConfig = JSON.stringify(fuzzyMatch, null, 2);
    } else {
      // Nothing matched via path – show empty
      filteredConfig = "// No matching config paths found";
    }
  } else {
    filteredConfig = configString;
  }

  // Apply contributor line-level filter on top, if present
  if (contributorFilterLower) {
    filteredConfig = filteredConfig
      .split("\n")
      .filter((line) => line.toLowerCase().includes(contributorFilterLower))
      .join("\n");
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <span>Full evaluated Nix configuration</span>
          <ConfigSourceBadge source={configSource} />
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => navigator.clipboard.writeText(configString)}
        >
          <Copy className="mr-2 h-3 w-3" />
          Copy JSON
        </Button>
      </div>

      {/* Filter */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <input
          type="text"
          placeholder="Filter by path (e.g. ide.zed) or keyword..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full rounded-md border bg-background px-9 py-2 text-sm"
        />
      </div>

      {/* Filter hint notice */}
      {showFilterHint && (
        <div className="relative flex gap-3 rounded-md border border-blue-200 bg-blue-50/50 px-3 py-2.5 text-xs text-blue-900 dark:border-blue-800 dark:bg-blue-950/30 dark:text-blue-200">
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <div className="space-y-1">
            <p className="font-medium">Supports dot-path filtering</p>
            <p className="text-blue-700 dark:text-blue-300">
              Use dot-separated paths to drill into the config and view full
              objects. Examples:
            </p>
            <div className="flex flex-wrap gap-x-3 gap-y-1 font-mono text-blue-800 dark:text-blue-200">
              <span>services.postgres</span>
              <span>ide.zed</span>
              <span>languages.javascript</span>
              <span>devshell</span>
              <span>stackpanel.scripts</span>
            </div>
          </div>
          <button
            onClick={() => setShowFilterHint(false)}
            className="absolute right-1.5 top-1.5 rounded p-0.5 text-blue-400 hover:text-blue-600 dark:text-blue-500 dark:hover:text-blue-300"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      <ScrollArea className="h-[500px]">
        <pre className="overflow-x-auto whitespace-pre-wrap break-all rounded-md border bg-muted/30 p-4 font-mono text-xs">
          {filteredConfig}
        </pre>
      </ScrollArea>
    </div>
  );
}

// =============================================================================
// Helpers
// =============================================================================

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function matchesContributor(
  value: string | null | undefined,
  contributor: string,
): boolean {
  return (value ?? "").toLowerCase() === contributor.toLowerCase();
}

function textContainsContributor(
  value: string | null | undefined,
  contributor: string,
): boolean {
  return (value ?? "").toLowerCase().includes(contributor.toLowerCase());
}

function filterInspectorDataByContributor(
  data: InspectorData,
  contributor: string,
): InspectorData {
  const files = data.generatedFiles.files.filter(
    (file) =>
      matchesContributor(file.source, contributor) ||
      textContainsContributor(file.description, contributor),
  );

  const integrations = data.integrations.filter(
    (integration) =>
      matchesContributor(integration.name, contributor) ||
      matchesContributor(integration.displayName, contributor) ||
      matchesContributor(integration.source?.path, contributor) ||
      textContainsContributor(integration.tags?.join(" "), contributor),
  );

  const scripts = data.scripts.filter(
    (script) =>
      matchesContributor(script.source, contributor) ||
      matchesContributor(script.name, contributor) ||
      textContainsContributor(script.description, contributor),
  );

  const dataFiles = data.dataFiles.filter(
    (file) =>
      textContainsContributor(file.name, contributor) ||
      textContainsContributor(file.path, contributor),
  );

  const stateFiles = data.stateFiles.filter(
    (file) =>
      textContainsContributor(file.name, contributor) ||
      textContainsContributor(file.path, contributor) ||
      textContainsContributor(file.content, contributor),
  );

  const enabledCount = files.filter((f) => f.enable).length;
  const staleCount = files.filter((f) => f.isStale).length;

  return {
    ...data,
    generatedFiles: {
      ...data.generatedFiles,
      files,
      totalCount: files.length,
      enabledCount,
      staleCount,
    },
    integrations,
    scripts,
    dataFiles,
    stateFiles,
  };
}

// =============================================================================
// Main Component
// =============================================================================

interface InspectorPanelProps {
  /** Initial contributor to filter by (from URL search params) */
  initialContributor?: string;
}

export function InspectorPanel({ initialContributor }: InspectorPanelProps = {}) {
  const { data, isLoading, isError, error, refetch } = useInspectorData();

  const contributors = data?.contributors ?? [];
  const [selectedContributor, setSelectedContributor] = useState<string | null>(
    initialContributor ?? null,
  );
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [_exportCopied, setExportCopied] = useState(false);

  const displayData = useMemo(() => {
    if (!data) return null;
    if (!selectedContributor) return data;
    return filterInspectorDataByContributor(data, selectedContributor);
  }, [data, selectedContributor]);

  const _activeContributor =
    contributors.find((c) => c.id === selectedContributor) ?? null;
  const inspectorData = displayData;

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refetch();
    } finally {
      setIsRefreshing(false);
    }
  };

  const _handleExport = () => {
    const exportSource = displayData ?? data;
    if (!exportSource) return;
    const exportData = {
      exportedAt: new Date().toISOString(),
      ...exportSource,
    };
    navigator.clipboard.writeText(JSON.stringify(exportData, null, 2));
    setExportCopied(true);
    setTimeout(() => setExportCopied(false), 2000);
  };

  if (isLoading) {
    return (
      <div className="flex min-h-[400px] items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex min-h-[400px] flex-col items-center justify-center gap-4">
        <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
          <p className="text-sm text-destructive">
            Failed to load inspector data: {error?.message ?? "Unknown error"}
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh}>
          Try again
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PanelHeader
        title="Environment Inspector"
        description="Comprehensive view of your Stackpanel environment for debugging and inspection"
        actions={
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
            <div className="flex items-center gap-2">
              <Select
                value={selectedContributor ?? ALL_CONTRIBUTORS_VALUE}
                onValueChange={(value) =>
                  setSelectedContributor(
                    value === ALL_CONTRIBUTORS_VALUE ? null : value,
                  )
                }
              >
                <SelectTrigger className="w-[240px]" aria-label="Filter by contributor">
                  <SelectValue placeholder="All contributors" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL_CONTRIBUTORS_VALUE}>
                    All contributors
                  </SelectItem>
                  <SelectSeparator />
                  {contributors.map((contributor) => (
                    <SelectItem key={contributor.id} value={contributor.id}>
                      <div className="flex items-center justify-between gap-2">
                        <span className="truncate">{contributor.label}</span>
                        <Badge variant="secondary" className="ml-2 text-[10px]">
                          {contributor.type === "extension"
                            ? "Extension"
                            : "Module"}
                        </Badge>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {/* {activeContributor && (
                <Badge variant="outline" className="text-xs">
                  Filtering by {activeContributor.label}
                </Badge>
              )} */}
            </div>
            <div className="flex items-center gap-2">
              {/* <Button
                variant="outline"
                size="sm"
                onClick={handleExport}
                disabled={!data}
              >
                {exportCopied ? (
                  <>
                    <Check className="mr-2 h-4 w-4 text-green-500" />
                    Copied!
                  </>
                ) : (
                  <>
                    <Copy className="mr-2 h-4 w-4" />
                    Export JSON
                  </>
                )}
              </Button> */}
              <Button
                variant="outline"
                size="sm"
                onClick={handleRefresh}
                disabled={isRefreshing}
              >
                <RefreshCw
                  className={cn("mr-2 h-4 w-4", isRefreshing && "animate-spin")}
                />
                {isRefreshing ? "Refreshing..." : "Refresh"}
              </Button>
            </div>
          </div>
        }
      />

      {/* Project Info */}
      {inspectorData?.project && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="flex items-center gap-2 text-base">
              <FolderOpen className="h-4 w-4" />
              Project
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <div>
                <span className="text-muted-foreground">Name:</span>{" "}
                <span className="font-medium">
                  {inspectorData.project.name}
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">Path:</span>{" "}
                <span className="truncate font-mono text-xs">
                  {inspectorData.project.path}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-muted-foreground">Config Source:</span>{" "}
                <ConfigSourceBadge source={inspectorData.configSource} />
              </div>
            </div>

            {/* Directories */}
            {inspectorData.directories && (
              <div className="border-t pt-4">
                <div className="mb-2 text-xs font-medium text-muted-foreground">
                  Stackpanel Directories
                </div>
                <div className="grid gap-1 text-xs">
                  {Object.entries(inspectorData.directories).map(
                    ([key, path]) => (
                      <div key={key} className="flex items-center gap-2">
                        <span className="w-16 text-muted-foreground capitalize">
                          {key}:
                        </span>
                        <code className="truncate rounded bg-muted px-1 font-mono text-xs">
                          {path}
                        </code>
                      </div>
                    ),
                  )}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tabs */}
      <Tabs defaultValue="files">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="files" className="gap-1">
            <FileCode className="h-3 w-3" />
            <span className="hidden sm:inline">Files</span>
            <Badge variant="secondary" className="ml-1 text-xs">
              {inspectorData?.generatedFiles.totalCount ?? 0}
            </Badge>
          </TabsTrigger>
          <TabsTrigger value="scripts" className="gap-1">
            <Terminal className="h-3 w-3" />
            <span className="hidden sm:inline">Scripts</span>
            <Badge variant="secondary" className="ml-1 text-xs">
              {inspectorData?.scripts.length ?? 0}
            </Badge>
          </TabsTrigger>
          <TabsTrigger value="state" className="gap-1">
            <FileJson className="h-3 w-3" />
            <span className="hidden sm:inline">State</span>
            <Badge variant="secondary" className="ml-1 text-xs">
              {inspectorData?.stateFiles.length ?? 0}
            </Badge>
          </TabsTrigger>
          <TabsTrigger value="config" className="gap-1">
            <Code className="h-3 w-3" />
            <span className="hidden sm:inline">Config</span>
          </TabsTrigger>
        </TabsList>

        <TabsContent value="files" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              <GeneratedFilesTab
                files={inspectorData?.generatedFiles.files ?? []}
                totalCount={inspectorData?.generatedFiles.totalCount ?? 0}
                staleCount={inspectorData?.generatedFiles.staleCount ?? 0}
                enabledCount={inspectorData?.generatedFiles.enabledCount ?? 0}
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="integrations" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              <IntegrationsTab integrations={inspectorData?.integrations ?? []} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="scripts" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              <ScriptsTab scripts={inspectorData?.scripts ?? []} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="state" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              <div className="space-y-6">
                <div>
                  <h3 className="mb-3 flex items-center gap-2 font-medium">
                    <FileJson className="h-4 w-4 text-orange-500" />
                    State Files
                  </h3>
                  <StateFilesTab files={inspectorData?.stateFiles ?? []} />
                </div>
                <div>
                  <h3 className="mb-3 flex items-center gap-2 font-medium">
                    <Database className="h-4 w-4 text-purple-500" />
                    Data Files
                  </h3>
                  <DataFilesTab files={inspectorData?.dataFiles ?? []} />
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="config" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              <ConfigTab
                config={inspectorData?.config ?? null}
                configSource={inspectorData?.configSource ?? null}
                contributorFilter={selectedContributor}
              />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
