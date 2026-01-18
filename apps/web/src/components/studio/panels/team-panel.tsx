"use client";

import { Avatar, AvatarFallback } from "@ui/avatar";
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
	BadgeCheck,
	Key,
	MoreVertical,
	Plus,
	Search,
	Shield,
} from "lucide-react";
import { PanelHeader } from "./shared/panel-header";
import { getRoleColor, useTeam } from "./team";

export function TeamPanel() {
	const {
		searchQuery,
		setSearchQuery,
		dialogOpen,
		setDialogOpen,
		filteredMembers,
		isLoading,
		totalMembers,
		keysRegistered,
		adminCount,
	} = useTeam();

	return (
		<TooltipProvider>
			<div className="space-y-6">
				<PanelHeader
					title="Team"
					description="Manage team members, roles, and secrets access"
					guideKey="team"
					actions={
						<Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
							<DialogTrigger asChild>
								<Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
									<Plus className="h-4 w-4" />
									Invite Member
								</Button>
							</DialogTrigger>
							<DialogContent>
								<DialogHeader>
									<DialogTitle>Invite Team Member</DialogTitle>
									<DialogDescription>
										Send an invitation to join your StackPanel organization via
										SSO.
									</DialogDescription>
								</DialogHeader>
								<div className="grid gap-4 py-4">
									<div className="grid gap-2">
										<Label htmlFor="email">Email Address</Label>
										<Input
											id="email"
											placeholder="colleague@acme.com"
											type="email"
										/>
									</div>
									<div className="grid gap-2">
										<Label>Role</Label>
										<Select defaultValue="developer">
											<SelectTrigger>
												<SelectValue />
											</SelectTrigger>
											<SelectContent>
												<SelectItem value="admin">Admin</SelectItem>
												<SelectItem value="developer">Developer</SelectItem>
												<SelectItem value="viewer">Viewer</SelectItem>
											</SelectContent>
										</Select>
									</div>
									<div className="rounded-lg border border-border bg-secondary/30 p-3">
										<p className="text-muted-foreground text-sm">
											The invited member will receive an email with SSO login
											instructions. Once they log in, they'll be prompted to add
											their age public key for secrets access.
										</p>
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
										Send Invitation
									</Button>
								</DialogFooter>
							</DialogContent>
						</Dialog>
					}
				/>

				<div className="grid gap-4 sm:grid-cols-3">
					<Card>
						<CardContent className="p-4">
							<div className="flex items-center gap-3">
								<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
									<Shield className="h-5 w-5 text-accent" />
								</div>
								<div>
									<p className="font-bold text-2xl text-foreground">
										{totalMembers}
									</p>
									<p className="text-muted-foreground text-sm">Total Members</p>
								</div>
							</div>
						</CardContent>
					</Card>
					<Card>
						<CardContent className="p-4">
							<div className="flex items-center gap-3">
								<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
									<Key className="h-5 w-5 text-accent" />
								</div>
								<div>
									<p className="font-bold text-2xl text-foreground">
										{keysRegistered}
									</p>
									<p className="text-muted-foreground text-sm">
										Keys Registered
									</p>
								</div>
							</div>
						</CardContent>
					</Card>
					<Card>
						<CardContent className="p-4">
							<div className="flex items-center gap-3">
								<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
									<BadgeCheck className="h-5 w-5 text-accent" />
								</div>
								<div>
									<p className="font-bold text-2xl text-foreground">
										{adminCount}
									</p>
									<p className="text-muted-foreground text-sm">Admins</p>
								</div>
							</div>
						</CardContent>
					</Card>
				</div>

				<div className="relative max-w-sm">
					<Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
					<Input
						className="pl-9"
						onChange={(e) => setSearchQuery(e.target.value)}
						placeholder="Search members..."
						value={searchQuery}
					/>
				</div>

				<div className="grid gap-3">
					{isLoading ? (
						<Card>
							<CardContent className="p-4">
								<p className="text-muted-foreground text-sm">
									Loading team data from the agent...
								</p>
							</CardContent>
						</Card>
					) : filteredMembers.length === 0 ? (
						<Card>
							<CardContent className="p-4">
								<p className="text-muted-foreground text-sm">
									No team members found yet.
								</p>
							</CardContent>
						</Card>
					) : (
						filteredMembers.map((member) => (
							<Card key={member.id}>
								<CardContent className="p-4">
									<div className="flex items-center justify-between">
										<div className="flex items-center gap-4">
											<Avatar className="h-10 w-10">
												<AvatarFallback className="bg-secondary text-foreground">
													{member.name
														.split(" ")
														.map((n) => n[0])
														.join("")}
												</AvatarFallback>
											</Avatar>
											<div>
												<div className="flex items-center gap-2">
													<h3 className="font-medium text-foreground">
														{member.name}
													</h3>
													<Badge
														className={getRoleColor(member.role)}
														variant="outline"
													>
														{member.role}
													</Badge>
													{member.status === "pending" && (
														<Badge
															className="border-yellow-500/20 bg-yellow-500/10 text-yellow-400"
															variant="outline"
														>
															Pending
														</Badge>
													)}
												</div>
												<p className="text-muted-foreground text-sm">
													{member.handle ?? "No handle"}
												</p>
											</div>
										</div>

										<div className="flex items-center gap-6">
											<div className="hidden items-center gap-6 text-muted-foreground text-sm sm:flex">
												<div className="flex items-center gap-2">
													<Key className="h-4 w-4" />
													<span>
														{member.publicKeys.length > 0
															? `${member.publicKeys.length} key${
																	member.publicKeys.length === 1 ? "" : "s"
																}`
															: "No keys"}
													</span>
												</div>
												<div className="flex items-center gap-2">
													<Shield className="h-4 w-4" />
													<span>
														{member.secretsAccess.length > 0
															? `Secrets: ${member.secretsAccess.join(", ")}`
															: `Source: ${
																	member.source === "github"
																		? "GitHub"
																		: "Stackpanel"
																}`}
													</span>
												</div>
											</div>
											<DropdownMenu>
												<DropdownMenuTrigger asChild>
													<Button
														className="h-8 w-8"
														size="icon"
														variant="ghost"
													>
														<MoreVertical className="h-4 w-4" />
													</Button>
												</DropdownMenuTrigger>
												<DropdownMenuContent align="end">
													<DropdownMenuItem>View profile</DropdownMenuItem>
													<DropdownMenuItem>Change role</DropdownMenuItem>
													<DropdownMenuItem>Regenerate invite</DropdownMenuItem>
													<DropdownMenuItem className="text-destructive">
														Remove
													</DropdownMenuItem>
												</DropdownMenuContent>
											</DropdownMenu>
										</div>
									</div>
								</CardContent>
							</Card>
						))
					)}
				</div>
			</div>
		</TooltipProvider>
	);
}
