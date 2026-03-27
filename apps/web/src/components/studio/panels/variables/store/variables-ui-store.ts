import { create } from "zustand";
import { devtools } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";
import type { VariableTypeName } from "../constants";

/**
 * Revealed secret state: { [variableId]: { value: string, loading: boolean } }
 */
export interface RevealedSecrets {
  [variableId: string]: { value: string; loading: boolean };
}

/**
 * Editing secret state
 */
export interface EditingSecret {
  id: string;
  key: string;
  group?: string;
  value?: string;
}

/**
 * Variables UI state store using Zustand with Immer
 * Manages filter, search, expanded state, and secret reveal/edit operations
 */
interface VariablesUIState {
  // Search and filtering
  searchQuery: string;
  selectedType: VariableTypeName | "all";

  // Expand/collapse state
  expandedId: string | null;

  // Secret reveal state
  revealedSecrets: RevealedSecrets;

  // Secret edit dialog state
  editingSecret: EditingSecret | null;

  // Actions
  setSearchQuery: (query: string) => void;
  setSelectedType: (type: VariableTypeName | "all") => void;
  toggleExpanded: (id: string) => void;
  clearExpanded: () => void;

  // Secret reveal actions
  setRevealedSecret: (
    variableId: string,
    value: string,
    loading: boolean,
  ) => void;
  clearRevealedSecret: (variableId: string) => void;
  clearAllRevealedSecrets: () => void;

  // Secret edit actions
  setEditingSecret: (secret: EditingSecret | null) => void;

  // Batch reset
  reset: () => void;
}

const initialState = {
  searchQuery: "",
  selectedType: "all" as const,
  expandedId: null,
  revealedSecrets: {},
  editingSecret: null,
};

export const useVariablesUIStore = create<VariablesUIState>()(
  devtools(
    immer((set: any) => ({
      ...initialState,

      setSearchQuery: (query: string) => {
        set(
          (state: any) => {
            state.searchQuery = query;
          },
          false,
          "setSearchQuery",
        );
      },

      setSelectedType: (type: VariableTypeName | "all") => {
        set(
          (state: any) => {
            state.selectedType = type;
          },
          false,
          "setSelectedType",
        );
      },

      toggleExpanded: (id: string) => {
        set(
          (state: any) => {
            state.expandedId = state.expandedId === id ? null : id;
          },
          false,
          "toggleExpanded",
        );
      },

      clearExpanded: () => {
        set(
          (state: any) => {
            state.expandedId = null;
          },
          false,
          "clearExpanded",
        );
      },

      setRevealedSecret: (
        variableId: string,
        value: string,
        loading: boolean,
      ) => {
        set(
          (state: any) => {
            state.revealedSecrets[variableId] = { value, loading };
          },
          false,
          "setRevealedSecret",
        );
      },

      clearRevealedSecret: (variableId: string) => {
        set(
          (state: any) => {
            delete state.revealedSecrets[variableId];
          },
          false,
          "clearRevealedSecret",
        );
      },

      clearAllRevealedSecrets: () => {
        set(
          (state: any) => {
            state.revealedSecrets = {};
          },
          false,
          "clearAllRevealedSecrets",
        );
      },

      setEditingSecret: (secret: EditingSecret | null) => {
        set(
          (state: any) => {
            state.editingSecret = secret;
          },
          false,
          "setEditingSecret",
        );
      },

      reset: () => {
        set(() => initialState, false, "reset");
      },
    })),
    {
      name: "VariablesUIStore",
      trace: true,
    },
  ),
);
