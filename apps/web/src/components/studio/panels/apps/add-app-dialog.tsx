"use client";

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
import { useCallback, useState } from "react";
import { toast } from "sonner";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import type { AppEntity } from "@/lib/types";
import { usePatchNixData } from "@/lib/use-agent";

import {
	type AppForm,
	AppFormFields,
	type AppFormValues,
	parsePortValue,
} from "./app-form-fields";

interface AddAppDialogProps {
	onSuccess: () => void;
}

export function AddAppDialog({ onSuccess }: AddAppDialogProps) {
	const { token } = useAgentContext();
	const client = useAgentClient();
	const patchNixData = usePatchNixData();
	const [dialogOpen, setDialogOpen] = useState(false);
	const [isSaving, setIsSaving] = useState(false);
	const [formRef, setFormRef] = useState<AppForm | null>(null);
	const [isFormValid, setIsFormValid] = useState(false);

	const handleFormReady = useCallback((form: AppForm) => {
		setFormRef(form);
	}, []);

	const handleValuesChange = useCallback((values: AppFormValues) => {
		const hasId = values.id?.trim().length > 0;
		const hasPath = values.path?.trim().length > 0;
		setIsFormValid(hasId && hasPath);
	}, []);

	const handleOpenChange = (open: boolean) => {
		setDialogOpen(open);
		if (!open) {
			// Reset form and validity when closing
			formRef?.reset();
			setIsFormValid(false);
		}
	};

	const handleSubmit = async () => {
		if (!formRef || !token) {
			toast.error("Not connected to agent");
			return;
		}

		// Trigger validation
		const isValid = await formRef.trigger();
		if (!isValid) return;

		const values = formRef.getValues();

		if (!values.id.trim()) {
			toast.error("Please enter an app ID");
			return;
		}

		setIsSaving(true);
		try {
			const appsClient = client.nix.mapEntity<AppEntity>("apps");

			const existingApp = await appsClient.get(values.id);
			if (existingApp) {
				toast.error(`App "${values.id}" already exists`);
				setIsSaving(false);
				return;
			}

			// With simplified schema: environments is Record<string, AppEnvironment>
			// Start with default "dev" environment
			const newApp: AppEntity = {
				id: values.id,
				name: values.name || values.id,
				description: values.description || undefined,
				path: values.path || `apps/${values.id}`,
				type: values.type || "bun",
				port: parsePortValue(values.port),
				domain: values.domain || undefined,
				environments: {
					dev: { name: "dev", env: {} },
				},
			};

			await patchNixData.mutateAsync({
				entity: "apps",
				key: "_root",
				path: values.id,
				value: JSON.stringify(newApp),
				valueType: "object",
			});
			toast.success(
				`Created app "${values.id}". You can now configure tasks and variables.`,
			);
			handleOpenChange(false);
			onSuccess();
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to create app");
		} finally {
			setIsSaving(false);
		}
	};

	return (
		<Dialog open={dialogOpen} onOpenChange={handleOpenChange}>
			<Button
				className="gap-2"
				onClick={() => setDialogOpen(true)}
				disabled={!token}
			>
				<Plus className="h-4 w-4" />
				Add App
			</Button>
			<DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Add New App</DialogTitle>
					<DialogDescription>
						Create a new app. You can configure tasks and variables after
						creation.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4">
					<AppFormFields
						showIdField
						hideTasksAndVariables
						onFormReady={handleFormReady}
						onValuesChange={handleValuesChange}
					/>
				</div>
				<DialogFooter>
					<Button variant="outline" onClick={() => handleOpenChange(false)}>
						Cancel
					</Button>
					<Button onClick={handleSubmit} disabled={!isFormValid || isSaving}>
						{isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Add App
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
