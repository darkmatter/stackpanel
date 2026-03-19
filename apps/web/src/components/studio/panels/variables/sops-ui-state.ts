import { useEffect, useState } from "react";
import type { Recipient, SecretsConfigEntity } from "@/lib/types";

const STORAGE_KEY = "stackpanel.sops-ui.optimistic";
const TTL_MS = 90_000;

type OptimisticState = {
  expiresAt: number;
  recipients?: Recipient[];
  secretsConfig?: SecretsConfigEntity;
};

function readState(): OptimisticState | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as OptimisticState;
    if (!parsed.expiresAt || parsed.expiresAt <= Date.now()) {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
    return parsed;
  } catch {
    localStorage.removeItem(STORAGE_KEY);
    return null;
  }
}

function writeState(next: OptimisticState | null) {
  if (typeof window === "undefined") return;
  if (!next) {
    localStorage.removeItem(STORAGE_KEY);
    return;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
}

function stableStringify(value: unknown) {
  return JSON.stringify(value);
}

export function useSopsUiOptimisticState() {
  const [optimistic, setOptimistic] = useState<OptimisticState | null>(() => readState());

  useEffect(() => {
    if (!optimistic) return;
    const delay = Math.max(0, optimistic.expiresAt - Date.now());
    const timer = window.setTimeout(() => {
      setOptimistic(null);
      writeState(null);
    }, delay);
    return () => window.clearTimeout(timer);
  }, [optimistic]);

  const update = (patch: Partial<OptimisticState>) => {
    const next: OptimisticState = {
      ...(optimistic ?? {}),
      ...patch,
      expiresAt: Date.now() + TTL_MS,
    };
    setOptimistic(next);
    writeState(next);
  };

  const clearIfSynced = (serverRecipients?: Recipient[], serverSecretsConfig?: SecretsConfigEntity | null) => {
    if (!optimistic) return;
    const recipientsMatch =
      optimistic.recipients === undefined ||
      stableStringify(optimistic.recipients) === stableStringify(serverRecipients ?? []);
    const configMatch =
      optimistic.secretsConfig === undefined ||
      stableStringify(optimistic.secretsConfig) === stableStringify(serverSecretsConfig ?? null);
    if (recipientsMatch && configMatch) {
      setOptimistic(null);
      writeState(null);
    }
  };

  return {
    optimistic,
    optimisticRecipients: optimistic?.recipients,
    optimisticSecretsConfig: optimistic?.secretsConfig,
    update,
    clearIfSynced,
  };
}

export function mergeRecipients(base: Recipient[], optimistic?: Recipient[]) {
  return optimistic ?? base;
}

export function mergeSecretsConfig(base: SecretsConfigEntity | null | undefined, optimistic?: SecretsConfigEntity) {
  return optimistic ?? base ?? {};
}
