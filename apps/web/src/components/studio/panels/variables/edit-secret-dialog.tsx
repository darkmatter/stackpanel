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
import { Textarea } from "@ui/textarea";
import { Switch } from "@ui/switch";
import { Eye, EyeOff, Key, Loader2, Settings, AlertCircle, Cloud } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { AgentHttpClient, type AgeIdentityResponse, type KMSConfigResponse } from "@/lib/agent";
import { useAgentContext } from "@/lib/agent-provider";

// Helper to create agent client
function createAgentClient(token: string) {
  return new AgentHttpClient("localhost", 9876, token);
}

interface EditSecretDialogProps {
  secretId: string;
  secretKey: string;
  description?: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSuccess: () => void;
}

export function EditSecretDialog({
  secretId,
  secretKey,
  description,
  open,
  onOpenChange,
  onSuccess,
}: EditSecretDialogProps) {
  const { token } = useAgentContext();
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [showValue, setShowValue] = useState(false);
  const [value, setValue] = useState("");
  const [newDescription, setNewDescription] = useState(description || "");
  const [identityPath, setIdentityPath] = useState("");
  const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [decryptError, setDecryptError] = useState<string | null>(null);

  // Load the identity config when dialog opens
  const loadIdentityConfig = useCallback(async () => {
    if (!token) return;
    try {
      const client = createAgentClient(token);
      const info = await client.getAgeIdentity();
      setIdentityInfo(info);
      if (info.type === "path") {
        setIdentityPath(info.value);
      } else if (info.type === "key") {
        setIdentityPath("(key stored in project)");
      }
    } catch (err) {
      console.warn("Failed to load identity config:", err);
    }
  }, [token]);

  // Load the secret value when dialog opens
  useEffect(() => {
    if (open && token && secretId) {
      loadIdentityConfig();
      loadSecret();
    }
  }, [open, token, secretId, loadIdentityConfig]);

  const loadSecret = async () => {
    if (!token) return;
    
    setIsLoading(true);
    setDecryptError(null);
    setValue("");
    
    try {
      const client = createAgentClient(token);
      // Don't pass identityPath - the server will use the configured identity
      const result = await client.readAgenixSecret({
        id: secretId,
      });
      setValue(result.value);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to decrypt secret";
      setDecryptError(message);
      // Show settings if it's an identity file issue
      if (message.includes("identity") || message.includes("key") || message.includes("configure")) {
        setShowSettings(true);
      }
    } finally {
      setIsLoading(false);
    }
  };

  const handleSaveIdentity = async (newValue: string) => {
    if (!token) return;
    try {
      const client = createAgentClient(token);
      const result = await client.setAgeIdentity(newValue);
      setIdentityInfo(result);
      if (result.type === "path") {
        setIdentityPath(result.value);
      } else if (result.type === "key") {
        setIdentityPath("(key stored in project)");
      } else {
        setIdentityPath("");
      }
      toast.success("Identity saved");
      // Retry decryption with new identity
      loadSecret();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save identity");
    }
  };

  const handleSave = async () => {
    if (!token || !value.trim()) {
      toast.error("Please enter a value");
      return;
    }

    setIsSaving(true);
    try {
      const client = createAgentClient(token);
      await client.writeAgenixSecret({
        id: secretId,
        key: secretKey,
        value: value,
        description: newDescription || undefined,
      });
      
      toast.success("Secret updated successfully");
      onOpenChange(false);
      onSuccess();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to update secret");
    } finally {
      setIsSaving(false);
    }
  };

  const handleRetryDecrypt = () => {
    loadSecret();
  };

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
              {secretId}
            </code>
          </DialogDescription>
        </DialogHeader>

        {/* Settings Panel */}
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
                Path to your private key. SSH keys (ed25519, RSA) are also supported.
                <br />
                Defaults (if empty):{" "}
                <code className="text-[10px]">~/.config/age/key.txt</code>,{" "}
                <code className="text-[10px]">~/.age/key.txt</code>
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

        {/* Content */}
        <div className="space-y-4 py-2">
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              <span className="ml-2 text-sm text-muted-foreground">
                Decrypting secret...
              </span>
            </div>
          ) : decryptError ? (
            <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
              <p className="text-sm text-destructive">{decryptError}</p>
              <p className="mt-2 text-xs text-muted-foreground">
                Configure your private key path above and try again.
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
                    style={{ 
                      WebkitTextSecurity: showValue ? "none" : "disc",
                    } as React.CSSProperties}
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
                <Label htmlFor="secret-description">Description (optional)</Label>
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

/**
 * Settings component for configuring the AGE identity path or key
 * Can be used standalone in the variables panel
 * Stores the identity in .stackpanel/state/ (gitignored)
 */
export function AgeIdentitySettings() {
  const { token } = useAgentContext();
  const [inputValue, setInputValue] = useState("");
  const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load current identity on mount
  useEffect(() => {
    if (!token) return;
    const loadIdentity = async () => {
      try {
        const client = createAgentClient(token);
        const info = await client.getAgeIdentity();
        setIdentityInfo(info);
        if (info.type === "path") {
          setInputValue(info.value);
        } else if (info.type === "key") {
          setInputValue(""); // Don't show the actual key
        }
      } catch (err) {
        console.warn("Failed to load identity:", err);
      } finally {
        setIsLoading(false);
      }
    };
    loadIdentity();
  }, [token]);

  const handleSave = async () => {
    if (!token) return;
    setIsSaving(true);
    setError(null);
    try {
      const client = createAgentClient(token);
      const result = await client.setAgeIdentity(inputValue);
      setIdentityInfo(result);
      if (result.type === "path") {
        setInputValue(result.value);
      } else if (result.type === "key") {
        setInputValue(""); // Clear after storing
      }
      toast.success(result.type ? "Identity saved" : "Identity cleared");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to save";
      setError(msg);
      toast.error(msg);
    } finally {
      setIsSaving(false);
    }
  };

  const handleClear = async () => {
    setInputValue("");
    if (!token) return;
    try {
      const client = createAgentClient(token);
      const result = await client.setAgeIdentity("");
      setIdentityInfo(result);
      toast.success("Identity cleared");
    } catch (err) {
      toast.error("Failed to clear identity");
    }
  };

  return (
    <div className="rounded-lg border border-border p-4 space-y-3">
      <div className="flex items-center gap-2">
        <Key className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm font-medium">Decryption Key</span>
        {identityInfo?.type && (
          <span className="text-xs px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-600">
            {identityInfo.type === "key" ? "Key stored" : "Path configured"}
          </span>
        )}
      </div>
      <p className="text-xs text-muted-foreground">
        Enter a path to your private key file, or paste the key content directly.
        Stored in <code>.stackpanel/state/</code> (gitignored).
      </p>
      
      {error && (
        <div className="flex items-center gap-2 text-xs text-destructive">
          <AlertCircle className="h-3 w-3" />
          {error}
        </div>
      )}
      
      <div className="flex gap-2">
        <Input
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          placeholder={identityInfo?.type === "key" ? "(key already stored)" : "~/.ssh/id_ed25519 or paste AGE key"}
          className="font-mono text-sm flex-1"
          disabled={isLoading}
        />
        <Button variant="outline" size="sm" onClick={handleSave} disabled={isSaving || isLoading}>
          {isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
        </Button>
        {identityInfo?.type && (
          <Button variant="ghost" size="sm" onClick={handleClear} disabled={isSaving}>
            Clear
          </Button>
        )}
      </div>
      
      <p className="text-[11px] text-muted-foreground/70">
        <strong>Paths:</strong> <code>~/.ssh/id_ed25519</code>, <code>~/.config/age/key.txt</code>
        <br />
        <strong>Keys:</strong> Paste content starting with <code>AGE-SECRET-KEY-</code> or <code>-----BEGIN</code>
      </p>
    </div>
  );
}

/**
 * Settings component for configuring AWS KMS encryption
 * Can be used standalone in the variables panel
 * Stores the config in .stackpanel/state/ (gitignored)
 */
export function KMSSettings() {
  const { token } = useAgentContext();
  const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [keyArn, setKeyArn] = useState("");
  const [awsProfile, setAwsProfile] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load current config on mount
  useEffect(() => {
    if (!token) return;
    const loadConfig = async () => {
      try {
        const client = createAgentClient(token);
        const config = await client.getKMSConfig();
        setKmsConfig(config);
        setEnabled(config.enable);
        setKeyArn(config.keyArn);
        setAwsProfile(config.awsProfile);
      } catch (err) {
        console.warn("Failed to load KMS config:", err);
      } finally {
        setIsLoading(false);
      }
    };
    loadConfig();
  }, [token]);

  const handleSave = async () => {
    if (!token) return;
    
    // Validate ARN if enabling
    if (enabled && keyArn && !keyArn.startsWith("arn:aws:kms:")) {
      setError("Invalid KMS ARN format - must start with arn:aws:kms:");
      return;
    }

    setIsSaving(true);
    setError(null);
    try {
      const client = createAgentClient(token);
      const result = await client.setKMSConfig({
        enable: enabled,
        keyArn: keyArn,
        awsProfile: awsProfile || undefined,
      });
      setKmsConfig(result);
      toast.success(result.enable ? "KMS enabled" : "KMS disabled");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to save";
      setError(msg);
      toast.error(msg);
    } finally {
      setIsSaving(false);
    }
  };

  const handleDisable = async () => {
    setEnabled(false);
    setKeyArn("");
    setAwsProfile("");
    if (!token) return;
    try {
      const client = createAgentClient(token);
      const result = await client.setKMSConfig({ enable: false, keyArn: "" });
      setKmsConfig(result);
      toast.success("KMS disabled");
    } catch (err) {
      toast.error("Failed to disable KMS");
    }
  };

  return (
    <div className="rounded-lg border border-border p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Cloud className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-medium">AWS KMS</span>
          {kmsConfig?.enable && (
            <span className="text-xs px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-600">
              Enabled
            </span>
          )}
        </div>
        <Switch
          checked={enabled}
          onCheckedChange={setEnabled}
          disabled={isLoading}
        />
      </div>
      
      <p className="text-xs text-muted-foreground">
        Use AWS KMS for secret encryption. Works with AWS Roles Anywhere.
      </p>

      {enabled && (
        <div className="space-y-3 pt-2">
          {error && (
            <div className="flex items-center gap-2 text-xs text-destructive">
              <AlertCircle className="h-3 w-3" />
              {error}
            </div>
          )}
          
          <div className="space-y-1.5">
            <Label className="text-xs">KMS Key ARN</Label>
            <Input
              value={keyArn}
              onChange={(e) => setKeyArn(e.target.value)}
              placeholder="arn:aws:kms:us-east-1:123456789012:key/..."
              className="font-mono text-xs"
              disabled={isLoading}
            />
          </div>
          
          <div className="space-y-1.5">
            <Label className="text-xs">AWS Profile (optional)</Label>
            <Input
              value={awsProfile}
              onChange={(e) => setAwsProfile(e.target.value)}
              placeholder="Leave empty for default credentials"
              className="font-mono text-xs"
              disabled={isLoading}
            />
          </div>

          <div className="flex gap-2 pt-1">
            <Button variant="outline" size="sm" onClick={handleSave} disabled={isSaving || isLoading}>
              {isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
            </Button>
            {kmsConfig?.enable && (
              <Button variant="ghost" size="sm" onClick={handleDisable} disabled={isSaving}>
                Disable
              </Button>
            )}
          </div>
        </div>
      )}

      {!enabled && kmsConfig?.source === "" && (
        <p className="text-[11px] text-muted-foreground/70">
          Enable to add KMS encryption to your SOPS secrets.
          Run <code>generate-sops-config</code> after enabling.
        </p>
      )}
    </div>
  );
}
