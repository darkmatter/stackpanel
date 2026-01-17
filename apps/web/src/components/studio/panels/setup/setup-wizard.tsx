"use client";

import { Button } from "@ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Progress } from "@ui/progress";
import {
  Check,
  ChevronRight,
  Circle,
  Cloud,
  Folder,
  FolderCog,
  GitBranch,
  Home,
  Key,
  Loader2,
  Lock,
  RefreshCw,
  Shield,
  Users,
  AlertCircle,
  CheckCircle2,
  Clock,
  ExternalLink,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { AgentHttpClient, type AgeIdentityResponse, type KMSConfigResponse, type Project } from "@/lib/agent";
import { useAgentContext } from "@/lib/agent-provider";
import { useNixConfig } from "@/lib/use-nix-config";

// Helper to create agent client
function createAgentClient(token: string) {
  return new AgentHttpClient("localhost", 9876, token);
}

// Step status types
type StepStatus = "complete" | "incomplete" | "in-progress" | "optional" | "blocked";

interface SetupStep {
  id: string;
  title: string;
  description: string;
  status: StepStatus;
  required: boolean;
  dependsOn?: string[];
  icon: React.ReactNode;
}

// Status badge component
function StatusBadge({ status }: { status: StepStatus }) {
  const config = {
    complete: { icon: CheckCircle2, text: "Complete", className: "text-emerald-600 bg-emerald-500/10" },
    incomplete: { icon: Circle, text: "Not configured", className: "text-muted-foreground bg-muted" },
    "in-progress": { icon: Loader2, text: "In progress", className: "text-blue-600 bg-blue-500/10" },
    optional: { icon: Clock, text: "Optional", className: "text-amber-600 bg-amber-500/10" },
    blocked: { icon: Lock, text: "Requires previous step", className: "text-muted-foreground bg-muted" },
  };
  const { icon: Icon, text, className } = config[status];
  return (
    <span className={cn("inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium", className)}>
      <Icon className={cn("h-3 w-3", status === "in-progress" && "animate-spin")} />
      {text}
    </span>
  );
}

// Step card component
function StepCard({
  step,
  isExpanded,
  onToggle,
  children,
}: {
  step: SetupStep;
  isExpanded: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  const isBlocked = step.status === "blocked";
  
  return (
    <Card className={cn(
      "transition-all duration-200",
      isExpanded && "ring-2 ring-primary/20",
      isBlocked && "opacity-60"
    )}>
      <CardHeader
        className={cn(
          "cursor-pointer hover:bg-muted/50 transition-colors",
          isBlocked && "cursor-not-allowed"
        )}
        onClick={() => !isBlocked && onToggle()}
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className={cn(
              "flex items-center justify-center w-10 h-10 rounded-full",
              step.status === "complete" ? "bg-emerald-500/10 text-emerald-600" : "bg-muted text-muted-foreground"
            )}>
              {step.icon}
            </div>
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                {step.title}
                {!step.required && (
                  <span className="text-xs font-normal text-muted-foreground">(optional)</span>
                )}
              </CardTitle>
              <CardDescription className="text-sm">{step.description}</CardDescription>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <StatusBadge status={step.status} />
            <ChevronRight className={cn(
              "h-5 w-5 text-muted-foreground transition-transform",
              isExpanded && "rotate-90"
            )} />
          </div>
        </div>
      </CardHeader>
      {isExpanded && (
        <CardContent className="pt-0 border-t">
          <div className="pt-4">
            {children}
          </div>
        </CardContent>
      )}
    </Card>
  );
}

export function SetupWizard() {
  const { token } = useAgentContext();
  const { data: nixConfig, isLoading: nixConfigLoading } = useNixConfig();
  const [expandedStep, setExpandedStep] = useState<string | null>("project-info");
  const [isLoading, setIsLoading] = useState(true);
  
  // Project info state
  const [projectInfo, setProjectInfo] = useState<Project | null>(null);
  const [projectConfirmed, setProjectConfirmed] = useState(false);
  
  // Step states
  const [identityInfo, setIdentityInfo] = useState<AgeIdentityResponse | null>(null);
  const [kmsConfig, setKmsConfig] = useState<KMSConfigResponse | null>(null);
  const [usersConfigured, setUsersConfigured] = useState(false);
  const [sopsConfigGenerated, setSopsConfigGenerated] = useState(false);
  
  // Form states
  const [identityInput, setIdentityInput] = useState("");
  const [kmsEnabled, setKmsEnabled] = useState(false);
  const [kmsArn, setKmsArn] = useState("");
  const [kmsProfile, setKmsProfile] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  // Derive org/repo from config or path
  const projectName = nixConfig?.name || projectInfo?.name || "Unknown";
  const projectPath = projectInfo?.path || "";
  const githubSource = nixConfig?.source?.repo || "";
  const localDataDir = ".stackpanel";
  const globalConfigDir = "~/.config/stackpanel";

  // Load current configuration
  const loadConfig = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    try {
      const client = createAgentClient(token);
      
      // Load project info
      const projectRes = await client.getCurrentProject();
      if (projectRes.project) {
        setProjectInfo(projectRes.project);
      }
      
      // Check if project was previously confirmed (stored in localStorage for now)
      const confirmed = localStorage.getItem("stackpanel-project-confirmed");
      setProjectConfirmed(confirmed === "true");
      
      // Load identity
      const identity = await client.getAgeIdentity();
      setIdentityInfo(identity);
      if (identity.type === "path") {
        setIdentityInput(identity.value);
      }
      
      // Load KMS config
      const kms = await client.getKMSConfig();
      setKmsConfig(kms);
      setKmsEnabled(kms.enable);
      setKmsArn(kms.keyArn);
      setKmsProfile(kms.awsProfile);
      
      // Check if users are configured (simple check - could be more sophisticated)
      // For now, assume configured if we have identity
      setUsersConfigured(identity.type !== "");
      
      // Check if .sops.yaml exists
      try {
        await client.readFile(".sops.yaml");
        setSopsConfigGenerated(true);
      } catch {
        setSopsConfigGenerated(false);
      }
    } catch (err) {
      console.warn("Failed to load config:", err);
    } finally {
      setIsLoading(false);
    }
  }, [token]);

  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  // Save identity
  const handleSaveIdentity = async () => {
    if (!token) return;
    setIsSaving(true);
    try {
      const client = createAgentClient(token);
      const result = await client.setAgeIdentity(identityInput);
      setIdentityInfo(result);
      toast.success("Decryption key saved");
      loadConfig();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setIsSaving(false);
    }
  };

  // Save KMS config
  const handleSaveKMS = async () => {
    if (!token) return;
    setIsSaving(true);
    try {
      const client = createAgentClient(token);
      const result = await client.setKMSConfig({
        enable: kmsEnabled,
        keyArn: kmsArn,
        awsProfile: kmsProfile || undefined,
      });
      setKmsConfig(result);
      toast.success(result.enable ? "KMS enabled" : "KMS disabled");
      loadConfig();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setIsSaving(false);
    }
  };

  // Confirm project configuration
  const handleConfirmProject = () => {
    localStorage.setItem("stackpanel-project-confirmed", "true");
    setProjectConfirmed(true);
    toast.success("Project configuration confirmed");
    setExpandedStep("decryption-key");
  };

  // Calculate step statuses
  const steps: SetupStep[] = [
    {
      id: "project-info",
      title: "Project Configuration",
      description: "Confirm your project details and directory structure",
      status: projectConfirmed ? "complete" : "incomplete",
      required: true,
      icon: <FolderCog className="h-5 w-5" />,
    },
    {
      id: "decryption-key",
      title: "Decryption Key",
      description: "Configure your private key for decrypting secrets",
      status: identityInfo?.type ? "complete" : (projectConfirmed ? "incomplete" : "blocked"),
      required: true,
      dependsOn: ["project-info"],
      icon: <Key className="h-5 w-5" />,
    },
    {
      id: "team-keys",
      title: "Team Public Keys",
      description: "Sync team members' public keys for encryption",
      status: usersConfigured ? "complete" : "optional",
      required: false,
      icon: <Users className="h-5 w-5" />,
    },
    {
      id: "kms",
      title: "AWS KMS (Optional)",
      description: "Add AWS KMS as an additional encryption layer",
      status: kmsConfig?.enable ? "complete" : "optional",
      required: false,
      icon: <Cloud className="h-5 w-5" />,
    },
    {
      id: "generate-config",
      title: "Generate SOPS Config",
      description: "Generate .sops.yaml with your encryption keys",
      status: sopsConfigGenerated ? "complete" : (identityInfo?.type ? "incomplete" : "blocked"),
      required: true,
      dependsOn: ["decryption-key"],
      icon: <Shield className="h-5 w-5" />,
    },
  ];

  const completedSteps = steps.filter(s => s.status === "complete").length;
  const requiredSteps = steps.filter(s => s.required);
  const requiredComplete = requiredSteps.filter(s => s.status === "complete").length;
  const progress = (completedSteps / steps.length) * 100;

  if (isLoading || nixConfigLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8 max-w-3xl">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Project Setup</h1>
        <p className="text-muted-foreground mt-2">
          Complete these steps to configure secrets management for your project.
        </p>
      </div>

      {/* Progress */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium">Setup Progress</span>
              <span className="text-sm text-muted-foreground">
                ({requiredComplete}/{requiredSteps.length} required)
              </span>
            </div>
            <span className="text-sm font-medium">{Math.round(progress)}%</span>
          </div>
          <Progress value={progress} className="h-2" />
          {requiredComplete === requiredSteps.length && (
            <p className="text-sm text-emerald-600 mt-3 flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4" />
              All required steps complete! Your project is ready to use secrets.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Steps */}
      <div className="space-y-4">
        {/* Step 1: Project Configuration */}
        <StepCard
          step={steps[0]}
          isExpanded={expandedStep === "project-info"}
          onToggle={() => setExpandedStep(expandedStep === "project-info" ? null : "project-info")}
        >
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground">
              Review your project configuration. Stackpanel uses two directories to organize
              project-specific and global settings.
            </p>

            {/* Project Identity */}
            <div className="space-y-3">
              <h4 className="font-medium flex items-center gap-2">
                <GitBranch className="h-4 w-4" />
                Project Identity
              </h4>
              <div className="grid gap-3 pl-6">
                <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                  <div>
                    <p className="text-sm font-medium">Project Name</p>
                    <p className="text-xs text-muted-foreground">Used for port allocation and identification</p>
                  </div>
                  <code className="text-sm font-mono bg-background px-2 py-1 rounded">{projectName}</code>
                </div>
                {githubSource && (
                  <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                    <div>
                      <p className="text-sm font-medium">GitHub Repository</p>
                      <p className="text-xs text-muted-foreground">Used for syncing collaborator keys</p>
                    </div>
                    <code className="text-sm font-mono bg-background px-2 py-1 rounded">{githubSource}</code>
                  </div>
                )}
                {projectPath && (
                  <div className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                    <div>
                      <p className="text-sm font-medium">Project Path</p>
                      <p className="text-xs text-muted-foreground">Root directory of this project</p>
                    </div>
                    <code className="text-sm font-mono bg-background px-2 py-1 rounded text-xs">{projectPath}</code>
                  </div>
                )}
              </div>
            </div>

            {/* Directory Structure */}
            <div className="space-y-3">
              <h4 className="font-medium flex items-center gap-2">
                <Folder className="h-4 w-4" />
                Directory Structure
              </h4>
              <div className="grid gap-4 pl-6">
                {/* Local Directory */}
                <div className="rounded-lg border p-4 space-y-2">
                  <div className="flex items-center gap-2">
                    <FolderCog className="h-4 w-4 text-blue-500" />
                    <code className="font-mono text-sm font-medium">{localDataDir}/</code>
                    <span className="text-xs bg-blue-500/10 text-blue-600 px-1.5 py-0.5 rounded">Project-local</span>
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Project-specific configuration and data. This directory is <strong>checked into git</strong> and shared with your team.
                  </p>
                  <ul className="text-xs text-muted-foreground space-y-1 mt-2">
                    <li><code>config.nix</code> — Main project configuration</li>
                    <li><code>data/</code> — Apps, variables, and other data tables</li>
                    <li><code>secrets/</code> — Encrypted secrets (age files)</li>
                    <li><code>state/</code> — Local state (gitignored)</li>
                  </ul>
                </div>

                {/* Global Directory */}
                <div className="rounded-lg border p-4 space-y-2">
                  <div className="flex items-center gap-2">
                    <Home className="h-4 w-4 text-purple-500" />
                    <code className="font-mono text-sm font-medium">{globalConfigDir}/</code>
                    <span className="text-xs bg-purple-500/10 text-purple-600 px-1.5 py-0.5 rounded">Global</span>
                  </div>
                  <p className="text-sm text-muted-foreground">
                    User-specific settings shared across all projects. This directory is <strong>not checked into git</strong>.
                  </p>
                  <ul className="text-xs text-muted-foreground space-y-1 mt-2">
                    <li><code>config.yaml</code> — Global preferences</li>
                    <li><code>projects.json</code> — List of known projects</li>
                    <li><code>cache/</code> — Cached data (nixpkgs, etc.)</li>
                  </ul>
                </div>
              </div>
            </div>

            {projectConfirmed ? (
              <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
                <p className="text-sm text-emerald-700 dark:text-emerald-400 flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4" />
                  Project configuration confirmed
                </p>
              </div>
            ) : (
              <Button onClick={handleConfirmProject}>
                <Check className="h-4 w-4 mr-2" />
                Confirm Configuration
              </Button>
            )}
          </div>
        </StepCard>

        {/* Step 2: Decryption Key */}
        <StepCard
          step={steps[1]}
          isExpanded={expandedStep === "decryption-key"}
          onToggle={() => setExpandedStep(expandedStep === "decryption-key" ? null : "decryption-key")}
        >
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Your decryption key allows you to decrypt secrets on this machine.
              This can be an AGE key or an SSH private key.
            </p>
            
            <div className="space-y-2">
              <Label>Private Key Path or Content</Label>
              <Input
                value={identityInput}
                onChange={(e) => setIdentityInput(e.target.value)}
                placeholder="~/.ssh/id_ed25519 or paste AGE key"
                className="font-mono"
              />
              <p className="text-xs text-muted-foreground">
                Common paths: <code>~/.ssh/id_ed25519</code>, <code>~/.config/age/key.txt</code>
              </p>
            </div>

            <div className="flex gap-2">
              <Button onClick={handleSaveIdentity} disabled={isSaving || !identityInput}>
                {isSaving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Check className="h-4 w-4 mr-2" />}
                Save Key
              </Button>
            </div>

            {identityInfo?.type && (
              <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
                <p className="text-sm text-emerald-700 dark:text-emerald-400 flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4" />
                  {identityInfo.type === "key" ? "Key stored securely" : `Using: ${identityInfo.value}`}
                </p>
              </div>
            )}
          </div>
        </StepCard>

        {/* Step 3: Team Keys */}
        <StepCard
          step={steps[2]}
          isExpanded={expandedStep === "team-keys"}
          onToggle={() => setExpandedStep(expandedStep === "team-keys" ? null : "team-keys")}
        >
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Team members' SSH public keys are automatically synced from GitHub collaborators.
              These keys are used to encrypt secrets so team members can decrypt them.
            </p>

            <div className="rounded-lg border p-4 space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-medium">GitHub Collaborators</h4>
                  <p className="text-sm text-muted-foreground">
                    Public keys are synced from your repository collaborators
                  </p>
                </div>
                <Button variant="outline" size="sm">
                  <RefreshCw className="h-4 w-4 mr-2" />
                  Sync Keys
                </Button>
              </div>
            </div>

            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <ExternalLink className="h-4 w-4" />
              <span>
                View team keys in <code>.stackpanel/data/external/users.nix</code>
              </span>
            </div>
          </div>
        </StepCard>

        {/* Step 4: AWS KMS */}
        <StepCard
          step={steps[3]}
          isExpanded={expandedStep === "kms"}
          onToggle={() => setExpandedStep(expandedStep === "kms" ? null : "kms")}
        >
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              AWS KMS provides an additional encryption layer. Secrets can be decrypted
              using either AGE keys or KMS, making it easier for CI/CD and production environments.
            </p>

            <div className="flex items-center justify-between p-4 rounded-lg border">
              <div>
                <h4 className="font-medium">Enable AWS KMS</h4>
                <p className="text-sm text-muted-foreground">
                  Add KMS encryption to SOPS secrets
                </p>
              </div>
              <Switch checked={kmsEnabled} onCheckedChange={setKmsEnabled} />
            </div>

            {kmsEnabled && (
              <div className="space-y-4 pl-4 border-l-2 border-primary/20">
                <div className="space-y-2">
                  <Label>KMS Key ARN</Label>
                  <Input
                    value={kmsArn}
                    onChange={(e) => setKmsArn(e.target.value)}
                    placeholder="arn:aws:kms:us-east-1:123456789012:key/..."
                    className="font-mono text-sm"
                  />
                </div>

                <div className="space-y-2">
                  <Label>AWS Profile (optional)</Label>
                  <Input
                    value={kmsProfile}
                    onChange={(e) => setKmsProfile(e.target.value)}
                    placeholder="Leave empty for default credentials"
                    className="font-mono text-sm"
                  />
                  <p className="text-xs text-muted-foreground">
                    Works with AWS Roles Anywhere if configured
                  </p>
                </div>
              </div>
            )}

            <Button onClick={handleSaveKMS} disabled={isSaving}>
              {isSaving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Check className="h-4 w-4 mr-2" />}
              {kmsEnabled ? "Save KMS Config" : "Disable KMS"}
            </Button>
          </div>
        </StepCard>

        {/* Step 5: Generate Config */}
        <StepCard
          step={steps[4]}
          isExpanded={expandedStep === "generate-config"}
          onToggle={() => setExpandedStep(expandedStep === "generate-config" ? null : "generate-config")}
        >
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Generate the <code>.sops.yaml</code> configuration file with all your encryption keys.
              This file tells SOPS how to encrypt and decrypt secrets.
            </p>

            {steps[4].status === "blocked" ? (
              <div className="rounded-lg bg-amber-500/10 border border-amber-500/20 p-3">
                <p className="text-sm text-amber-700 dark:text-amber-400 flex items-center gap-2">
                  <AlertCircle className="h-4 w-4" />
                  Complete the "Decryption Key" step first
                </p>
              </div>
            ) : (
              <>
                <div className="rounded-lg bg-muted p-4">
                  <p className="text-sm font-mono mb-2">$ generate-sops-config</p>
                  <p className="text-xs text-muted-foreground">
                    Run this command in your terminal to generate the config
                  </p>
                </div>

                {sopsConfigGenerated && (
                  <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 p-3">
                    <p className="text-sm text-emerald-700 dark:text-emerald-400 flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4" />
                      .sops.yaml exists and is configured
                    </p>
                  </div>
                )}

                <Button variant="outline" onClick={() => toast.info("Run 'generate-sops-config' in your terminal")}>
                  <RefreshCw className="h-4 w-4 mr-2" />
                  Regenerate Config
                </Button>
              </>
            )}
          </div>
        </StepCard>
      </div>

      {/* Next Steps */}
      {requiredComplete === requiredSteps.length && (
        <Card className="bg-gradient-to-r from-emerald-500/10 to-blue-500/10 border-emerald-500/20">
          <CardContent className="pt-6">
            <h3 className="font-semibold text-lg mb-2">🎉 Setup Complete!</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Your project is ready for secrets management. Here's what you can do next:
            </p>
            <ul className="space-y-2 text-sm">
              <li className="flex items-center gap-2">
                <Check className="h-4 w-4 text-emerald-600" />
                Create secrets in the Variables panel
              </li>
              <li className="flex items-center gap-2">
                <Check className="h-4 w-4 text-emerald-600" />
                Use <code>sops</code> to encrypt/decrypt files
              </li>
              <li className="flex items-center gap-2">
                <Check className="h-4 w-4 text-emerald-600" />
                Run <code>generate-sops-secrets</code> to create environment YAML files
              </li>
            </ul>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
