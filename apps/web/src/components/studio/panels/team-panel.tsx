"use client";

import {
	CheckCircle2,
	Clock,
	Key,
	MoreVertical,
	Plus,
	Search,
	Shield,
} from "lucide-react";
import { useState } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
	DialogTrigger,
} from "@/components/ui/dialog";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/components/ui/select";

const teamMembers = [
	{
		name: "Jane Doe",
		email: "jane@acme.com",
		role: "Admin",
		status: "active",
		lastActive: "2 minutes ago",
		publicKey: "age1qy...x8k4",
		ssoEnabled: true,
	},
	{
		name: "Mike Chen",
		email: "mike@acme.com",
		role: "Developer",
		status: "active",
		lastActive: "15 minutes ago",
		publicKey: "age1ht...p9m2",
		ssoEnabled: true,
	},
	{
		name: "Sarah Wilson",
		email: "sarah@acme.com",
		role: "Developer",
		status: "active",
		lastActive: "1 hour ago",
		publicKey: "age1kz...n3j7",
		ssoEnabled: true,
	},
	{
		name: "Alex Rivera",
		email: "alex@acme.com",
		role: "Developer",
		status: "pending",
		lastActive: "Never",
		publicKey: null,
		ssoEnabled: false,
	},
	{
		name: "Jordan Lee",
		email: "jordan@acme.com",
		role: "Viewer",
		status: "active",
		lastActive: "3 hours ago",
		publicKey: "age1mw...d4s9",
		ssoEnabled: true,
	},
];

export function TeamPanel() {
	const [searchQuery, setSearchQuery] = useState("");
	const [dialogOpen, setDialogOpen] = useState(false);

	const filteredMembers = teamMembers.filter(
		(member) =>
			member.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
			member.email.toLowerCase().includes(searchQuery.toLowerCase()),
	);

	const getRoleColor = (role: string) => {
		switch (role) {
			case "Admin":
				return "bg-purple-500/10 text-purple-400 border-purple-500/20";
			case "Developer":
				return "bg-accent/10 text-accent border-accent/20";
			case "Viewer":
				return "bg-blue-500/10 text-blue-400 border-blue-500/20";
			default:
				return "";
		}
	};

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Team</h2>
					<p className="text-muted-foreground text-sm">
						Manage team members, roles, and SSO access
					</p>
				</div>
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
								Send an invitation to join your StackPanel organization via SSO.
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
							<Button onClick={() => setDialogOpen(false)} variant="outline">
								Cancel
							</Button>
							<Button className="bg-accent text-accent-foreground hover:bg-accent/90">
								Send Invitation
							</Button>
						</DialogFooter>
					</DialogContent>
				</Dialog>
			</div>

			<div className="grid gap-4 sm:grid-cols-3">
				<Card>
					<CardContent className="p-4">
						<div className="flex items-center gap-3">
							<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
								<Shield className="h-5 w-5 text-accent" />
							</div>
							<div>
								<p className="font-bold text-2xl text-foreground">
									{teamMembers.length}
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
									{teamMembers.filter((m) => m.publicKey).length}
								</p>
								<p className="text-muted-foreground text-sm">Keys Registered</p>
							</div>
						</div>
					</CardContent>
				</Card>
				<Card>
					<CardContent className="p-4">
						<div className="flex items-center gap-3">
							<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
								<CheckCircle2 className="h-5 w-5 text-accent" />
							</div>
							<div>
								<p className="font-bold text-2xl text-foreground">
									{teamMembers.filter((m) => m.ssoEnabled).length}
								</p>
								<p className="text-muted-foreground text-sm">SSO Enabled</p>
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
				{filteredMembers.map((member) => (
					<Card key={member.email}>
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
											{member.email}
										</p>
									</div>
								</div>

								<div className="flex items-center gap-6">
									<div className="hidden items-center gap-6 text-muted-foreground text-sm sm:flex">
										<div className="flex items-center gap-2">
											<Key className="h-4 w-4" />
											<span>{member.publicKey || "No key"}</span>
										</div>
										<div className="flex items-center gap-2">
											<Clock className="h-4 w-4" />
											<span>{member.lastActive}</span>
										</div>
									</div>
									<DropdownMenu>
										<DropdownMenuTrigger asChild>
											<Button className="h-8 w-8" size="icon" variant="ghost">
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
				))}
			</div>
		</div>
	);
}
