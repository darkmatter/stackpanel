"use client";

import { useEffect, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Cloud,
  KeyRound,
  Loader2,
  RefreshCw,
  ShieldCheck,
  Terminal,
  Users,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { Switch } from "@ui/switch";
import { Label } from "@ui/label";
import {
  useSopsAgeKeysStatus,
  useNixEntityData,
  useRecipients,
  useAddRecipient,
} from "@/lib/use-agent";
import { KeySourcesConfig } from "../../variables/key-sources-config";
import { RecipientsSection } from "../../variables/recipients-section";
import { useAgentClient } from "@/lib/agent-provider";
import type { SecretsConfigEntity } from "@/lib/types";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

type Section = "local-key" | "sources" | "recipients" | "verify";

interface SectionHeaderProps {
  icon: React.ElementType;
  title: string;
  subtitle: string;
  status: "complete" | "incomplete" | "optional";
  expanded: boolean;
  onToggle: () => void;
  step: number;
}

function SectionHeader({ icon: Icon, title, subtitle, status, expanded, onToggle, step }: SectionHeaderProps) {
  return (
    <button
      type="button"
      className="flex w-full items-center gap-3 rounded-lg border bg-card px-4 py-3 text-left transition-colors hover:bg-muted/40"
      onClick={onToggle}
    >
      <div className={`flex h-7 w-7 items-center justify-center rounded-full text-xs font-medium shrink-0 ${status === "complete" ? "bg-green-500/10 text-green-600" : "bg-muted text-muted-foreground"}`}>
        {status === "complete" ? <CheckCircle2 className="h-4 w-4" /> : step}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
          <span className="text-sm font-medium">{title}</span>
          {status === "incomplete" && <Badge variant="outline" className="border-amber-500/40 text-amber-600"><AlertTriangle className="h-3 w-3" /></Badge>}
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{subtitle}</p>
      </div>
      {expanded ? <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground" /> : <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />}
    </button>
  );
}

export function SecretsStep() {
  const { expandedStep, setExpandedStep, isChamber } = useSetupContext();
  const agentClient = useAgentClient();
  const { data: keyStatus, refetch: refetchKeyStatus, isLoading: keyStatusLoading } = useSopsAgeKeysStatus();
  const { data: secretsConfig, set } = useNixEntityData<SecretsConfigEntity>("secrets");
  const { data: recipients } = useRecipients();
  const addRecipient = useAddRecipient();


  const [openSection, setOpenSection] = useState<Section>("local-key");
  const [generatingKey, setGeneratingKey] = useState(false);
  const [localKeyExists, setLocalKeyExists] = useState(false);
  const [localKeyPublic, setLocalKeyPublic] = useState<string | null>(null);
  const [kmsEnabled, setKmsEnabled] = useState(false);
  const [kmsArn, setKmsArn] = useState("");
  const [sopsVerified, setSopsVerified] = useState(false);

  // Check local key on mount
  useEffect(() => {
    if (!keyStatus) return;
    setLocalKeyExists(keyStatus.localKeyExists);
    setLocalKeyPublic(keyStatus.publicKeys?.[0] ?? null);
  }, [keyStatus]);

  // Load KMS config
  useEffect(() => {
    const kms = ((secretsConfig?.kms ?? {}) as { "key-arn"?: string })["key-arn"] ?? "";
    setKmsArn(kms);
    setKmsEnabled(kms !== "");
  }, [secretsConfig]);

  const handleGenerateLocalKey = async () => {
    setGeneratingKey(true);
    try {
      const res = await agentClient.readFile(".stack/keys/local.txt").catch(() => null);
      if (res) {
        toast.info("Local key already exists at .stack/keys/local.txt");
        await refetchKeyStatus();
        return;
      }
      // Age-keygen via shell — tell user to run in devshell since agent can't write keys
      toast.info("Run the devshell to auto-generate your local key", {
        description: "A local AGE key at .stack/keys/local.txt is generated automatically on shell entry.",
        duration: 8000,
      });
    } finally {
      setGeneratingKey(false);
      await refetchKeyStatus();
    }
  };

  const handleAutoAddLocalRecipient = async () => {
    if (!localKeyPublic) return;
    const alreadyAdded = (recipients?.recipients ?? []).some(
      (r) => r.publicKey === localKeyPublic,
    );
    if (alreadyAdded) {
      toast.info("Local key is already a recipient");
      return;
    }
    await addRecipient.mutateAsync({
      name: "local",
      publicKey: localKeyPublic,
      tags: ["dev"],
    });
    toast.success("Local key added as recipient 'local'");
  };

  const handleSopsVerify = async () => {
    try {
      const result = await refetchKeyStatus();
      const data = result.data;
      if (data?.available && data?.recipientMatch) {
        setSopsVerified(true);
        toast.success("Round-trip check passed", {
          description: `${data.keyCount} key(s) resolved and matched a configured recipient.`,
        });
      } else {
        setSopsVerified(false);
        toast.error("Round-trip check failed", {
          description: data?.recommendation || "No matching recipient key found.",
        });
      }
    } catch {
      toast.error("Check failed");
    }
  };

  const handleSaveKms = async () => {
    const next: SecretsConfigEntity = {
      ...secretsConfig,
      kms: { "key-arn": kmsEnabled ? kmsArn : "" },
    };
    await set(next);
    toast.success(kmsEnabled ? "KMS ARN saved — reload shell to apply" : "KMS disabled");
  };

  const recipientCount = (recipients?.recipients ?? []).length;
  const localKeySection: SectionStatus = localKeyExists ? "complete" : "incomplete";
  const sourcesSection: SectionStatus = (keyStatus?.available) ? "complete" : "incomplete";
  const recipientsSection: SectionStatus = recipientCount > 0 ? "complete" : "incomplete";
  const verifySection: SectionStatus = sopsVerified || (keyStatus?.available && keyStatus?.recipientMatch) ? "complete" : "incomplete";

  type SectionStatus = "complete" | "incomplete" | "optional";

  const overallComplete = !isChamber && [localKeySection, sourcesSection, recipientsSection, verifySection].every(s => s === "complete");

  const step: SetupStep = {
    id: "secrets",
    title: "Secrets",
    description: "Set up SOPS encryption, key sources, and recipients",
    status: isChamber ? "complete" : overallComplete ? "complete" : "incomplete",
    required: !isChamber,
    dependsOn: ["project-info"],
    icon: <ShieldCheck className="h-5 w-5" />,
  };

  const toggleSection = (s: Section) => setOpenSection(openSection === s ? "local-key" : s);

  return (
    <StepCard
      step={step}
      isExpanded={expandedStep === "secrets"}
      onToggle={() => setExpandedStep(expandedStep === "secrets" ? null : "secrets")}
    >
      <div className="space-y-3">
        {/* ── 1. Local Key ─────────────────────────────────────── */}
        <div>
          <SectionHeader
            icon={Terminal}
            title="Local decryption key"
            subtitle={localKeyExists ? ".stack/keys/local.txt exists" : "Auto-generated on shell entry"}
            status={localKeySection}
            expanded={openSection === "local-key"}
            onToggle={() => toggleSection("local-key")}
            step={1}
          />
          {openSection === "local-key" && (
            <Card className="mt-1 rounded-t-none border-t-0">
              <CardContent className="pt-4 space-y-3">
                <p className="text-sm text-muted-foreground">
                  A local AGE key is auto-generated at <code>.stack/keys/local.txt</code> every
                  time you enter the devshell. No action is needed unless you are setting up from
                  scratch outside a shell.
                </p>
                <div className="flex items-center justify-between rounded-lg border bg-muted/20 px-4 py-3">
                  <div className="flex items-center gap-2">
                    {keyStatusLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : localKeyExists ? <CheckCircle2 className="h-4 w-4 text-green-500" /> : <AlertTriangle className="h-4 w-4 text-amber-500" />}
                    <span className="text-sm font-medium">
                      {localKeyExists ? "Local key present" : "No local key found"}
                    </span>
                  </div>
                  <Button variant="outline" size="sm" onClick={handleGenerateLocalKey} disabled={generatingKey}>
                    {generatingKey ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <RefreshCw className="mr-1 h-3.5 w-3.5" />}
                    Re-check
                  </Button>
                </div>
                {localKeyPublic && (
                  <div className="space-y-2">
                    <p className="text-xs font-medium text-muted-foreground">Derived public key</p>
                    <code className="block rounded bg-secondary px-2 py-1 font-mono text-[11px] break-all">{localKeyPublic}</code>
                    <Button size="sm" variant="outline" onClick={handleAutoAddLocalRecipient} disabled={addRecipient.isPending}>
                      <Users className="mr-1 h-3.5 w-3.5" />
                      Add as recipient
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          )}
        </div>

        {/* ── 2. Key Sources ────────────────────────────────────── */}
        <div>
          <SectionHeader
            icon={KeyRound}
            title="Additional key sources"
            subtitle={keyStatus?.available ? `${keyStatus.keyCount} key(s) resolved` : "Configure sources like SSH keys, 1Password, Keychain"}
            status={sourcesSection}
            expanded={openSection === "sources"}
            onToggle={() => toggleSection("sources")}
            step={2}
          />
          {openSection === "sources" && (
            <Card className="mt-1 rounded-t-none border-t-0">
              <CardContent className="pt-4">
                <KeySourcesConfig
                  config={secretsConfig ?? {}}
                  onSave={async (next) => { await set(next as SecretsConfigEntity); }}
                />
              </CardContent>
            </Card>
          )}
        </div>

        {/* ── 3. Recipients ─────────────────────────────────────── */}
        <div>
          <SectionHeader
            icon={Users}
            title="Recipients"
            subtitle={recipientCount > 0 ? `${recipientCount} recipient(s) configured` : "Add public keys that SOPS encrypts to"}
            status={recipientsSection}
            expanded={openSection === "recipients"}
            onToggle={() => toggleSection("recipients")}
            step={3}
          />
          {openSection === "recipients" && (
            <Card className="mt-1 rounded-t-none border-t-0">
              <CardContent className="pt-4">
                <p className="mb-3 text-sm text-muted-foreground">
                  Add the public key for each machine or team member that needs to decrypt secrets.
                  The local key is pre-added automatically above.
                </p>
                <RecipientsSection />
              </CardContent>
            </Card>
          )}
        </div>

        {/* ── 4. Verify + AWS ───────────────────────────────────── */}
        <div>
          <SectionHeader
            icon={ShieldCheck}
            title="Verify & options"
            subtitle={verifySection === "complete" ? "Round-trip passed" : "Check key resolves and matches a recipient"}
            status={verifySection}
            expanded={openSection === "verify"}
            onToggle={() => toggleSection("verify")}
            step={4}
          />
          {openSection === "verify" && (
            <Card className="mt-1 rounded-t-none border-t-0">
              <CardContent className="pt-4 space-y-5">
                {/* Round-trip check */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between rounded-lg border bg-muted/20 px-4 py-3">
                    <div>
                      <p className="text-sm font-medium">Round-trip check</p>
                      <p className="text-xs text-muted-foreground">
                        {keyStatus?.available && keyStatus?.recipientMatch
                          ? `✓ ${keyStatus.keyCount} key(s) resolved and matched a recipient`
                          : keyStatus?.available
                            ? `${keyStatus.keyCount} key(s) resolved but no recipient match`
                            : "No key resolved"}
                      </p>
                    </div>
                    <Button variant="outline" size="sm" onClick={handleSopsVerify}>
                      <RefreshCw className="mr-1 h-3.5 w-3.5" />
                      Re-check
                    </Button>
                  </div>
                  {keyStatus?.recommendation && (
                    <div className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3 text-sm text-muted-foreground">
                      <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5" />
                      <span>{keyStatus.recommendation}</span>
                    </div>
                  )}
                </div>

                {/* AWS KMS toggle */}
                <div className="space-y-3 border-t pt-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <Cloud className="h-4 w-4 text-muted-foreground" />
                      <div>
                        <p className="text-sm font-medium">AWS KMS recipient</p>
                        <p className="text-xs text-muted-foreground">Add a KMS ARN to every SOPS creation rule</p>
                      </div>
                    </div>
                    <Switch checked={kmsEnabled} onCheckedChange={setKmsEnabled} />
                  </div>
                  {kmsEnabled && (
                    <div className="space-y-2">
                      <Label className="text-xs">KMS Key ARN</Label>
                      <input
                        className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-xs font-mono shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                        placeholder="arn:aws:kms:us-east-1:123456789012:key/mrk-..."
                        value={kmsArn}
                        onChange={(e) => setKmsArn(e.target.value)}
                      />
                      <Button size="sm" onClick={handleSaveKms}>Save KMS ARN</Button>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </StepCard>
  );
}
