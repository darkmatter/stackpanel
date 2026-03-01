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
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ui/select";
import { Textarea } from "@ui/textarea";
import { Eye, EyeOff, Key, Loader2, Settings, Shield } from "lucide-react";
import { useEditSecretDialog } from "./edit-secret-dialog/use-edit-secret-dialog";
import type { EditSecretDialogProps } from "./edit-secret-dialog/types";

// Re-export standalone components
export { AgeIdentitySettings } from "./edit-secret-dialog/age-identity-settings";
export { KMSSettings } from "./edit-secret-dialog/kms-settings";

export function EditSecretDialog({
  secretId,
  secretKey,
  group: initialGroup,
  description,
  open,
  onOpenChange,
  onSuccess,
}: EditSecretDialogProps) {
  const {
    // State
    isLoading,
    isSaving,
    showValue,
    setShowValue,
    value,
    setValue,
    newDescription,
    setNewDescription,
    group,
    setGroup,
    availableGroups,
    identityPath,
    setIdentityPath,
    showSettings,
    setShowSettings,
    decryptError,
    isChamber,
    useGroupSecrets,

    // Handlers
    handleSave,
    handleRetryDecrypt,
  } = useEditSecretDialog({
    secretId,
    secretKey,
    group: initialGroup,
    description,
    open,
    onOpenChange,
    onSuccess,
  });

  // Build the SOPS file path preview
  const sopsFilePreview = useGroupSecrets
    ? `.stackpanel/secrets/vars/${group}.sops.yaml`
    : null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Key className="h-5 w-5" />
            Edit Secret
          </DialogTitle>
          <DialogDescription>
            <code className="text-sm font-mono bg-muted px-1.5 py-0.5 rounded">
              {secretKey}
            </code>
          </DialogDescription>
        </DialogHeader>

        {/* Group Selector (for group-based secrets) */}
        {useGroupSecrets && (
          <div className="border rounded-lg p-3 bg-muted/30">
            <div className="flex items-center gap-2 mb-2">
              <Shield className="h-4 w-4" />
              <span className="text-sm font-medium">Access Control Group</span>
            </div>
            <Select value={group} onValueChange={setGroup}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Select a group" />
              </SelectTrigger>
              <SelectContent>
                {(availableGroups.length > 0
                  ? availableGroups
                  : ["dev", "staging", "prod", "common"]
                ).map((g) => (
                  <SelectItem key={g} value={g}>
                    {g}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground mt-2">
              Secrets are encrypted per group. Only users with access to this
              group's keys can decrypt.
            </p>
            {sopsFilePreview && (
              <div className="mt-2 p-2 bg-muted rounded text-xs font-mono break-all">
                <span className="text-muted-foreground">SOPS file: </span>
                {sopsFilePreview}
              </div>
            )}
          </div>
        )}

        {/* Settings Panel (vals/SOPS backend only — chamber uses AWS credentials) */}
        {!isChamber && (
          <div className="border rounded-lg p-3 bg-muted/30">
            <button
              type="button"
              onClick={() => setShowSettings(!showSettings)}
              className="flex items-center gap-2 text-sm font-medium w-full"
            >
              <Settings className="h-4 w-4" />
              Private Key Configuration
              <span className="ml-auto text-xs text-muted-foreground">
                {identityPath || "Using default location"}
              </span>
            </button>

            {showSettings && (
              <div className="mt-3 space-y-2">
                <Label htmlFor="identity-path" className="text-xs">
                  AGE / SSH Identity File Path
                </Label>
                <Input
                  id="identity-path"
                  value={identityPath}
                  onChange={(e) => setIdentityPath(e.target.value)}
                  placeholder="Leave empty for default"
                  className="font-mono text-sm"
                />
                <p className="text-xs text-muted-foreground">
                  Path to your private key. SSH keys (ed25519, RSA) are also
                  supported.
                  <br />
                  Defaults (if empty):{" "}
                  <code className="text-[10px]">
                    ~/.config/age/key.txt
                  </code>, <code className="text-[10px]">~/.age/key.txt</code>
                  <br />
                  For SSH keys, specify explicitly:{" "}
                  <code className="text-[10px]">~/.ssh/id_ed25519</code>
                </p>
                {decryptError && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={handleRetryDecrypt}
                    className="mt-2"
                  >
                    Retry Decrypt
                  </Button>
                )}
              </div>
            )}
          </div>
        )}

        {/* Content */}
        <div className="space-y-4 py-2">
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              <span className="ml-2 text-sm text-muted-foreground">
                {isChamber ? "Loading secret..." : "Decrypting secret..."}
              </span>
            </div>
          ) : decryptError ? (
            <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
              <p className="text-sm text-destructive">{decryptError}</p>
              <p className="mt-2 text-xs text-muted-foreground">
                {isChamber
                  ? "Check your AWS credentials and permissions, then try again."
                  : "Configure your private key path above and try again."}
              </p>
            </div>
          ) : (
            <>
              <div className="space-y-2">
                <Label htmlFor="secret-value">Value</Label>
                <div className="relative">
                  <Textarea
                    id="secret-value"
                    value={value}
                    onChange={(e) => setValue(e.target.value)}
                    className="font-mono pr-10"
                    rows={4}
                    placeholder={
                      useGroupSecrets ? "Enter secret value..." : undefined
                    }
                    style={
                      {
                        WebkitTextSecurity: showValue ? "none" : "disc",
                      } as React.CSSProperties
                    }
                  />
                  <button
                    type="button"
                    onClick={() => setShowValue(!showValue)}
                    className="absolute right-2 top-2 text-muted-foreground hover:text-foreground"
                  >
                    {showValue ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </button>
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="secret-description">
                  Description (optional)
                </Label>
                <Input
                  id="secret-description"
                  value={newDescription}
                  onChange={(e) => setNewDescription(e.target.value)}
                  placeholder="What is this secret used for?"
                />
              </div>
            </>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={handleSave}
            disabled={isSaving || isLoading || !!decryptError}
          >
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Save Changes
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
