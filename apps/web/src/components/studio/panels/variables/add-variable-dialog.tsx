"use client";

import { VariableType } from "@stackpanel/proto";
import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
import { Loader2, Plus } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import type { Variable } from "@/lib/types";
import { type VariableForm, VariableFormFields } from "./variable-form-fields";

interface AddVariableDialogProps {
	onSuccess: () => void;
}

export function AddVariableDialog({ onSuccess }: AddVariableDialogProps) {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const [dialogOpen, setDialogOpen] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const formRef = useRef<VariableForm | null>(null);

	const handleOpenChange = (open: boolean) => {
		setDialogOpen(open);
		if (!open) {
			// Reset form when closing
			formRef.current?.reset();
		}
	};

	const handleSubmit = async () => {
		if (!formRef.current || !token) {
			toast.error(!token ? "Not connected to agent" : "Form not ready");
			return;
		}

		const values = formRef.current.getValues();

		// Validate required fields
		if (!values.id?.trim()) {
			toast.error("Please enter a variable ID");
			return;
		}

		if (!values.value?.trim()) {
			toast.error("Please enter a variable value");
			return;
		}

		setIsSaving(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<Variable>("variables");

			console.log("[AddVariable] Checking if variable exists:", values.id);
			console.log("[AddVariable] Form values:", values);
			console.log(
				"[AddVariable] VariableType.SECRET =",
				VariableType.SECRET,
				"values.type =",
				values.type,
			);

			const existing = await variablesClient.get(values.id);
			const exists = Boolean(existing);
			console.log("[AddVariable] Variable exists:", exists);

			if (exists) {
				toast.error(`Variable "${values.id}" already exists`);
				setIsSaving(false);
				return;
			}

			// Check if this is a SECRET type - needs agenix encryption
			const isSecret = values.type === VariableType.SECRET;
			console.log("[AddVariable] isSecret:", isSecret);

			if (isSecret) {
				// Use the agenix endpoint to encrypt and write the secret
				console.log("[AddVariable] Creating secret via agenix...");
				const result = await agentClient.writeAgenixSecret({
					id: values.id,
					key: values.key || values.id,
					value: values.value,
					description: values.description || undefined,
				});
				console.log("[AddVariable] Secret created:", result);
				toast.success(`Created secret "${values.id}" (encrypted with age)`);
			} else {
				// Regular variable - write directly to variables.nix
				const newVariable: Variable = {
					key: values.key || values.id,
					description: values.description || "",
					type: values.type,
					value: values.value,
				};

				await variablesClient.set(values.id, newVariable);
				toast.success(`Created variable "${values.id}"`);
			}

			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[AddVariable] Error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to create variable",
			);
		} finally {
			setIsSaving(false);
		}
	};

	return (
		<Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
			<button
				type="button"
				onClick={() => setDialogOpen(true)}
				disabled={!token}
				className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-dashed border-border bg-background text-xs hover:border-blue-500/50 hover:bg-blue-500/5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
			>
				<Plus className="h-3 w-3 text-blue-500" />
				<span className="font-medium">Add Variable</span>
			</button>
			<DialogContent className="sm:max-w-4xl">
				<DialogHeader>
					<DialogTitle>Add New Variable</DialogTitle>
					<DialogDescription>
						Create a new environment variable that can be linked to apps.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4">
					<VariableFormFields
						showIdField
						onFormReady={(form) => {
							formRef.current = form;
						}}
					/>
				</div>
				<DialogFooter>
					<Button variant="outline" onClick={() => handleOpenChange(false)}>
						Cancel
					</Button>
					<Button
						onClick={handleSubmit}
						disabled={isSaving}
						className="bg-accent text-accent-foreground hover:bg-accent/90"
					>
						{isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Add Variable
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
