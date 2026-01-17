"use client";

import { Button } from "@ui/button";
import { Checkbox } from "@ui/checkbox";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import { Plus } from "lucide-react";
import { useState } from "react";

interface MultiSelectWithAddProps {
	/** Available options */
	options: string[];
	/** Currently selected values */
	selectedValues: string[];
	/** Callback when selection changes */
	onSelectionChange: (values: string[]) => void;
	/** Placeholder text */
	placeholder?: string;
	/** Whether the field is disabled */
	disabled?: boolean;
}

export function MultiSelectWithAdd({
	options,
	selectedValues,
	onSelectionChange,
	placeholder = "Select...",
	disabled = false,
}: MultiSelectWithAddProps) {
	const [open, setOpen] = useState(false);
	const [newValue, setNewValue] = useState("");

	const toggleValue = (value: string) => {
		if (selectedValues.includes(value)) {
			onSelectionChange(selectedValues.filter((v) => v !== value));
		} else {
			onSelectionChange([...selectedValues, value]);
		}
	};

	const handleAddNew = () => {
		const trimmed = newValue.trim();
		if (!trimmed) return;

		// Add to selection if not already selected
		if (!selectedValues.includes(trimmed)) {
			onSelectionChange([...selectedValues, trimmed]);
		}

		setNewValue("");
	};

	const handleKeyDown = (e: React.KeyboardEvent) => {
		if (e.key === "Enter") {
			e.preventDefault();
			handleAddNew();
		}
	};

	// Combine options with selected values (in case some selected aren't in options)
	const allOptions = Array.from(
		new Set([...options, ...selectedValues]),
	).sort();

	return (
		<Popover open={open} onOpenChange={setOpen}>
			<PopoverTrigger asChild>
				<Button
					variant="outline"
					className="w-full justify-start text-xs h-8 font-normal"
					disabled={disabled}
				>
					{selectedValues.length === 0 ? (
						<span className="text-muted-foreground">{placeholder}</span>
					) : selectedValues.length === 1 ? (
						<span className="capitalize">{selectedValues[0]}</span>
					) : (
						<span>{selectedValues.length} selected</span>
					)}
				</Button>
			</PopoverTrigger>
			<PopoverContent className="w-56 p-2" align="start">
				<div className="space-y-2">
					{/* Add new input */}
					<div className="flex gap-1">
						<Input
							placeholder="Add environment..."
							value={newValue}
							onChange={(e) => setNewValue(e.target.value)}
							onKeyDown={handleKeyDown}
							className="h-7 text-xs"
						/>
						<Button
							size="icon"
							variant="ghost"
							className="h-7 w-7"
							onClick={handleAddNew}
							disabled={!newValue.trim()}
						>
							<Plus className="h-3 w-3" />
						</Button>
					</div>

					{/* Options list */}
					<div className="max-h-48 space-y-1 overflow-y-auto">
						{allOptions.length === 0 ? (
							<p className="py-2 text-center text-muted-foreground text-xs">
								No options available
							</p>
						) : (
							allOptions.map((option) => (
								<div
									key={option}
									className="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-secondary/50"
								>
									<Checkbox
										id={`env-${option}`}
										checked={selectedValues.includes(option)}
										onCheckedChange={() => toggleValue(option)}
									/>
									<Label
										htmlFor={`env-${option}`}
										className="flex-1 cursor-pointer text-xs capitalize"
									>
										{option}
									</Label>
								</div>
							))
						)}
					</div>

					{selectedValues.length > 0 && (
						<div className="border-t pt-2">
							<Button
								variant="ghost"
								size="sm"
								className="h-6 w-full text-xs"
								onClick={() => onSelectionChange([])}
							>
								Clear all
							</Button>
						</div>
					)}
				</div>
			</PopoverContent>
		</Popover>
	);
}
