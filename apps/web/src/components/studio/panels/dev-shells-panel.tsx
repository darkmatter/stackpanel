"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Checkbox } from "@ui/checkbox";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Switch } from "@ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { TooltipProvider } from "@ui/tooltip";
import {
	AlertTriangle,
	Code,
	FileCode,
	GitBranch,
	Loader2,
	Package,
	Play,
	Plus,
	Terminal,
} from "lucide-react";
import { useDevShells } from "./devshells";
import { PanelHeader } from "./shared/panel-header";

export function DevShellsPanel() {
	const {
		dialogOpen,
		setDialogOpen,
		activeTab,
		setActiveTab,
		visibleItems,
		healthStatus,
		token,
		availableTools,
		scripts,
		devShells,
	} = useDevShells();

	return (
		<TooltipProvider>
			<div className="space-y-6">
				<PanelHeader
					title="Dev Shells"
					description="Nix-based development environments powered by devenv"
					guideKey="devshell"
					actions={
						<Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
							<DialogTrigger asChild>
								<Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
									<Plus className="h-4 w-4" />
									Create Shell
								</Button>
							</DialogTrigger>
							<DialogContent className="max-w-2xl">
								<DialogHeader>
									<DialogTitle>Create Dev Shell</DialogTitle>
									<DialogDescription>
										Configure a new Nix development environment for your team.
									</DialogDescription>
								</DialogHeader>
								<div className="grid gap-4 py-4">
									<div className="grid gap-2">
										<Label htmlFor="shell-name">Shell Name</Label>
										<Input id="shell-name" placeholder="my-shell" />
									</div>
									<div className="grid gap-2">
										<Label>Languages & Runtimes</Label>
										<div className="grid grid-cols-3 gap-2">
											{availableTools
												.filter(
													(t) =>
														t.category === "language" ||
														t.category === "runtime",
												)
												.map((tool) => (
													<label
														className="flex cursor-pointer items-center gap-2 rounded-lg border border-border p-3 hover:bg-secondary/50"
														key={tool.id}
													>
														<Checkbox id={tool.id} />
														<div className="text-sm">
															<p className="font-medium text-foreground">
																{tool.name}
															</p>
															<p className="text-muted-foreground text-xs">
																{tool.version}
															</p>
														</div>
													</label>
												))}
										</div>
									</div>
									<div className="grid gap-2">
										<Label>Git Hooks</Label>
										<div className="flex gap-4">
											<label className="flex items-center gap-2">
												<Checkbox id="pre-commit" />
												<span className="text-sm">pre-commit</span>
											</label>
											<label className="flex items-center gap-2">
												<Checkbox id="commit-msg" />
												<span className="text-sm">commit-msg</span>
											</label>
											<label className="flex items-center gap-2">
												<Checkbox id="pre-push" />
												<span className="text-sm">pre-push</span>
											</label>
										</div>
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
										Create Shell
									</Button>
								</DialogFooter>
							</DialogContent>
						</Dialog>
					}
				/>

				<Tabs onValueChange={setActiveTab} value={activeTab}>
					<TabsList>
						<TabsTrigger value="shells">Shells</TabsTrigger>
						<TabsTrigger value="tools">Available Tools</TabsTrigger>
						<TabsTrigger value="scripts">Scripts</TabsTrigger>
					</TabsList>

					<TabsContent className="mt-6 space-y-4" value="shells">
						{healthStatus === "checking" && (
							<Card>
								<CardContent className="flex items-center gap-2 p-4 text-muted-foreground text-sm">
									<Loader2 className="h-4 w-4 animate-spin" />
									Checking agent status...
								</CardContent>
							</Card>
						)}
						{healthStatus === "unavailable" && (
							<Card className="border-amber-500/40 bg-amber-500/10">
								<CardContent className="flex items-center gap-2 p-4 text-amber-600 text-sm dark:text-amber-400">
									<AlertTriangle className="h-4 w-4" />
									Agent unavailable. Start the agent to load devshell data.
								</CardContent>
							</Card>
						)}
						{healthStatus === "available" && !token && (
							<Card className="border-amber-500/40 bg-amber-500/10">
								<CardContent className="flex items-center gap-2 p-4 text-amber-600 text-sm dark:text-amber-400">
									<AlertTriangle className="h-4 w-4" />
									Pair with the agent to load devshell data.
								</CardContent>
							</Card>
						)}
						{devShells.length === 0 ? (
							<Card>
								<CardContent className="p-6">
									<p className="text-muted-foreground text-sm">
										Connect to the agent to load devshell details.
									</p>
								</CardContent>
							</Card>
						) : (
							devShells.map((shell) => (
								<Card key={shell.name}>
									<CardContent className="p-6">
										<div className="flex items-start justify-between">
											<div className="flex items-start gap-4">
												<div className="flex h-12 w-12 items-center  shrink-0 justify-center rounded-lg bg-accent/10">
													<Terminal className="h-6 w-6 text-accent" />
												</div>
												<div>
													<div className="flex items-center gap-2">
														<h3 className="font-medium text-foreground">
															{shell.name}
														</h3>
														{shell.active && (
															<Badge
																className="border-accent text-accent"
																variant="outline"
															>
																Active
															</Badge>
														)}
													</div>
													<p className="mt-1 text-muted-foreground text-sm">
														{shell.description}
													</p>

													<div className="mt-4 space-y-3">
														<div className="flex items-center gap-2">
															<Code className="h-4 w-4 text-muted-foreground" />
															<div className="flex flex-wrap gap-1">
																{shell.languages.map((lang) => (
																	<Badge
																		className="text-xs"
																		key={lang}
																		variant="secondary"
																	>
																		{lang}
																	</Badge>
																))}
															</div>
														</div>
														<div className="flex items-center gap-2">
															<Package className="h-4 w-4 text-muted-foreground" />
															<div className="flex flex-wrap gap-1">
																{shell.tools
																	.slice(0, visibleItems)
																	.map((tool) => (
																		<Badge
																			className="text-xs"
																			key={tool}
																			variant="outline"
																		>
																			{tool}
																		</Badge>
																	))}
																{shell.tools.length > visibleItems && (
																	<Badge className="text-xs" variant="outline">
																		{shell.tools.length - visibleItems}+
																	</Badge>
																)}
															</div>
														</div>
														{shell.hooks.length > 0 && (
															<div className="flex items-center gap-2">
																<GitBranch className="h-4 w-4 text-muted-foreground" />
																<div className="flex flex-wrap gap-1">
																	{shell.hooks.map((hook) => (
																		<Badge
																			className="border-accent/50 text-accent text-xs"
																			key={hook}
																			variant="outline"
																		>
																			{hook}
																		</Badge>
																	))}
																</div>
															</div>
														)}
													</div>
												</div>
											</div>

											<div className="flex items-center gap-4">
												<div className="flex items-center gap-2">
													<Label
														className="text-muted-foreground text-sm"
														htmlFor={`active-${shell.name}`}
													>
														Active
													</Label>
													<Switch
														checked={shell.active}
														id={`active-${shell.name}`}
													/>
												</div>
												<Button size="sm" variant="outline">
													Edit
												</Button>
											</div>
										</div>
									</CardContent>
								</Card>
							))
						)}
					</TabsContent>

					<TabsContent className="mt-6" value="tools">
						{availableTools.length === 0 ? (
							<Card>
								<CardContent className="p-6">
									<p className="text-muted-foreground text-sm">
										No installed tools detected yet.
									</p>
								</CardContent>
							</Card>
						) : (
							<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
								{availableTools.map((tool) => (
									<Card
										className="cursor-pointer transition-colors hover:border-accent/50"
										key={tool.id}
									>
										<CardContent className="flex items-center gap-4 p-4">
											<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
												<Package className="h-5 w-5 text-muted-foreground" />
											</div>
											<div className="flex-1">
												<p className="font-medium text-foreground">
													{tool.name}
												</p>
												<p className="text-muted-foreground text-sm">
													{tool.version}
												</p>
											</div>
											<Badge className="text-xs" variant="outline">
												{tool.category}
											</Badge>
										</CardContent>
									</Card>
								))}
							</div>
						)}
					</TabsContent>

					<TabsContent className="mt-6 space-y-4" value="scripts">
						<Card>
							<CardHeader>
								<CardTitle className="flex items-center gap-2 text-base">
									<FileCode className="h-5 w-5 text-accent" />
									Available Scripts
								</CardTitle>
							</CardHeader>
							<CardContent className="space-y-3">
								{scripts.length === 0 ? (
									<p className="text-muted-foreground text-sm">
										No scripts configured yet.
									</p>
								) : (
									scripts.map((script) => (
										<div
											className="flex items-center justify-between rounded-lg border border-border bg-secondary/30 p-3"
											key={script.name}
										>
											<div className="flex items-center gap-3">
												<code className="font-medium text-accent text-sm">
													{script.name}
												</code>
												<span className="text-muted-foreground text-sm">
													{script.description}
												</span>
											</div>
											<Button className="gap-2" size="sm" variant="ghost">
												<Play className="h-4 w-4" />
												Run
											</Button>
										</div>
									))
								)}
							</CardContent>
						</Card>
					</TabsContent>
				</Tabs>
			</div>
		</TooltipProvider>
	);
}
