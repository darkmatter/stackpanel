"use client";

import { useQuery } from "@tanstack/react-query";
import {
  AlertCircle,
  CheckCircle2,
  Clock,
  Cloud,
  Loader2,
  Lock,
  Server,
  ShieldAlert,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAgentContext } from "@/lib/agent-provider";
import { useNixConfig } from "@/lib/use-nix-config";
import { useTRPC } from "@/utils/trpc";

type AWSSessionStatus = {
  enabled: boolean;
  valid: boolean;
  expires_at?: string;
  expires_in?: string;
  profile_arn?: string;
  role_arn?: string;
  region?: string;
  error?: string;
  has_credentials: boolean;
};

type CertificateStatus = {
  enabled: boolean;
  valid: boolean;
  expires_at?: string;
  expires_in?: string;
  subject?: string;
  issuer?: string;
  cert_path?: string;
  error?: string;
  ca_reachable: boolean;
  ca_url?: string;
};

function StatusIcon({
  status,
  size = "sm",
}: {
  status: "valid" | "warning" | "error" | "disabled";
  size?: "sm" | "md";
}) {
  const sizeClass = size === "sm" ? "h-4 w-4" : "h-5 w-5";

  switch (status) {
    case "valid":
      return <CheckCircle2 className={`${sizeClass} text-accent`} />;
    case "warning":
      return <AlertCircle className={`${sizeClass} text-yellow-500`} />;
    case "error":
      return <XCircle className={`${sizeClass} text-destructive`} />;
    case "disabled":
      return <Clock className={`${sizeClass} text-muted-foreground`} />;
  }
}

function AWSStatusSection({ status }: { status: AWSSessionStatus }) {
  if (!status.enabled) {
    return (
      <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
          <Cloud className="h-5 w-5 text-muted-foreground" />
        </div>
        <div className="flex-1">
          <p className="font-medium text-muted-foreground text-sm">
            AWS Roles Anywhere
          </p>
          <p className="text-muted-foreground text-xs">Not configured</p>
        </div>
        <Badge variant="outline" className="text-muted-foreground">
          Disabled
        </Badge>
      </div>
    );
  }

  const statusType = status.valid
    ? "valid"
    : status.error
      ? "error"
      : "warning";

  return (
    <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-3">
      <div
        className={`flex h-10 w-10 items-center justify-center rounded-lg ${
          status.valid ? "bg-accent/20" : "bg-secondary"
        }`}
      >
        <Cloud
          className={`h-5 w-5 ${status.valid ? "text-accent" : "text-muted-foreground"}`}
        />
      </div>
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <p className="font-medium text-foreground text-sm">
            AWS Roles Anywhere
          </p>
          {status.valid && (
            <Badge variant="outline" className="border-accent text-accent">
              Active
            </Badge>
          )}
        </div>
        <p className="text-muted-foreground text-xs">
          {status.valid
            ? status.region
              ? `Region: ${status.region}`
              : "Session active"
            : (status.error ?? "Session expired or invalid")}
        </p>
      </div>
      <StatusIcon status={statusType} />
    </div>
  );
}

function CertificateStatusSection({ status }: { status: CertificateStatus }) {
  if (!status.enabled) {
    return (
      <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
          <Lock className="h-5 w-5 text-muted-foreground" />
        </div>
        <div className="flex-1">
          <p className="font-medium text-muted-foreground text-sm">
            Step CA Certificate
          </p>
          <p className="text-muted-foreground text-xs">Not configured</p>
        </div>
        <Badge variant="outline" className="text-muted-foreground">
          Disabled
        </Badge>
      </div>
    );
  }

  const statusType = status.valid
    ? "valid"
    : status.error
      ? "error"
      : "warning";

  return (
    <div className="space-y-2">
      {/* Certificate Status */}
      <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-3">
        <div
          className={`flex h-10 w-10 items-center justify-center rounded-lg ${
            status.valid ? "bg-accent/20" : "bg-secondary"
          }`}
        >
          <Lock
            className={`h-5 w-5 ${status.valid ? "text-accent" : "text-muted-foreground"}`}
          />
        </div>
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <p className="font-medium text-foreground text-sm">
              Device Certificate
            </p>
            {status.valid && (
              <Badge variant="outline" className="border-accent text-accent">
                Valid
              </Badge>
            )}
          </div>
          <p className="text-muted-foreground text-xs">
            {status.valid
              ? status.expires_in
                ? `Expires in ${status.expires_in}`
                : (status.subject ?? "Certificate valid")
              : (status.error ?? "Certificate invalid or expired")}
          </p>
        </div>
        <StatusIcon status={statusType} />
      </div>

      {/* CA Reachability */}
      <div className="flex items-center gap-3 rounded-lg border border-border bg-secondary/30 p-3">
        <div
          className={`flex h-10 w-10 items-center justify-center rounded-lg ${
            status.ca_reachable ? "bg-accent/20" : "bg-secondary"
          }`}
        >
          <Server
            className={`h-5 w-5 ${status.ca_reachable ? "text-accent" : "text-muted-foreground"}`}
          />
        </div>
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <p className="font-medium text-foreground text-sm">Internal CA</p>
            {status.ca_reachable && (
              <Badge variant="outline" className="border-accent text-accent">
                Reachable
              </Badge>
            )}
          </div>
          <p className="text-muted-foreground text-xs">
            {status.ca_url ?? "Step CA server"}
          </p>
        </div>
        <StatusIcon status={status.ca_reachable ? "valid" : "error"} />
      </div>
    </div>
  );
}

export function SecurityStatusCard() {
  const { host, port, token, isConnected } = useAgentContext();
  const { data: config } = useNixConfig();
  const trpc = useTRPC();

  // Check if AWS or Step CA are configured in the nix config
  const awsEnabled = config?.aws?.["roles-anywhere"]?.enable ?? false;
  const stepCaEnabled = config?.stepCa?.["step-ca"]?.enable ?? false;

  // Don't show the card if neither feature is enabled
  const shouldShow = awsEnabled || stepCaEnabled;

  const {
    data: securityStatus,
    isLoading,
    error,
  } = useQuery(
    trpc.agent.getSecurityStatus.queryOptions(
      { host, port, token: token ?? "" },
      {
        enabled: isConnected && !!token && shouldShow,
        staleTime: 30000, // 30 seconds
        refetchInterval: 60000, // Refresh every minute
      },
    ),
  );

  // Don't render if features are not enabled
  if (!shouldShow) {
    return null;
  }

  // Loading state
  if (isLoading || !securityStatus) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 font-medium text-base">
            <ShieldCheck className="h-4 w-4 text-accent" />
            Security Status
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            <span className="ml-2 text-muted-foreground text-sm">
              Checking security status...
            </span>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Error state
  if (error) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 font-medium text-base">
            <ShieldAlert className="h-4 w-4 text-destructive" />
            Security Status
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 p-3">
            <AlertCircle className="h-5 w-5 text-destructive" />
            <p className="text-destructive text-sm">
              Unable to check security status
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Calculate overall status
  const awsOk = !securityStatus.aws.enabled || securityStatus.aws.valid;
  const certOk =
    !securityStatus.certificate.enabled || securityStatus.certificate.valid;
  const caOk =
    !securityStatus.certificate.enabled ||
    securityStatus.certificate.ca_reachable;
  const allOk = awsOk && certOk && caOk;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 font-medium text-base">
          {allOk ? (
            <ShieldCheck className="h-4 w-4 text-accent" />
          ) : (
            <ShieldAlert className="h-4 w-4 text-yellow-500" />
          )}
          Security Status
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {awsEnabled && <AWSStatusSection status={securityStatus.aws} />}
        {stepCaEnabled && (
          <CertificateStatusSection status={securityStatus.certificate} />
        )}

        {allOk && (
          <div className="rounded-lg border border-accent/20 bg-accent/5 p-3">
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-accent" />
              <span className="font-medium text-foreground text-sm">
                All security checks passed
              </span>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
