"use client";

import React, { useState, useCallback, useRef, useEffect } from "react";
import { Button } from "@ui/button";
import { ButtonGroup, ButtonGroupSeparator } from "@ui/button-group";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import { Badge } from "@ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import {
  Check,
  ChevronDown,
  Copy,
  Info,
  Loader2,
  Play,
  Terminal,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { useExec } from "@/lib/use-agent";

// =============================================================================
// Types
// =============================================================================

export interface CommandRunnerProps {
  /** The command to execute (e.g., "bun", "nix", "stackpanel") */
  command: string;
  /** Arguments to pass to the command */
  args?: string[];
  /** Working directory (relative to project root) */
  cwd?: string;
  /** Environment variables to set */
  env?: Record<string, string>;
  /** Human-readable label for the command (shown in UI) */
  label?: string;
  /** Optional description shown in the dialog header */
  description?: string;
  /** Size variant for buttons */
  size?: "sm" | "default" | "lg" | "icon";
  /** Variant for buttons */
  variant?: "default" | "outline" | "secondary" | "ghost";
  /** Called when execution completes */
  onComplete?: (result: { exitCode: number; stdout: string; stderr: string }) => void;
  /** Called when execution fails */
  onError?: (error: Error) => void;
  /** Whether to show the command text in a code block */
  showCommand?: boolean;
  /** Custom class for the button group */
  className?: string;
  /** Disable the run button */
  disabled?: boolean;
}

export interface CommandRunnerDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  command: string;
  args?: string[];
  cwd?: string;
  env?: Record<string, string>;
  label?: string;
  description?: string;
  /** Auto-run the command when dialog opens */
  autoRun?: boolean;
  onComplete?: (result: { exitCode: number; stdout: string; stderr: string }) => void;
  onError?: (error: Error) => void;
}

// =============================================================================
// Utilities
// =============================================================================

/**
 * Format command + args into a copyable string.
 */
function formatCommand(command: string, args?: string[]): string {
  if (!args || args.length === 0) return command;
  
  // Quote args that have spaces
  const quotedArgs = args.map((arg) =>
    arg.includes(" ") ? `"${arg}"` : arg
  );
  
  return `${command} ${quotedArgs.join(" ")}`;
}

// =============================================================================
// CommandRunnerDialog
// =============================================================================

/**
 * Dialog component that shows command execution output.
 * Can be used standalone or controlled by CommandRunner.
 */
export function CommandRunnerDialog({
  open,
  onOpenChange,
  command,
  args = [],
  cwd,
  env,
  label,
  description,
  autoRun = true,
  onComplete,
  onError,
}: CommandRunnerDialogProps) {
  const outputRef = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState<"idle" | "running" | "success" | "error">("idle");
  const [output, setOutput] = useState<string[]>([]);
  const [exitCode, setExitCode] = useState<number | null>(null);
  const hasRun = useRef(false);

  const exec = useExec();
  const fullCommand = formatCommand(command, args);

  // Auto-scroll to bottom when output changes
  useEffect(() => {
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [output]);

  // Run the command
  const runCommand = useCallback(async () => {
    setStatus("running");
    setOutput([`$ ${fullCommand}`, ""]);
    setExitCode(null);

    try {
      const result = await exec.mutateAsync({
        command,
        args,
        cwd,
        env,
      });

      // Combine stdout and stderr with proper labeling
      const lines: string[] = [];
      
      if (result.stdout) {
        lines.push(...result.stdout.split("\n"));
      }
      
      if (result.stderr) {
        // Add stderr with dim styling hint (we'll style it in the render)
        lines.push("", "--- stderr ---");
        lines.push(...result.stderr.split("\n"));
      }

      setOutput((prev) => [...prev, ...lines]);
      setExitCode(result.exitCode);
      setStatus(result.exitCode === 0 ? "success" : "error");

      onComplete?.({
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      });

      if (result.exitCode === 0) {
        toast.success(`Command completed successfully`);
      } else {
        toast.error(`Command failed with exit code ${result.exitCode}`);
      }
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      setOutput((prev) => [...prev, "", `Error: ${error.message}`]);
      setStatus("error");
      onError?.(error);
      toast.error(`Failed to execute command: ${error.message}`);
    }
  }, [exec, command, args, cwd, env, fullCommand, onComplete, onError]);

  // Auto-run on open
  useEffect(() => {
    if (open && autoRun && !hasRun.current) {
      hasRun.current = true;
      runCommand();
    }
    
    // Reset when dialog closes
    if (!open) {
      hasRun.current = false;
      setStatus("idle");
      setOutput([]);
      setExitCode(null);
    }
  }, [open, autoRun, runCommand]);

  // Copy output to clipboard
  const copyOutput = () => {
    navigator.clipboard.writeText(output.join("\n"));
    toast.success("Output copied to clipboard");
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Terminal className="h-5 w-5" />
            {label || "Run Command"}
            {status === "running" && (
              <Badge variant="outline" className="ml-2 text-xs border-blue-500/30 text-blue-500">
                <Loader2 className="mr-1 h-3 w-3 animate-spin" />
                Running
              </Badge>
            )}
            {status === "success" && (
              <Badge variant="outline" className="ml-2 text-xs border-emerald-500/30 text-emerald-500">
                <Check className="mr-1 h-3 w-3" />
                Success
              </Badge>
            )}
            {status === "error" && (
              <Badge variant="outline" className="ml-2 text-xs border-red-500/30 text-red-500">
                <X className="mr-1 h-3 w-3" />
                Failed{exitCode !== null && ` (${exitCode})`}
              </Badge>
            )}
          </DialogTitle>
          {description && (
            <DialogDescription>{description}</DialogDescription>
          )}
        </DialogHeader>

        {/* Command preview */}
        <div className="flex items-center gap-2 bg-muted/50 rounded-lg px-3 py-2 font-mono text-sm">
          <span className="text-muted-foreground">$</span>
          <code className="flex-1 truncate">{fullCommand}</code>
          <Button
            variant="ghost"
            size="icon"
            className="h-6 w-6"
            onClick={() => {
              navigator.clipboard.writeText(fullCommand);
              toast.success("Command copied");
            }}
          >
            <Copy className="h-3 w-3" />
          </Button>
        </div>

        {/* Output container */}
        <div
          ref={outputRef}
          className="flex-1 overflow-auto bg-black/90 rounded-lg p-4 font-mono text-xs min-h-[200px] max-h-[400px]"
        >
          {output.length === 0 && status === "idle" ? (
            <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
              <Terminal className="h-8 w-8 mb-2" />
              <p>Ready to execute</p>
              <Button
                variant="outline"
                size="sm"
                className="mt-4"
                onClick={runCommand}
              >
                <Play className="mr-2 h-4 w-4" />
                Run Command
              </Button>
            </div>
          ) : (
            <pre className="whitespace-pre-wrap break-all">
              {output.map((line, i) => (
                <div
                  key={i}
                  className={cn(
                    "px-1 -mx-1",
                    // Style the command line
                    line.startsWith("$") && "text-cyan-400",
                    // Style stderr section
                    line.includes("stderr") && "text-muted-foreground",
                    // Style errors
                    line.startsWith("Error:") && "text-red-400",
                    // Default output color
                    !line.startsWith("$") && !line.includes("stderr") && !line.startsWith("Error:") && "text-green-400"
                  )}
                >
                  {line}
                </div>
              ))}
              {status === "running" && (
                <span className="inline-block w-2 h-4 bg-green-400 animate-pulse" />
              )}
            </pre>
          )}
        </div>

        {/* Footer actions */}
        <div className="flex items-center justify-between pt-2 border-t">
          <div className="text-xs text-muted-foreground">
            {cwd && <span>cwd: {cwd}</span>}
          </div>
          <div className="flex items-center gap-2">
            {output.length > 0 && (
              <Button variant="outline" size="sm" onClick={copyOutput}>
                <Copy className="mr-2 h-4 w-4" />
                Copy Output
              </Button>
            )}
            {status !== "running" && (
              <Button
                variant={status === "error" ? "default" : "outline"}
                size="sm"
                onClick={runCommand}
              >
                <Play className="mr-2 h-4 w-4" />
                {status === "idle" ? "Run" : "Run Again"}
              </Button>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// =============================================================================
// CommandRunner
// =============================================================================

/**
 * A split button with popover for running shell commands from the UI.
 * 
 * Features:
 * - Main "Run" button opens a popover with options
 * - Copy button to copy the command to clipboard
 * - Execute button that runs the command in a dialog
 * - Clear disclaimer about UI execution reliability
 * 
 * @example
 * ```tsx
 * <CommandRunner
 *   command="bun"
 *   args={["run", "build"]}
 *   label="Build"
 * />
 * 
 * // With custom options
 * <CommandRunner
 *   command="nix"
 *   args={["develop", "--impure"]}
 *   cwd="."
 *   label="Enter Devshell"
 *   description="Start a new development shell"
 *   size="sm"
 *   variant="outline"
 *   onComplete={(result) => console.log("Done:", result)}
 * />
 * ```
 */
export function CommandRunner({
  command,
  args = [],
  cwd,
  env,
  label,
  description,
  size = "sm",
  variant = "outline",
  onComplete,
  onError,
  showCommand = false,
  className,
  disabled = false,
}: CommandRunnerProps) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [popoverOpen, setPopoverOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const fullCommand = formatCommand(command, args);

  // Copy command to clipboard
  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(fullCommand);
    setCopied(true);
    toast.success("Command copied to clipboard");
    setTimeout(() => setCopied(false), 2000);
  }, [fullCommand]);

  // Open dialog to run command
  const handleRun = useCallback(() => {
    setPopoverOpen(false);
    setDialogOpen(true);
  }, []);

  return (
    <>
      <div className={cn("flex items-center gap-2", className)}>
        {showCommand && (
          <code className="text-xs bg-muted px-2 py-1 rounded font-mono truncate max-w-[200px]">
            {fullCommand}
          </code>
        )}
        
        <Popover open={popoverOpen} onOpenChange={setPopoverOpen}>
          <PopoverTrigger asChild>
            <ButtonGroup>
              <Button
                variant={variant}
                size={size}
                disabled={disabled}
                className="gap-1.5"
              >
                <Terminal className="h-3.5 w-3.5" />
                {label || "Run"}
              </Button>
              <ButtonGroupSeparator />
              <Button
                variant={variant}
                size={size}
                disabled={disabled}
                className="px-1.5"
              >
                <ChevronDown className="h-3.5 w-3.5" />
              </Button>
            </ButtonGroup>
          </PopoverTrigger>
          <PopoverContent align="end" className="w-80">
            <div className="space-y-3">
              {/* Command preview */}
              <div>
                <div className="text-xs font-medium text-muted-foreground mb-1.5">
                  Command
                </div>
                <div className="flex items-center gap-2 bg-muted/50 rounded-md px-3 py-2 font-mono text-xs">
                  <span className="text-muted-foreground">$</span>
                  <code className="flex-1 truncate">{fullCommand}</code>
                </div>
              </div>

              {/* Description if provided */}
              {description && (
                <p className="text-xs text-muted-foreground">{description}</p>
              )}

              {/* Actions */}
              <div className="space-y-2">
                {/* Copy action */}
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleCopy}
                  className="w-full justify-start gap-2"
                >
                  {copied ? (
                    <Check className="h-4 w-4 text-emerald-500" />
                  ) : (
                    <Copy className="h-4 w-4" />
                  )}
                  {copied ? "Copied!" : "Copy to clipboard"}
                </Button>

                {/* Execute action */}
                <Button
                  variant="default"
                  size="sm"
                  onClick={handleRun}
                  className="w-full justify-start gap-2"
                >
                  <Play className="h-4 w-4" />
                  Execute in UI
                </Button>
              </div>

              {/* Disclaimer */}
              <div className="flex gap-2 rounded-md bg-amber-500/10 border border-amber-500/20 p-2">
                <Info className="h-4 w-4 text-amber-500 shrink-0 mt-0.5" />
                <p className="text-[11px] text-amber-700 dark:text-amber-300 leading-relaxed">
                  For best results, copy and run in your terminal. UI execution 
                  may not handle all interactive commands reliably.
                </p>
              </div>
            </div>
          </PopoverContent>
        </Popover>
      </div>

      <CommandRunnerDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        command={command}
        args={args}
        cwd={cwd}
        env={env}
        label={label}
        description={description}
        onComplete={onComplete}
        onError={onError}
      />
    </>
  );
}

// =============================================================================
// CommandRunnerDropdown (for multiple commands)
// =============================================================================

export interface CommandOption {
  id: string;
  command: string;
  args?: string[];
  cwd?: string;
  env?: Record<string, string>;
  label: string;
  description?: string;
}

export interface CommandRunnerDropdownProps {
  commands: CommandOption[];
  /** Label for the dropdown button */
  label?: string;
  size?: "sm" | "default" | "lg";
  variant?: "default" | "outline" | "secondary" | "ghost";
  className?: string;
  disabled?: boolean;
}

/**
 * A dropdown variant that allows choosing from multiple commands.
 * 
 * @example
 * ```tsx
 * <CommandRunnerDropdown
 *   label="Actions"
 *   commands={[
 *     { id: "build", command: "bun", args: ["run", "build"], label: "Build" },
 *     { id: "test", command: "bun", args: ["test"], label: "Test" },
 *     { id: "lint", command: "bun", args: ["run", "lint"], label: "Lint" },
 *   ]}
 * />
 * ```
 */
export function CommandRunnerDropdown({
  commands,
  label = "Run",
  size = "sm",
  variant = "outline",
  className,
  disabled = false,
}: CommandRunnerDropdownProps) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [selectedCommand, setSelectedCommand] = useState<CommandOption | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);

  const handleSelect = useCallback((cmd: CommandOption) => {
    setSelectedCommand(cmd);
    setMenuOpen(false);
    setDialogOpen(true);
  }, []);

  return (
    <>
      <div className={cn("relative", className)}>
        <Button
          variant={variant}
          size={size}
          onClick={() => setMenuOpen(!menuOpen)}
          disabled={disabled}
          className="gap-1.5"
        >
          <Play className="h-3.5 w-3.5" />
          {label}
          <ChevronDown className="h-3.5 w-3.5 ml-1" />
        </Button>

        {menuOpen && (
          <>
            {/* Backdrop to close menu */}
            <div
              className="fixed inset-0 z-40"
              onClick={() => setMenuOpen(false)}
            />
            
            {/* Menu */}
            <div className="absolute right-0 top-full mt-1 z-50 min-w-[180px] rounded-md border bg-popover p-1 shadow-md">
              {commands.map((cmd) => (
                <button
                  key={cmd.id}
                  type="button"
                  onClick={() => handleSelect(cmd)}
                  className="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent hover:text-accent-foreground cursor-pointer"
                >
                  <Terminal className="h-3.5 w-3.5" />
                  {cmd.label}
                </button>
              ))}
            </div>
          </>
        )}
      </div>

      {selectedCommand && (
        <CommandRunnerDialog
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          command={selectedCommand.command}
          args={selectedCommand.args}
          cwd={selectedCommand.cwd}
          env={selectedCommand.env}
          label={selectedCommand.label}
          description={selectedCommand.description}
        />
      )}
    </>
  );
}
