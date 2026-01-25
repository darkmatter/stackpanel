// @ts-nocheck - Legacy component using old VariableType schema
"use client";

// Note: This component uses the old schema with VariableType.
// The new schema uses simple id/value pairs.
// This file needs to be migrated to the new schema.

// Legacy type - no longer in proto schema
enum VariableType {
  UNSPECIFIED = 0,
  VARIABLE = 1,
  SECRET = 2,
  VALS = 3,
}
import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
import { Loader2, Pencil, Trash2 } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import type { Variable } from "@/lib/types";
import { type VariableForm, VariableFormFields } from "./variable-form-fields";

interface EditVariableDialogProps {
	variable: {
		id: string;
		key: string;
		description?: string;
		type: VariableType | number;
		value?: string;
	};
	onSuccess: () => void;
	trigger?: React.ReactNode;
}

export function EditVariableDialog({
	variable,
	onSuccess,
	trigger,
}: EditVariableDialogProps) {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const [dialogOpen, setDialogOpen] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [isDeleting, setIsDeleting] = useState(false);
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
		if (!values.value?.trim()) {
			toast.error("Please enter a variable value");
			return;
		}

		setIsSaving(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<Variable>("variables");

			// Check if this is a SECRET type - needs agenix encryption
			const isSecret = values.type === VariableType.SECRET;

			if (isSecret) {
				// Use the agenix endpoint to encrypt and write the secret
				await agentClient.writeAgenixSecret({
					id: variable.id,
					key: values.key || variable.id,
					value: values.value,
					description: values.description || undefined,
				});
				toast.success(`Updated secret "${variable.id}"`);
			} else {
				// Regular variable - write directly to variables.nix
				const updatedVariable: Variable = {
					key: values.key || variable.id,
					description: values.description || "",
					type: values.type,
					value: values.value,
				};

				await variablesClient.set(variable.id, updatedVariable);
				toast.success(`Updated variable "${variable.id}"`);
			}

			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[EditVariable] Error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to update variable",
			);
		} finally {
			setIsSaving(false);
		}
	};

	const handleDelete = async () => {
		if (!token) {
			toast.error("Not connected to agent");
			return;
		}

		if (!confirm(`Are you sure you want to delete "${variable.id}"?`)) {
			return;
		}

		setIsDeleting(true);
		try {
			const client = agentClient;
			if (token) client.setToken(token);
			const variablesClient = client.nix.mapEntity<Variable>("variables");

			await variablesClient.remove(variable.id);
			toast.success(`Deleted variable "${variable.id}"`);
			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			console.error("[EditVariable] Delete error:", err);
			toast.error(
				err instanceof Error ? err.message : "Failed to delete variable",
			);
		} finally {
			setIsDeleting(false);
		}
	};

	return (
		<Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
			{trigger ? (
				<div onClick={() => setDialogOpen(true)}>{trigger}</div>
			) : (
				<Button
					variant="ghost"
					size="sm"
					onClick={() => setDialogOpen(true)}
					disabled={!token}
					className="h-7 px-2 text-xs"
				>
					<Pencil className="h-3 w-3 mr-1" />
					Edit
				</Button>
			)}
			<DialogContent className="sm:max-w-4xl">
				<DialogHeader>
					<DialogTitle>Edit Variable</DialogTitle>
					<DialogDescription>
						Update the variable configuration. The variable ID cannot be
						changed.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4">
					<VariableFormFields
						showIdField={false}
						defaultValues={{
							id: variable.id,
							key: variable.key,
							description: variable.description || "",
							type: variable.type as VariableType,
							value: variable.value || "",
						}}
						onFormReady={(form) => {
							formRef.current = form;
						}}
					/>
					<div className="mt-4 p-3 rounded-lg bg-muted/50 border border-border">
						<p className="text-xs text-muted-foreground">
							<span className="font-medium">Variable ID:</span>{" "}
							<code className="font-mono">{variable.id}</code>
						</p>
					</div>
				</div>
				<DialogFooter className="flex justify-between sm:justify-between">
					<Button
						variant="destructive"
						onClick={handleDelete}
						disabled={isDeleting || isSaving}
						className="gap-1"
					>
						{isDeleting && <Loader2 className="h-4 w-4 animate-spin" />}
						<Trash2 className="h-4 w-4" />
						Delete
					</Button>
					<div className="flex gap-2">
						<Button variant="outline" onClick={() => handleOpenChange(false)}>
							Cancel
						</Button>
						<Button
							onClick={handleSubmit}
							disabled={isSaving || isDeleting}
							className="bg-accent text-accent-foreground hover:bg-accent/90"
						>
							{isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
							Save Changes
						</Button>
					</div>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
