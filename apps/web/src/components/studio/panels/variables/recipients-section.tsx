"use client";

import { useEffect, useState, useMemo } from "react";
import { toast } from "sonner";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Info, Loader2, Plus, Users } from "lucide-react";
import {
  useRecipients,
  useAddRecipient,
  useRemoveRecipient,
} from "@/lib/use-agent";
import { mergeRecipients, useSopsUiOptimisticState } from "./sops-ui-state";
import { AddRecipientForm } from "./components/add-recipient-form";
import { RecipientItem } from "./components/recipient-item";
import { RemoveRecipientDialog } from "./components/remove-recipient-dialog";

export function RecipientsSection() {
  const { data: recipients, isLoading } = useRecipients();
  const addRecipient = useAddRecipient();
  const removeRecipient = useRemoveRecipient();
  const { optimisticRecipients, update, clearIfSynced } =
    useSopsUiOptimisticState();

  const [showAddForm, setShowAddForm] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState<string | null>(null);

  const recipientList = mergeRecipients(
    recipients?.recipients ?? [],
    optimisticRecipients,
  );

  const knownTags = useMemo(
    () =>
      Array.from(
        new Set(recipientList.flatMap((recipient) => recipient.tags ?? [])),
      ).sort((a, b) => a.localeCompare(b)),
    [recipientList],
  );

  useEffect(() => {
    clearIfSynced(recipients?.recipients ?? [], undefined);
  }, [clearIfSynced, recipients]);

  const handleAdd = async (data: {
    name: string;
    publicKey: string;
    keyType: "age" | "ssh";
    tags: string[];
  }) => {
    const { name, publicKey, keyType, tags } = data;

    if (!name.trim() || !publicKey.trim()) {
      toast.error("Name and public key are required");
      return;
    }

    if (tags.length === 0) {
      toast.error("Add at least one tag");
      return;
    }

    const optimisticRecipient = {
      name: name.trim(),
      publicKey: publicKey.trim(),
      tags,
      source: "secrets" as const,
      canDelete: true,
    };

    update({ recipients: [...recipientList, optimisticRecipient] });

    try {
      await addRecipient.mutateAsync({
        name: name.trim(),
        publicKey: keyType === "age" ? publicKey.trim() : undefined,
        sshPublicKey: keyType === "ssh" ? publicKey.trim() : undefined,
        tags,
      });
      toast.success(`Added recipient "${name.trim()}"`);
      setShowAddForm(false);
    } catch (err) {
      update({ recipients: recipientList });
      toast.error(
        err instanceof Error ? err.message : "Failed to add recipient",
      );
    }
  };

  const handleRemove = async (recipientName: string) => {
    update({
      recipients: recipientList.filter(
        (recipient) => recipient.name !== recipientName,
      ),
    });
    try {
      await removeRecipient.mutateAsync(recipientName);
      toast.success(`Removed recipient "${recipientName}"`);
      setConfirmRemove(null);
    } catch (err) {
      update({ recipients: recipientList });
      toast.error(
        err instanceof Error ? err.message : "Failed to remove recipient",
      );
    }
  };

  const copyKey = (key: string) => {
    navigator.clipboard.writeText(key);
    toast.success("Public key copied");
  };

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Users className="h-5 w-5 text-muted-foreground" />
              <div>
                <CardTitle className="text-base">Recipients</CardTitle>
                <CardDescription>
                  Team members who can decrypt secrets
                </CardDescription>
              </div>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowAddForm(!showAddForm)}
            >
              <Plus className="mr-1 h-3.5 w-3.5" />
              Add
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Add recipient form */}
          {showAddForm && (
            <AddRecipientForm
              onAdd={handleAdd}
              isPending={addRecipient.isPending}
              knownTags={knownTags}
              onCancel={() => setShowAddForm(false)}
            />
          )}

          {/* Recipients list */}
          {isLoading ? (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              Loading recipients...
            </div>
          ) : recipientList.length === 0 ? (
            <div className="text-center py-6 text-sm text-muted-foreground">
              <Users className="mx-auto mb-2 h-8 w-8 opacity-50" />
              <p>No recipients yet</p>
              <p className="text-xs mt-1">
                Add recipients in Nix config under{" "}
                <code>stackpanel.secrets.recipients</code>
              </p>
            </div>
          ) : (
            <div className="space-y-1.5">
              {recipientList.map((recipient) => (
                <RecipientItem
                  key={recipient.name}
                  recipient={recipient}
                  onCopy={copyKey}
                  onRemove={setConfirmRemove}
                />
              ))}
            </div>
          )}

          {/* Info box */}
          <div className="rounded-md bg-muted/50 p-3">
            <div className="flex items-start gap-2 text-xs text-muted-foreground">
              <Info className="h-4 w-4 shrink-0 mt-0.5" />
              <div>
                <p className="font-medium text-foreground">
                  Self-service onboarding
                </p>
                <p className="mt-1">
                  Add/remove here writes{" "}
                  <code>stackpanel.secrets.recipients</code> in
                  <code>.stack/config.nix</code>. Re-enter the devshell to
                  regenerate
                  <code>.stack/secrets/.sops.yaml</code>, then run{" "}
                  <code>.stack/secrets/bin/rekey.sh</code>.
                </p>
                <p className="mt-1">
                  Recipients marked <code>users</code> are derived from{" "}
                  <code>stackpanel.users</code>
                  and must be changed there.
                </p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Remove confirmation dialog */}
      <RemoveRecipientDialog
        recipientName={confirmRemove}
        onOpenChange={(open) => !open && setConfirmRemove(null)}
        onConfirm={handleRemove}
        isPending={removeRecipient.isPending}
      />
    </div>
  );
}

export { clipPublicKey } from "./components/recipient-item";
