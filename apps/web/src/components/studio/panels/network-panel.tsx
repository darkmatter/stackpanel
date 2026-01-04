"use client";

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
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

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

const certificates = [
	{
		name: "*.internal.acme.com",
		type: "Wildcard",
		issued: "2024-01-15",
		expires: "2025-01-15",
		status: "valid",
	},
	{
		name: "api.acme.com",
		type: "Single",
		issued: "2024-02-01",
		expires: "2025-02-01",
		status: "valid",
	},
	{
		name: "db.internal.acme.com",
		type: "Single",
		issued: "2024-01-20",
		expires: "2025-01-20",
		status: "valid",
	},
];

const internalDomains = [
	{ domain: "stackpanel.internal", target: "Dashboard", ip: "100.64.0.100" },
	{ domain: "api.internal", target: "API Gateway", ip: "100.64.0.10" },
	{ domain: "db.internal", target: "PostgreSQL", ip: "100.64.0.20" },
	{ domain: "redis.internal", target: "Redis Cache", ip: "100.64.0.21" },
	{ domain: "logs.internal", target: "ELK Stack", ip: "100.64.0.30" },
	{ domain: "metrics.internal", target: "Prometheus", ip: "100.64.0.31" },
];

export function NetworkPanel() {
	return (
		<div className="space-y-6">
			<div>
				<h2 className="font-semibold text-foreground text-xl">Network</h2>
				<p className="text-muted-foreground text-sm">
					Tailscale mesh network, internal CA, and DNS configuration
				</p>
			</div>

			<div className="grid gap-4 sm:grid-cols-3">
				<Card>
					<CardContent className="p-4">
						<div className="flex items-center gap-3">
							<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
								<Network className="h-5 w-5 text-accent" />
							</div>
							<div>
								<p className="font-bold text-2xl text-foreground">
									{tailscaleDevices.filter((d) => d.status === "online").length}
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
									{certificates.length}
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
									{internalDomains.length}
								</p>
								<p className="text-muted-foreground text-sm">
									Internal Domains
								</p>
							</div>
						</div>
					</CardContent>
				</Card>
			</div>

			<Tabs defaultValue="devices">
				<TabsList>
					<TabsTrigger value="devices">Tailscale Devices</TabsTrigger>
					<TabsTrigger value="certificates">Certificates</TabsTrigger>
					<TabsTrigger value="dns">Internal DNS</TabsTrigger>
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
				</TabsContent>

				<TabsContent className="mt-6 space-y-4" value="certificates">
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
									Certificates are automatically issued to all machines and team
									members via the internal CA.
								</p>
							</div>
							<Button size="sm" variant="outline">
								View CA Config
							</Button>
						</CardContent>
					</Card>

					<Card>
						<CardHeader>
							<CardTitle className="font-medium text-base">
								Issued Certificates
							</CardTitle>
						</CardHeader>
						<CardContent>
							<div className="space-y-3">
								{certificates.map((cert) => (
									<div
										className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
										key={cert.name}
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
													Expires {cert.expires}
												</p>
											</div>
										</div>
										<div className="flex items-center gap-2">
											<CheckCircle2 className="h-4 w-4 text-accent" />
											<span className="text-accent text-sm">Valid</span>
										</div>
									</div>
								))}
							</div>
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
								<p className="mt-1 text-muted-foreground text-sm">
									Search domain:{" "}
									<code className="text-accent">internal.acme.com</code>
								</p>
							</div>
							<Button size="sm" variant="outline">
								Add Record
							</Button>
						</CardHeader>
						<CardContent>
							<div className="space-y-3">
								{internalDomains.map((record) => (
									<div
										className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
										key={record.domain}
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
													{record.target}
												</p>
											</div>
										</div>
										<div className="flex items-center gap-4">
											<code className="text-muted-foreground text-sm">
												{record.ip}
											</code>
											<Button className="h-8 w-8" size="icon" variant="ghost">
												<ExternalLink className="h-4 w-4" />
											</Button>
										</div>
									</div>
								))}
							</div>
						</CardContent>
					</Card>
				</TabsContent>
			</Tabs>
		</div>
	);
}
