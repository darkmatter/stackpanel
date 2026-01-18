"use client";

import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { Input } from "@ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import { TooltipProvider } from "@ui/tooltip";
import {
	ChevronDown,
	ChevronRight,
	Loader2,
	Pencil,
	Search,
	Settings,
	VariableIcon,
} from "lucide-react";
import { useMemo, useState } from "react";
import { useVariables } from "@/lib/use-nix-config";
import { PanelHeader } from "../shared/panel-header";
import { AddVariableDialog } from "./add-variable-dialog";
import {
	getTypeConfig,
	VARIABLE_TYPES,
	type VariableTypeName,
} from "./constants";
import {
	AgeIdentitySettings,
	EditSecretDialog,
	KMSSettings,
} from "./edit-secret-dialog";
import { VariableUsageInfo } from "./variable-usage-info";

export function VariablesPanel() {
	const { data: variables, isLoading, error, refetch } = useVariables();

	const [searchQuery, setSearchQuery] = useState("");
	const [selectedType, setSelectedType] = useState<VariableTypeName | "all">(
		"all",
	);
	const [expandedId, setExpandedId] = useState<string | null>(null);
	const [editingSecret, setEditingSecret] = useState<{
		id: string;
		key: string;
		description?: string;
	} | null>(null);

	const variablesList = useMemo(() => {
		if (!variables) return [];
		return Object.entries(variables).map(([id, variable]) => ({
			...variable,
			// Use id as the primary display name, key is the env var name
			name: id,
			envKey: variable.key ?? id,
			description: variable.description ?? "",
			id,
		}));
	}, [variables]);

	// Filter variables based on search and type
	const filteredVariables = useMemo(() => {
		const query = searchQuery.trim().toLowerCase();

		return variablesList
			.filter((variable) => {
				const matchesSearch =
					!query ||
					variable.name.toLowerCase().includes(query) ||
					variable.description.toLowerCase().includes(query) ||
					variable.id.toLowerCase().includes(query);

				const matchesType =
					selectedType.includes("all") ||
					// @ts-expect-error
					selectedType.includes(variable.type as string);

				return matchesSearch && matchesType;
			})
			.sort((a, b) => a.name.localeCompare(b.name));
	}, [variablesList, searchQuery, selectedType]);

	const toggleExpanded = (id: string) => {
		setExpandedId((current) => (current === id ? null : id));
	};

	const totalVariables = variablesList.length;
	const emptyStateMessage =
		searchQuery || selectedType !== "all"
			? "No variables match your search"
			: "No variables defined yet";

	if (isLoading) {
		return (
			<Card>
				<CardContent className="flex items-center justify-center py-12">
					<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
				</CardContent>
			</Card>
		);
	}

	if (error) {
		return (
			<Card className="border-destructive/40">
				<CardContent className="space-y-4 py-8 text-center">
					<p className="text-destructive">
						Error loading variables: {error.message}
					</p>
					<Button variant="outline" onClick={refetch}>
						Retry
					</Button>
				</CardContent>
			</Card>
		);
	}

	return (
		<TooltipProvider>
			<div className="space-y-6">
				<PanelHeader
					title="Variables & Secrets"
					description={`${totalVariables} variable${totalVariables !== 1 ? "s" : ""} defined`}
					guideKey="variables"
					size="lg"
					actions={<AddVariableDialog onSuccess={refetch} />}
				/>

				<Tabs defaultValue="manage" className="w-full">
					<TabsList className="grid w-full grid-cols-2 max-w-xs">
						<TabsTrigger value="manage" className="flex items-center gap-2">
							<VariableIcon className="h-4 w-4" />
							Manage
						</TabsTrigger>
						<TabsTrigger value="configure" className="flex items-center gap-2">
							<Settings className="h-4 w-4" />
							Configure
						</TabsTrigger>
					</TabsList>

					<TabsContent value="manage" className="mt-6 space-y-6">
						<div className="flex flex-col gap-4">
							<div className="flex flex-wrap items-center gap-3">
								<div className="relative flex-1 min-w-60">
									<Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
									<Input
										placeholder="Search variables..."
										value={searchQuery}
										onChange={(e) => setSearchQuery(e.target.value)}
										className="pl-9"
									/>
								</div>
								<ToggleGroup
									type="single"
									variant="outline"
									value={selectedType}
									onValueChange={(value) => {
										setSelectedType(
											(value || "all") as VariableTypeName | "all",
										);
									}}
									className="flex-wrap "
								>
									<ToggleGroupItem
										value="all"
										size="sm"
										className="text-[11px] px-2"
									>
										All
									</ToggleGroupItem>
									{VARIABLE_TYPES.map((type) => {
										const TypeIcon = type.icon;
										return (
											<ToggleGroupItem
												key={type.value}
												value={type.value}
												size="sm"
												className="text-[11px] px-6"
											>
												<TypeIcon className="size-4 opacity-80 shrink-0" />
												{type.label}
											</ToggleGroupItem>
										);
									})}
								</ToggleGroup>
								<div className="text-xs text-muted-foreground">
									{filteredVariables.length} result
									{filteredVariables.length === 1 ? "" : "s"}
								</div>
							</div>
						</div>

						<div className="space-y-2">
							{filteredVariables.length === 0 ? (
								<Card>
									<CardContent className="py-10 text-center text-muted-foreground">
										<VariableIcon className="mx-auto h-10 w-10 text-muted-foreground/50" />
										<p className="mt-3 text-sm">{emptyStateMessage}</p>
									</CardContent>
								</Card>
							) : (
								filteredVariables.map((variable) => {
									const typeConfig = getTypeConfig(variable.type);
									const TypeIcon = typeConfig.icon;
									const isExpanded = expandedId === variable.id;

									return (
										<div
											key={variable.id}
											className="rounded-lg border border-border bg-card transition-colors hover:border-primary/50"
										>
											<div className="p-4">
												<div className="flex items-start gap-3">
													<button
														type="button"
														onClick={() => toggleExpanded(variable.id)}
														className="mt-0.5 text-muted-foreground"
													>
														<ChevronRight
															className={`h-4 w-4 transition-transform ${
																isExpanded ? "rotate-90" : ""
															}`}
														/>
													</button>
													<div className="flex-1 min-w-0">
														<div className="flex items-center gap-2 mb-1 flex-wrap">
															<TypeIcon className="h-4 w-4 text-muted-foreground" />
															<code className="text-sm font-semibold font-mono">
																{variable.name}
															</code>
															<span
																className={`px-2 py-0.5 text-xs rounded ${typeConfig.color}`}
															>
																{typeConfig.label}
															</span>
														</div>
														<p className="text-sm text-muted-foreground">
															{variable.description ||
																"No description provided."}
														</p>
													</div>
												</div>
											</div>

											{isExpanded && (
												<div className="border-t border-border px-4 py-4 bg-muted/30 space-y-4">
													<div className="grid gap-4 sm:grid-cols-2">
														<div className="space-y-1">
															<p className="text-xs font-medium text-muted-foreground">
																Environment Key
															</p>
															<p className="text-sm font-mono">
																{variable.envKey}
															</p>
														</div>
														<div className="space-y-1">
															<p className="text-xs font-medium text-muted-foreground">
																Value
															</p>
															<div className="flex items-center gap-2">
																<p className="text-sm font-mono">
																	{typeConfig.value === "secret"
																		? "••••••••"
																		: variable.value || "—"}
																</p>
																{typeConfig.value === "secret" && (
																	<Button
																		variant="ghost"
																		size="sm"
																		className="h-6 px-2 text-xs"
																		onClick={(e) => {
																			e.stopPropagation();
																			setEditingSecret({
																				id: variable.id,
																				key: variable.envKey,
																				description: variable.description,
																			});
																		}}
																	>
																		<Pencil className="h-3 w-3 mr-1" />
																		Edit
																	</Button>
																)}
															</div>
														</div>
														<div className="space-y-1">
															<p className="text-xs font-medium text-muted-foreground">
																Type Details
															</p>
															<p className="text-sm text-muted-foreground">
																{typeConfig.description}
															</p>
														</div>
													</div>
													<div>
														<p className="text-xs font-medium text-muted-foreground mb-2">
															Used by
														</p>
														<VariableUsageInfo variableId={variable.id} />
													</div>
												</div>
											)}
										</div>
									);
								})
							)}
						</div>

						<div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
							<h4 className="mb-2 flex items-center gap-2 text-sm font-medium text-blue-600 dark:text-blue-400">
								<ChevronDown className="h-4 w-4" />
								Variables vs Secrets
							</h4>
							<ul className="ml-6 list-disc space-y-1 text-sm text-muted-foreground">
								<li>
									<strong>Configs</strong> are regular environment values like
									URLs and feature flags.
								</li>
								<li>
									<strong>Secrets</strong> are sensitive values that should stay
									encrypted.
								</li>
								<li>
									Computed and service variables are generated automatically
									based on config.
								</li>
							</ul>
						</div>
					</TabsContent>

					<TabsContent value="configure" className="mt-6 space-y-6">
						<div className="space-y-4">
							<div>
								<h3 className="text-lg font-medium mb-1">
									Encryption Settings
								</h3>
								<p className="text-sm text-muted-foreground">
									Configure how secrets are encrypted and decrypted in this
									project.
								</p>
							</div>

							<div className="space-y-4">
								<AgeIdentitySettings />
								<KMSSettings />
							</div>

							<div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-4">
								<h4 className="mb-2 text-sm font-medium text-amber-600 dark:text-amber-400">
									After changing settings
								</h4>
								<p className="text-sm text-muted-foreground">
									Run{" "}
									<code className="bg-muted px-1.5 py-0.5 rounded text-xs">
										generate-sops-config
									</code>{" "}
									to update your <code>.sops.yaml</code> file with the new
									encryption keys.
								</p>
							</div>
						</div>
					</TabsContent>
				</Tabs>

				{/* Edit Secret Dialog */}
				{editingSecret && (
					<EditSecretDialog
						secretId={editingSecret.id}
						secretKey={editingSecret.key}
						description={editingSecret.description}
						open={!!editingSecret}
						onOpenChange={(open) => {
							if (!open) setEditingSecret(null);
						}}
						onSuccess={refetch}
					/>
				)}
			</div>
		</TooltipProvider>
	);
}
