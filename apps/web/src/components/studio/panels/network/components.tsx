/**
 * Reusable components for the Network Panel
 */

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
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
import type {
	NetworkStatsProps,
	DeviceListProps,
	CertificatesTabProps,
	DnsTabProps,
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
