"use client";

import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { ScrollArea } from "@ui/scroll-area";
import { Check, Copy, FileCode } from "lucide-react";
import { useState } from "react";
import type { GeneratedNixConfig, NixOutputFormat } from "./types";

interface NixOutputDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  generateNix: (format?: NixOutputFormat) => GeneratedNixConfig;
}

export function NixOutputDialog({
  open,
  onOpenChange,
  generateNix,
}: NixOutputDialogProps) {
  const [format, setFormat] = useState<NixOutputFormat>("partial");
  const [copied, setCopied] = useState(false);

  const config = generateNix(format);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(config.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileCode className="h-5 w-5" />
            Generated Nix Configuration
          </DialogTitle>
          <DialogDescription>
            Copy this Nix expression to configure process-compose in your project.
          </DialogDescription>
        </DialogHeader>

        <div className="flex items-center gap-4 py-2">
          <span className="text-sm text-muted-foreground">Format:</span>
          <Select value={format} onValueChange={(v) => setFormat(v as NixOutputFormat)}>
            <SelectTrigger className="w-[200px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="partial">
                Partial (for .stackpanel/gen/)
              </SelectItem>
              <SelectItem value="inline">
                Inline (paste into config)
              </SelectItem>
              <SelectItem value="full">
                Full Module
              </SelectItem>
            </SelectContent>
          </Select>
        </div>

        {config.partialPath && (
          <div className="rounded-lg bg-accent/10 p-3 text-sm">
            <span className="text-muted-foreground">Output path: </span>
            <code className="text-accent">{config.partialPath}</code>
          </div>
        )}

        <ScrollArea className="h-[400px] w-full rounded-lg border bg-secondary/30 overflow-hidden">
          <div className="p-4 overflow-x-auto">
            <pre className="text-sm whitespace-pre-wrap break-words overflow-wrap-anywhere" style={{ wordBreak: 'break-word' }}>
              <code className="language-nix">{config.content}</code>
            </pre>
          </div>
        </ScrollArea>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          <Button onClick={handleCopy} className="gap-2">
            {copied ? (
              <>
                <Check className="h-4 w-4" />
                Copied!
              </>
            ) : (
              <>
                <Copy className="h-4 w-4" />
                Copy to Clipboard
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
