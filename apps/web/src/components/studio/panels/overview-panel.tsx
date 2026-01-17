"use client";

import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import {
	Activity,
	ArrowUpRight,
	CheckCircle2,
	Clock,
	Cpu,
	Database,
	HardDrive,
	KeyRound,
	Server,
	Terminal,
	Users,
	Wifi,
} from "lucide-react";
import { AgentConnect } from "@/components/agent-connect";
import { SecurityStatusCard } from "@/components/studio/security-status-card";

const quickStats = [
	{
		label: "Services",
		value: "12",
		change: "+2 this week",
		icon: Server,
		path: "/studio/services",
	},
	{
		label: "Databases",
		value: "4",
		change: "3 PostgreSQL, 1 Redis",
		icon: Database,
		path: "/studio/databases",
	},
	{
		label: "Secrets",
		value: "47",
		change: "Last rotated 3d ago",
		icon: KeyRound,
		path: "/studio/secrets",
	},
	{
		label: "Team Members",
		value: "8",
		change: "All active",
		icon: Users,
		path: "/studio/team",
	},
];

const recentActivity = [
	{
		action: "Deployed",
		target: "api-gateway v2.4.1",
		user: "Sarah",
		time: "2 min ago",
		status: "success",
	},
	{
		action: "Secret rotated",
		target: "DATABASE_URL",
		user: "System",
		time: "3 hours ago",
		status: "success",
	},
	{
		action: "Service scaled",
		target: "worker-service",
		user: "Mike",
		time: "5 hours ago",
		status: "success",
	},
	{
		action: "New member",
		target: "alex@acme.com",
		user: "Admin",
		time: "1 day ago",
		status: "pending",
	},
	{
		action: "Database backup",
		target: "main-postgres",
		user: "System",
		time: "1 day ago",
		status: "success",
	},
];

const systemHealth = [
	{ name: "CPU Usage", value: 34, max: 100, unit: "%", icon: Cpu },
	{ name: "Memory", value: 12.4, max: 32, unit: "GB", icon: HardDrive },
	{ name: "Network", value: 2.1, max: 10, unit: "Gbps", icon: Wifi },
];

export function OverviewPanel() {
	return (
		<div className="space-y-6">
			{/* Agent Connection Status */}
			{/*<AgentConnect />*/}

			{/* Security Status (AWS Session & Certificates) */}
			<SecurityStatusCard />

			{/* Quick Stats */}
			<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
				{quickStats.map((stat) => {
					const Icon = stat.icon;
					return (
						<Link key={stat.label} to={stat.path}>
							<Card className="cursor-pointer transition-colors hover:border-accent/50">
								<CardContent className="p-6">
									<div className="flex items-center justify-between">
										<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
											<Icon className="h-5 w-5 text-accent" />
										</div>
										<ArrowUpRight className="h-4 w-4 text-muted-foreground" />
									</div>
									<div className="mt-4">
										<p className="font-bold text-3xl text-foreground">
											{stat.value}
										</p>
										<p className="text-muted-foreground text-sm">
											{stat.label}
										</p>
									</div>
									<p className="mt-2 text-muted-foreground text-xs">
										{stat.change}
									</p>
								</CardContent>
							</Card>
						</Link>
					);
				})}
			</div>

			<div className="grid gap-6 lg:grid-cols-3">
				{/* Recent Activity */}
				<Card className="lg:col-span-2">
					<CardHeader className="flex flex-row items-center justify-between">
						<CardTitle className="font-medium text-base">
							Recent Activity
						</CardTitle>
						<Button className="text-muted-foreground" size="sm" variant="ghost">
							View all
						</Button>
					</CardHeader>
					<CardContent>
						<div className="space-y-4">
							{recentActivity.map((activity, index) => (
								<div className="flex items-center justify-between" key={index}>
									<div className="flex items-center gap-3">
										<div
											className={`flex h-8 w-8 items-center justify-center rounded-full ${
												activity.status === "success"
													? "bg-accent/10"
													: "bg-yellow-500/10"
											}`}
										>
											{activity.status === "success" ? (
												<CheckCircle2 className="h-4 w-4 text-accent" />
											) : (
												<Clock className="h-4 w-4 text-yellow-500" />
											)}
										</div>
										<div>
											<p className="text-foreground text-sm">
												<span className="font-medium">{activity.action}</span>{" "}
												<span className="text-muted-foreground">
													{activity.target}
												</span>
											</p>
											<p className="text-muted-foreground text-xs">
												by {activity.user}
											</p>
										</div>
									</div>
									<span className="text-muted-foreground text-xs">
										{activity.time}
									</span>
								</div>
							))}
						</div>
					</CardContent>
				</Card>

				{/* System Health */}
				<Card>
					<CardHeader>
						<CardTitle className="flex items-center gap-2 font-medium text-base">
							<Activity className="h-4 w-4 text-accent" />
							System Health
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-6">
						{systemHealth.map((metric) => {
							const Icon = metric.icon;
							const percentage = (metric.value / metric.max) * 100;
							return (
								<div className="space-y-2" key={metric.name}>
									<div className="flex items-center justify-between text-sm">
										<div className="flex items-center gap-2 text-muted-foreground">
											<Icon className="h-4 w-4" />
											{metric.name}
										</div>
										<span className="font-medium text-foreground">
											{metric.value} {metric.unit}
										</span>
									</div>
									<div className="h-2 rounded-full bg-secondary">
										<div
											className="h-full rounded-full bg-accent transition-all"
											style={{ width: `${percentage}%` }}
										/>
									</div>
								</div>
							);
						})}

						<div className="rounded-lg border border-border bg-secondary/30 p-3">
							<div className="flex items-center gap-2">
								<span className="h-2 w-2 rounded-full bg-accent" />
								<span className="font-medium text-foreground text-sm">
									All systems operational
								</span>
							</div>
							<p className="mt-1 text-muted-foreground text-xs">
								Last checked 30 seconds ago
							</p>
						</div>
					</CardContent>
				</Card>
			</div>

			{/* Quick Actions */}
			<Card>
				<CardHeader>
					<CardTitle className="font-medium text-base">Quick Actions</CardTitle>
				</CardHeader>
				<CardContent>
					<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
						<Link to="/studio/services">
							<Button
								className="h-auto w-full flex-col gap-2 bg-transparent py-4"
								variant="outline"
							>
								<Server className="h-5 w-5 text-accent" />
								<span>Deploy Service</span>
							</Button>
						</Link>
						<Link to="/studio/databases">
							<Button
								className="h-auto w-full flex-col gap-2 bg-transparent py-4"
								variant="outline"
							>
								<Database className="h-5 w-5 text-accent" />
								<span>Create Database</span>
							</Button>
						</Link>
						<Link to="/studio/secrets">
							<Button
								className="h-auto w-full flex-col gap-2 bg-transparent py-4"
								variant="outline"
							>
								<KeyRound className="h-5 w-5 text-accent" />
								<span>Add Secret</span>
							</Button>
						</Link>
						<Link to="/studio/terminal">
							<Button
								className="h-auto w-full flex-col gap-2 bg-transparent py-4"
								variant="outline"
							>
								<Terminal className="h-5 w-5 text-accent" />
								<span>Open Terminal</span>
							</Button>
						</Link>
					</div>
				</CardContent>
			</Card>
		</div>
	);
}
