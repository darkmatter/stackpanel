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
