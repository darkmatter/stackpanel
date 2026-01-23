/**
 * Module Browser Hooks
 *
 * React Query hooks for fetching and mutating module data.
 */

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useAgentClient } from "@/lib/agent-provider";
import type {
  ModuleConfig,
  ModuleDetailResponse,
  ModulesResponse,
} from "./types";

// =============================================================================
// Query Keys
// =============================================================================

export const moduleQueryKeys = {
  all: ["modules"] as const,
  list: (params?: { includeHealth?: boolean; includeDisabled?: boolean; category?: string }) =>
    [...moduleQueryKeys.all, "list", params] as const,
  detail: (name: string, includeHealth?: boolean) =>
    [...moduleQueryKeys.all, "detail", name, { includeHealth }] as const,
  config: (name: string) => [...moduleQueryKeys.all, "config", name] as const,
};

// =============================================================================
// List Modules Hook
// =============================================================================

export interface UseModulesOptions {
  includeHealth?: boolean;
  includeDisabled?: boolean;
  category?: string;
  enabled?: boolean;
}

export function useModules(options: UseModulesOptions = {}) {
  const client = useAgentClient();
  const {
    includeHealth = false,
    includeDisabled = false,
    category,
    enabled = true,
  } = options;

  return useQuery({
    queryKey: moduleQueryKeys.list({ includeHealth, includeDisabled, category }),
    queryFn: async (): Promise<ModulesResponse> => {
      const params = new URLSearchParams();
      if (includeHealth) params.set("includeHealth", "true");
      if (includeDisabled) params.set("includeDisabled", "true");
      if (category) params.set("category", category);

      const url = `/api/modules${params.toString() ? `?${params}` : ""}`;
      // API returns { success: true, data: ModulesResponse }
      const response = await client.get<{
        success: boolean;
        data: ModulesResponse;
      }>(url);
      return response.data;
    },
    enabled,
    staleTime: 30 * 1000, // 30 seconds
    refetchOnWindowFocus: true,
  });
}

// =============================================================================
// Single Module Hook
// =============================================================================

export interface UseModuleOptions {
  includeHealth?: boolean;
  enabled?: boolean;
}

export function useModule(name: string, options: UseModuleOptions = {}) {
  const client = useAgentClient();
  const { includeHealth = true, enabled = true } = options;

  return useQuery({
    queryKey: moduleQueryKeys.detail(name, includeHealth),
    queryFn: async (): Promise<ModuleDetailResponse> => {
      const params = new URLSearchParams();
      if (includeHealth) params.set("includeHealth", "true");

      const url = `/api/modules/${name}${params.toString() ? `?${params}` : ""}`;
      // API returns { success: true, data: ModuleDetailResponse }
      const response = await client.get<{
        success: boolean;
        data: ModuleDetailResponse;
      }>(url);
      return response.data;
    },
    enabled: enabled && !!name,
    staleTime: 30 * 1000,
  });
}

// =============================================================================
// Module Config Hook
// =============================================================================

export function useModuleConfig(name: string) {
  const client = useAgentClient();

  return useQuery({
    queryKey: moduleQueryKeys.config(name),
    queryFn: async (): Promise<ModuleConfig> => {
      // API returns { success: true, data: ModuleConfig }
      const response = await client.get<{
        success: boolean;
        data: ModuleConfig;
      }>(`/api/modules/${name}/config`);
      return response.data;
    },
    enabled: !!name,
  });
}

// =============================================================================
// Save Module Config Mutation
// =============================================================================

export function useSaveModuleConfig(name: string) {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (config: ModuleConfig) => {
      return client.post<{ success: boolean; message: string }>(`/api/modules/${name}/config`, config);
    },
    onSuccess: () => {
      // Invalidate queries to refetch fresh data
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.config(name) });
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.detail(name) });
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.list() });
    },
  });
}

// =============================================================================
// Enable/Disable Module Mutation
// =============================================================================

export function useEnableModule(name: string) {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (enable: boolean) => {
      // API returns { success: true, data: { success, message } }
      const response = await client.post<{
        success: boolean;
        data: { success: boolean; message: string };
      }>(`/api/modules/${name}/enable`, { enable });
      return response.data;
    },
    onSuccess: () => {
      // Invalidate all module and registry queries
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.all });
      queryClient.invalidateQueries({ queryKey: registryQueryKeys.all });
    },
  });
}

// Dynamic version that doesn't require name upfront
export function useEnableModuleDynamic() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ moduleId, enable }: { moduleId: string; enable: boolean }) => {
      // API returns { success: true, data: { success, message } }
      const response = await client.post<{
        success: boolean;
        data: { success: boolean; message: string };
      }>(`/api/modules/${moduleId}/enable`, { enable });
      return response.data;
    },
    onSuccess: () => {
      // Invalidate all module and registry queries
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.all });
      queryClient.invalidateQueries({ queryKey: registryQueryKeys.all });
    },
  });
}

// =============================================================================
// Run Module Health Checks Mutation
// =============================================================================

export function useRunModuleHealthchecks(name: string) {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      return client.post<unknown>(`/api/healthchecks?module=${name}`, {});
    },
    onSuccess: () => {
      // Invalidate module detail to refresh health status
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.detail(name) });
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.list() });
    },
  });
}

// =============================================================================
// Registry Query Keys
// =============================================================================

export const registryQueryKeys = {
  all: ["registry"] as const,
  modules: (params?: { search?: string; category?: string }) =>
    [...registryQueryKeys.all, "modules", params] as const,
};

// =============================================================================
// Registry Modules Hook
// =============================================================================

export interface UseRegistryModulesOptions {
  search?: string;
  category?: string;
  enabled?: boolean;
}

export function useRegistryModules(options: UseRegistryModulesOptions = {}) {
  const client = useAgentClient();
  const { search, category, enabled = true } = options;

  return useQuery({
    queryKey: registryQueryKeys.modules({ search, category }),
    queryFn: async (): Promise<import("./types").RegistryModulesResponse> => {
      const params = new URLSearchParams();
      if (search) params.set("search", search);
      if (category) params.set("category", category);

      const url = `/api/registry/modules${params.toString() ? `?${params}` : ""}`;
      // API returns { success: true, data: RegistryModulesResponse }
      const response = await client.get<{
        success: boolean;
        data: import("./types").RegistryModulesResponse;
      }>(url);
      return response.data;
    },
    enabled,
    staleTime: 5 * 60 * 1000, // 5 minutes (registry data is more static)
    refetchOnWindowFocus: false,
  });
}

// =============================================================================
// Install Module Mutation
// =============================================================================

export function useInstallModule() {
  const client = useAgentClient();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (request: import("./types").InstallModuleRequest) => {
      // API returns { success: true, data: InstallModuleResponse }
      const response = await client.post<{
        success: boolean;
        data: import("./types").InstallModuleResponse;
      }>("/api/registry/modules/install", request);
      return response.data;
    },
    onSuccess: () => {
      // Invalidate registry queries to update installed status
      queryClient.invalidateQueries({ queryKey: registryQueryKeys.all });
      queryClient.invalidateQueries({ queryKey: moduleQueryKeys.all });
    },
  });
}
