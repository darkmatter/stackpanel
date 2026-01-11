export interface VariableFormState {
  name: string;
  description: string;
  type: "secret" | "config" | "computed" | "service";
  required: boolean;
  sensitive: boolean;
  default: string;
  options: string;
  service: string;
}

export const defaultFormState: VariableFormState = {
  name: "",
  description: "",
  type: "config",
  required: false,
  sensitive: false,
  default: "",
  options: "",
  service: "",
};
