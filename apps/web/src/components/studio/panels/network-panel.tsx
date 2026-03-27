"use client";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { TooltipProvider } from "@ui/tooltip";
import { PanelHeader } from "./shared/panel-header";
import {
  NetworkStats,
  DevicesList,
  CertificatesTab,
  DnsTab,
  AddRecordDialog,
  ViewCaConfigDialog,
  MOCK_TAILSCALE_DEVICES,
  useNetwork,
} from "./network";

export function NetworkPanel() {
  const {
    stepEnabled,
    caUrl,
    caFingerprint,
    certificates,
    dnsRecords,
    dnsZoneLabel,
    isEnabling,
    handleEnableStepCa,
    addRecordDialogOpen,
    setAddRecordDialogOpen,
    handleAddRecord,
    isSavingRecord,
    viewCaConfigDialogOpen,
    setViewCaConfigDialogOpen,
  } = useNetwork();

  const devicesOnline = MOCK_TAILSCALE_DEVICES.filter(
    (d) => d.status === "online",
  ).length;

  return (
    <TooltipProvider>
      <div className="space-y-6">
        <PanelHeader
          title="Network"
          description="Tailscale mesh network, internal CA, and DNS configuration"
          guideKey="network"
        />

        <NetworkStats
          devicesOnline={devicesOnline}
          activeCertificates={stepEnabled ? certificates.length : 0}
          internalDomains={stepEnabled ? dnsRecords.length : 0}
        />

        <Tabs defaultValue="dns">
          <TabsList>
            {/*<TabsTrigger value="devices">Tailscale Devices</TabsTrigger>*/}
            <TabsTrigger value="dns">Internal DNS</TabsTrigger>
            <TabsTrigger value="certificates">Certificates</TabsTrigger>
          </TabsList>

          <TabsContent value="devices">
            <DevicesList devices={MOCK_TAILSCALE_DEVICES} />
          </TabsContent>

          <TabsContent value="certificates">
            <CertificatesTab
              stepEnabled={stepEnabled}
              certificates={certificates}
              caUrl={caUrl}
              caFingerprint={caFingerprint}
              isEnabling={isEnabling}
              onEnableStepCa={handleEnableStepCa}
              onViewCaConfig={() => setViewCaConfigDialogOpen(true)}
            />
          </TabsContent>

          <TabsContent value="dns">
            <DnsTab
              stepEnabled={stepEnabled}
              dnsRecords={dnsRecords}
              dnsZoneLabel={dnsZoneLabel}
              onAddRecord={() => setAddRecordDialogOpen(true)}
            />
          </TabsContent>
        </Tabs>

        <AddRecordDialog
          open={addRecordDialogOpen}
          onOpenChange={setAddRecordDialogOpen}
          onSubmit={handleAddRecord}
          isSaving={isSavingRecord}
          dnsZoneLabel={dnsZoneLabel}
        />

        <ViewCaConfigDialog
          open={viewCaConfigDialogOpen}
          onOpenChange={setViewCaConfigDialogOpen}
          caUrl={caUrl}
          caFingerprint={caFingerprint}
          stepEnabled={stepEnabled}
          certificates={certificates}
        />
      </div>
    </TooltipProvider>
  );
}
