import { useMemo } from "react";
import { getTypeConfig, type VariablesBackend } from "../constants";
import { useVariablesUIStore } from "../store/variables-ui-store";

export interface Variable {
  id: string;
  value: string;
  name: string;
  envKey: string;
}

/**
 * Hook for filtering and searching variables
 * Uses Zustand store for search query and type filter
 */
export function useVariableFilters(
  variables: Variable[] | undefined,
  backend: VariablesBackend,
) {
  const searchQuery = useVariablesUIStore((state: any) => state.searchQuery);
  const selectedType = useVariablesUIStore((state: any) => state.selectedType);

  const variablesList = useMemo(() => {
    if (!variables) return [];
    return variables;
  }, [variables]);

  const filteredVariables = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();

    return variablesList
      .filter((variable) => {
        const matchesSearch =
          !query ||
          variable.name.toLowerCase().includes(query) ||
          variable.id.toLowerCase().includes(query) ||
          variable.value.toLowerCase().includes(query);

        const variableUiType = getTypeConfig(
          variable.id,
          variable.value,
          backend,
        ).value;
        const matchesType =
          selectedType === "all" || selectedType === variableUiType;

        return matchesSearch && matchesType;
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [variablesList, searchQuery, selectedType, backend]);

  return {
    filteredVariables,
    totalVariables: variablesList.length,
    filteredCount: filteredVariables.length,
  };
}
