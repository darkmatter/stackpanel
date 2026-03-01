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
import { useState } from "react";
import { toast } from "sonner";
import { MachineFormFields } from "./machine-form-fields";
import {
	type MachineConfig,
	DEFAULT_MACHINE,
	type useMachinesConfig,
} from "./use-machines";

interface AddMachineDialogProps {
	machines: ReturnType<typeof useMachinesConfig>;
}

export function AddMachineDialog({ machines }: AddMachineDialogProps) {
	const [open, setOpen] = useState(false);
	const [saving, setSaving] = useState(false);
	const [machineId, setMachineId] = useState("");
	const [values, setValues] = useState<MachineConfig>({ ...DEFAULT_MACHINE });

	const handleOpenChange = (isOpen: boolean) => {
		setOpen(isOpen);
		if (!isOpen) {
			setMachineId("");
			setValues({ ...DEFAULT_MACHINE });
		}
	};

	const isValid = machineId.trim().length > 0 && /^[a-z0-9-]+$/.test(machineId.trim());

	const handleSubmit = async () => {
		const id = machineId.trim();
		if (!id) {
			toast.error("Machine ID is required");
			return;
		}
		if (machines.config.machines[id]) {
			toast.error(`Machine "${id}" already exists`);
			return;
		}

		setSaving(true);
		try {
			await machines.addMachine(id, values);
			toast.success(`Machine "${id}" added`);
			handleOpenChange(false);
		} catch (err) {
			toast.error(err instanceof Error ? err.message : "Failed to add machine");
		} finally {
			setSaving(false);
		}
	};

	return (
		<Dialog open={open} onOpenChange={handleOpenChange}>
			<Button className="gap-2" size="sm" onClick={() => setOpen(true)}>
				<Plus className="h-4 w-4" />
				Add Machine
			</Button>
			<DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Add Machine</DialogTitle>
					<DialogDescription>
						Add a new machine to your deployment inventory.
					</DialogDescription>
				</DialogHeader>
				<div className="py-4">
					<MachineFormFields
						values={values}
						onChange={setValues}
						showIdField
						machineId={machineId}
						onIdChange={setMachineId}
					/>
				</div>
				<DialogFooter>
					<Button variant="outline" onClick={() => handleOpenChange(false)}>
						Cancel
					</Button>
					<Button onClick={handleSubmit} disabled={!isValid || saving}>
						{saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
						Add Machine
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
