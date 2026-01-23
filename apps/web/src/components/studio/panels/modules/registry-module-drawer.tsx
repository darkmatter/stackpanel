/**
 * Registry Module Detail Drawer
 *
 * A slide-out panel that shows detailed information about a module from the registry,
 * with options to enable (built-in) or install (external) the module.
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@ui/sheet";
import {
  Check,
  Cloud,
  Code,
  Copy,
  Database,
  Download,
  ExternalLink,
  FileCode,
  Heart,
  Key,
  Loader2,
  Package,
  Puzzle,
  Sparkles,
  Star,
  Terminal,
  Zap,
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { useEnableModuleDynamic } from "./use-modules";
import { type RegistryModule, getCategoryLabel } from "./types";

// =============================================================================
// Props
// =============================================================================

interface RegistryModuleDrawerProps {
  module: RegistryModule | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onEnableSuccess?: (moduleName: string) => void;
}

// =============================================================================
// Feature Grid
// =============================================================================

function FeatureGrid({ features }: { features: RegistryModule["features"] }) {
  const featureList = [
    {
      key: "files",
      icon: FileCode,
      label: "Config Files",
      description: "Generates configuration files",
    },
    {
      key: "scripts",
      icon: Terminal,
      label: "Shell Scripts",
      description: "Adds shell commands",
    },
    {
      key: "healthchecks",
      icon: Heart,
      label: "Health Checks",
      description: "Monitors module health",
    },
    {
      key: "services",
      icon: Cloud,
      label: "Services",
      description: "Runs background services",
    },
    {
      key: "secrets",
      icon: Key,
      label: "Secrets",
      description: "Manages sensitive data",
    },
    {
      key: "packages",
      icon: Package,
      label: "Packages",
      description: "Adds Nix packages",
    },
    {
      key: "tasks",
      icon: Code,
      label: "Tasks",
      description: "Turbo/build tasks",
    },
  ] as const;

  const activeFeatures = featureList.filter(
    (f) => features[f.key as keyof typeof features],
  );

  if (activeFeatures.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">No features declared</p>
    );
  }

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {activeFeatures.map(({ key, icon: Icon, label, description }) => (
        <div key={key} className="flex items-start gap-3 rounded-lg border p-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10">
            <Icon className="h-4 w-4 text-primary" />
          </div>
          <div>
            <p className="font-medium text-sm">{label}</p>
            <p className="text-xs text-muted-foreground">{description}</p>
          </div>
        </div>
      ))}
    </div>
  );
}

// =============================================================================
// Category Icon
// =============================================================================

function CategoryIcon({ category }: { category: string }) {
  const iconMap: Record<string, typeof Puzzle> = {
    database: Database,
    infrastructure: Cloud,
    development: Code,
    secrets: Key,
    monitoring: Heart,
  };
  const Icon = iconMap[category] || Puzzle;
  return <Icon className="h-5 w-5" />;
}

// =============================================================================
// Install Code Section
// =============================================================================

function InstallCodeSection({ module }: { module: RegistryModule }) {
  const [copied, setCopied] = useState<"flake" | "module" | null>(null);

  const flakeInputCode = `    ${module.id.replace(/-/g, "_")} = {
      url = "${module.flakeUrl}";
      inputs.nixpkgs.follows = "nixpkgs";
    };`;

  const moduleImportCode = `    inputs.${module.id.replace(/-/g, "_")}.${module.flakePath || "stackpanelModules.default"}`;

  const copyToClipboard = async (text: string, type: "flake" | "module") => {
    await navigator.clipboard.writeText(text);
    setCopied(type);
    setTimeout(() => setCopied(null), 2000);
  };

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-medium">1. Add to flake.nix inputs:</h4>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => copyToClipboard(flakeInputCode, "flake")}
          >
            {copied === "flake" ? (
              <Check className="mr-2 h-4 w-4 text-green-500" />
            ) : (
              <Copy className="mr-2 h-4 w-4" />
            )}
            {copied === "flake" ? "Copied!" : "Copy"}
          </Button>
        </div>
        <pre className="overflow-auto rounded-md bg-muted p-3 text-xs">
          {flakeInputCode}
        </pre>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-medium">2. Add to devenv.nix imports:</h4>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => copyToClipboard(moduleImportCode, "module")}
          >
            {copied === "module" ? (
              <Check className="mr-2 h-4 w-4 text-green-500" />
            ) : (
              <Copy className="mr-2 h-4 w-4" />
            )}
            {copied === "module" ? "Copied!" : "Copy"}
          </Button>
        </div>
        <pre className="overflow-auto rounded-md bg-muted p-3 text-xs">
          {moduleImportCode}
        </pre>
      </div>

      <div className="rounded-md border border-yellow-500/30 bg-yellow-500/10 p-3 text-sm">
        <p className="font-medium text-yellow-600 dark:text-yellow-400">
          After adding the code:
        </p>
        <ol className="mt-2 list-inside list-decimal text-muted-foreground">
          <li>
            Run `nix flake lock --update-input {module.id.replace(/-/g, "_")}`
          </li>
          <li>Re-enter your devshell to load the new module</li>
        </ol>
      </div>
    </div>
  );
}

// =============================================================================
// Enable Code Section (for built-in modules)
// =============================================================================

function EnableCodeSection({ module }: { module: RegistryModule }) {
  const [copied, setCopied] = useState(false);
  const enableCode =
    module.flakePath || `stackpanel.modules.${module.id}.enable = true`;

  const copyToClipboard = async () => {
    await navigator.clipboard.writeText(enableCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-medium">Add to your config.nix:</h4>
          <Button variant="ghost" size="sm" onClick={copyToClipboard}>
            {copied ? (
              <Check className="mr-2 h-4 w-4 text-green-500" />
            ) : (
              <Copy className="mr-2 h-4 w-4" />
            )}
            {copied ? "Copied!" : "Copy"}
          </Button>
        </div>
        <pre className="overflow-auto rounded-md bg-muted p-3 text-xs">
          {enableCode}
        </pre>
      </div>
    </div>
  );
}

// =============================================================================
// Main Component
// =============================================================================

export function RegistryModuleDrawer({
  module,
  open,
  onOpenChange,
  onEnableSuccess,
}: RegistryModuleDrawerProps) {
  const enableMutation = useEnableModuleDynamic();
  const [showInstallCode, setShowInstallCode] = useState(false);

  if (!module) return null;

  const handleEnable = async () => {
    try {
      await enableMutation.mutateAsync({ moduleId: module.id, enable: true });
      onEnableSuccess?.(module.meta.name);
      onOpenChange(false);
    } catch (err) {
      console.error("Failed to enable module:", err);
    }
  };

  const isBuiltin = module.builtin;
  const isInstalled = module.installed;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl px-4">
        <SheetHeader className="space-y-4">
          {/* Header with icon and badges */}
          <div className="flex items-start gap-4">
            <div
              className={cn(
                "flex h-12 w-12 items-center justify-center rounded-lg",
                isBuiltin ? "bg-primary/10" : "bg-muted",
              )}
            >
              <CategoryIcon category={module.meta.category} />
            </div>
            <div className="flex-1 space-y-1">
              <div className="flex items-center gap-2 flex-wrap">
                <SheetTitle className="text-xl">{module.meta.name}</SheetTitle>
                {isInstalled && (
                  <Badge
                    variant="outline"
                    className="gap-1 text-xs text-green-600 border-green-600/30 bg-green-500/10"
                  >
                    <Check className="h-3 w-3" />
                    {isBuiltin ? "Enabled" : "Installed"}
                  </Badge>
                )}
                {isBuiltin && !isInstalled && (
                  <Badge
                    variant="default"
                    className="gap-1 text-xs bg-primary/90"
                  >
                    <Sparkles className="h-3 w-3" />
                    Built-in
                  </Badge>
                )}
                {module.meta.version && (
                  <Badge variant="secondary" className="text-xs">
                    v{module.meta.version}
                  </Badge>
                )}
              </div>
              <SheetDescription className="text-sm">
                {module.meta.description}
              </SheetDescription>
            </div>
          </div>

          {/* Stats Row */}
          <div className="flex items-center gap-4 text-sm text-muted-foreground">
            {module.downloads !== undefined && (
              <div className="flex items-center gap-1">
                <Download className="h-4 w-4" />
                <span>{module.downloads.toLocaleString()} downloads</span>
              </div>
            )}
            {module.rating !== undefined && (
              <div className="flex items-center gap-1">
                <Star className="h-4 w-4 fill-yellow-500 text-yellow-500" />
                <span>{module.rating.toFixed(1)}</span>
              </div>
            )}
            <span>{getCategoryLabel(module.meta.category)}</span>
          </div>
        </SheetHeader>

        <div className="mt-6 space-y-6">
          {/* Action Button */}
          {!isInstalled && (
            <div className="flex flex-col gap-3">
              {isBuiltin ? (
                <>
                  <Button
                    size="lg"
                    onClick={handleEnable}
                    disabled={enableMutation.isPending}
                    className="w-full"
                  >
                    {enableMutation.isPending ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Enabling...
                      </>
                    ) : (
                      <>
                        <Zap className="mr-2 h-4 w-4" />
                        Enable Module
                      </>
                    )}
                  </Button>
                  <p className="text-xs text-center text-muted-foreground">
                    This will update your Nix config. Re-enter devshell to
                    apply.
                  </p>
                </>
              ) : (
                <>
                  <Button
                    size="lg"
                    onClick={() => setShowInstallCode(!showInstallCode)}
                    className="w-full"
                  >
                    <Download className="mr-2 h-4 w-4" />
                    {showInstallCode
                      ? "Hide Install Instructions"
                      : "Install Module"}
                  </Button>
                </>
              )}
            </div>
          )}

          {/* Install Code (for external modules) */}
          {!isBuiltin && showInstallCode && (
            <InstallCodeSection module={module} />
          )}

          {/* Features */}
          <div>
            <h3 className="mb-3 text-sm font-semibold">Features</h3>
            <FeatureGrid features={module.features} />
          </div>

          {/* Tags */}
          {module.tags && module.tags.length > 0 && (
            <div>
              <h3 className="mb-3 text-sm font-semibold">Tags</h3>
              <div className="flex flex-wrap gap-2">
                {module.tags.map((tag) => (
                  <Badge key={tag} variant="secondary">
                    {tag}
                  </Badge>
                ))}
              </div>
            </div>
          )}

          {/* Module Info */}
          <div>
            <h3 className="mb-3 text-sm font-semibold">Details</h3>
            <div className="space-y-2 text-sm">
              {module.meta.author && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Author</span>
                  <span>{module.meta.author}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-muted-foreground">Category</span>
                <span>{getCategoryLabel(module.meta.category)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Source</span>
                <span>{isBuiltin ? "Built-in" : "External"}</span>
              </div>
              {!isBuiltin && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Flake URL</span>
                  <code className="text-xs">{module.flakeUrl}</code>
                </div>
              )}
              {module.updatedAt && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Last Updated</span>
                  <span>{new Date(module.updatedAt).toLocaleDateString()}</span>
                </div>
              )}
            </div>
          </div>

          {/* Enable Instructions for built-in (manual option) */}
          {isBuiltin && !isInstalled && (
            <div>
              <h3 className="mb-3 text-sm font-semibold">Manual Enable</h3>
              <p className="text-sm text-muted-foreground mb-3">
                You can also manually add this to your config:
              </p>
              <EnableCodeSection module={module} />
            </div>
          )}

          {/* Homepage Link */}
          {module.meta.homepage && (
            <Button variant="outline" className="w-full" asChild>
              <a
                href={module.meta.homepage}
                target="_blank"
                rel="noopener noreferrer"
              >
                <ExternalLink className="mr-2 h-4 w-4" />
                View Documentation
              </a>
            </Button>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
