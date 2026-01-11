"use client";

import { useState } from "react";
import { ChevronDown, ChevronRight, Play } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { AppTask } from "@/lib/types";

interface AppTasksProps {
  /** Tasks linked to this app (map of task name to AppTask) */
  tasks: Record<string, AppTask> | undefined;
}

/**
 * Component to display linked tasks for an app
 */
export function AppTasks({ tasks }: AppTasksProps) {
  const [isOpen, setIsOpen] = useState(false);

  const taskEntries = Object.entries(tasks ?? {});

  if (taskEntries.length === 0) {
    return (
      <span className="text-muted-foreground text-xs">No tasks linked</span>
    );
  }

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
        <Play className="h-3 w-3 text-accent" />
        <span>
          {taskEntries.length} task{taskEntries.length !== 1 ? "s" : ""}
        </span>
      </Button>
      {isOpen && (
        <div className="mt-2 space-y-1">
          {taskEntries.map(([taskName, task]) => (
            <div
              key={taskName}
              className="flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
            >
              <Play className="h-3 w-3 text-muted-foreground" />
              <span className="font-medium">{task.key || taskName}</span>
              {task.description && (
                <span className="text-muted-foreground">
                  - {task.description}
                </span>
              )}
              {task.command && (
                <code className="ml-auto rounded bg-muted px-1 py-0.5 text-[10px] text-muted-foreground">
                  {task.command}
                </code>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
