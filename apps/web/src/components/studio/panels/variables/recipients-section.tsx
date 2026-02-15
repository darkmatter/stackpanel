import { useState } from "react";
import { toast } from "sonner";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
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
import {
  Copy,
  Info,
  Key,
  Loader2,
  Plus,
  Trash2,
  Users,
  CheckCircle2,
  XCircle,
  GitBranch,
} from "lucide-react";
import {
  useRecipients,
  useAddRecipient,
  useRemoveRecipient,
  useRekeyWorkflowStatus,
} from "@/lib/use-agent";

export function RecipientsSection() {
  const { data: recipients, isLoading } = useRecipients();
  const { data: workflowStatus } = useRekeyWorkflowStatus();
  const addRecipient = useAddRecipient();
  const removeRecipient = useRemoveRecipient();

  const [showAddForm, setShowAddForm] = useState(false);
  const [name, setName] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const [keyType, setKeyType] = useState<"age" | "ssh">("age");
  const [confirmRemove, setConfirmRemove] = useState<string | null>(null);

  const handleAdd = async () => {
    if (!name.trim() || !publicKey.trim()) {
      toast.error("Name and public key are required");
      return;
    }

    try {
      await addRecipient.mutateAsync({
        name: name.trim(),
        publicKey: keyType === "age" ? publicKey.trim() : undefined,
        sshPublicKey: keyType === "ssh" ? publicKey.trim() : undefined,
      });
      toast.success(`Added recipient "${name.trim()}"`);
      setName("");
      setPublicKey("");
      setShowAddForm(false);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to add recipient",
      );
    }
  };

  const handleRemove = async (recipientName: string) => {
    try {
      await removeRecipient.mutateAsync(recipientName);
      toast.success(`Removed recipient "${recipientName}"`);
      setConfirmRemove(null);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to remove recipient",
      );
    }
  };

  const copyKey = (key: string) => {
    navigator.clipboard.writeText(key);
    toast.success("Public key copied");
  };

  const recipientList = recipients?.recipients ?? [];

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
            <Card className="border-dashed">
              <CardContent className="space-y-3 pt-4">
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="recipient-name">Name</Label>
                    <Input
                      id="recipient-name"
                      placeholder="e.g. alice"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label>Key type</Label>
                    <Select
                      value={keyType}
                      onValueChange={(v) => setKeyType(v as "age" | "ssh")}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="age">AGE public key</SelectItem>
                        <SelectItem value="ssh">
                          SSH public key (converted via ssh-to-age)
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="recipient-key">Public key</Label>
                  <Input
                    id="recipient-key"
                    placeholder={
                      keyType === "age"
                        ? "age1..."
                        : "ssh-ed25519 AAAA... or ssh-rsa AAAA..."
                    }
                    value={publicKey}
                    onChange={(e) => setPublicKey(e.target.value)}
                    className="font-mono text-xs"
                  />
                </div>
                <div className="flex justify-end gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowAddForm(false)}
                  >
                    Cancel
                  </Button>
                  <Button
                    size="sm"
                    onClick={handleAdd}
                    disabled={addRecipient.isPending}
                  >
                    {addRecipient.isPending ? (
                      <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Key className="mr-1 h-3.5 w-3.5" />
                    )}
                    Add recipient
                  </Button>
                </div>
              </CardContent>
            </Card>
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
                Recipients are auto-registered when team members enter the
                devshell
              </p>
            </div>
          ) : (
            <div className="space-y-2">
              {recipientList.map((recipient) => (
                <div
                  key={recipient.name}
                  className="flex items-center justify-between rounded-md border px-3 py-2"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <Key className="h-4 w-4 shrink-0 text-muted-foreground" />
                    <div className="min-w-0">
                      <span className="text-sm font-medium">
                        {recipient.name}
                      </span>
                      <p className="text-xs text-muted-foreground font-mono truncate">
                        {recipient.publicKey}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7"
                      onClick={() => copyKey(recipient.publicKey)}
                    >
                      <Copy className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7 text-destructive hover:text-destructive"
                      onClick={() => setConfirmRemove(recipient.name)}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Rekey workflow status */}
          {workflowStatus && (
            <div className="rounded-md border px-3 py-2">
              <div className="flex items-center gap-2 text-sm">
                <GitBranch className="h-4 w-4 text-muted-foreground" />
                <span className="font-medium">Rekey Workflow</span>
                {workflowStatus.exists ? (
                  <span className="flex items-center gap-1 text-xs text-green-600">
                    <CheckCircle2 className="h-3.5 w-3.5" />
                    Installed
                  </span>
                ) : (
                  <span className="flex items-center gap-1 text-xs text-muted-foreground">
                    <XCircle className="h-3.5 w-3.5" />
                    Not installed
                  </span>
                )}
              </div>
              {!workflowStatus.exists && (
                <p className="text-xs text-muted-foreground mt-1 ml-6">
                  Run <code>secrets:init-group</code> to generate the GitHub
                  Actions rekey workflow
                </p>
              )}
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
                  New team members automatically register their AGE public key
                  when they enter the devshell. When they push the key file, the
                  GitHub Actions rekey workflow re-encrypts secrets for all
                  recipients.
                </p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Remove confirmation dialog */}
      <AlertDialog
        open={confirmRemove !== null}
        onOpenChange={(open) => !open && setConfirmRemove(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove recipient</AlertDialogTitle>
            <AlertDialogDescription>
              Remove <strong>{confirmRemove}</strong> from the recipients list?
              They will no longer be able to decrypt secrets after the next
              rekey.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => confirmRemove && handleRemove(confirmRemove)}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {removeRecipient.isPending ? (
                <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
              ) : null}
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
