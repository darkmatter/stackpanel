import { Resource } from "alchemy/Resource";
import * as Neon from "alchemy/Neon";

export interface NeonProjectProps {
  name: string;
  regionId?: string;
  pgVersion?: number;
  databaseName?: string;
  roleName?: string;
}

export interface NeonProject extends Resource<
  "Neon.Project",
  NeonProjectProps,
  {
    projectId: string;
    connectionUri: string;
    host: string;
    databaseName: string;
    roleName: string;
    regionId: string;
  }
> {}

export const NeonProject = Resource<NeonProject>("Neon.Project");

/**
 * Neon resource providers, sourced from alchemy's native Neon module.
 *
 * `Neon.providers()` registers the Project/Branch providers and resolves
 * credentials internally (via alchemy's auth profile system), so no manual
 * credentials layer is required here.
 */
export const neonProviders = () => Neon.providers();
