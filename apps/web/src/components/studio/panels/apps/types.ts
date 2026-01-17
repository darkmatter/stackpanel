import type { VariableType } from "@stackpanel/proto";

export interface AppFormState {
  name: string;
  description: string;
  path: string;
  type: string;
  port?: number;
  domain?: string;
  commands: string[];
  variables: string[];
}

export const defaultFormState: AppFormState = {
  name: "",
  description: "",
  path: "",
  type: "bun",
  commands: [],
  variables: [],
};

/** Task with resolved command for display */
export interface TaskWithCommand {
  name: string;
  command: string;
  isOverridden: boolean;
}

/** Variable with resolved details for display */
export interface DisplayVariable {
  envKey: string;
  variableId: string;
  variableKey: string;
  type: VariableType | null;
  description: string;
  value?: string;
  environments: string[];
  isSecret: boolean;
}
