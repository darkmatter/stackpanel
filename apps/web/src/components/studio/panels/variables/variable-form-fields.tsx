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
import {
	EntityForm,
	type EntityForm as EntityFormType,
	type FieldConfig,
} from "../shared/entity-form";
import { VARIABLE_TYPES } from "./constants";

// =============================================================================
// Types
// =============================================================================

export interface VariableFormValues {
	id: string;
	key: string;
	description?: string;
	type: VariableType;
	value: string;
}

export type VariableForm = EntityFormType<VariableFormValues>;

// =============================================================================
// Type Mapping Helpers
// =============================================================================

/**
 * Map VariableType enum to the string values used in VARIABLE_TYPES constant
 */
function variableTypeToString(type: VariableType): string {
	switch (type) {
		case VariableType.SECRET:
			return "secret";
		case VariableType.VALS:
			return "computed";
		default:
			return "config";
	}
}

/**
 * Map string value back to VariableType enum
 */
function stringToVariableType(value: string): VariableType {
	switch (value) {
		case "secret":
			return VariableType.SECRET;
		case "computed":
			return VariableType.VALS;
		default:
			return VariableType.VARIABLE;
	}
}

// =============================================================================
// Field Configuration
// =============================================================================

const createVariableFields = (
	showIdField: boolean,
	currentType: VariableType,
): FieldConfig<VariableFormValues>[] => {
	const isSecret = currentType === VariableType.SECRET;

	const fields: FieldConfig<VariableFormValues>[] = [];

	if (showIdField) {
		fields.push({
			name: "id",
			label: "Variable ID",
			type: "text",
			required: true,
			placeholder: "e.g., my-database-url, /prod/api-key",
			description:
				"Unique identifier for this variable (kebab-case or path-based)",
			className: "bg-background font-mono",
			rules: {
				required: "Variable ID is required",
				pattern: {
					value: /^[a-zA-Z0-9/_-]+$/,
					message:
						"ID must contain only letters, numbers, hyphens, underscores, and slashes",
				},
			},
		});
	}

	fields.push(
		{
			name: "key",
			label: "Default Environment Key",
			type: "text",
			required: false,
			placeholder: "e.g., DATABASE_URL, API_KEY (optional)",
			description:
				"Optional: The key used in environment variables (SCREAMING_SNAKE_CASE)",
			className: "bg-background font-mono",
			transformValue: (value) =>
				value.toUpperCase().replace(/[^A-Z0-9_]/g, "_"),
			rules: {
				pattern: {
					value: /^[A-Z0-9_]*$/,
					message: "Key must be SCREAMING_SNAKE_CASE",
				},
			},
		},
		{
			name: "description",
			label: "Description",
			type: "textarea",
			placeholder: "What is this variable used for?",
			rows: 2,
		},
		{
			name: "type",
			label: "Type",
			type: "custom",
			render: (field) => (
				<TypeSelectField
					value={field.value as VariableType}
					onChange={field.onChange}
				/>
			),
		},
		{
			name: "value",
			label: "Value",
			type: "textarea",
			placeholder: isSecret
				? "Secret value (will be encrypted)"
				: "Variable value",
			description:
				currentType === VariableType.VALS
					? "For VALS type, use a vals-compatible descriptor like ref+awsssm://PATH/TO/PARAM[?region=us-east-1]"
					: undefined,
			className: "bg-background font-mono",
			rows: 4,
		},
	);

	return fields;
};

// =============================================================================
// Custom Field Components
// =============================================================================

import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";

interface TypeSelectFieldProps {
	value: VariableType;
	onChange: (value: unknown) => void;
}

function TypeSelectField({ value, onChange }: TypeSelectFieldProps) {
	return (
		<Select
			value={variableTypeToString(value)}
			onValueChange={(val) => onChange(stringToVariableType(val))}
		>
			<SelectTrigger className="bg-background">
				<SelectValue />
			</SelectTrigger>
			<SelectContent>
				{VARIABLE_TYPES.filter((t) => !t.readonly).map((t) => (
					<SelectItem key={t.value} value={t.value}>
						<div className="flex items-center gap-2">
							<t.icon className="h-4 w-4" />
							<span>{t.label}</span>
							<span className="text-muted-foreground text-xs">
								- {t.description}
							</span>
						</div>
					</SelectItem>
				))}
			</SelectContent>
		</Select>
	);
}

// =============================================================================
// Main Component
// =============================================================================

interface VariableFormFieldsProps {
	/** Show the ID field (for "add" mode) */
	showIdField?: boolean;
	/** Default values to populate the form */
	defaultValues?: Partial<VariableFormValues>;
	/** Callback when form values change */
	onValuesChange?: (values: VariableFormValues) => void;
	/** Expose form instance to parent */
	onFormReady?: (form: VariableForm) => void;
}

export function VariableFormFields({
	showIdField = false,
	defaultValues,
	onValuesChange,
	onFormReady,
}: VariableFormFieldsProps) {
	// Track current type for conditional field rendering
	const currentType = defaultValues?.type ?? VariableType.SECRET;

	return (
		<EntityForm<VariableFormValues>
			fields={createVariableFields(showIdField, currentType)}
			defaultValues={{
				id: "",
				key: "",
				description: "",
				type: VariableType.SECRET,
				value: "",
				...defaultValues,
			}}
			onValuesChange={onValuesChange}
			onFormReady={onFormReady}
		/>
	);
}
