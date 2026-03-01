"use client";

import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import type { MachineConfig } from "./use-machines";

interface MachineFormFieldsProps {
	values: MachineConfig;
	onChange: (values: MachineConfig) => void;
	showIdField?: boolean;
	machineId?: string;
	onIdChange?: (id: string) => void;
}

const ARCH_OPTIONS = [
	{ value: "x86_64-linux", label: "x86_64-linux" },
	{ value: "aarch64-linux", label: "aarch64-linux" },
];

const PROVIDER_OPTIONS = [
	{ value: "aws", label: "AWS" },
	{ value: "hetzner", label: "Hetzner" },
	{ value: "gcp", label: "GCP" },
	{ value: "azure", label: "Azure" },
	{ value: "digitalocean", label: "DigitalOcean" },
	{ value: "bare-metal", label: "Bare Metal" },
];

const ENV_OPTIONS = [
	{ value: "production", label: "Production" },
	{ value: "staging", label: "Staging" },
	{ value: "development", label: "Development" },
];

function updateField<K extends keyof MachineConfig>(
	values: MachineConfig,
	onChange: (v: MachineConfig) => void,
	key: K,
	value: MachineConfig[K],
) {
	onChange({ ...values, [key]: value });
}

export function MachineFormFields({
	values,
	onChange,
	showIdField,
	machineId,
	onIdChange,
}: MachineFormFieldsProps) {
	return (
		<div className="space-y-4">
			{/* Identity */}
			{showIdField && (
				<div className="space-y-2">
					<Label htmlFor="machine-id">Machine ID</Label>
					<Input
						id="machine-id"
						placeholder="web-1"
						value={machineId ?? ""}
						onChange={(e) => onIdChange?.(e.target.value)}
					/>
					<p className="text-xs text-muted-foreground">
						Unique identifier used as the Nix attribute name. Use lowercase with hyphens.
					</p>
				</div>
			)}

			<div className="space-y-2">
				<Label htmlFor="machine-name">Display Name</Label>
				<Input
					id="machine-name"
					placeholder="Web Server 1"
					value={values.name ?? ""}
					onChange={(e) =>
						updateField(values, onChange, "name", e.target.value || null)
					}
				/>
			</div>

			{/* Connection */}
			<fieldset className="rounded-lg border border-border p-4 space-y-3">
				<legend className="px-2 text-sm font-medium">Connection</legend>

				<div className="space-y-2">
					<Label htmlFor="machine-host">Host</Label>
					<Input
						id="machine-host"
						placeholder="10.0.1.10 or web1.example.com"
						value={values.host ?? ""}
						onChange={(e) =>
							updateField(values, onChange, "host", e.target.value || null)
						}
					/>
				</div>

				<div className="grid grid-cols-3 gap-3">
					<div className="space-y-2">
						<Label htmlFor="ssh-user">SSH User</Label>
						<Input
							id="ssh-user"
							placeholder="root"
							value={values.ssh.user}
							onChange={(e) =>
								updateField(values, onChange, "ssh", {
									...values.ssh,
									user: e.target.value || "root",
								})
							}
						/>
					</div>
					<div className="space-y-2">
						<Label htmlFor="ssh-port">SSH Port</Label>
						<Input
							id="ssh-port"
							type="number"
							placeholder="22"
							value={values.ssh.port}
							onChange={(e) =>
								updateField(values, onChange, "ssh", {
									...values.ssh,
									port: Number.parseInt(e.target.value, 10) || 22,
								})
							}
						/>
					</div>
					<div className="space-y-2">
						<Label htmlFor="ssh-key">SSH Key Path</Label>
						<Input
							id="ssh-key"
							placeholder="~/.ssh/id_ed25519"
							value={values.ssh.key_path ?? ""}
							onChange={(e) =>
								updateField(values, onChange, "ssh", {
									...values.ssh,
									key_path: e.target.value || null,
								})
							}
						/>
					</div>
				</div>
			</fieldset>

			{/* Networking */}
			<div className="grid grid-cols-2 gap-3">
				<div className="space-y-2">
					<Label htmlFor="public-ip">Public IP</Label>
					<Input
						id="public-ip"
						placeholder="203.0.113.10"
						value={values.public_ip ?? ""}
						onChange={(e) =>
							updateField(values, onChange, "public_ip", e.target.value || null)
						}
					/>
				</div>
				<div className="space-y-2">
					<Label htmlFor="private-ip">Private IP</Label>
					<Input
						id="private-ip"
						placeholder="10.0.1.10"
						value={values.private_ip ?? ""}
						onChange={(e) =>
							updateField(
								values,
								onChange,
								"private_ip",
								e.target.value || null,
							)
						}
					/>
				</div>
			</div>

			{/* Classification */}
			<div className="grid grid-cols-3 gap-3">
				<div className="space-y-2">
					<Label htmlFor="machine-arch">Architecture</Label>
					<Select
						value={values.arch ?? ""}
						onValueChange={(v) =>
							updateField(values, onChange, "arch", v || null)
						}
					>
						<SelectTrigger id="machine-arch">
							<SelectValue placeholder="Select..." />
						</SelectTrigger>
						<SelectContent>
							{ARCH_OPTIONS.map((opt) => (
								<SelectItem key={opt.value} value={opt.value}>
									{opt.label}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>

				<div className="space-y-2">
					<Label htmlFor="machine-provider">Provider</Label>
					<Select
						value={values.provider ?? ""}
						onValueChange={(v) =>
							updateField(values, onChange, "provider", v || null)
						}
					>
						<SelectTrigger id="machine-provider">
							<SelectValue placeholder="Select..." />
						</SelectTrigger>
						<SelectContent>
							{PROVIDER_OPTIONS.map((opt) => (
								<SelectItem key={opt.value} value={opt.value}>
									{opt.label}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>

				<div className="space-y-2">
					<Label htmlFor="machine-env">Environment</Label>
					<Select
						value={values.target_env ?? ""}
						onValueChange={(v) =>
							updateField(values, onChange, "target_env", v || null)
						}
					>
						<SelectTrigger id="machine-env">
							<SelectValue placeholder="Select..." />
						</SelectTrigger>
						<SelectContent>
							{ENV_OPTIONS.map((opt) => (
								<SelectItem key={opt.value} value={opt.value}>
									{opt.label}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>
			</div>

			{/* Roles and Tags */}
			<div className="grid grid-cols-2 gap-3">
				<div className="space-y-2">
					<Label htmlFor="machine-roles">Roles</Label>
					<Input
						id="machine-roles"
						placeholder="web, app (comma-separated)"
						value={values.roles.join(", ")}
						onChange={(e) =>
							updateField(
								values,
								onChange,
								"roles",
								e.target.value
									.split(",")
									.map((s) => s.trim())
									.filter(Boolean),
							)
						}
					/>
					<p className="text-xs text-muted-foreground">
						Used for app-to-machine targeting
					</p>
				</div>
				<div className="space-y-2">
					<Label htmlFor="machine-tags">Tags</Label>
					<Input
						id="machine-tags"
						placeholder="production, us-east (comma-separated)"
						value={values.tags.join(", ")}
						onChange={(e) =>
							updateField(
								values,
								onChange,
								"tags",
								e.target.value
									.split(",")
									.map((s) => s.trim())
									.filter(Boolean),
							)
						}
					/>
					<p className="text-xs text-muted-foreground">
						Used for grouping and filtering
					</p>
				</div>
			</div>
		</div>
	);
}
