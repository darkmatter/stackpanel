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
import { ScrollArea } from "@ui/scroll-area";
import { Check, Code2, Copy, FileCode } from "lucide-react";
import { useState } from "react";

interface YamlPreviewDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  yaml: string;
  onShowNix?: () => void;
}

export function YamlPreviewDialog({
  open,
  onOpenChange,
  yaml,
  onShowNix,
}: YamlPreviewDialogProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(yaml);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileCode className="h-5 w-5" />
            Process Compose YAML Preview
          </DialogTitle>
          <DialogDescription>
            This is the process-compose.yaml that will be generated from your configuration.
          </DialogDescription>
        </DialogHeader>

        <div className="rounded-lg bg-accent/10 p-3 text-sm">
          <span className="text-muted-foreground">Note: </span>
          This YAML is generated at build time by the Nix configuration. Click{" "}
          <strong>Save & Rebuild</strong> in the main panel to apply your changes.
        </div>

        <ScrollArea className="h-[400px] w-full rounded-lg border bg-secondary/30 overflow-hidden">
          <div className="p-4 overflow-x-auto">
            <pre className="text-sm whitespace-pre-wrap break-words overflow-wrap-anywhere" style={{ wordBreak: 'break-word' }}>
              <code className="language-yaml">{yaml}</code>
            </pre>
          </div>
        </ScrollArea>

        <DialogFooter className="flex-col sm:flex-row gap-2">
          {onShowNix && (
            <Button variant="outline" onClick={onShowNix} className="sm:mr-auto">
              <Code2 className="mr-2 h-4 w-4" />
              Show Nix Config
            </Button>
          )}
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
