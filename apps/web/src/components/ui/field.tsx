import { Label } from "@ui/label";
import * as React from "react";
import { cn } from "@/lib/utils";

interface FieldProps extends React.ComponentProps<"div"> {
	/** Field label */
	label?: string;
	/** Help text shown below the input */
	description?: string;
	/** Whether the field is required */
	required?: boolean;
	/** Error message to display */
	error?: string;
	/** HTML id for the input (auto-generated if not provided) */
	htmlFor?: string;
}

/**
 * A simple field wrapper that provides consistent styling for
 * label + input + description patterns without react-hook-form.
 *
 * @example
 * ```tsx
 * <Field label="Email" description="We'll never share your email.">
 *   <Input type="email" placeholder="you@example.com" />
 * </Field>
 * ```
 */
function Field({
	label,
	description,
	required,
	error,
	htmlFor,
	className,
	children,
	...props
}: FieldProps) {
	const id = React.useId();
	const inputId = htmlFor ?? id;

	return (
		<div className={cn("space-y-2", className)} {...props}>
			{label && (
				<Label htmlFor={inputId} className={cn(error && "text-destructive")}>
					{label}
					{required && <span className="text-destructive ml-0.5">*</span>}
				</Label>
			)}
			{children}
			{description && !error && (
				<p className="text-muted-foreground text-xs">{description}</p>
			)}
			{error && <p className="text-destructive text-xs">{error}</p>}
		</div>
	);
}

interface FieldGroupProps extends React.ComponentProps<"div"> {
	/** Title for the group */
	title?: string;
	/** Description for the group */
	description?: string;
}

/**
 * A fieldset-like container for grouping related fields.
 */
function FieldGroup({
	title,
	description,
	className,
	children,
	...props
}: FieldGroupProps) {
	return (
		<div
			className={cn("rounded-lg border border-border p-4 space-y-4", className)}
			{...props}
		>
			{(title || description) && (
				<div className="space-y-1">
					{title && (
						<h4 className="text-sm font-medium leading-none">{title}</h4>
					)}
					{description && (
						<p className="text-muted-foreground text-xs">{description}</p>
					)}
				</div>
			)}
			{children}
		</div>
	);
}

interface FieldRowProps extends React.ComponentProps<"div"> {
	/** Number of columns (default: 2) */
	columns?: 2 | 3 | 4;
}

/**
 * A responsive grid for laying out fields in columns.
 */
function FieldRow({
	columns = 2,
	className,
	children,
	...props
}: FieldRowProps) {
	const gridCols = {
		2: "sm:grid-cols-2",
		3: "sm:grid-cols-3",
		4: "sm:grid-cols-4",
	};

	return (
		<div className={cn("grid gap-4", gridCols[columns], className)} {...props}>
			{children}
		</div>
	);
}

interface SwitchFieldProps extends React.ComponentProps<"div"> {
	/** Field label */
	label: string;
	/** Description shown below the label */
	description?: string;
	/** The switch element */
	children: React.ReactNode;
}

/**
 * A field layout for switch/toggle inputs with label on the left.
 */
function SwitchField({
	label,
	description,
	className,
	children,
	...props
}: SwitchFieldProps) {
	return (
		<div
			className={cn("flex items-center justify-between", className)}
			{...props}
		>
			<div className="space-y-0.5">
				<Label>{label}</Label>
				{description && (
					<p className="text-muted-foreground text-xs">{description}</p>
				)}
			</div>
			{children}
		</div>
	);
}

export { Field, FieldGroup, FieldRow, SwitchField };
