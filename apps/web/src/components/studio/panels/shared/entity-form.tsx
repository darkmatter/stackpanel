"use client";

import {
	Form,
	FormControl,
	FormDescription,
	FormField,
	FormItem,
	FormLabel,
	FormMessage,
} from "@ui/form";
import { Input } from "@ui/input";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { Textarea } from "@ui/textarea";
import { useEffect } from "react";
import {
	type DefaultValues,
	type FieldValues,
	type Path,
	type RegisterOptions,
	type UseFormReturn,
	useForm,
} from "react-hook-form";

// =============================================================================
// Types
// =============================================================================

export type EntityForm<T extends FieldValues> = UseFormReturn<T>;

export interface FieldOption {
	value: string;
	label: string;
	description?: string;
	icon?: React.ComponentType<{ className?: string }>;
	disabled?: boolean;
}

export type FieldType =
	| "text"
	| "textarea"
	| "password"
	| "number"
	| "select"
	| "custom";

export interface FieldConfig<T extends FieldValues> {
	/** Field name matching a key in your form values */
	name: Path<T>;
	/** Display label */
	label: string;
	/** Field type */
	type: FieldType;
	/** Placeholder text */
	placeholder?: string;
	/** Help text shown below the field */
	description?: string;
	/** Validation rules */
	rules?: RegisterOptions<T, Path<T>>;
	/** Options for select fields */
	options?: FieldOption[];
	/** Whether the field is required (adds asterisk to label) */
	required?: boolean;
	/** Custom class name for the input */
	className?: string;
	/** Number of rows for textarea */
	rows?: number;
	/** Transform value on change (e.g., toUpperCase) */
	transformValue?: (value: string) => string;
	/** Condition to show/hide the field */
	showWhen?: (values: T) => boolean;
	/** Custom render function for complex fields */
	render?: (field: {
		value: unknown;
		onChange: (value: unknown) => void;
		onBlur: () => void;
		name: string;
	}) => React.ReactNode;
}

export interface EntityFormProps<T extends FieldValues> {
	/** Field configurations */
	fields: FieldConfig<T>[];
	/** Default values for the form */
	defaultValues: DefaultValues<T>;
	/** Callback when form values change */
	onValuesChange?: (values: T) => void;
	/** Expose form instance to parent */
	onFormReady?: (form: EntityForm<T>) => void;
	/** Additional class name for the form container */
	className?: string;
}

// =============================================================================
// Component
// =============================================================================

/**
 * A generic, reusable form component for proto-backed entities.
 *
 * @example
 * ```tsx
 * interface MyFormValues {
 *   id: string;
 *   name: string;
 *   type: MyType;
 * }
 *
 * const fields: FieldConfig<MyFormValues>[] = [
 *   {
 *     name: "id",
 *     label: "ID",
 *     type: "text",
 *     required: true,
 *     rules: { required: "ID is required" },
 *   },
 *   {
 *     name: "name",
 *     label: "Name",
 *     type: "text",
 *   },
 *   {
 *     name: "type",
 *     label: "Type",
 *     type: "select",
 *     options: [
 *       { value: "option1", label: "Option 1" },
 *       { value: "option2", label: "Option 2" },
 *     ],
 *   },
 * ];
 *
 * <EntityForm
 *   fields={fields}
 *   defaultValues={{ id: "", name: "", type: MyType.OPTION1 }}
 *   onFormReady={setFormRef}
 *   onValuesChange={handleValuesChange}
 * />
 * ```
 */
export function EntityForm<T extends FieldValues>({
	fields,
	defaultValues,
	onValuesChange,
	onFormReady,
	className,
}: EntityFormProps<T>) {
	const form = useForm<T>({
		defaultValues,
	});

	// Expose form to parent
	useEffect(() => {
		onFormReady?.(form);
	}, [form, onFormReady]);

	// Watch for changes and notify parent
	useEffect(() => {
		if (!onValuesChange) return;

		const subscription = form.watch((values) => {
			onValuesChange(values as T);
		});

		return () => subscription.unsubscribe();
	}, [form, onValuesChange]);

	// Get current values for conditional rendering
	const currentValues = form.watch();

	return (
		<Form {...form}>
			<div className={className ?? "space-y-4"}>
				{fields.map((fieldConfig) => {
					// Check if field should be shown
					if (fieldConfig.showWhen && !fieldConfig.showWhen(currentValues)) {
						return null;
					}

					return (
						<FormField
							key={fieldConfig.name}
							control={form.control}
							name={fieldConfig.name}
							rules={fieldConfig.rules}
							render={({ field }) => (
								<FormItem>
									<FormLabel>
										{fieldConfig.label}
										{fieldConfig.required && " *"}
									</FormLabel>
									<FormControl>{renderField(fieldConfig, field)}</FormControl>
									{fieldConfig.description && (
										<FormDescription>{fieldConfig.description}</FormDescription>
									)}
									<FormMessage />
								</FormItem>
							)}
						/>
					);
				})}
			</div>
		</Form>
	);
}

// =============================================================================
// Field Renderers
// =============================================================================

function renderField<T extends FieldValues>(
	config: FieldConfig<T>,
	field: {
		value: unknown;
		onChange: (value: unknown) => void;
		onBlur: () => void;
		name: string;
	},
): React.ReactNode {
	// Custom render takes precedence
	if (config.type === "custom" && config.render) {
		return config.render(field);
	}

	const handleChange = (value: string) => {
		const transformed = config.transformValue
			? config.transformValue(value)
			: value;
		field.onChange(transformed);
	};

	switch (config.type) {
		case "textarea":
			return (
				<Textarea
					className={config.className ?? "bg-background"}
					placeholder={config.placeholder}
					rows={config.rows ?? 2}
					value={(field.value as string) ?? ""}
					onChange={(e) => handleChange(e.target.value)}
					onBlur={field.onBlur}
				/>
			);

		case "select":
			return (
				<Select
					value={String(field.value ?? "")}
					onValueChange={(value) => field.onChange(value)}
				>
					<SelectTrigger className={config.className ?? "bg-background"}>
						<SelectValue placeholder={config.placeholder} />
					</SelectTrigger>
					<SelectContent>
						{config.options?.map((option) => (
							<SelectItem
								key={option.value}
								value={option.value}
								disabled={option.disabled}
							>
								<div className="flex items-center gap-2">
									{option.icon && <option.icon className="h-4 w-4" />}
									<span>{option.label}</span>
									{option.description && (
										<span className="text-muted-foreground text-xs">
											- {option.description}
										</span>
									)}
								</div>
							</SelectItem>
						))}
					</SelectContent>
				</Select>
			);

		case "password":
			return (
				<Input
					type="password"
					className={config.className ?? "bg-background"}
					placeholder={config.placeholder}
					value={(field.value as string) ?? ""}
					onChange={(e) => handleChange(e.target.value)}
					onBlur={field.onBlur}
				/>
			);

		case "number":
			return (
				<Input
					type="number"
					className={config.className ?? "bg-background"}
					placeholder={config.placeholder}
					value={(field.value as string | number) ?? ""}
					onChange={(e) => handleChange(e.target.value)}
					onBlur={field.onBlur}
				/>
			);

		case "text":
		default:
			return (
				<Input
					type="text"
					className={config.className ?? "bg-background"}
					placeholder={config.placeholder}
					value={(field.value as string) ?? ""}
					onChange={(e) => handleChange(e.target.value)}
					onBlur={field.onBlur}
				/>
			);
	}
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Helper to create field options from a proto enum
 *
 * @example
 * ```tsx
 * const options = createEnumOptions(MyProtoEnum, {
 *   [MyProtoEnum.VALUE_A]: { label: "Value A", description: "First option" },
 *   [MyProtoEnum.VALUE_B]: { label: "Value B", description: "Second option" },
 * });
 * ```
 */
export function createEnumOptions<E extends Record<string, number | string>>(
	enumObj: E,
	config: Partial<
		Record<
			E[keyof E],
			{
				label: string;
				description?: string;
				icon?: React.ComponentType<{ className?: string }>;
				disabled?: boolean;
			}
		>
	>,
): FieldOption[] {
	return Object.entries(enumObj)
		.filter(([key]) => Number.isNaN(Number(key))) // Filter out reverse mappings
		.map(([key, value]) => {
			const cfg = config[value as E[keyof E]];
			return {
				value: String(value),
				label: cfg?.label ?? key,
				description: cfg?.description,
				icon: cfg?.icon,
				disabled: cfg?.disabled,
			};
		});
}

/**
 * Helper to create a text transform function for SCREAMING_SNAKE_CASE
 */
export const toScreamingSnakeCase = (value: string): string =>
	value.toUpperCase().replace(/[^A-Z0-9_]/g, "_");

/**
 * Helper to create a text transform function for kebab-case
 */
export const toKebabCase = (value: string): string =>
	value.toLowerCase().replace(/[^a-z0-9-]/g, "-");
