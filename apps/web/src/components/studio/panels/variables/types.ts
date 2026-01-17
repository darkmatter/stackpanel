import { type Variable, VariableType } from "@stackpanel/proto";
export interface VariableFormState extends Variable {
  sensitive: boolean;
  default: string;
  options: string;
  service: string;
}

export const defaultFormState: VariableFormState = {
  id: "",
  key: "",
  value: "",
  description: "",
  type: VariableType.SECRET,
  environments: [],
  sensitive: true,
  default: "",
  options: "",
  service: "",
};
