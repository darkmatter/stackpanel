export interface CommandFormState {
  name: string;
  description: string;
  category: string;
  command?: string;
}

export const defaultFormState: CommandFormState = {
  name: "",
  description: "",
  category: "development",
  command: "",
};
