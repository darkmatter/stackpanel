/**
 * Type definitions for Network Panel
 */

export type StepCaData = {
  enable?: boolean;
  ca_url?: string;
  ca_fingerprint?: string;
  cert_name?: string;
  provisioner?: string;
  prompt_on_shell?: boolean;
};

export type DnsRecord = {
  type?: string;
  name?: string;
  value?: string;
  ttl?: number;
  comment?: string;
};

export type DnsZone = {
  domain?: string;
  records?: DnsRecord[];
};

export type DnsData = {
  zones?: Record<string, DnsZone>;
};

export type TailscaleDevice = {
  name: string;
  type: "laptop" | "server" | "phone";
  ip: string;
  status: "online" | "offline";
  os: string;
};

export type CertificateItem = {
  name: string;
  type: string;
  detail: string;
};

export type ProcessedDnsRecord = {
  domain: string;
  target: string;
  type: string;
  comment: string;
};

export interface NetworkStatsProps {
  devicesOnline: number;
  activeCertificates: number;
  internalDomains: number;
}

export interface DeviceListProps {
  devices: TailscaleDevice[];
}

export interface CertificatesTabProps {
  stepEnabled: boolean;
  certificates: CertificateItem[];
  caUrl: string | null;
  caFingerprint: string | null;
  isEnabling: boolean;
  onEnableStepCa: () => void;
  onViewCaConfig: () => void;
}

export interface DnsTabProps {
  stepEnabled: boolean;
  dnsRecords: ProcessedDnsRecord[];
  dnsZoneLabel: string | null;
  onAddRecord: () => void;
}

export interface AddRecordDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (record: NewDnsRecord) => void;
  isSaving: boolean;
  dnsZoneLabel: string | null;
}

export interface NewDnsRecord {
  name: string;
  type: string;
  value: string;
  comment: string;
}

export interface ViewCaConfigDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  caUrl: string | null;
  caFingerprint: string | null;
  stepEnabled: boolean;
  certificates: CertificateItem[];
}
