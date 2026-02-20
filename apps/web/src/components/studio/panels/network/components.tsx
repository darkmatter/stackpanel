/**
 * Reusable components for the Network Panel
 */

import { useState } from "react";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
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
import {
  CheckCircle2,
  Copy,
  ExternalLink,
  Globe,
  Laptop,
  Lock,
  Loader2,
  Network,
  Plus,
  RefreshCw,
  Server,
  Shield,
  Smartphone,
} from "lucide-react";
import type {
  NetworkStatsProps,
  DeviceListProps,
  CertificatesTabProps,
  DnsTabProps,
  AddRecordDialogProps,
  ViewCaConfigDialogProps,
} from "./types";

// =============================================================================
// Network Stats Cards
// =============================================================================

export function NetworkStats({
  devicesOnline,
  activeCertificates,
  internalDomains,
}: NetworkStatsProps) {
  return (
    <div className="grid gap-4 sm:grid-cols-3">
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
              <Network className="h-5 w-5 text-accent" />
            </div>
            <div>
              <p className="font-bold text-2xl text-foreground">
                {devicesOnline}
              </p>
              <p className="text-muted-foreground text-sm">Devices Online</p>
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
                {activeCertificates}
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
                {internalDomains}
              </p>
              <p className="text-muted-foreground text-sm">Internal Domains</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// =============================================================================
// Devices List
// =============================================================================

export function DevicesList({ devices }: DeviceListProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="font-medium text-base">
          Connected Devices
        </CardTitle>
        <Button className="gap-2 bg-transparent" size="sm" variant="outline">
          <RefreshCw className="h-4 w-4" />
          Refresh
        </Button>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {devices.map((device) => {
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
                    <p className="text-muted-foreground text-sm">{device.os}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <code className="text-muted-foreground text-sm">
                    {device.ip}
                  </code>
                  <Button className="h-8 w-8" size="icon" variant="ghost">
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}

// =============================================================================
// Certificates Tab
// =============================================================================

export function CertificatesTab({
  stepEnabled,
  certificates,
  caUrl,
  caFingerprint,
  isEnabling,
  onEnableStepCa,
  onViewCaConfig,
}: CertificatesTabProps) {
  return (
    <div className="mt-6 space-y-4">
      {!stepEnabled ? (
        <Card className="border-dashed border-muted-foreground/40 bg-secondary/20">
          <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="font-medium text-foreground text-sm">
                Step CA is not enabled yet
              </p>
              <p className="text-muted-foreground text-xs">
                Enable Step CA to issue device and Roles Anywhere certificates.
              </p>
            </div>
            <Button
              onClick={onEnableStepCa}
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
            <Button size="sm" variant="outline" onClick={onViewCaConfig}>
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
    </div>
  );
}

// =============================================================================
// DNS Tab
// =============================================================================

export function DnsTab({
  stepEnabled,
  dnsRecords,
  dnsZoneLabel,
  onAddRecord,
}: DnsTabProps) {
  return (
    <div className="mt-6 space-y-4">
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
          <Button
            size="sm"
            variant="outline"
            disabled={!stepEnabled}
            onClick={onAddRecord}
            className="gap-2"
          >
            <Plus className="h-4 w-4" />
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
                    <Button className="h-8 w-8" size="icon" variant="ghost">
                      <ExternalLink className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// =============================================================================
// Add Record Dialog
// =============================================================================

const DNS_RECORD_TYPES = ["A", "AAAA", "CNAME", "TXT", "MX", "SRV", "NS"];

export function AddRecordDialog({
  open,
  onOpenChange,
  onSubmit,
  isSaving,
  dnsZoneLabel,
}: AddRecordDialogProps) {
  const [name, setName] = useState("");
  const [type, setType] = useState("A");
  const [value, setValue] = useState("");
  const [comment, setComment] = useState("");

  const resetForm = () => {
    setName("");
    setType("A");
    setValue("");
    setComment("");
  };

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen) {
      resetForm();
    }
    onOpenChange(nextOpen);
  };

  const isValid = name.trim() !== "" && value.trim() !== "";

  const handleSubmit = () => {
    if (!isValid) return;
    onSubmit({
      name: name.trim(),
      type,
      value: value.trim(),
      comment: comment.trim(),
    });
    resetForm();
  };

  const zoneSuffix = dnsZoneLabel ? `.${dnsZoneLabel}` : "";

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Add DNS Record</DialogTitle>
          <DialogDescription>
            Add a new internal DNS record
            {dnsZoneLabel ? (
              <>
                {" "}
                to the <code className="text-accent">{dnsZoneLabel}</code> zone
              </>
            ) : null}
            .
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="record-name">Hostname</Label>
            <div className="flex items-center gap-1">
              <Input
                id="record-name"
                placeholder="e.g. api, db, grafana"
                value={name}
                onChange={(e) => setName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && isValid) {
                    handleSubmit();
                  }
                }}
              />
              {zoneSuffix && (
                <span className="shrink-0 text-muted-foreground text-sm">
                  {zoneSuffix}
                </span>
              )}
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="record-type">Record Type</Label>
            <Select value={type} onValueChange={setType}>
              <SelectTrigger id="record-type">
                <SelectValue placeholder="Select type" />
              </SelectTrigger>
              <SelectContent>
                {DNS_RECORD_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>
                    {t}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="record-value">Value</Label>
            <Input
              id="record-value"
              placeholder={
                type === "A"
                  ? "e.g. 100.64.0.10"
                  : type === "CNAME"
                    ? "e.g. api-gateway.internal"
                    : type === "AAAA"
                      ? "e.g. fd7a:115c:a1e0::1"
                      : type === "MX"
                        ? "e.g. 10 mail.internal"
                        : "Value"
              }
              value={value}
              onChange={(e) => setValue(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && isValid) {
                  handleSubmit();
                }
              }}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="record-comment">
              Description{" "}
              <span className="text-muted-foreground">(optional)</span>
            </Label>
            <Input
              id="record-comment"
              placeholder="e.g. API gateway endpoint"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && isValid) {
                  handleSubmit();
                }
              }}
            />
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => handleOpenChange(false)}
            disabled={isSaving}
          >
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={!isValid || isSaving}>
            {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Add Record
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// =============================================================================
// View CA Config Dialog
// =============================================================================

export function ViewCaConfigDialog({
  open,
  onOpenChange,
  caUrl,
  caFingerprint,
  stepEnabled,
  certificates,
}: ViewCaConfigDialogProps) {
  const [copiedField, setCopiedField] = useState<string | null>(null);

  const handleCopy = (value: string, field: string) => {
    navigator.clipboard.writeText(value);
    setCopiedField(field);
    setTimeout(() => setCopiedField(null), 2000);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Certificate Authority Configuration</DialogTitle>
          <DialogDescription>
            Internal CA details for your Step CA instance.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label className="text-muted-foreground text-xs uppercase tracking-wide">
                Status
              </Label>
              <div className="flex items-center gap-2">
                {stepEnabled ? (
                  <>
                    <CheckCircle2 className="h-4 w-4 text-accent" />
                    <span className="font-medium text-accent text-sm">
                      Active
                    </span>
                  </>
                ) : (
                  <>
                    <Shield className="h-4 w-4 text-muted-foreground" />
                    <span className="font-medium text-muted-foreground text-sm">
                      Inactive
                    </span>
                  </>
                )}
              </div>
            </div>

            {caUrl && (
              <div className="space-y-1.5">
                <Label className="text-muted-foreground text-xs uppercase tracking-wide">
                  CA URL
                </Label>
                <div className="flex items-center gap-2">
                  <code className="flex-1 rounded-md border border-border bg-secondary/50 px-3 py-2 text-foreground text-sm">
                    {caUrl}
                  </code>
                  <Button
                    className="h-8 w-8 shrink-0"
                    size="icon"
                    variant="ghost"
                    onClick={() => handleCopy(caUrl, "url")}
                    aria-label="Copy CA URL"
                  >
                    {copiedField === "url" ? (
                      <CheckCircle2 className="h-4 w-4 text-accent" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
            )}

            {caFingerprint && (
              <div className="space-y-1.5">
                <Label className="text-muted-foreground text-xs uppercase tracking-wide">
                  CA Fingerprint
                </Label>
                <div className="flex items-center gap-2">
                  <code className="flex-1 truncate rounded-md border border-border bg-secondary/50 px-3 py-2 font-mono text-foreground text-sm">
                    {caFingerprint}
                  </code>
                  <Button
                    className="h-8 w-8 shrink-0"
                    size="icon"
                    variant="ghost"
                    onClick={() => handleCopy(caFingerprint, "fingerprint")}
                    aria-label="Copy CA fingerprint"
                  >
                    {copiedField === "fingerprint" ? (
                      <CheckCircle2 className="h-4 w-4 text-accent" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
            )}

            {!caUrl && !caFingerprint && stepEnabled && (
              <p className="text-muted-foreground text-sm">
                CA is active but no URL or fingerprint is configured.
                Certificates are managed automatically.
              </p>
            )}

            {certificates.length > 0 && (
              <div className="space-y-1.5">
                <Label className="text-muted-foreground text-xs uppercase tracking-wide">
                  Issued Certificates ({certificates.length})
                </Label>
                <div className="space-y-2">
                  {certificates.map((cert) => (
                    <div
                      className="flex items-center justify-between rounded-md border border-border bg-secondary/30 px-3 py-2"
                      key={`${cert.name}-${cert.type}`}
                    >
                      <div className="flex items-center gap-2">
                        <Shield className="h-4 w-4 text-accent" />
                        <code className="text-foreground text-sm">
                          {cert.name}
                        </code>
                      </div>
                      <Badge className="text-xs" variant="outline">
                        {cert.type}
                      </Badge>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
