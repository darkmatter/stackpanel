"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@ui/dropdown-menu";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { TooltipProvider } from "@ui/tooltip";
import {
	Activity,
	Clock,
	Cpu,
	ExternalLink,
	GitBranch,
	MoreVertical,
	Play,
	Plus,
	RefreshCw,
	Search,
	Square,
} from "lucide-react";
import { useState } from "react";
import { PanelHeader } from "./shared/panel-header";

const services = [
	{
		name: "api-gateway",
		status: "running",
		replicas: "3/3",
		cpu: "12%",
		memory: "256MB",
		lastDeploy: "2 min ago",
		branch: "main",
		image: "api-gateway:v2.4.1",
	},
	{
		name: "auth-service",
		status: "running",
		replicas: "2/2",
		cpu: "8%",
		memory: "128MB",
		lastDeploy: "1 hour ago",
		branch: "main",
		image: "auth-service:v1.2.0",
	},
	{
		name: "worker-service",
		status: "running",
		replicas: "4/4",
		cpu: "45%",
		memory: "512MB",
		lastDeploy: "5 hours ago",
		branch: "main",
		image: "worker-service:v3.1.2",
	},
	{
		name: "frontend",
		status: "running",
		replicas: "2/2",
		cpu: "5%",
		memory: "64MB",
		lastDeploy: "3 days ago",
		branch: "main",
		image: "frontend:v4.0.0",
	},
	{
		name: "notification-service",
		status: "stopped",
		replicas: "0/1",
		cpu: "0%",
		memory: "0MB",
		lastDeploy: "1 week ago",
		branch: "feature/email",
		image: "notification-service:v0.9.0",
	},
	{
		name: "analytics-collector",
		status: "running",
		replicas: "1/1",
		cpu: "22%",
		memory: "384MB",
		lastDeploy: "2 days ago",
		branch: "main",
		image: "analytics-collector:v1.0.5",
	},
];

export function ServicesPanel() {
	const [searchQuery, setSearchQuery] = useState("");
	const [dialogOpen, setDialogOpen] = useState(false);

	const filteredServices = services.filter((service) =>
		service.name.toLowerCase().includes(searchQuery.toLowerCase()),
	);

	return (
		<TooltipProvider>
			<div className="space-y-6">
				<PanelHeader
					title="Services"
					description="Manage your deployed services and infrastructure"
					guideKey="services"
					actions={
						<Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
							<DialogTrigger asChild>
								<Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
									<Plus className="h-4 w-4" />
									Deploy Service
								</Button>
							</DialogTrigger>
							<DialogContent>
								<DialogHeader>
									<DialogTitle>Deploy New Service</DialogTitle>
									<DialogDescription>
										Deploy a new service from your GitHub repository or a custom
										image.
									</DialogDescription>
								</DialogHeader>
								<div className="grid gap-4 py-4">
									<div className="grid gap-2">
										<Label htmlFor="service-name">Service Name</Label>
										<Input id="service-name" placeholder="my-service" />
									</div>
									<div className="grid gap-2">
										<Label htmlFor="repo">Repository</Label>
										<Select>
											<SelectTrigger>
												<SelectValue placeholder="Select repository" />
											</SelectTrigger>
											<SelectContent>
												<SelectItem value="api">acme-corp/api</SelectItem>
												<SelectItem value="frontend">
													acme-corp/frontend
												</SelectItem>
												<SelectItem value="workers">
													acme-corp/workers
												</SelectItem>
											</SelectContent>
										</Select>
									</div>
									<div className="grid gap-2">
										<Label htmlFor="branch">Branch</Label>
										<Input defaultValue="main" id="branch" />
									</div>
									<div className="grid gap-2">
										<Label htmlFor="replicas">Replicas</Label>
										<Select defaultValue="2">
											<SelectTrigger>
												<SelectValue />
											</SelectTrigger>
											<SelectContent>
												<SelectItem value="1">1</SelectItem>
												<SelectItem value="2">2</SelectItem>
												<SelectItem value="3">3</SelectItem>
												<SelectItem value="4">4</SelectItem>
											</SelectContent>
										</Select>
									</div>
								</div>
								<DialogFooter>
									<Button
										onClick={() => setDialogOpen(false)}
										variant="outline"
									>
										Cancel
									</Button>
									<Button className="bg-accent text-accent-foreground hover:bg-accent/90">
										Deploy
									</Button>
								</DialogFooter>
							</DialogContent>
						</Dialog>
					}
				/>

				<div className="flex items-center gap-4">
					<div className="relative max-w-sm flex-1">
						<Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
						<Input
							className="pl-9"
							onChange={(e) => setSearchQuery(e.target.value)}
							placeholder="Search services..."
							value={searchQuery}
						/>
					</div>
					<div className="flex items-center gap-2 text-muted-foreground text-sm">
						<span className="h-2 w-2 rounded-full bg-accent" />
						{services.filter((s) => s.status === "running").length} running
						<span className="mx-2">·</span>
						<span className="h-2 w-2 rounded-full bg-muted-foreground" />
						{services.filter((s) => s.status === "stopped").length} stopped
					</div>
				</div>

				<div className="grid gap-4">
					{filteredServices.map((service) => (
						<Card className="overflow-hidden" key={service.name}>
							<CardContent className="p-0">
								<div className="flex items-center gap-6 p-4">
									<div className="flex min-w-0 flex-1 items-center gap-4">
										<div
											className={`h-3 w-3 rounded-full ${
												service.status === "running"
													? "bg-accent"
													: "bg-muted-foreground"
											}`}
										/>
										<div className="min-w-0">
											<div className="flex items-center gap-2">
												<h3 className="truncate font-medium text-foreground">
													{service.name}
												</h3>
												<Badge className="text-xs" variant="outline">
													{service.replicas}
												</Badge>
											</div>
											<p className="truncate text-muted-foreground text-sm">
												{service.image}
											</p>
										</div>
									</div>

									<div className="hidden items-center gap-8 text-sm lg:flex">
										<div className="flex items-center gap-2 text-muted-foreground">
											<Cpu className="h-4 w-4" />
											<span className="w-12">{service.cpu}</span>
										</div>
										<div className="flex items-center gap-2 text-muted-foreground">
											<Activity className="h-4 w-4" />
											<span className="w-16">{service.memory}</span>
										</div>
										<div className="flex items-center gap-2 text-muted-foreground">
											<GitBranch className="h-4 w-4" />
											<span className="w-24 truncate">{service.branch}</span>
										</div>
										<div className="flex items-center gap-2 text-muted-foreground">
											<Clock className="h-4 w-4" />
											<span className="w-24">{service.lastDeploy}</span>
										</div>
									</div>

									<div className="flex items-center gap-2">
										<Button
											className="text-muted-foreground hover:text-foreground"
											size="icon"
											variant="ghost"
										>
											<ExternalLink className="h-4 w-4" />
										</Button>
										<DropdownMenu>
											<DropdownMenuTrigger asChild>
												<Button
													className="text-muted-foreground hover:text-foreground"
													size="icon"
													variant="ghost"
												>
													<MoreVertical className="h-4 w-4" />
												</Button>
											</DropdownMenuTrigger>
											<DropdownMenuContent align="end">
												{service.status === "running" ? (
													<DropdownMenuItem>
														<Square className="mr-2 h-4 w-4" />
														Stop
													</DropdownMenuItem>
												) : (
													<DropdownMenuItem>
														<Play className="mr-2 h-4 w-4" />
														Start
													</DropdownMenuItem>
												)}
												<DropdownMenuItem>
													<RefreshCw className="mr-2 h-4 w-4" />
													Redeploy
												</DropdownMenuItem>
												<DropdownMenuItem>View logs</DropdownMenuItem>
												<DropdownMenuItem>Edit config</DropdownMenuItem>
												<DropdownMenuItem className="text-destructive">
													Delete
												</DropdownMenuItem>
											</DropdownMenuContent>
										</DropdownMenu>
									</div>
								</div>
							</CardContent>
						</Card>
					))}
				</div>
			</div>
		</TooltipProvider>
	);
}
