"use client";

import { Globe, Play, Variable } from "lucide-react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { MultiSelect } from "../shared/multi-select";
import { APP_TYPES } from "./constants";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useEffect } from "react";
import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
  InputGroupText,
} from "@/components/ui/input-group";
import { Label } from "@/components/ui/label";

interface TaskItem {
  id: string;
  name: string;
}

interface VariableItem {
  id: string;
  name: string;
  type: string;
}

export const appFormSchema = z.object({
  id: z.string().min(1, "App ID is required").max(36),
  name: z.string().max(100).optional(),
  description: z.string().max(500).optional(),
  path: z.string().min(1, "Path is required").max(200),
  type: z.string().min(1),
  port: z.string().optional(),
  domain: z.string().max(100).optional(),
  tasks: z.array(z.string()),
  variables: z.array(z.string()),
});

export type AppFormValues = z.infer<typeof appFormSchema>;

export type AppForm = ReturnType<typeof useForm<AppFormValues>>;

/** Convert form values port string to number for API submission */
export function parsePortValue(port: string | undefined): number | undefined {
  if (!port) return undefined;
  const parsed = Number.parseInt(port, 10);
  return Number.isNaN(parsed) ? undefined : parsed;
}

interface AppFormFieldsProps {
  /** Task items for selection (when showing tasks) */
  taskItems?: TaskItem[];
  /** Variable items for selection (when showing variables) */
  variableItems?: VariableItem[];
  /** Optional ID field for "add" mode - not shown in edit mode */
  showIdField?: boolean;
  /** Hide tasks and variables sections (used in Add App form) */
  hideTasksAndVariables?: boolean;
  /** Default values to populate the form */
  defaultValues?: Partial<AppFormValues>;
  /** Callback when form values change */
  onValuesChange?: (values: AppFormValues) => void;
  /** Expose form instance to parent */
  onFormReady?: (form: AppForm) => void;
}

export function AppFormFields({
  taskItems = [],
  variableItems = [],
  showIdField = false,
  hideTasksAndVariables = false,
  defaultValues,
  onValuesChange,
  onFormReady,
}: AppFormFieldsProps) {
  const form = useForm<AppFormValues>({
    resolver: zodResolver(appFormSchema),
    defaultValues: {
      id: "",
      name: "",
      description: "",
      path: "",
      type: "bun",
      port: "",
      domain: "",
      tasks: [],
      variables: [],
      ...defaultValues,
    },
  });

  // Expose form to parent
  useEffect(() => {
    onFormReady?.(form);
  }, [form, onFormReady]);

  // Watch for changes and notify parent
  useEffect(() => {
    if (!onValuesChange) return;

    const subscription = form.watch((values) => {
      onValuesChange(values as AppFormValues);
    });

    return () => subscription.unsubscribe();
  }, [form, onValuesChange]);

  return (
    <Form {...form}>
      <div className="space-y-4">
        {showIdField && (
          <FormField
            control={form.control}
            name="id"
            render={({ field }) => (
              <FormItem>
                <FormLabel>App ID *</FormLabel>
                <FormControl>
                  <Input
                    className="bg-background"
                    placeholder="e.g., web, api, mobile"
                    {...field}
                  />
                </FormControl>
                <FormDescription>
                  Unique identifier for this app
                </FormDescription>
                <FormMessage />
              </FormItem>
            )}
          />
        )}
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="name"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Display Name</FormLabel>
                <FormControl>
                  <Input
                    className="bg-background"
                    placeholder="e.g., Web Frontend"
                    {...field}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="type"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Type</FormLabel>
                <Select value={field.value} onValueChange={field.onChange}>
                  <FormControl>
                    <SelectTrigger className="bg-background">
                      <SelectValue />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    {APP_TYPES.map((type) => (
                      <SelectItem key={type.value} value={type.value}>
                        {type.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>
        <FormField
          control={form.control}
          name="description"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Description</FormLabel>
              <FormControl>
                <Input
                  className="bg-background"
                  placeholder="Brief description of the app"
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="path"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Path {showIdField && "*"}</FormLabel>
              <FormControl>
                <Input
                  className="bg-background"
                  placeholder="apps/web"
                  {...field}
                />
              </FormControl>
              <FormDescription>
                Relative path to the app directory
              </FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="port"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Dev Port</FormLabel>
                <FormControl>
                  <Input
                    className="bg-background"
                    type="number"
                    placeholder="3000"
                    {...field}
                    value={field.value ?? ""}
                  />
                </FormControl>
                <FormDescription>Port for local development</FormDescription>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="domain"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Local Domain</FormLabel>
                <FormControl>
                  <InputGroup className="w-full max-w-sm bg-background">
                    <InputGroupAddon>
                      <Label htmlFor={field.name}>
                        <Globe className="size-4" />
                      </Label>
                    </InputGroupAddon>
                    <InputGroupInput {...field} />
                    <InputGroupAddon align="inline-end">
                      <InputGroupText>.internal</InputGroupText>
                    </InputGroupAddon>
                  </InputGroup>
                </FormControl>
                <FormDescription>Custom local domain</FormDescription>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        {!hideTasksAndVariables && (
          <>
            <FormField
              control={form.control}
              name="tasks"
              render={({ field }) => (
                <FormItem>
                  <MultiSelect
                    label="Tasks"
                    items={taskItems}
                    selectedIds={field.value}
                    onSelectionChange={field.onChange}
                    renderItem={(item) => (
                      <span className="flex items-center gap-2">
                        <Play className="h-3 w-3 text-muted-foreground" />
                        {item.name}
                      </span>
                    )}
                  />
                  <FormDescription>
                    Tasks from turbo.json that can be run for this app
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="variables"
              render={({ field }) => (
                <FormItem>
                  <MultiSelect
                    label="Variables"
                    items={variableItems}
                    selectedIds={field.value}
                    onSelectionChange={field.onChange}
                    renderItem={(item) => (
                      <span className="flex items-center gap-2">
                        <Variable className="h-3 w-3 text-muted-foreground" />
                        <code className="font-mono text-xs">{item.name}</code>
                      </span>
                    )}
                  />
                  <FormMessage />
                </FormItem>
              )}
            />
          </>
        )}
      </div>
    </Form>
  );
}
