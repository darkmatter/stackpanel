"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  Plus,
  Terminal,
  Shield,
  Copy,
  Check,
  Info,
  Trash2,
  Edit2,
  Copy as CopyIcon,
  ChevronDown,
  ChevronUp,
  ArrowUp,
  ArrowDown,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import type { SecretsConfigEntity } from "@/lib/types";
import { useSopsAgeKeysStatus } from "@/lib/use-agent";
import { useAgentClient } from "@/lib/agent-provider";
import type { SopsAgeKeysStatusResponse } from "@/lib/agent";

export type KeySourceType =
  | "user-key-path"
  | "repo-key-path"
  | "file"
  | "ssh-key"
  | "keychain"
  | "aws-kms"
  | "op-ref"
  | "keyservice"
  | "vals"
  | "script";

export interface KeySource {
  id: string;
  type: KeySourceType;
  value: string;
  enabled: boolean;
  name: string;
  priority?: number;
  account?: string;
}

const KEY_SOURCE_LABELS: Record<KeySourceType, string> = {
  "user-key-path": "User Key Path",
  "repo-key-path": "Repo Key Path",
  file: "File Path",
  "ssh-key": "SSH Private Key",
  keychain: "macOS Keychain",
  "aws-kms": "AWS SSM / Secrets Manager",
  "op-ref": "1Password Reference",
  keyservice: "SOPS Keyservice",
  vals: "Vals Reference",
  script: "Script",
};

const KEY_SOURCE_DESCRIPTIONS: Record<KeySourceType, string> = {
  "user-key-path": "AGE key file in user home directory",
  "repo-key-path": "AGE key file in repository",
  file: "AGE key file at custom path",
  "ssh-key":
    "SSH Ed25519 private key file. Converted to AGE via ssh-to-age at key-resolution time. Use this if your recipients are SSH public keys.",
  keychain:
    "Retrieve keys from macOS Keychain using security find-generic-password",
  "aws-kms":
    "Retrieve an AGE private key stored in AWS SSM Parameter Store (use a /path) or Secrets Manager (use the ARN). The parameter value must contain the AGE-SECRET-KEY-... private key.",
  "op-ref": "AGE key stored in 1Password",
  keyservice:
    "Set SOPS_KEYSERVICE for SOPS. This does not participate in source ordering.",
  vals: "Resolve an AGE key via vals",
  script: "Run a shell command that prints AGE private keys",
};

const KEY_SOURCE_PLACEHOLDERS: Record<KeySourceType, string> = {
  "user-key-path": "$XDG_CONFIG_HOME/sops/age/keys.txt",
  "repo-key-path": ".stack/keys/local.txt",
  file: "~/.ssh/id_ed25519",
  "ssh-key": "~/.ssh/id_ed25519",
  keychain: "stackpanel.sops-age-key",
  "aws-kms": "/myapp/sops-age-key or arn:aws:secretsmanager:...",
  "op-ref": "op://vault/item/field",
  keyservice: "tcp://127.0.0.1:5000",
  vals: "ref+sops://path/to/secret.sops.yaml#/age_key",
  script: "security find-generic-password -s sops-age-key -a age-key -w",
};

const KEY_SOURCE_TYPES: KeySourceType[] = [
  "user-key-path",
  "repo-key-path",
  "file",
  "ssh-key",
  "keychain",
  "aws-kms",
  "op-ref",
  "keyservice",
  "vals",
  "script",
];

function generateCommand(sources: KeySource[]): string {
  const enabledSources = sources.filter((s) => s.enabled);
  if (enabledSources.length === 0) {
    return "# No key sources enabled";
  }

  const commands: string[] = [];

  for (const source of enabledSources) {
    switch (source.type) {
      case "user-key-path":
      case "repo-key-path":
      case "file":
        commands.push(`cat "${source.value}"`);
        break;
      case "ssh-key":
        commands.push(`ssh-to-age -private-key -i "${source.value}"`);
        break;
      case "aws-kms":
        commands.push(
          source.value.startsWith("arn:")
            ? `aws secretsmanager get-secret-value --secret-id "${source.value}" --query SecretString --output text`
            : `aws ssm get-parameter --name "${source.value}" --with-decryption --query Parameter.Value --output text`,
        );
        break;
      case "keychain":
        commands.push(
          `security find-generic-password -s "${source.value}" -a "${source.account || "age-public-key"}" -w`,
        );
        break;
      case "op-ref":
        commands.push(
          `op read ${source.account ? `--account "${source.account}" ` : ""}"${source.value}"`,
        );
        break;
      case "keyservice":
        commands.push(`# exported separately: SOPS_KEYSERVICE="${source.value}"`);
        break;
      case "vals":
        commands.push(`vals eval -e "${source.value}"`);
        break;
      case "script":
        commands.push(source.value);
        break;
    }
  }

  if (commands.length === 1) {
    return commands[0];
  }

  return commands.join(" || \\\n  ");
}

function generateSingleSourceCommand(source: KeySource): string {
  switch (source.type) {
    case "user-key-path":
    case "repo-key-path":
    case "file":
      return `cat "${source.value}"`;
      case "ssh-key":
        return `ssh-to-age -private-key -i "${source.value}"`;
      case "aws-kms":
        return source.value.startsWith("arn:")
          ? `aws secretsmanager get-secret-value --secret-id "${source.value}" --query SecretString --output text`
          : `aws ssm get-parameter --name "${source.value}" --with-decryption --query Parameter.Value --output text`;
      case "keychain":
      return `security find-generic-password -s "${source.value}" -a "${source.account || "age-public-key"}" -w`;
    case "op-ref":
      return `op read ${source.account ? `--account "${source.account}" ` : ""}"${source.value}"`;
    case "keyservice":
      return `# exported separately: SOPS_KEYSERVICE="${source.value}"`;
    case "vals":
      return `vals eval -e "${source.value}"`;
    case "script":
      return source.value;
  }
}

function createDefaultSource(type: KeySourceType, priority: number): KeySource {
  return {
    id: Math.random().toString(36).substr(2, 9),
    type,
    value:
      type === "user-key-path"
        ? "$XDG_CONFIG_HOME/sops/age/keys.txt"
        : type === "repo-key-path"
          ? ".stack/keys/local.txt"
          : type === "ssh-key"
            ? "~/.ssh/id_ed25519"
            : type === "keychain"
              ? "stackpanel.sops-age-key"
              : type === "keyservice"
                ? "tcp://127.0.0.1:5000"
                : type === "script"
                  ? ""
                  : "",
    enabled: true,
    name: KEY_SOURCE_LABELS[type],
    priority,
    account: type === "keychain" ? "" : undefined,
  };
}

function buildSources(
  config: SecretsConfigEntity | null | undefined,
  status?: {
    userKeyPath?: string;
    repoKeyPath?: string;
    keychainService?: string;
  },
): KeySource[] {
  const raw = (config?.["sops-age-keys"] ?? {}) as {
    sources?: KeySource[];
    "user-key-path"?: string;
    "repo-key-path"?: string;
    paths?: string[];
    "op-refs"?: string[];
  };

  if (raw.sources && raw.sources.length > 0) {
    return raw.sources.map((s, idx) => ({
      ...s,
      priority: s.priority ?? idx,
    }));
  }

  const sources: KeySource[] = [];
  let priority = 0;

  const userPath = raw["user-key-path"] ?? status?.userKeyPath;
  if (userPath) {
    sources.push({
      id: Math.random().toString(36).substr(2, 9),
      type: "user-key-path",
      value: userPath,
      enabled: true,
      name: "User key path",
      priority: priority++,
    });
  }

  const repoPath =
    raw["repo-key-path"] ?? status?.repoKeyPath ?? ".stack/keys/local.txt";
  if (repoPath) {
    sources.push({
      id: Math.random().toString(36).substr(2, 9),
      type: "repo-key-path",
      value: repoPath,
      enabled: true,
      name: "Repo key path",
      priority: priority++,
    });
  }

  for (const path of raw.paths ?? []) {
    sources.push({
      id: Math.random().toString(36).substr(2, 9),
      type: "file",
      value: path,
      enabled: true,
      name: "File path",
      priority: priority++,
    });
  }

  for (const source of raw.sources ?? []) {
    if (
      source.type === "keychain" ||
      source.type === "keyservice" ||
      source.type === "vals" ||
      source.type === "script"
    ) {
      sources.push({
        ...source,
        priority: source.priority ?? priority++,
      });
    }
  }

  for (const ref of raw["op-refs"] ?? []) {
    sources.push({
      id: Math.random().toString(36).substr(2, 9),
      type: "op-ref",
      value: ref,
      enabled: true,
      name: "1Password ref",
      priority: priority++,
    });
  }

  return sources;
}

function serializeSources(
  config: SecretsConfigEntity,
  sources: KeySource[],
): SecretsConfigEntity {
  const userPath =
    sources.find((source) => source.type === "user-key-path")?.value ?? "";
  const repoPath =
    sources.find((source) => source.type === "repo-key-path")?.value ??
    ".stack/keys/local.txt";
  const paths = sources
    .filter((source) => source.type === "file")
    .map((source) => source.value)
    .filter(Boolean);
  const opRefs = sources
    .filter((source) => source.type === "op-ref")
    .map((source) => source.value)
    .filter(Boolean);
  const extraTypedSources = sources.filter((source) =>
    ["keychain", "aws-kms", "keyservice", "vals", "script"].includes(source.type),
  );

  return {
    ...config,
    "sops-age-keys": {
      sources: [
        ...sources.filter(
          (s) =>
            s.value.trim() !== "" &&
            !["keychain", "aws-kms", "keyservice", "vals", "script"].includes(s.type),
        ),
        ...extraTypedSources.filter((s) => s.value.trim() !== ""),
      ],
      "user-key-path": userPath,
      "repo-key-path": repoPath,
      paths,
      "op-refs": opRefs,
    },
  };
}

interface KeySourceCardProps {
  source: KeySource;
  index: number;
  total: number;
  checkResult?: {
    timestamp: number;
    status: SopsAgeKeysStatusResponse;
  };
  isChecking?: boolean;
  onToggle: (id: string, enabled: boolean) => void;
  onEdit: (source: KeySource) => void;
  onDelete: (id: string) => void;
  onDuplicate: (id: string) => void;
  onMove: (id: string, direction: -1 | 1) => void;
  onValidate: (source: KeySource) => void;
}

function KeySourceCard({
  source,
  index,
  total,
  checkResult,
  isChecking,
  onToggle,
  onEdit,
  onDelete,
  onDuplicate,
  onMove,
  onValidate,
}: KeySourceCardProps) {
  const [open, setOpen] = useState(false);
  return (
    <Card className="relative overflow-hidden">
      <Collapsible open={open} onOpenChange={setOpen}>
        <CardContent>
          <div className="flex items-start gap-4">
            <Checkbox
              checked={source.enabled}
              onCheckedChange={(checked) =>
                onToggle(source.id, checked === true)
              }
              className="mt-1"
            />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-medium text-foreground">
                  {source.name}
                </span>
                <Badge variant="outline" className="text-xs">
                  {KEY_SOURCE_LABELS[source.type]}
                </Badge>
                {!source.enabled && (
                  <Badge variant="secondary" className="text-xs">
                    Disabled
                  </Badge>
                )}
              </div>
              <p className="mt-1 font-mono text-sm text-muted-foreground break-all">
                {(source.type === "op-ref" || source.type === "keychain") &&
                source.account
                  ? `${source.account}: ${source.value}`
                  : source.value}
              </p>
            </div>
            <div className="flex gap-1 shrink-0">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onValidate(source)}
                className="h-8 px-2"
              >
                {isChecking ? (
                  <Check className="h-4 w-4 animate-pulse" />
                ) : (
                  <Shield className="h-4 w-4" />
                )}
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onMove(source.id, -1)}
                className="h-8 w-8 p-0"
                disabled={index === 0}
              >
                <ArrowUp className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onMove(source.id, 1)}
                className="h-8 w-8 p-0"
                disabled={index === total - 1}
              >
                <ArrowDown className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onEdit(source)}
                className="h-8 w-8 p-0"
              >
                <Edit2 className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onDuplicate(source.id)}
                className="h-8 w-8 p-0"
              >
                <CopyIcon className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onDelete(source.id)}
                className="h-8 w-8 p-0 text-destructive hover:text-destructive"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
              <CollapsibleTrigger asChild>
                <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                  {open ? (
                    <ChevronUp className="h-4 w-4" />
                  ) : (
                    <ChevronDown className="h-4 w-4" />
                  )}
                </Button>
              </CollapsibleTrigger>
            </div>
          </div>
        </CardContent>
        <CollapsibleContent>
          <div className="border-t bg-muted/20 px-6 py-4 text-xs text-muted-foreground space-y-3">
            <div>{KEY_SOURCE_DESCRIPTIONS[source.type]}</div>
            {checkResult ? (
              <div className="rounded-md border bg-background p-3 space-y-2">
                <div className="text-[11px] text-muted-foreground">
                  Last checked{" "}
                  {new Date(checkResult.timestamp).toLocaleString()}
                </div>
                {checkResult.status.publicKeys.length > 0 ? (
                  <div className="space-y-1">
                    {checkResult.status.publicKeys.map((key) => (
                      <div
                        key={key}
                        className={
                          "rounded px-2 py-1 font-mono text-[11px] break-all border " +
                          (checkResult.status.matchedPublicKeys.includes(key)
                            ? "border-green-500/40 bg-green-500/10 text-green-700 dark:text-green-400"
                            : "bg-secondary text-muted-foreground")
                        }
                      >
                        {key}
                      </div>
                    ))}
                  </div>
                ) : null}
                <div className="flex flex-wrap gap-1">
                  {checkResult.status.matchingRecipients.map((name) => (
                    <Badge
                      key={name}
                      variant="secondary"
                      className="bg-green-500/10 text-green-700 border border-green-500/30 dark:text-green-400"
                    >
                      {name}
                    </Badge>
                  ))}
                  {checkResult.status.decryptableGroups.map((name) => (
                    <Badge
                      key={name}
                      variant="outline"
                      className="border-green-500/30 text-green-700 bg-green-500/5 dark:text-green-400"
                    >
                      @{name}
                    </Badge>
                  ))}
                </div>
                {checkResult.status.error ? (
                  <div className="text-destructive whitespace-pre-wrap">
                    {checkResult.status.error}
                  </div>
                ) : null}
              </div>
            ) : null}
          </div>
        </CollapsibleContent>
      </Collapsible>
    </Card>
  );
}

export function KeySourcesConfig({
  config,
  onSave,
}: {
  config: SecretsConfigEntity;
  onSave: (next: SecretsConfigEntity) => Promise<void>;
}) {
  const agentClient = useAgentClient();
  const {
    data: keyStatus,
    refetch: refetchKeyStatus,
    isLoading: keyStatusLoading,
  } = useSopsAgeKeysStatus();
  const [sources, setSources] = useState<KeySource[]>([]);
  const [selectedType, setSelectedType] = useState<KeySourceType | null>(null);
  const [editingSource, setEditingSource] = useState<KeySource | null>(null);
  const [formData, setFormData] = useState<Partial<KeySource>>({});
  const [dialogOpen, setDialogOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [validatingSource, setValidatingSource] = useState(false);
  const [sourceCheck, setSourceCheck] =
    useState<SopsAgeKeysStatusResponse | null>(null);
  const [sourceChecks, setSourceChecks] = useState<
    Record<string, { timestamp: number; status: SopsAgeKeysStatusResponse }>
  >({});
  const [checkingSourceId, setCheckingSourceId] = useState<string | null>(null);
  const [lastCheck, setLastCheck] = useState<{
    timestamp: number;
    status: Awaited<ReturnType<typeof refetchKeyStatus>>["data"];
  } | null>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const raw = window.sessionStorage.getItem("stackpanel.sops-key-check");
      if (!raw) return;
      const parsed = JSON.parse(raw) as {
        timestamp: number;
        status: typeof keyStatus;
      };
      setLastCheck(parsed);
    } catch {
      // ignore bad session state
    }
    try {
      const raw = window.sessionStorage.getItem(
        "stackpanel.sops-source-checks",
      );
      if (raw) {
        setSourceChecks(JSON.parse(raw));
      }
    } catch {
      // ignore bad session state
    }
  }, []);

  useEffect(() => {
    setSources(buildSources(config, keyStatus));
  }, [config, keyStatus]);

  const handleStartAdd = (type: KeySourceType) => {
    setSelectedType(type);
    setEditingSource(null);
    const defaultSource = createDefaultSource(type, sources.length);
    if (type === "keychain" && keyStatus?.keychainService) {
      defaultSource.value = keyStatus.keychainService;
    }
    setFormData(defaultSource);
    setSourceCheck(null);
  };

  const handleStartEdit = (source: KeySource) => {
    setEditingSource(source);
    setSelectedType(null);
    setFormData(source);
    setDialogOpen(true);
    setSourceCheck(null);
  };

  const handleSave = async () => {
    if (editingSource) {
      setSources((prev) =>
        prev.map((s) =>
          s.id === editingSource.id ? { ...s, ...formData } : s,
        ),
      );
    } else if (selectedType) {
      const newSource = {
        ...formData,
        id: Math.random().toString(36).substr(2, 9),
      } as KeySource;
      setSources((prev) => [...prev, newSource]);
    }
    setDialogOpen(false);
    setSelectedType(null);
    setEditingSource(null);
    setFormData({});
  };

  const handleValidateSource = async () => {
    const source = formData as KeySource;
    if (!selectedType && !editingSource) return;
    if (!source.type || !source.value?.trim()) {
      toast.error("Source value is required before validation");
      return;
    }
    setValidatingSource(true);
    try {
      const result = await agentClient.validateSopsAgeKeySource({
        type: source.type,
        value: source.value,
        account: source.account,
      });
      setSourceCheck(result);
      if (result.available) {
        toast.success("Source returned key material", {
          description: result.recipientMatch
            ? `Matched ${result.matchingRecipients.length} recipient(s).`
            : `Found ${result.publicKeys.length} public key(s).`,
        });
      } else {
        toast.error("Source did not return a usable key", {
          description:
            result.error || result.recommendation || "No AGE key found.",
        });
      }
    } catch (error) {
      toast.error("Source validation failed", {
        description: error instanceof Error ? error.message : "Unknown error",
      });
    } finally {
      setValidatingSource(false);
    }
  };

  const handleValidateSavedSource = async (source: KeySource) => {
    setCheckingSourceId(source.id);
    try {
      const result = await agentClient.validateSopsAgeKeySource({
        type: source.type,
        value: source.value,
        account: source.account,
      });
      const next = { timestamp: Date.now(), status: result };
      setSourceChecks((prev) => {
        const updated = { ...prev, [source.id]: next };
        if (typeof window !== "undefined") {
          window.sessionStorage.setItem(
            "stackpanel.sops-source-checks",
            JSON.stringify(updated),
          );
        }
        return updated;
      });
      if (result.available) {
        toast.success("Source check complete", {
          description: result.recipientMatch
            ? `Matched ${result.matchingRecipients.length} recipient(s).`
            : `Found ${result.publicKeys.length} public key(s).`,
        });
      } else {
        toast.error("Source did not return a usable key", {
          description:
            result.error || result.recommendation || "No AGE key found.",
        });
      }
    } catch (error) {
      toast.error("Source validation failed", {
        description: error instanceof Error ? error.message : "Unknown error",
      });
    } finally {
      setCheckingSourceId(null);
    }
  };

  const handleToggle = (id: string, enabled: boolean) => {
    setSources((prev) =>
      prev.map((s) => (s.id === id ? { ...s, enabled } : s)),
    );
  };

  const handleDelete = (id: string) => {
    setSources((prev) => prev.filter((s) => s.id !== id));
  };

  const handleDuplicate = (id: string) => {
    const source = sources.find((s) => s.id === id);
    if (source) {
      const newSource: KeySource = {
        ...source,
        id: Math.random().toString(36).substr(2, 9),
        name: `${source.name} (Copy)`,
        priority: (source.priority ?? 0) + sources.length,
      };
      setSources((prev) => [...prev, newSource]);
    }
  };

  const handleMove = (id: string, direction: -1 | 1) => {
    setSources((prev) => {
      const index = prev.findIndex((source) => source.id === id);
      if (index === -1) return prev;
      const nextIndex = index + direction;
      if (nextIndex < 0 || nextIndex >= prev.length) return prev;
      const next = [...prev];
      const [item] = next.splice(index, 1);
      next.splice(nextIndex, 0, item);
      return next.map((source, idx) => ({ ...source, priority: idx }));
    });
  };

  const saveSources = async () => {
    await onSave(serializeSources(config, sources));
  };

  const generatedCommand = generateCommand(sources);

  const handleCopyCommand = async () => {
    await navigator.clipboard.writeText(generatedCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleRecheck = async () => {
    const result = await refetchKeyStatus();
    const status = result.data;
    if (!status) {
      toast.error("Key command check failed", {
        description: "No status response returned.",
      });
      return;
    }
    const next = { timestamp: Date.now(), status };
    setLastCheck(next);
    if (typeof window !== "undefined") {
      window.sessionStorage.setItem(
        "stackpanel.sops-key-check",
        JSON.stringify(next),
      );
    }
    if (status.available && status.recipientMatch) {
      toast.success("Key command check passed", {
        description: `Resolved ${status.keyCount} key(s); matched ${status.matchingRecipients.length} recipient(s).`,
      });
    } else {
      toast.error("Key command check needs attention", {
        description:
          status.recommendation || "No matching recipient key was found.",
      });
    }
  };

  useEffect(() => {
    const handler = () => {
      void (async () => {
        const result = await refetchKeyStatus();
        const status = result.data;
        if (!status) {
          toast.error("Key command check failed", {
            description: "No status response returned.",
          });
          return;
        }
        const next = { timestamp: Date.now(), status };
        setLastCheck(next);
        if (typeof window !== "undefined") {
          window.sessionStorage.setItem(
            "stackpanel.sops-key-check",
            JSON.stringify(next),
          );
        }
        if (status.available && status.recipientMatch) {
          toast.success("Key command check passed", {
            description: `Resolved ${status.keyCount} key(s); matched ${status.matchingRecipients.length} recipient(s).`,
          });
        } else {
          toast.error("Key command check needs attention", {
            description:
              status.recommendation || "No matching recipient key was found.",
          });
        }
      })();
    };
    window.addEventListener(
      "stackpanel:sops-run-check",
      handler as EventListener,
    );
    return () => {
      window.removeEventListener(
        "stackpanel:sops-run-check",
        handler as EventListener,
      );
    };
  }, [refetchKeyStatus]);

  const renderForm = () => {
    const type = editingSource?.type || selectedType;
    if (!type) return null;

    const updateFormData = (updates: Partial<KeySource>) => {
      setSourceCheck(null);
      setFormData((prev) => ({ ...prev, ...updates }));
    };

    return (
      <div className="space-y-4 max-w-full overflow-x-hidden">
        <div>
          <Label htmlFor="source-name">Source Name</Label>
          <Input
            id="source-name"
            value={(formData as KeySource).name || ""}
            onChange={(e) => updateFormData({ name: e.target.value })}
            placeholder="Enter a name for this source"
            className="mt-1"
          />
        </div>

        <div>
          <Label htmlFor="source-value">{KEY_SOURCE_LABELS[type]} Value</Label>
          <Input
            id="source-value"
            value={(formData as KeySource).value || ""}
            onChange={(e) => updateFormData({ value: e.target.value })}
            placeholder={
              type === "keychain" && keyStatus?.keychainService
                ? keyStatus.keychainService
                : KEY_SOURCE_PLACEHOLDERS[type]
            }
            className="mt-1 font-mono text-sm"
          />
          <p className="mt-1 text-xs text-muted-foreground">
            {KEY_SOURCE_DESCRIPTIONS[type]}
          </p>
        </div>

        {type === "op-ref" ? (
          <div>
            <Label htmlFor="source-account">1Password Account (optional)</Label>
            <Input
              id="source-account"
              value={(formData as KeySource).account || ""}
              onChange={(e) => updateFormData({ account: e.target.value })}
              placeholder="my.1password.com"
              className="mt-1"
            />
            <p className="mt-1 text-xs text-muted-foreground">
              Passed to <code>op read --account ...</code> when set.
            </p>
          </div>
        ) : null}

        {type === "keychain" ? (
          <div>
            <Label htmlFor="source-account">Keychain Account (optional)</Label>
            <Input
              id="source-account"
              value={(formData as KeySource).account || ""}
              onChange={(e) => updateFormData({ account: e.target.value })}
              placeholder="age1..."
              className="mt-1 font-mono text-sm"
            />
            <p className="mt-1 text-xs text-muted-foreground">
              Deterministic lookup key used with{" "}
              <code>security find-generic-password -a</code>. Setting this will
              cause the keychain value to be ignored. Typically used if you want
              to match on the age public key instead of the account name.
            </p>
          </div>
        ) : null}

        <div className="flex items-center gap-2">
          <Checkbox
            id="source-enabled"
            checked={(formData as KeySource).enabled || true}
            onCheckedChange={(checked) =>
              updateFormData({ enabled: checked === true })
            }
          />
          <Label htmlFor="source-enabled" className="text-sm font-normal">
            Enabled
          </Label>
        </div>

        <div className="rounded-lg border bg-muted/20 p-3 space-y-2">
          <div className="text-xs uppercase tracking-wide text-muted-foreground">
            Command Preview
          </div>
          <pre className="overflow-x-auto rounded-md bg-background p-3 text-xs text-muted-foreground">
            <code>{generateSingleSourceCommand(formData as KeySource)}</code>
          </pre>
        </div>

        <div className="space-y-3 rounded-lg border bg-muted/20 p-3">
          <div className="flex items-center justify-between gap-3">
            <div>
              <div className="text-sm font-medium">Validate this source</div>
              <p className="text-xs text-muted-foreground">
                Check whether this source resolves a key and which recipients or
                groups it matches.
              </p>
            </div>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={handleValidateSource}
              disabled={validatingSource}
            >
              {validatingSource ? (
                <Check className="mr-2 h-4 w-4 animate-pulse" />
              ) : (
                <Shield className="mr-2 h-4 w-4" />
              )}
              Validate
            </Button>
          </div>

          {sourceCheck ? (
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded border p-3">
                <div className="text-xs uppercase tracking-wide text-muted-foreground">
                  Public Keys
                </div>
                <div className="mt-2 space-y-1">
                  {sourceCheck.publicKeys.length ? (
                    sourceCheck.publicKeys.map((key: string) => (
                      <div
                        key={key}
                        className={
                          "rounded px-2 py-1 font-mono text-[11px] break-all border " +
                          (sourceCheck.matchedPublicKeys.includes(key)
                            ? "border-green-500/40 bg-green-500/10 text-green-700 dark:text-green-400"
                            : "bg-secondary text-muted-foreground")
                        }
                      >
                        {key}
                      </div>
                    ))
                  ) : (
                    <p className="text-sm text-muted-foreground">None</p>
                  )}
                </div>
              </div>
              <div className="rounded border p-3">
                <div className="text-xs uppercase tracking-wide text-muted-foreground">
                  Matching Recipients
                </div>
                <div className="mt-2 flex flex-wrap gap-1">
                  {sourceCheck.matchingRecipients.length ? (
                    sourceCheck.matchingRecipients.map((name: string) => (
                      <Badge
                        key={name}
                        variant="secondary"
                        className="bg-green-500/10 text-green-700 border border-green-500/30 dark:text-green-400"
                      >
                        {name}
                      </Badge>
                    ))
                  ) : (
                    <p className="text-sm text-muted-foreground">None</p>
                  )}
                </div>
              </div>
              <div className="rounded border p-3">
                <div className="text-xs uppercase tracking-wide text-muted-foreground">
                  Decryptable Groups
                </div>
                <div className="mt-2 flex flex-wrap gap-1">
                  {sourceCheck.decryptableGroups.length ? (
                    sourceCheck.decryptableGroups.map((name: string) => (
                      <Badge
                        key={name}
                        variant="outline"
                        className="border-green-500/30 text-green-700 bg-green-500/5 dark:text-green-400"
                      >
                        {name}
                      </Badge>
                    ))
                  ) : (
                    <p className="text-sm text-muted-foreground">None</p>
                  )}
                </div>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <Tabs defaultValue="sources" className="w-full">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="sources">Key Sources</TabsTrigger>
          <TabsTrigger value="output">Generated Command</TabsTrigger>
        </TabsList>

        <TabsContent value="sources" className="space-y-6">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base flex items-center gap-2">
                    <Shield className="h-4 w-4" />
                    Configured Sources
                  </CardTitle>
                  <CardDescription>
                    Sources are tried in order until one succeeds
                  </CardDescription>
                </div>
                <Dialog
                  open={dialogOpen}
                  onOpenChange={(open) => {
                    setDialogOpen(open);
                    if (!open) {
                      setSelectedType(null);
                      setEditingSource(null);
                      setFormData({});
                    }
                  }}
                >
                  <DialogTrigger asChild>
                    <Button
                      onClick={() => {
                        setSelectedType(null);
                        setEditingSource(null);
                        setFormData({});
                      }}
                    >
                      <Plus className="mr-2 h-4 w-4" />
                      Add Source
                    </Button>
                  </DialogTrigger>
                  <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
                    <DialogHeader>
                      <DialogTitle>
                        {editingSource
                          ? `Edit ${KEY_SOURCE_LABELS[editingSource.type]}`
                          : selectedType
                            ? `Add ${KEY_SOURCE_LABELS[selectedType]}`
                            : "Add Key Source"}
                      </DialogTitle>
                      <DialogDescription>
                        {editingSource
                          ? "Update the configuration for this key source"
                          : selectedType
                            ? KEY_SOURCE_DESCRIPTIONS[selectedType]
                            : "Select a key source type to configure"}
                      </DialogDescription>
                    </DialogHeader>

                    {!selectedType && !editingSource ? (
                      <div className="grid grid-cols-1 gap-3 py-4">
                        {KEY_SOURCE_TYPES.map((type) => (
                          <button
                            key={type}
                            onClick={() => handleStartAdd(type)}
                            className="flex items-start gap-4 rounded-lg border border-border bg-card p-4 text-left transition-colors hover:border-accent hover:bg-secondary"
                          >
                            <div className="flex-1">
                              <div className="font-medium text-foreground">
                                {KEY_SOURCE_LABELS[type]}
                              </div>
                              <div className="mt-1 text-sm text-muted-foreground">
                                {KEY_SOURCE_DESCRIPTIONS[type]}
                              </div>
                            </div>
                          </button>
                        ))}
                      </div>
                    ) : (
                      <>
                        {renderForm()}
                        <DialogFooter className="mt-6">
                          <Button
                            variant="outline"
                            onClick={() => {
                              if (editingSource) {
                                setDialogOpen(false);
                              } else {
                                setSelectedType(null);
                                setFormData({});
                              }
                            }}
                          >
                            {editingSource ? "Cancel" : "Back"}
                          </Button>
                          <Button onClick={handleSave}>
                            {editingSource ? "Save Changes" : "Add Source"}
                          </Button>
                        </DialogFooter>
                      </>
                    )}
                  </DialogContent>
                </Dialog>
              </div>
            </CardHeader>
            <CardContent>
              {sources.length === 0 ? (
                <div className="rounded-lg border border-dashed px-4 py-6 text-sm text-muted-foreground text-center flex flex-col items-center">
                  <Shield className="h-8 w-8 mb-2 opacity-50" />
                  <p className="font-medium">No key sources configured</p>
                  <p className="text-xs mt-1">
                    Add a key source to get started with SOPS encryption
                  </p>
                </div>
              ) : (
                <div className="space-y-3">
                  {sources.map((source, index) => (
                    <KeySourceCard
                      key={source.id}
                      source={source}
                      index={index}
                      total={sources.length}
                      checkResult={sourceChecks[source.id]}
                      isChecking={checkingSourceId === source.id}
                      onToggle={handleToggle}
                      onEdit={handleStartEdit}
                      onDelete={handleDelete}
                      onDuplicate={handleDuplicate}
                      onMove={handleMove}
                      onValidate={handleValidateSavedSource}
                    />
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          {sources.length > 0 && (
            <div className="flex items-start gap-3 rounded-lg border border-border bg-secondary/30 p-4">
              <Info className="h-5 w-5 shrink-0 text-muted-foreground mt-0.5" />
              <div className="text-sm text-muted-foreground">
                <p className="font-medium text-foreground">Fallback Behavior</p>
                <p className="mt-1">
                  Key sources are tried in the order shown above. The first
                  source that successfully returns a key will be used.
                </p>
              </div>
            </div>
          )}

          <Button onClick={saveSources} className="w-full">
            <Check className="mr-2 h-4 w-4" />
            Save Key Sources
          </Button>
        </TabsContent>

        <TabsContent value="output" className="space-y-6">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between gap-3">
                <div>
                  <CardTitle className="text-base">
                    Check Configured Key Command
                  </CardTitle>
                  <CardDescription>
                    Run the configured `sops-age-keys` command, inspect returned
                    public keys, and see which recipients and groups match.
                  </CardDescription>
                </div>
                <Button variant="outline" size="sm" onClick={handleRecheck}>
                  {keyStatusLoading ? (
                    <Check className="mr-2 h-4 w-4 animate-pulse" />
                  ) : (
                    <Shield className="mr-2 h-4 w-4" />
                  )}
                  Re-check
                </Button>
              </div>
            </CardHeader>
            {lastCheck ? (
              <CardContent className="space-y-4">
                <div className="text-xs text-muted-foreground">
                  Last checked {new Date(lastCheck.timestamp).toLocaleString()}
                </div>
                {lastCheck.status?.keychainService ? (
                  <div className="rounded-lg border p-3">
                    <div className="text-xs uppercase tracking-wide text-muted-foreground">
                      Suggested Keychain Service
                    </div>
                    <div className="mt-2 rounded bg-secondary px-2 py-1 font-mono text-[11px] break-all">
                      {lastCheck.status.keychainService}
                    </div>
                  </div>
                ) : null}
                <div className="grid gap-4 md:grid-cols-3">
                  <div className="rounded-lg border p-3">
                    <div className="text-xs uppercase tracking-wide text-muted-foreground">
                      Public Keys
                    </div>
                    <div className="mt-2 space-y-1">
                      {lastCheck.status?.publicKeys?.length ? (
                        lastCheck.status.publicKeys.map((key: string) => (
                          <div
                            key={key}
                            className={
                              "rounded px-2 py-1 font-mono text-[11px] break-all border " +
                              (lastCheck.status?.matchedPublicKeys?.includes(
                                key,
                              )
                                ? "border-green-500/40 bg-green-500/10 text-green-700 dark:text-green-400"
                                : "bg-secondary text-muted-foreground")
                            }
                          >
                            {key}
                          </div>
                        ))
                      ) : (
                        <p className="text-sm text-muted-foreground">None</p>
                      )}
                    </div>
                  </div>
                  <div className="rounded-lg border p-3">
                    <div className="text-xs uppercase tracking-wide text-muted-foreground">
                      Matching Recipients
                    </div>
                    <div className="mt-2 flex flex-wrap gap-1">
                      {lastCheck.status?.matchingRecipients?.length ? (
                        lastCheck.status.matchingRecipients.map(
                          (name: string) => (
                            <Badge
                              key={name}
                              variant="secondary"
                              className="bg-green-500/10 text-green-700 border border-green-500/30 dark:text-green-400"
                            >
                              {name}
                            </Badge>
                          ),
                        )
                      ) : (
                        <p className="text-sm text-muted-foreground">None</p>
                      )}
                    </div>
                  </div>
                  <div className="rounded-lg border p-3">
                    <div className="text-xs uppercase tracking-wide text-muted-foreground">
                      Decryptable Groups
                    </div>
                    <div className="mt-2 flex flex-wrap gap-1">
                      {lastCheck.status?.decryptableGroups?.length ? (
                        lastCheck.status.decryptableGroups.map(
                          (name: string) => (
                            <Badge
                              key={name}
                              variant="outline"
                              className="border-green-500/30 text-green-700 bg-green-500/5 dark:text-green-400"
                            >
                              {name}
                            </Badge>
                          ),
                        )
                      ) : (
                        <p className="text-sm text-muted-foreground">None</p>
                      )}
                    </div>
                  </div>
                </div>
              </CardContent>
            ) : null}
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Terminal className="h-5 w-5" />
                    SOPS_AGE_KEY_CMD
                  </CardTitle>
                  <CardDescription className="mt-1">
                    Set this as your SOPS_AGE_KEY_CMD environment variable
                  </CardDescription>
                </div>
                <Button variant="outline" size="sm" onClick={handleCopyCommand}>
                  {copied ? (
                    <>
                      <Check className="mr-2 h-4 w-4 text-green-600" />
                      Copied
                    </>
                  ) : (
                    <>
                      <Copy className="mr-2 h-4 w-4" />
                      Copy
                    </>
                  )}
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <pre className="overflow-x-auto rounded-lg bg-secondary p-4 font-mono text-sm text-foreground border">
                {generatedCommand}
              </pre>

              {sources.filter((s) => s.enabled).length > 1 && (
                <div className="mt-4 flex items-start gap-2 rounded-lg bg-secondary/50 p-3 border border-border">
                  <Badge variant="outline" className="mt-0.5 shrink-0">
                    Note
                  </Badge>
                  <p className="text-sm text-muted-foreground">
                    Multiple sources are chained with fallback (||). The first
                    successful command will provide the key.
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Usage Examples</CardTitle>
              <CardDescription>
                How to set the environment variable in different contexts
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <h4 className="mb-2 text-sm font-medium text-foreground">
                  Shell (bash/zsh)
                </h4>
                <pre className="overflow-x-auto rounded-lg bg-secondary p-3 font-mono text-sm text-foreground border">
                  {`export SOPS_AGE_KEY_CMD="${generatedCommand.replace(/"/g, '\\"')}"`}
                </pre>
              </div>
              <div>
                <h4 className="mb-2 text-sm font-medium text-foreground">
                  direnv (.envrc)
                </h4>
                <pre className="overflow-x-auto rounded-lg bg-secondary p-3 font-mono text-sm text-foreground border">
                  {`export SOPS_AGE_KEY_CMD="${generatedCommand.replace(/"/g, '\\"')}"`}
                </pre>
              </div>
              <div>
                <h4 className="mb-2 text-sm font-medium text-foreground">
                  GitHub Actions
                </h4>
                <pre className="overflow-x-auto rounded-lg bg-secondary p-3 font-mono text-sm text-foreground border">
                  {`env:
  SOPS_AGE_KEY_CMD: |
    ${generatedCommand.split("\n").join("\n    ")}`}
                </pre>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
