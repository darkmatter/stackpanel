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
import { Tabs, TabsList, TabsTrigger } from "@ui/tabs";
import { Textarea } from "@ui/textarea";
import {
	AlertCircle,
	Clock,
	Copy,
	Eye,
	EyeOff,
	KeyRound,
	Loader2,
	Lock,
	MoreVertical,
	Plus,
	RefreshCw,
	Search,
	Shield,
	Trash2,
} from "lucide-react";
import { useVariablesBackend } from "@/lib/use-agent";
import { getTypeColor, useSecrets } from "./secrets";

export function SecretsPanel() {
	const { data: backendData } = useVariablesBackend();
	const isChamber = backendData?.backend === "chamber";

	const {
		// State
		searchQuery,
		setSearchQuery,
		dialogOpen,
		setDialogOpen,
		selectedEnvironment,
		setSelectedEnvironment,
		newSecretKey,
		setNewSecretKey,
		newSecretValue,
		setNewSecretValue,
		showSecret,
		setShowSecret,
		secretValues,
		isLoading,
		isSaving,
		error,
		isPaired,

		// Computed
		filteredSecrets,

		// Handlers
		loadSecrets,
		handleAddSecret,
		handleDeleteSecret,
	} = useSecrets();

	if (isChamber) {
		return (
			<div className="space-y-6">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Secrets</h2>
					<p className="text-muted-foreground text-sm">
						Secrets are managed via AWS Parameter Store (Chamber)
					</p>
				</div>
				<Card>
					<CardContent className="py-12 text-center space-y-3">
						<Shield className="mx-auto h-12 w-12 text-muted-foreground/50" />
						<p className="text-muted-foreground text-sm">
							This project uses the <strong>Chamber</strong> backend for secrets management.
							Secrets are stored in AWS Systems Manager Parameter Store and encrypted via KMS.
						</p>
						<p className="text-muted-foreground text-xs">
							Use the <strong>Variables & Secrets</strong> panel to manage secrets in the{" "}
							<code className="bg-muted px-1 py-0.5 rounded text-xs">/dev/</code>,{" "}
							<code className="bg-muted px-1 py-0.5 rounded text-xs">/staging/</code>, and{" "}
							<code className="bg-muted px-1 py-0.5 rounded text-xs">/prod/</code> keygroups.
						</p>
					</CardContent>
				</Card>
			</div>
		);
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h2 className="font-semibold text-foreground text-xl">Secrets</h2>
					<p className="text-muted-foreground text-sm">
						Manage encrypted secrets using age encryption with team public keys
					</p>
				</div>
				<Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
					<DialogTrigger asChild>
						<Button
							className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
							disabled={!isPaired}
						>
							<Plus className="h-4 w-4" />
							Add Secret
						</Button>
					</DialogTrigger>
					<DialogContent>
						<DialogHeader>
							<DialogTitle>Add New Secret</DialogTitle>
							<DialogDescription>
								Secrets are encrypted with your team members' public keys using
								age.
							</DialogDescription>
						</DialogHeader>
						<div className="grid gap-4 py-4">
							<div className="grid gap-2">
								<Label htmlFor="secret-key">Key</Label>
								<Input
									className="font-mono"
									id="secret-key"
									onChange={(e) =>
										setNewSecretKey(e.target.value.toUpperCase())
									}
									placeholder="MY_SECRET_KEY"
									value={newSecretKey}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="secret-value">Value</Label>
								<Textarea
									className="font-mono"
									id="secret-value"
									onChange={(e) => setNewSecretValue(e.target.value)}
									placeholder="Enter secret value..."
									value={newSecretValue}
								/>
							</div>
							<div className="grid gap-2">
								<Label>Environment</Label>
								<Tabs
									onValueChange={setSelectedEnvironment}
									value={selectedEnvironment}
								>
									<TabsList className="grid w-full grid-cols-3">
										<TabsTrigger value="dev">Development</TabsTrigger>
										<TabsTrigger value="staging">Staging</TabsTrigger>
										<TabsTrigger value="prod">Production</TabsTrigger>
									</TabsList>
								</Tabs>
							</div>
							{error && (
								<div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3">
									<p className="text-destructive text-sm">{error}</p>
								</div>
							)}
						</div>
						<DialogFooter>
							<Button onClick={() => setDialogOpen(false)} variant="outline">
								Cancel
							</Button>
							<Button
								className="bg-accent text-accent-foreground hover:bg-accent/90"
								disabled={isSaving || !newSecretKey || !newSecretValue}
								onClick={handleAddSecret}
							>
								{isSaving ? (
									<>
										<Loader2 className="mr-2 h-4 w-4 animate-spin" />
										Saving...
									</>
								) : (
									"Encrypt & Save"
								)}
							</Button>
						</DialogFooter>
					</DialogContent>
				</Dialog>
			</div>

			{!isPaired ? (
				<Card className="border-yellow-500/30 bg-yellow-500/5">
					<CardContent className="flex items-center gap-4 p-4">
						<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-yellow-500/20">
							<AlertCircle className="h-5 w-5 text-yellow-500" />
						</div>
						<div className="flex-1">
							<p className="font-medium text-foreground text-sm">
								Agent Not Connected
							</p>
							<p className="text-muted-foreground text-xs">
								Connect to the local agent to manage SOPS-encrypted secrets.
								Showing demo data.
							</p>
						</div>
					</CardContent>
				</Card>
			) : (
				<Card className="border-accent/20 bg-accent/5">
					<CardContent className="flex items-center gap-4 p-4">
						<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
							<Shield className="h-5 w-5 text-accent" />
						</div>
						<div className="flex-1">
							<p className="font-medium text-foreground text-sm">
								Age Encryption Enabled
							</p>
							<p className="text-muted-foreground text-xs">
								All secrets are encrypted using your team's public keys. Only
								authorized members can decrypt.
							</p>
						</div>
						<Button onClick={loadSecrets} size="sm" variant="outline">
							<RefreshCw className="mr-2 h-4 w-4" />
							Refresh
						</Button>
					</CardContent>
				</Card>
			)}

			<div className="flex items-center gap-4">
				<div className="relative max-w-sm flex-1">
					<Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
					<Input
						className="pl-9"
						onChange={(e) => setSearchQuery(e.target.value)}
						placeholder="Search secrets..."
						value={searchQuery}
					/>
				</div>
				<Tabs
					onValueChange={setSelectedEnvironment}
					value={selectedEnvironment}
				>
					<TabsList>
						<TabsTrigger value="dev">Dev</TabsTrigger>
						<TabsTrigger value="staging">Staging</TabsTrigger>
						<TabsTrigger value="prod">Prod</TabsTrigger>
					</TabsList>
				</Tabs>
			</div>

			{isLoading ? (
				<div className="flex items-center justify-center py-12">
					<Loader2 className="h-8 w-8 animate-spin text-accent" />
				</div>
			) : filteredSecrets.length === 0 ? (
				<Card>
					<CardContent className="py-12 text-center">
						<KeyRound className="mx-auto h-12 w-12 text-muted-foreground/50" />
						<p className="mt-4 text-muted-foreground">
							No secrets found for {selectedEnvironment} environment
						</p>
						{isPaired && (
							<Button
								className="mt-4"
								onClick={() => setDialogOpen(true)}
								variant="outline"
							>
								<Plus className="mr-2 h-4 w-4" />
								Add First Secret
							</Button>
						)}
					</CardContent>
				</Card>
			) : (
				<div className="grid gap-3">
					{filteredSecrets.map((secret) => (
						<Card key={secret.key}>
							<CardContent className="p-4">
								<div className="flex items-center justify-between">
									<div className="flex items-center gap-4">
										<div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
											<KeyRound className="h-5 w-5 text-muted-foreground" />
										</div>
										<div>
											<div className="flex items-center gap-2">
												<h3 className="font-medium font-mono text-foreground text-sm">
													{secret.key}
												</h3>
												{secret.type && (
													<Badge
														className={getTypeColor(secret.type)}
														variant="outline"
													>
														{secret.type}
													</Badge>
												)}
											</div>
											<div className="mt-1 flex items-center gap-4 text-muted-foreground text-xs">
												<span className="flex items-center gap-1">
													<Clock className="h-3 w-3" />
													{secret.environment}
												</span>
											</div>
										</div>
									</div>

									<div className="flex items-center gap-2">
										{isPaired && secretValues[secret.key] && (
											<Button
												className="h-8 w-8"
												onClick={() =>
													setShowSecret(
														showSecret === secret.key ? null : secret.key,
													)
												}
												size="icon"
												variant="ghost"
											>
												{showSecret === secret.key ? (
													<EyeOff className="h-4 w-4" />
												) : (
													<Eye className="h-4 w-4" />
												)}
											</Button>
										)}
										<Button
											className="h-8 w-8"
											onClick={() => {
												if (secretValues[secret.key]) {
													navigator.clipboard.writeText(
														secretValues[secret.key],
													);
												}
											}}
											size="icon"
											variant="ghost"
										>
											<Copy className="h-4 w-4" />
										</Button>
										<DropdownMenu>
											<DropdownMenuTrigger asChild>
												<Button className="h-8 w-8" size="icon" variant="ghost">
													<MoreVertical className="h-4 w-4" />
												</Button>
											</DropdownMenuTrigger>
											<DropdownMenuContent align="end">
												<DropdownMenuItem>
													<RefreshCw className="mr-2 h-4 w-4" />
													Rotate
												</DropdownMenuItem>
												<DropdownMenuItem>Edit</DropdownMenuItem>
												<DropdownMenuItem
													className="text-destructive"
													onClick={() => handleDeleteSecret(secret.key)}
												>
													<Trash2 className="mr-2 h-4 w-4" />
													Delete
												</DropdownMenuItem>
											</DropdownMenuContent>
										</DropdownMenu>
									</div>
								</div>

								{showSecret === secret.key && secretValues[secret.key] && (
									<div className="mt-3 rounded-lg bg-secondary/50 p-3 font-mono text-foreground text-xs">
										<div className="flex items-center gap-2">
											<Lock className="h-3 w-3 text-muted-foreground" />
											<span className="break-all">
												{secretValues[secret.key]}
											</span>
										</div>
									</div>
								)}

								{showSecret === secret.key && !secretValues[secret.key] && (
									<div className="mt-3 rounded-lg bg-secondary/50 p-3 font-mono text-muted-foreground text-xs">
										<div className="flex items-center gap-2">
											<Lock className="h-3 w-3" />
											••••••••••••••••••••••••••••••••
										</div>
									</div>
								)}
							</CardContent>
						</Card>
					))}
				</div>
			)}
		</div>
	);
}
