"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Trash2, type LucideIcon } from "lucide-react";

export type KeySourceType = "user-key-path" | "repo-key-path" | "file" | "op-ref";

export interface KeySource {
  type: KeySourceType;
  value: string;
  enabled?: boolean;
  name?: string | null;
}

interface KeySourceItemProps {
  source: KeySource;
  index: number;
  meta: {
    label: string;
    placeholder: string;
    icon: LucideIcon;
  };
  onUpdate: (index: number, patch: Partial<KeySource>) => void;
  onRemove: (index: number) => void;
}

export function KeySourceItem({
  source,
  index,
  meta,
  onUpdate,
  onRemove,
}: KeySourceItemProps) {
  const Icon = meta.icon;

  return (
    <div className="rounded-lg border bg-card px-3 py-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2 min-w-0">
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-muted">
            <Icon className="h-4 w-4 text-muted-foreground" />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium">
                {source.name || meta.label}
              </span>
              <Badge variant="outline" className="h-5 px-1.5">
                {meta.label}
              </Badge>
            </div>
          </div>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 text-destructive"
          onClick={() => onRemove(index)}
        >
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      </div>
      <div className="mt-3 grid gap-2">
        <Input
          value={source.name ?? ""}
          onChange={(e) => onUpdate(index, { name: e.target.value })}
          placeholder={meta.label}
        />
        <Input
          value={source.value}
          onChange={(e) => onUpdate(index, { value: e.target.value })}
          placeholder={meta.placeholder}
          className="font-mono text-sm"
        />
      </div>
    </div>
  );
}
