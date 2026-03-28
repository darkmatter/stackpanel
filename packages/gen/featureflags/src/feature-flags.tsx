"use client";

import { useLocation } from "@tanstack/react-router";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

type FlagKind = "boolean" | "variant";

type BaseFeatureFlagDefinition = {
  key: string;
  kind: FlagKind;
  label: string;
  description: string;
  defaultValue: string | boolean;
  rollout?: number;
};

export type BooleanFeatureFlagDefinition = BaseFeatureFlagDefinition & {
  kind: "boolean";
  defaultValue: boolean;
};

export type VariantFeatureFlagDefinition = BaseFeatureFlagDefinition & {
  kind: "variant";
  defaultValue: string;
  variants: readonly string[];
  weights?: Partial<Record<string, number>>;
};

export type FeatureFlagDefinition =
  | BooleanFeatureFlagDefinition
  | VariantFeatureFlagDefinition;

export type FeatureFlagValue = string | boolean;

type RawOverrides = Record<string, string>;

export const FEATURE_FLAG_KEYS = {"overviewLayout":"studio.overview.layout","overviewPulseBanner":"studio.overview.pulse-banner"} as const;

export const featureFlagDefinitions: readonly FeatureFlagDefinition[] =
  [{"defaultValue":"classic","description":"Select between classic and compact studio overview layouts for experiments.","key":"studio.overview.layout","kind":"variant","label":"Overview layout","rollout":100,"variants":["classic","compact"]},{"defaultValue":false,"description":"Show the experimental pulse indicator in the overview panel.","key":"studio.overview.pulse-banner","kind":"boolean","label":"Pulse banner on overview","rollout":0}] as const;

const STORAGE_KEY = "stackpanel.feature-flags";
const IDENTIFIER_KEY = "stackpanel.feature-flags.identity";
const URL_OVERRIDE_PARAM = "ff";

interface FeatureFlagsContextValue {
  definitions: readonly FeatureFlagDefinition[];
  flags: Readonly<Record<string, FeatureFlagValue>>;
  identity: string;
  setOverride: (key: string, value: string | boolean) => void;
  clearOverride: (key: string) => void;
  clearAllOverrides: () => void;
  isEnabled: (key: string) => boolean;
  getVariant: (key: string, fallback?: string) => string;
  getValue: (key: string) => FeatureFlagValue;
  localOverrides: RawOverrides;
  isOverridden: (key: string) => boolean;
}

const FeatureFlagsContext = createContext<FeatureFlagsContextValue | null>(
  null,
);

const featureFlagMap = Object.fromEntries(
  featureFlagDefinitions.map((flag) => [flag.key, flag]),
) as Record<string, FeatureFlagDefinition>;

function isBrowser(): boolean {
  return typeof window !== "undefined";
}

function clampRolloutPercent(value: number | undefined): number {
  if (!value) {
    return 0;
  }

  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.min(100, Math.max(0, Math.floor(value)));
}

function getIdentity(): string {
  if (!isBrowser()) {
    return "ssr";
  }

  const cached = localStorage.getItem(IDENTIFIER_KEY);
  if (cached && cached.length > 0) {
    return cached;
  }

  const generated = crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  localStorage.setItem(IDENTIFIER_KEY, generated);
  return generated;
}

function parseQueryOverrides(search: string): RawOverrides {
  const params = new URLSearchParams(search);
  const overrides: RawOverrides = {};

  for (const [paramName, value] of params.entries()) {
    if (!paramName.startsWith("ff_")) {
      continue;
    }

    const key = paramName.slice("ff_".length);
    if (key.length > 0) {
      overrides[key] = value;
    }
  }

  const bundle = params.get(URL_OVERRIDE_PARAM);
  if (!bundle) {
    return overrides;
  }

  for (const token of bundle.split(",")) {
    const trimmed = token.trim();
    if (!trimmed) {
      continue;
    }

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex < 1 || separatorIndex === trimmed.length - 1) {
      continue;
    }

    overrides[trimmed.slice(0, separatorIndex)] = trimmed.slice(
      separatorIndex + 1,
    );
  }

  return overrides;
}

function loadOverrides(): RawOverrides {
  if (!isBrowser()) {
    return {};
  }

  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) {
    return {};
  }

  try {
    const parsed = JSON.parse(raw) as unknown;
    if (
      typeof parsed === "object" &&
      parsed !== null &&
      !Array.isArray(parsed)
    ) {
      const overrides: RawOverrides = {};
      for (const [key, value] of Object.entries(
        parsed as Record<string, unknown>,
      )) {
        if (typeof value === "string" || typeof value === "number") {
          overrides[key] = String(value);
        }
      }

      return overrides;
    }
  } catch {
    return {};
  }

  return {};
}

function normalizeBoolean(value: string): boolean | undefined {
  const normalized = value.toLowerCase();
  if (normalized === "true" || normalized === "1") {
    return true;
  }

  if (normalized === "false" || normalized === "0") {
    return false;
  }

  return undefined;
}

function hashToBucket(value: string, modulo: number): number {
  let hash = 2166136261 >>> 0;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }

  return modulo === 0 ? 0 : hash % modulo;
}

function resolveBooleanFlag(
  flag: BooleanFeatureFlagDefinition,
  identity: string,
  queryOverrides: RawOverrides,
  localOverrides: RawOverrides,
): boolean {
  const queryValue = queryOverrides[flag.key];
  if (queryValue !== undefined) {
    const parsed = normalizeBoolean(queryValue);
    if (parsed !== undefined) {
      return parsed;
    }
  }

  const localValue = localOverrides[flag.key];
  if (localValue !== undefined) {
    const parsed = normalizeBoolean(localValue);
    if (parsed !== undefined) {
      return parsed;
    }
  }

  const rollout = clampRolloutPercent(flag.rollout);
  if (rollout === 0) {
    return flag.defaultValue;
  }

  const bucket = hashToBucket(`${identity}:${flag.key}`, 100);
  return bucket < rollout;
}

function resolveVariantFlag(
  flag: VariantFeatureFlagDefinition,
  identity: string,
  queryOverrides: RawOverrides,
  localOverrides: RawOverrides,
): string {
  const queryValue = queryOverrides[flag.key];
  if (queryValue !== undefined && flag.variants.includes(queryValue)) {
    return queryValue;
  }

  const localValue = localOverrides[flag.key];
  if (localValue !== undefined && flag.variants.includes(localValue)) {
    return localValue;
  }

  const rollout = clampRolloutPercent(flag.rollout);
  if (rollout > 0 && rollout < 100) {
    const rolloutBucket = hashToBucket(`${identity}:${flag.key}`, 100);
    if (rolloutBucket >= rollout) {
      return flag.defaultValue;
    }
  }

  const weights = flag.variants.map(
    (variant) => Math.max(0, flag.weights?.[variant] ?? 1),
  );
  const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
  if (totalWeight <= 0) {
    return flag.defaultValue;
  }

  const bucket = hashToBucket(`${identity}:${flag.key}:variant`, totalWeight);
  let top = 0;

  for (let index = 0; index < flag.variants.length; index += 1) {
    top += weights[index] ?? 0;
    if (bucket < top) {
      return flag.variants[index] ?? flag.defaultValue;
    }
  }

  return flag.defaultValue;
}

function isValidOverrideValue(
  flag: FeatureFlagDefinition,
  value: string,
): boolean {
  if (flag.kind === "boolean") {
    return normalizeBoolean(value) !== undefined;
  }

  return flag.variants.includes(value);
}

function evaluateFlags(
  identity: string,
  search: string,
  localOverrides: RawOverrides,
): Record<string, FeatureFlagValue> {
  const queryOverrides = parseQueryOverrides(search);
  const values: Record<string, FeatureFlagValue> = {};

  for (const flag of featureFlagDefinitions) {
    if (flag.kind === "boolean") {
      values[flag.key] = resolveBooleanFlag(
        flag,
        identity,
        queryOverrides,
        localOverrides,
      );
      continue;
    }

    values[flag.key] = resolveVariantFlag(
      flag,
      identity,
      queryOverrides,
      localOverrides,
    );
  }

  return values;
}

export function FeatureFlagProvider({ children }: { children: ReactNode }) {
  const { search } = useLocation();
  const [identity] = useState(getIdentity);
  const [localOverrides, setLocalOverrides] = useState(loadOverrides);
  const normalizedSearch =
    typeof search === "string"
      ? search
      : new URLSearchParams(
          Object.entries(search).reduce<Record<string, string>>(
            (acc, [key, value]) => {
              if (typeof value === "string") {
                acc[key] = value;
              }

              if (Array.isArray(value) && value[0] !== undefined) {
                acc[key] = value[0] ?? "";
              }

              return acc;
            },
            {},
          ),
        ).toString();

  useEffect(() => {
    if (!isBrowser()) {
      return;
    }

    localStorage.setItem(STORAGE_KEY, JSON.stringify(localOverrides));
  }, [localOverrides]);

  const flags = useMemo(
    () => evaluateFlags(identity, normalizedSearch, localOverrides),
    [identity, localOverrides, normalizedSearch],
  );

  const setOverride = useCallback((key: string, value: string | boolean) => {
    const definition = featureFlagMap[key];
    if (!definition) {
      return;
    }

    const normalized = String(value);
    if (!isValidOverrideValue(definition, normalized)) {
      return;
    }

    setLocalOverrides((prev) => ({
      ...prev,
      [key]: normalized,
    }));
  }, []);

  const clearOverride = useCallback((key: string) => {
    setLocalOverrides((prev) => {
      if (!Object.prototype.hasOwnProperty.call(prev, key)) {
        return prev;
      }

      const next = { ...prev };
      delete next[key];
      return next;
    });
  }, []);

  const clearAllOverrides = useCallback(() => {
    setLocalOverrides({});
  }, []);

  const isOverridden = useCallback(
    (key: string) => Object.prototype.hasOwnProperty.call(localOverrides, key),
    [localOverrides],
  );

  const getValue = useCallback(
    (key: string): FeatureFlagValue => {
      if (key in flags) {
        return flags[key];
      }

      const definition = featureFlagMap[key];
      if (!definition) {
        return false;
      }

      return definition.defaultValue;
    },
    [flags],
  );

  const isEnabled = useCallback(
    (key: string): boolean => getValue(key) === true,
    [getValue],
  );

  const getVariant = useCallback(
    (key: string, fallback = "") => {
      const value = getValue(key);
      if (typeof value === "string") {
        return value;
      }

      if (fallback.length > 0) {
        return fallback;
      }

      const definition = featureFlagMap[key];
      if (
        definition &&
        definition.kind === "variant" &&
        definition.variants.length > 0
      ) {
        return definition.defaultValue;
      }

      return fallback;
    },
    [getValue],
  );

  const contextValue = useMemo<FeatureFlagsContextValue>(
    () => ({
      definitions: featureFlagDefinitions,
      flags,
      identity,
      setOverride,
      clearOverride,
      clearAllOverrides,
      isEnabled,
      getVariant,
      getValue,
      localOverrides,
      isOverridden,
    }),
    [
      clearAllOverrides,
      clearOverride,
      flags,
      getValue,
      getVariant,
      identity,
      isEnabled,
      isOverridden,
      localOverrides,
      setOverride,
    ],
  );

  return (
    <FeatureFlagsContext.Provider value={contextValue}>
      {children}
    </FeatureFlagsContext.Provider>
  );
}

export function useFeatureFlags(): FeatureFlagsContextValue {
  const context = useContext(FeatureFlagsContext);
  if (!context) {
    throw new Error(
      "useFeatureFlags must be used within <FeatureFlagProvider />",
    );
  }

  return context;
}
