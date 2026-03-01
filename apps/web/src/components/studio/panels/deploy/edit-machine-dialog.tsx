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
import { Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { MachineFormFields } from "./machine-form-fields";
import type { MachineConfig, useMachinesConfig } from "./use-machines";

interface EditMachineDialogProps {
	machineId: string;
	machine: MachineConfig;
	machines: ReturnType<typeof useMachinesConfig>;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}

export function EditMachineDialog({
	machineId,
	machine,
	machines,
	open,
	onOpenChange,
}: EditMachineDialogProps) {
	const [saving, setSaving] = useState(false);
	const [deleting, setDeleting] = useState(false);
	const [values, setValues] = useState<MachineConfig>({ ...machine });

	useEffect(() => {
		if (open) {
			setValues({ ...machine });
		}
	}, [open, machine]);

	const handleSave = async () => {
		setSaving(true);
		try {
			await machines.updateMachine(machineId, values);
			toast.success(`Machine "${machineId}" updated`);
			onOpenChange(false);
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to update machine",
			);
		} finally {
			setSaving(false);
		}
	};

	const handleDelete = async () => {
		setDeleting(true);
		try {
			await machines.removeMachine(machineId);
			toast.success(`Machine "${machineId}" removed`);
			onOpenChange(false);
		} catch (err) {
			toast.error(
				err instanceof Error ? err.message : "Failed to remove machine",
			);
		} finally {
			setDeleting(false);
		}
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Edit Machine: {machineId}</DialogTitle>
					<DialogDescription>
						Update machine configuration. Changes are written to your Nix config.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4">
					<MachineFormFields values={values} onChange={setValues} />
				</div>
				<DialogFooter className="flex justify-between sm:justify-between">
					<Button
						variant="destructive"
						size="sm"
						onClick={handleDelete}
						disabled={deleting || saving}
					>
						{deleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Delete
					</Button>
					<div className="flex gap-2">
						<Button variant="outline" onClick={() => onOpenChange(false)}>
							Cancel
						</Button>
						<Button onClick={handleSave} disabled={saving || deleting}>
							{saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
							Save
						</Button>
					</div>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
