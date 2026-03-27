"use client";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Loader2 } from "lucide-react";

interface RemoveRecipientDialogProps {
  recipientName: string | null;
  onOpenChange: (open: boolean) => void;
  onConfirm: (name: string) => Promise<void>;
  isPending: boolean;
}

export function RemoveRecipientDialog({
  recipientName,
  onOpenChange,
  onConfirm,
  isPending,
}: RemoveRecipientDialogProps) {
  return (
    <AlertDialog
      open={recipientName !== null}
      onOpenChange={onOpenChange}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Remove recipient</AlertDialogTitle>
          <AlertDialogDescription>
            Remove <strong>{recipientName}</strong> from the recipients list?
            This removes the entry from{" "}
            <code>stackpanel.secrets.recipients</code>. They will no longer be
            able to decrypt secrets after the next rekey.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isPending}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={() => recipientName && onConfirm(recipientName)}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            disabled={isPending}
          >
            {isPending && <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />}
            Remove
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
