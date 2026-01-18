"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { TooltipProvider } from "@ui/tooltip";
import {
  CheckCircle2,
  Copy,
  ExternalLink,
  Globe,
  Laptop,
  Lock,
  Network,
  RefreshCw,
  Server,
  Shield,
  Smartphone,
} from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import { useNixConfig, useNixData } from "@/lib/use-nix-config";
import { PanelHeader } from "./shared/panel-header";

type StepCaData = {
  enable?: boolean;
  ca_url?: string;
  ca_fingerprint?: string;
  cert_name?: string;
  provisioner?: string;
  prompt_on_shell?: boolean;
};

type DnsRecord = {
  type?: string;
  name?: string;
  value?: string;
  ttl?: number;
  comment?: string;
};

type DnsZone = {
  domain?: string;
  records?: DnsRecord[];
};

type DnsData = {
  zones?: Record<string, DnsZone>;
};

const tailscaleDevices = [
  {
    name: "janes-macbook",
    type: "laptop",
    ip: "100.64.0.1",
    status: "online",
    os: "macOS",
  },
  {
    name: "mikes-workstation",
    type: "laptop",
    ip: "100.64.0.2",
    status: "online",
    os: "Linux",
  },
  {
    name: "api-gateway-1",
    type: "server",
    ip: "100.64.0.10",
    status: "online",
    os: "Linux",
  },
  {
    name: "api-gateway-2",
    type: "server",
    ip: "100.64.0.11",
    status: "online",
    os: "Linux",
  },
  {
    name: "db-primary",
    type: "server",
    ip: "100.64.0.20",
    status: "online",
    os: "Linux",
  },
  {
    name: "sarahs-iphone",
    type: "phone",
    ip: "100.64.0.3",
    status: "offline",
    os: "iOS",
  },
];

type CertificateItem = {
  name: string;
  type: string;
  detail: string;
};

export function NetworkPanel() {
  const { data: config } = useNixConfig();
  const { data: stepCaData, mutate: setStepCa } =
    useNixData<StepCaData>("step-ca");
  const { data: dnsData } = useNixData<DnsData>("dns");
  const [isEnabling, setIsEnabling] = useState(false);

  const stepConfig = config?.stepCa?.["step-ca"];
  const stepEnabled = stepConfig?.enable ?? stepCaData?.enable ?? false;
  const caUrl = stepConfig?.["ca-url"] ?? stepCaData?.ca_url;
  const caFingerprint =
    stepConfig?.["ca-fingerprint"] ?? stepCaData?.ca_fingerprint;
  const certName = stepConfig?.["cert-name"] ?? stepCaData?.cert_name;
  const awsRolesAnywhere = config?.aws?.["roles-anywhere"];

  const certificates = useMemo(() => {
    const items: CertificateItem[] = [];

    if (stepEnabled) {
      items.push({
        name: certName ?? "Device certificate",
        type: "Step CA",
        detail: caUrl ? `CA: ${caUrl}` : "Managed by Step CA",
      });
    }

    if (awsRolesAnywhere?.enable) {
      items.push({
        name: awsRolesAnywhere["role-name"] ?? "AWS Roles Anywhere",
        type: "AWS Roles Anywhere",
        detail: awsRolesAnywhere["profile-arn"]
          ? `Profile: ${awsRolesAnywhere["profile-arn"]}`
          : "Certificate auth enabled",
      });
    }

    return items;
  }, [awsRolesAnywhere, caUrl, certName, stepEnabled]);

  const dnsRecords = useMemo(() => {
    const zones = dnsData?.zones ?? {};
    return Object.values(zones).flatMap((zone) => {
      const domain = zone.domain ?? "";
      return (zone.records ?? []).map((record) => {
        const host =
          record.name && record.name !== "@"
            ? `${record.name}.${domain}`
            : domain;
        return {
          domain: host || domain,
          target: record.value ?? "",
          type: record.type ?? "",
          comment: record.comment ?? "",
        };
      });
    });
  }, [dnsData]);

  const dnsZoneLabel = useMemo(() => {
    const zones = Object.values(dnsData?.zones ?? {});
    return zones[0]?.domain ?? null;
  }, [dnsData]);

  const handleEnableStepCa = useCallback(async () => {
    if (isEnabling) return;
    setIsEnabling(true);
    try {
      await setStepCa({
        ...(stepCaData ?? {}),
        enable: true,
      });
    } finally {
      setIsEnabling(false);
    }
  }, [isEnabling, setStepCa, stepCaData]);

  return (
    <TooltipProvider>
      <div className="space-y-6">
        <PanelHeader
          title="Network"
          description="Tailscale mesh network, internal CA, and DNS configuration"
          guideKey="network"
        />

        <div className="grid gap-4 sm:grid-cols-3">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                  <Network className="h-5 w-5 text-accent" />
                </div>
                <div>
                  <p className="font-bold text-2xl text-foreground">
                    {
                      tailscaleDevices.filter((d) => d.status === "online")
                        .length
                    }
                  </p>
                  <p className="text-muted-foreground text-sm">
                    Devices Online
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                  <Shield className="h-5 w-5 text-accent" />
                </div>
                <div>
                  <p className="font-bold text-2xl text-foreground">
                    {stepEnabled ? certificates.length : 0}
                  </p>
                  <p className="text-muted-foreground text-sm">
                    Active Certificates
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                  <Globe className="h-5 w-5 text-accent" />
                </div>
                <div>
                  <p className="font-bold text-2xl text-foreground">
                    {stepEnabled ? dnsRecords.length : 0}
                  </p>
                  <p className="text-muted-foreground text-sm">
                    Internal Domains
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <Tabs defaultValue="dns">
          <TabsList>
            {/*<TabsTrigger value="devices">Tailscale Devices</TabsTrigger>*/}
            <TabsTrigger value="dns">Internal DNS</TabsTrigger>
            <TabsTrigger value="certificates">Certificates</TabsTrigger>
          </TabsList>

          <TabsContent className="mt-6 space-y-4" value="devices">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle className="font-medium text-base">
                  Connected Devices
                </CardTitle>
                <Button
                  className="gap-2 bg-transparent"
                  size="sm"
                  variant="outline"
                >
                  <RefreshCw className="h-4 w-4" />
                  Refresh
                </Button>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  {tailscaleDevices.map((device) => {
                    const Icon =
                      device.type === "server"
                        ? Server
                        : device.type === "phone"
                          ? Smartphone
                          : Laptop;
                    return (
                      <div
                        className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
                        key={device.name}
                      >
                        <div className="flex items-center gap-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
                            <Icon className="h-5 w-5 text-muted-foreground" />
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <p className="font-medium text-foreground">
                                {device.name}
                              </p>
                              <Badge
                                className={
                                  device.status === "online"
                                    ? "border-accent text-accent"
                                    : "border-muted-foreground text-muted-foreground"
                                }
                                variant="outline"
                              >
                                {device.status}
                              </Badge>
                            </div>
                            <p className="text-muted-foreground text-sm">
                              {device.os}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <code className="text-muted-foreground text-sm">
                            {device.ip}
                          </code>
                          <Button
                            className="h-8 w-8"
                            size="icon"
                            variant="ghost"
                          >
                            <Copy className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent className="mt-6 space-y-4" value="certificates">
            {!stepEnabled ? (
              <Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
                <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="font-medium text-foreground text-sm">
                      Step CA is not enabled yet
                    </p>
                    <p className="text-muted-foreground text-xs">
                      Enable Step CA to issue device and Roles Anywhere
                      certificates.
                    </p>
                  </div>
                  <Button
                    onClick={handleEnableStepCa}
                    disabled={isEnabling}
                    size="sm"
                    variant="outline"
                  >
                    {isEnabling ? "Enabling..." : "Enable Step CA"}
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="border-accent/20 bg-accent/5">
                <CardContent className="flex items-center gap-4 p-4">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
                    <Lock className="h-5 w-5 text-accent" />
                  </div>
                  <div className="flex-1">
                    <p className="font-medium text-foreground text-sm">
                      Internal Certificate Authority
                    </p>
                    <p className="text-muted-foreground text-xs">
                      {caUrl
                        ? `CA URL: ${caUrl}`
                        : "Certificates are issued automatically for the team."}
                    </p>
                    {caFingerprint && (
                      <p className="text-muted-foreground text-xs">
                        Fingerprint: {caFingerprint}
                      </p>
                    )}
                  </div>
                  <Button size="sm" variant="outline">
                    View CA Config
                  </Button>
                </CardContent>
              </Card>
            )}

            <Card>
              <CardHeader>
                <CardTitle className="font-medium text-base">
                  Issued Certificates
                </CardTitle>
              </CardHeader>
              <CardContent>
                {!stepEnabled ? (
                  <p className="text-muted-foreground text-sm">
                    Enable Step CA to view certificate inventory.
                  </p>
                ) : certificates.length === 0 ? (
                  <p className="text-muted-foreground text-sm">
                    No certificates detected yet.
                  </p>
                ) : (
                  <div className="space-y-3">
                    {certificates.map((cert) => (
                      <div
                        className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
                        key={`${cert.name}-${cert.type}`}
                      >
                        <div className="flex items-center gap-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
                            <Shield className="h-5 w-5 text-accent" />
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <code className="font-medium text-foreground text-sm">
                                {cert.name}
                              </code>
                              <Badge className="text-xs" variant="outline">
                                {cert.type}
                              </Badge>
                            </div>
                            <p className="text-muted-foreground text-xs">
                              {cert.detail}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <CheckCircle2 className="h-4 w-4 text-accent" />
                          <span className="text-accent text-sm">Enabled</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent className="mt-6 space-y-4" value="dns">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between">
                <div>
                  <CardTitle className="font-medium text-base">
                    Internal DNS Records
                  </CardTitle>
                  {stepEnabled ? (
                    <p className="mt-1 text-muted-foreground text-sm">
                      Zone:{" "}
                      <code className="text-accent">
                        {dnsZoneLabel ?? "No zones configured"}
                      </code>
                    </p>
                  ) : (
                    <p className="mt-1 text-muted-foreground text-sm">
                      Enable Step CA to manage internal DNS.
                    </p>
                  )}
                </div>
                <Button size="sm" variant="outline" disabled={!stepEnabled}>
                  Add Record
                </Button>
              </CardHeader>
              <CardContent>
                {!stepEnabled ? (
                  <p className="text-muted-foreground text-sm">
                    Enable Step CA to view DNS records.
                  </p>
                ) : dnsRecords.length === 0 ? (
                  <p className="text-muted-foreground text-sm">
                    No DNS records configured yet.
                  </p>
                ) : (
                  <div className="space-y-3">
                    {dnsRecords.map((record) => (
                      <div
                        className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
                        key={`${record.domain}-${record.target}-${record.type}`}
                      >
                        <div className="flex items-center gap-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
                            <Globe className="h-5 w-5 text-muted-foreground" />
                          </div>
                          <div>
                            <code className="font-medium text-foreground text-sm">
                              {record.domain}
                            </code>
                            <p className="text-muted-foreground text-xs">
                              {record.comment || "No description"}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <Badge className="text-xs" variant="outline">
                            {record.type || "record"}
                          </Badge>
                          <code className="text-muted-foreground text-sm">
                            {record.target}
                          </code>
                          <Button
                            className="h-8 w-8"
                            size="icon"
                            variant="ghost"
                          >
                            <ExternalLink className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </TooltipProvider>
  );
}
