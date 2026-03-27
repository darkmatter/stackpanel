"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Copy, Key, Trash2 } from "lucide-react";

export interface Recipient {
  name: string;
  publicKey: string;
  source?: string;
  tags?: string[];
  canDelete?: boolean;
}

interface RecipientItemProps {
  recipient: Recipient;
  onCopy: (key: string) => void;
  onRemove: (name: string) => void;
}

export function RecipientItem({
  recipient,
  onCopy,
  onRemove,
}: RecipientItemProps) {
  return (
    <div className="flex items-center justify-between rounded-md border px-3 py-2">
      <div className="flex items-center gap-2 min-w-0">
        <Key className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-sm font-medium leading-none">
              {recipient.name}
            </span>
            {recipient.source && (
              <Badge variant="outline" className="h-5 px-1.5">
                {recipient.source === "secrets" ? "config" : "users"}
              </Badge>
            )}
            {(recipient.tags ?? []).map((tag) => (
              <Badge
                key={`${recipient.name}-${tag}`}
                variant="secondary"
                className="h-5 px-1.5"
              >
                {tag}
              </Badge>
            ))}
          </div>
          <p className="mt-1 text-[11px] text-muted-foreground font-mono truncate">
            {clipPublicKey(recipient.publicKey)}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-1 shrink-0">
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          onClick={() => onCopy(recipient.publicKey)}
        >
          <Copy className="h-3.5 w-3.5" />
        </Button>
        {recipient.canDelete ? (
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive hover:text-destructive"
            onClick={() => onRemove(recipient.name)}
          >
            <Trash2 className="h-3.5 w-3.5" />
          </Button>
        ) : null}
      </div>
    </div>
  );
}

export function clipPublicKey(pub: string) {
  if (pub.length > 120) {
    return `${pub.slice(0, 60)}...${pub.slice(-60)}`;
  }
  return pub;
}
