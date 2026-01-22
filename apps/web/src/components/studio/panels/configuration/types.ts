/**
 * Type definitions for the configuration panel.
 *
 * These types are derived from the generated nix-types.ts which uses
 * kebab-case to match the actual Nix config format from `nix eval`.
 *
 * We use Partial<> wrappers because config data may be incomplete when read.
 *
 * Regenerate nix-types.ts: ./nix/stackpanel/core/generate-types.sh ts
 */

import type {
  StepCA,
  RolesAnywhere,
  ThemeTheme,
  SecretsSecrets,
} from "@/lib/generated/nix-types";

// Partial versions of generated types for reading incomplete config data
export type StepCaData = Partial<StepCA>;
export type AwsRolesAnywhereData = Partial<RolesAnywhere>;
export type AwsData = {
  "roles-anywhere"?: Partial<RolesAnywhere>;
  "default-profile"?: string;
  "extra-config"?: string;
};
export type ThemeData = Partial<ThemeTheme>;
export type SecretsData = Partial<SecretsSecrets>;

// Types not yet in nix-types.ts - these should be added to the schema
// TODO: Add IDE and BinaryCache schemas to nix/stackpanel/db/schemas/

export type IdeData = {
  enable?: boolean;
  vscode?: {
    enable?: boolean;
    "output-mode"?: "workspace" | "settingsJson";
  };
};

export type UsersSettingsData = {
  "disable-github-sync"?: boolean;
};

export type BinaryCacheData = {
  enable?: boolean;
  cachix?: {
    enable?: boolean;
    cache?: string;
    "token-path"?: string;
  };
};

export type ProjectData = {
  name?: string;
  type?: string;
  owner?: string;
  repo?: string;
};
