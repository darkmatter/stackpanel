"use client";

import { useState } from "react";
import { ChevronDown, ChevronRight, Terminal, Package } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { Command } from "@/lib/types";

interface AppCommandsProps {
  /** Commands linked to this app (map of command name to Command) */
  commands: Record<string, Command> | undefined;
}

/**
 * Component to display linked commands for an app.
 * Commands use the proto Command shape with package, bin, args, etc.
 */
export function AppCommands({ commands }: AppCommandsProps) {
  const [isOpen, setIsOpen] = useState(false);

  const commandEntries = Object.entries(commands ?? {});

  if (commandEntries.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">No commands linked</span>
    );
  }

  /**
   * Build a display string for the command
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

  return (
    <div>
      <Button
        variant="ghost"
        size="sm"
        className="h-auto gap-1 p-1 text-xs"
        onClick={() => setIsOpen(!isOpen)}
      >
        {isOpen ? (
          <ChevronDown className="h-3 w-3" />
        ) : (
          <ChevronRight className="h-3 w-3" />
        )}
        <Terminal className="h-3 w-3 text-accent" />
        <span>
          {commandEntries.length} command
          {commandEntries.length !== 1 ? "s" : ""}
        </span>
      </Button>
      {isOpen && (
        <div className="mt-2 space-y-1">
          {commandEntries.map(([cmdName, cmd]) => (
            <div
              key={cmdName}
              className="flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
            >
              <Terminal className="h-3 w-3 text-muted-foreground" />
              <span className="font-medium">{cmdName}</span>
              <div className="flex items-center gap-1 text-muted-foreground">
                <Package className="h-3 w-3" />
                <span>{cmd.package}</span>
              </div>
              {cmd.args.length > 0 && (
                <code className="ml-auto rounded bg-muted px-1 py-0.5 text-[10px] text-muted-foreground truncate max-w-40">
                  {getCommandString(cmd)}
                </code>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
